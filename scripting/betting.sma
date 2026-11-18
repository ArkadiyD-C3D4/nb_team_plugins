#include <amxmodx>
#include <amxmisc>
#include <sqlx>
#include <fun>
#include <hamsandwich>
#include <string>

#define PLUGIN "Betting System"
#define VERSION "3.0-RECONNECT"
#define AUTHOR "nb_team"

// ---------- Нативы Points Core ----------
native points_get(id);
native points_set(id, amount);
native points_is_loaded(id);
native points_load(id);

// ---------- CVARS ----------
new cvar_min_bet, cvar_max_bet, cvar_max_coef, cvar_commission, cvar_bet_time;
new Float:g_fMinBet, Float:g_fMaxBet, Float:g_fMaxCoef, Float:g_fCommission;
new g_iBetTime;

// ---------- БД (Только для Банка сервера) ----------
new Handle:g_hDB;
new bool:g_bDBConnected;
new g_iRetryCount;
new g_iBank;

// ---------- Игроки ----------
new g_iBetAmount[33];
new g_iBetTarget[33]; // 0 - CT, 1 - TT
new bool:g_bPlayerDisconnected[33];
new bool:g_bAutoMenuShown[33];

// ---------- Дуэль ----------
new bool:g_bDuelActive;
new bool:g_bBettingOpen;
new g_iFighterCT, g_iFighterTT;
new g_iTotalBet[2]; // [0] - на CT, [1] - на TT
new g_iDuelTask;

// ---------- Настройки ----------
public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    cvar_min_bet = register_cvar("betting_min_bet", "10");
    cvar_max_bet = register_cvar("betting_max_bet", "1000");
    cvar_max_coef = register_cvar("betting_max_coef", "10.0");
    cvar_commission = register_cvar("betting_commission", "5");
    cvar_bet_time = register_cvar("betting_time", "10");

    register_clcmd("say /bet", "Cmd_Bet");
    register_clcmd("say_team /bet", "Cmd_Bet");
    register_clcmd("say /bank", "Cmd_Bank");
    register_clcmd("say_team /bank", "Cmd_Bank");
    register_clcmd("bet_custom", "Cmd_CustomBet");
    register_clcmd("amx_bankreset", "Cmd_BankReset", ADMIN_BAN, " - обнулить банк сервера");

    RegisterHam(Ham_Killed, "player", "Ham_PlayerKilled_Post", 1);
    register_event("HLTV", "Event_HLTV_RoundEnd", "a", "1=0", "2=0");
}

public plugin_cfg() {
    // Размазываем старт, чтобы не штурмовать БД одновременно с другими плагинами
    set_task(random_float(3.0, 10.0), "InitDatabase");
    
    // Читаем квары
    g_fMinBet = get_pcvar_float(cvar_min_bet);
    g_fMaxBet = get_pcvar_float(cvar_max_bet);
    g_fMaxCoef = get_pcvar_float(cvar_max_coef);
    g_fCommission = get_pcvar_float(cvar_commission);
    g_iBetTime = get_pcvar_num(cvar_bet_time);
    
    if(g_fMinBet < 0.0) g_fMinBet = 1.0;
    if(g_fMaxBet < g_fMinBet) g_fMaxBet = g_fMinBet + 1.0;
    if(g_fCommission < 0.0) g_fCommission = 0.0;
    if(g_fCommission > 100.0) g_fCommission = 100.0;
    if(g_iBetTime < 3) g_iBetTime = 3;
    if(g_iBetTime > 30) g_iBetTime = 30;
}

public plugin_end() {
    if(g_hDB != Empty_Handle) {
        SQL_FreeHandle(g_hDB);
        g_hDB = Empty_Handle;
    }
}

// ---------- БД (Только Банк) — С ПЕРЕПОДКЛЮЧЕНИЕМ ----------
public InitDatabase() {
    if(g_bDBConnected) return;
    
    // Освобождаем старый tuple, если была предыдущая попытка
    if(g_hDB != Empty_Handle) {
        SQL_FreeHandle(g_hDB);
        g_hDB = Empty_Handle;
    }
    
    new host[64], user[64], pass[64], db[64];
    get_cvar_string("amx_sql_host", host, charsmax(host));
    get_cvar_string("amx_sql_user", user, charsmax(user));
    get_cvar_string("amx_sql_pass", pass, charsmax(pass));
    get_cvar_string("amx_sql_db",   db,   charsmax(db));

    g_hDB = SQL_MakeDbTuple(host, user, pass, db);
    
    // НЕТ блокирующего SQL_Connect — проверяем через фоновый поток
    SQL_ThreadQuery(g_hDB, "CheckDBConnection", "SELECT 1");
}

public CheckDBConnection(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt) {
    if(FailState != TQUERY_SUCCESS) {
        g_iRetryCount++;
        if(g_iRetryCount < 30) {
            log_amx("[Betting] DB not ready (%s), retry #%d in 10s...", Error, g_iRetryCount);
            set_task(10.0, "InitDatabase");
        } else {
            log_amx("[Betting] DB connection failed permanently after 30 attempts.");
        }
        return;
    }
    
    g_bDBConnected = true;
    g_iRetryCount = 0;
    log_amx("[Betting] Database connected via thread.");
    
    // Создаём таблицы и загружаем банк
    CreateTablesAndLoadBank();
}

public CreateTablesAndLoadBank() {
    new q[512];
    formatex(q, charsmax(q), "CREATE TABLE IF NOT EXISTS server_data (key VARCHAR(32) PRIMARY KEY, value INT DEFAULT 0)");
    SQL_ThreadQuery(g_hDB, "EmptyCallback", q);
    
    formatex(q, charsmax(q), "INSERT IGNORE INTO server_data (key, value) VALUES ('bank', 0)");
    SQL_ThreadQuery(g_hDB, "EmptyCallback", q);

    LoadBank();
}

public EmptyCallback(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt) { }

LoadBank() {
    if(!g_bDBConnected) return;
    new q[128];
    formatex(q, charsmax(q), "SELECT value FROM server_data WHERE key='bank'");
    SQL_ThreadQuery(g_hDB, "LoadBankCB", q);
}

public LoadBankCB(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt) {
    if(FailState != TQUERY_SUCCESS || SQL_NumResults(Q) == 0) {
        g_iBank = 0;
        return;
    }
    g_iBank = SQL_ReadResult(Q, 0);
}

UpdateBank() {
    if(!g_bDBConnected) return;
    new q[256];
    formatex(q, charsmax(q), "UPDATE server_data SET value=%d WHERE key='bank'", g_iBank);
    SQL_ThreadQuery(g_hDB, "EmptyCallback", q);
}

// ---------- Игроки ----------
public client_putinserver(id) {
    ResetPlayerBet(id);
    g_bPlayerDisconnected[id] = false;
    g_bAutoMenuShown[id] = false;
    
    points_load(id);
}

public client_disconnected(id) {
    if(g_iBetAmount[id] > 0) {
        g_bPlayerDisconnected[id] = true;
    }
}

ResetPlayerBet(id) {
    g_iBetAmount[id] = 0;
    g_iBetTarget[id] = -1;
    g_bPlayerDisconnected[id] = false;
}

// ---------- Определение дуэли ----------
public Ham_PlayerKilled_Post(victim, killer, shouldgib) {
    if(g_bDuelActive) {
        if(victim == g_iFighterCT || victim == g_iFighterTT) {
            new winner;
            if(is_user_alive(g_iFighterCT) && g_iFighterCT != victim)
                winner = g_iFighterCT;
            else if(is_user_alive(g_iFighterTT) && g_iFighterTT != victim)
                winner = g_iFighterTT;
            else
                winner = killer;
            EndDuel(winner);
        }
        return;
    }

    CheckAndStartDuel();
}

public CheckAndStartDuel() {
    if(g_bDuelActive) return;

    new iCT = 0, iTT = 0;
    new iCTIndex = 0, iTTIndex = 0;
    new szTeam[32];
    new max_players = get_maxplayers();
    new szName1[32], szName2[32];
    
    for(new i = 1; i <= max_players; i++) {
        if(!is_user_alive(i)) continue;
        get_user_team(i, szTeam, charsmax(szTeam));
        if(equal(szTeam, "CT")) {
            iCT++;
            iCTIndex = i;
        } else if(equal(szTeam, "TERRORIST")) {
            iTT++;
            iTTIndex = i;
        }
    }

    if(iCT == 1 && iTT == 1) {
        g_iFighterCT = iCTIndex;
        g_iFighterTT = iTTIndex;
        g_bDuelActive = true;
        g_bBettingOpen = true;
        g_iTotalBet[0] = 0;
        g_iTotalBet[1] = 0;
        
        for(new i = 1; i <= max_players; i++) {
            ResetPlayerBet(i);
            g_bAutoMenuShown[i] = false;
        }

        get_user_name(g_iFighterCT, szName1, charsmax(szName1));
        get_user_name(g_iFighterTT, szName2, charsmax(szName2));
        client_print(0, print_chat, "[DUEL] %s (CT) vs %s (TT)! Ставки принимаются %d секунд.", szName1, szName2, g_iBetTime);

        for(new i = 1; i <= max_players; i++) {
            if(!is_user_connected(i)) continue;
            if(i == g_iFighterCT || i == g_iFighterTT) continue;
            if(points_get(i) >= floatround(g_fMinBet)) {
                ShowBetChoiceMenu(i);
                g_bAutoMenuShown[i] = true;
            }
        }

        g_iDuelTask = set_task(float(g_iBetTime), "CloseBetting");
    }
}

public CloseBetting() {
    g_bBettingOpen = false;
    PrintBetSummary();
    client_print(0, print_chat, "[DUEL] Приём ставок окончен. Бой начинается!");

    if(!is_user_alive(g_iFighterCT) || !is_user_alive(g_iFighterTT)) {
        new winner = is_user_alive(g_iFighterCT) ? g_iFighterCT : g_iFighterTT;
        EndDuel(winner);
    }
}

PrintBetSummary() {
    client_print(0, print_chat, "=========================================");
    client_print(0, print_chat, "[СТАВКИ] Итоги приёма ставок:");
    
    new szName1[32], szName2[32];
    get_user_name(g_iFighterCT, szName1, charsmax(szName1));
    get_user_name(g_iFighterTT, szName2, charsmax(szName2));
    
    client_print(0, print_chat, "[СТАВКИ] На %s (CT): %d очков", szName1, g_iTotalBet[0]);
    client_print(0, print_chat, "[СТАВКИ] На %s (TT): %d очков", szName2, g_iTotalBet[1]);
    client_print(0, print_chat, "-----------------------------------------");
    
    new max_players = get_maxplayers();
    new bHasBets = false;
    for(new i = 1; i <= max_players; i++) {
        if(g_iBetAmount[i] > 0) {
            new szPlayer[32], szFighter[32];
            get_user_name(i, szPlayer, charsmax(szPlayer));
            get_user_name((g_iBetTarget[i] == 0) ? g_iFighterCT : g_iFighterTT, szFighter, charsmax(szFighter));
            client_print(0, print_chat, "[СТАВКИ] %s -> %d на %s", szPlayer, g_iBetAmount[i], szFighter);
            bHasBets = true;
        }
    }
    
    if(!bHasBets) {
        client_print(0, print_chat, "[СТАВКИ] Никто не сделал ставку.");
    }
    client_print(0, print_chat, "=========================================");
}

// ---------- Завершение дуэли и распределение ----------
EndDuel(winner) {
    if(!g_bDuelActive) return;

    if(g_iDuelTask) {
        remove_task(g_iDuelTask);
        g_iDuelTask = 0;
    }

    new iWinnerSide = (winner == g_iFighterCT) ? 0 : 1;
    new iLoserSide = 1 - iWinnerSide;

    new Float:fWinTotal = float(g_iTotalBet[iWinnerSide]);
    new Float:fLoseTotal = float(g_iTotalBet[iLoserSide]);

    if(fWinTotal == 0.0) {
        new max_players = get_maxplayers();
        for(new i = 1; i <= max_players; i++) {
            if(g_iBetAmount[i] > 0) {
                points_set(i, points_get(i) + g_iBetAmount[i]);
                ResetPlayerBet(i);
            }
        }
        client_print(0, print_chat, "[DUEL] На победителя не было ставок. Все ставки возвращены.");
        CleanupDuelState();
        return;
    }

    new Float:fCommission = g_fCommission / 100.0;
    new Float:fLoseAfterComm = fLoseTotal * (1.0 - fCommission);
    new iCommissionAmount = floatround(fLoseTotal - fLoseAfterComm);
    
    if(iCommissionAmount > 0) {
        g_iBank += iCommissionAmount;
        UpdateBank();
        client_print(0, print_chat, "[DUEL] Комиссия сервера: %d очков", iCommissionAmount);
    }

    new iTotalPaid = 0;
    new max_players = get_maxplayers();
    for(new i = 1; i <= max_players; i++) {
        if(g_iBetAmount[i] == 0) continue;
        
        if(g_iBetTarget[i] == iWinnerSide) {
            new Float:fBet = float(g_iBetAmount[i]);
            new Float:fCoeff = 1.0 + (fLoseAfterComm / fWinTotal);
            if(g_fMaxCoef > 0.0 && fCoeff > g_fMaxCoef) {
                fCoeff = g_fMaxCoef;
            }
            new iWin = floatround(fBet * fCoeff);
            if(iWin < 0) iWin = 0;

            points_set(i, points_get(i) + iWin);
            iTotalPaid += iWin;

            if(is_user_connected(i)) {
                client_print(i, print_chat, "[DUEL] Вы выиграли %d очков (ставка %d)", iWin, g_iBetAmount[i]);
            }
        } else {
            if(is_user_connected(i)) {
                client_print(i, print_chat, "[DUEL] Ваша ставка проиграла.");
            }
        }
        ResetPlayerBet(i);
    }

    new iRemain = g_iTotalBet[iWinnerSide] + floatround(fLoseAfterComm) - iTotalPaid;
    if(iRemain > 0) {
        g_iBank += iRemain;
        UpdateBank();
    }

    new szWinnerName[32];
    get_user_name(winner, szWinnerName, charsmax(szWinnerName));
    client_print(0, print_chat, "[DUEL] Победил %s! Выигрыши выплачены.", szWinnerName);
    
    CleanupDuelState();
}

public Event_HLTV_RoundEnd() {
    if(!g_bDuelActive) return;

    new winner = 0;
    new bool:bCTAlive = is_user_alive(g_iFighterCT);
    new bool:bTTAlive = is_user_alive(g_iFighterTT);

    if(bCTAlive && !bTTAlive) {
        winner = g_iFighterCT;
    } else if(bTTAlive && !bCTAlive) {
        winner = g_iFighterTT;
    } else {
        new max_players = get_maxplayers();
        for(new i = 1; i <= max_players; i++) {
            if(g_iBetAmount[i] > 0) {
                points_set(i, points_get(i) + g_iBetAmount[i]);
                ResetPlayerBet(i);
            }
        }
        client_print(0, print_chat, "[DUEL] Раунд завершился вничью. Все ставки возвращены.");
        CleanupDuelState();
        return;
    }

    EndDuel(winner);
}

CleanupDuelState() {
    g_bDuelActive = false;
    g_bBettingOpen = false;
    g_iTotalBet[0] = 0;
    g_iTotalBet[1] = 0;
    if(g_iDuelTask) {
        remove_task(g_iDuelTask);
        g_iDuelTask = 0;
    }
    new max_players = get_maxplayers();
    for(new i = 1; i <= max_players; i++) {
        g_bAutoMenuShown[i] = false;
    }
}

// ---------- Команды игроков ----------
public Cmd_Bet(id) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED;
    if(!g_bBettingOpen) {
        client_print(id, print_chat, "[DUEL] Приём ставок закрыт или дуэль не активна.");
        return PLUGIN_HANDLED;
    }
    if(id == g_iFighterCT || id == g_iFighterTT) {
        client_print(id, print_chat, "[DUEL] Бойцы не могут делать ставки.");
        return PLUGIN_HANDLED;
    }
    if(g_iBetAmount[id] > 0) {
        client_print(id, print_chat, "[DUEL] Вы уже сделали ставку.");
        return PLUGIN_HANDLED;
    }
    ShowBetChoiceMenu(id);
    return PLUGIN_HANDLED;
}

ShowBetChoiceMenu(id) {
    if(id == g_iFighterCT || id == g_iFighterTT) {
        client_print(id, print_chat, "[DUEL] Бойцы не могут делать ставки.");
        return;
    }
    
    new menu = menu_create("\yВыберите бойца:", "BetChoiceHandler");
    new szName1[32], szName2[32], szItem[128];
    get_user_name(g_iFighterCT, szName1, charsmax(szName1));
    get_user_name(g_iFighterTT, szName2, charsmax(szName2));

    formatex(szItem, charsmax(szItem), "%s (CT) [банк: %d]", szName1, g_iTotalBet[0]);
    menu_additem(menu, szItem, "0");
    formatex(szItem, charsmax(szItem), "%s (TT) [банк: %d]", szName2, g_iTotalBet[1]);
    menu_additem(menu, szItem, "1");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public BetChoiceHandler(id, menu, item) {
    if(item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    new szInfo[2];
    menu_item_getinfo(menu, item, _, szInfo, charsmax(szInfo), _, _, _);
    new iTarget = str_to_num(szInfo);
    menu_destroy(menu);
    g_iBetTarget[id] = iTarget;

    ShowBetAmountMenu(id);
    return PLUGIN_HANDLED;
}

ShowBetAmountMenu(id) {
    new menu = menu_create("\yСумма ставки:", "BetAmountHandler");
    new iMin = floatround(g_fMinBet);
    new iMax = floatround(g_fMaxBet);
    new iAmounts[8] = {10, 50, 100, 500, 1000, 5000, 10000};
    new szInfo[16], szItem[64];
    
    for(new i = 0; i < sizeof(iAmounts); i++) {
        if(iAmounts[i] < iMin || iAmounts[i] > iMax) continue;
        num_to_str(iAmounts[i], szInfo, charsmax(szInfo));
        formatex(szItem, charsmax(szItem), "%d", iAmounts[i]);
        menu_additem(menu, szItem, szInfo);
    }
    menu_additem(menu, "Своя сумма", "custom");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public BetAmountHandler(id, menu, item) {
    if(item == MENU_EXIT) {
        menu_destroy(menu);
        g_iBetTarget[id] = -1;
        return PLUGIN_HANDLED;
    }
    new szInfo[16];
    menu_item_getinfo(menu, item, _, szInfo, charsmax(szInfo), _, _, _);
    menu_destroy(menu);

    if(equal(szInfo, "custom")) {
        client_print(id, print_chat, "[DUEL] Введите сумму (целое число) в чат:");
        client_cmd(id, "messagemode bet_custom");
        return PLUGIN_HANDLED;
    }

    new iAmount = str_to_num(szInfo);
    ProcessBet(id, iAmount);
    return PLUGIN_HANDLED;
}

public Cmd_CustomBet(id) {
    if(!g_bBettingOpen || g_iBetTarget[id] == -1 || g_iBetAmount[id] > 0) 
        return PLUGIN_HANDLED;
    
    new arg[32];
    read_argv(1, arg, charsmax(arg));
    replace_string(arg, charsmax(arg), "^"", "");  
    new iAmount = str_to_num(arg);
    if(iAmount > 0) {
        ProcessBet(id, iAmount);
    } else {
        client_print(id, print_chat, "[DUEL] Некорректная сумма. Попробуйте снова.");
        ShowBetAmountMenu(id);
    }
    return PLUGIN_HANDLED;
}

ProcessBet(id, iAmount) {
    if(!g_bBettingOpen) {
        client_print(id, print_chat, "[DUEL] Приём ставок уже закрыт.");
        ResetPlayerBet(id);
        return;
    }
    
    if(!points_is_loaded(id)) {
        client_print(id, print_chat, "[DUEL] Данные об очках ещё загружаются, подождите...");
        ResetPlayerBet(id);
        return;
    }

    if(iAmount < floatround(g_fMinBet)) {
        client_print(id, print_chat, "[DUEL] Минимальная ставка: %d", floatround(g_fMinBet));
        ResetPlayerBet(id);
        return;
    }
    if(iAmount > floatround(g_fMaxBet)) {
        client_print(id, print_chat, "[DUEL] Максимальная ставка: %d", floatround(g_fMaxBet));
        ResetPlayerBet(id);
        return;
    }
    
    new current_points = points_get(id);
    if(current_points < iAmount) {
        client_print(id, print_chat, "[DUEL] Недостаточно очков. У вас: %d", current_points);
        ResetPlayerBet(id);
        return;
    }

    points_set(id, current_points - iAmount);

    g_iBetAmount[id] = iAmount;
    new iTarget = g_iBetTarget[id];
    g_iTotalBet[iTarget] += iAmount;

    new szName[32], szFighter[32];
    get_user_name(id, szName, charsmax(szName));
    get_user_name((iTarget == 0) ? g_iFighterCT : g_iFighterTT, szFighter, charsmax(szFighter));
    client_print(id, print_chat, "[DUEL] Вы поставили %d очков на %s", iAmount, szFighter);
    client_print(0, print_chat, "[DUEL] %s поставил %d очков на %s", szName, iAmount, szFighter);
}

// ---------- Команда просмотра банка ----------
public Cmd_Bank(id) {
    client_print(id, print_chat, "[BANK] Банк сервера: %d очков", g_iBank);
    return PLUGIN_HANDLED;
}

// ---------- Админ-команда сброса банка ----------
public Cmd_BankReset(id, level, cid) {
    if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    g_iBank = 0;
    UpdateBank();
    console_print(id, "[BANK] Банк сервера обнулён.");
    client_print(0, print_chat, "[BANK] Банк сервера обнулён администратором.");
    return PLUGIN_HANDLED;
}