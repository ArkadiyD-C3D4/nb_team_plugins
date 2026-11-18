#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <sqlx>
#include <fakemeta>

new const VERSION[] = "2.6.0";
new const PREFIX[] = "[SKILLS]";

// Нативы из points_core — очки хранятся и управляются там
native points_get(id);
native points_set(id, amount);
native points_is_loaded(id);

#define KEY_1 (1<<0)
#define KEY_2 (1<<1)
#define KEY_3 (1<<2)
#define KEY_4 (1<<3)
#define KEY_5 (1<<4)
#define KEY_6 (1<<5)
#define KEY_9 (1<<8)
#define KEY_0 (1<<9)
#define KEYS_ALL 1023

new const MENU_MAIN[] = "SkillsMainMenu";
new const MENU_JUMP[] = "SkillsJumpMenu";
new const MENU_HEALTH[] = "SkillsHealthMenu";
new const MENU_DROP[] = "SkillsDropMenu";
new const MENU_VAMP[] = "SkillsVampMenu";
new const MENU_MULT[] = "SkillsMultMenu";
new const MENU_AMMO[] = "SkillsAmmoMenu";

new Handle:g_hDB;
new bool:g_bDBConnected = false;

new g_szMainMenuCmd[64]; // команда возврата в главное меню (из menuSystem.ini)

new g_iPlayerJumpLevel[33];
new g_iPlayerHealthLevel[33];
new g_iPlayerDropLevel[33];
new g_iPlayerVampLevel[33];
new g_iPlayerMultiplierLevel[33];
new g_iPlayerAmmoLevel[33];

// === ДОПОЛНИТЕЛЬНЫЕ УРОВНИ (Не сохраняются в БД, по умолчанию 0) ===
new g_iPlayerExtraJumpLevel[33];
new g_iPlayerExtraHealthLevel[33];
new g_iPlayerExtraDropLevel[33];
new g_iPlayerExtraVampLevel[33];
new g_iPlayerExtraMultiplierLevel[33];
new g_iPlayerExtraAmmoLevel[33];

new g_szPlayerAuth[33][35];
new bool:g_bPlayerLoaded[33];
new bool:g_bPlayerQueued[33];

// Состояние меню: 0 - закрыто, 1 - главное, 2 - прыжок, 3 - здоровье, 4 - дроп, 5 - вампиризм, 6 - множитель, 7 - патроны
new g_iPlayerMenuState[33];

new g_iMaxPlayers;

new g_iMaxJumpLevel;
new g_iJumpCostBase;
new g_iJumpCostIncrement;

new g_iMaxHealthLevel;
new g_iHealthCostBase;
new g_iHealthCostIncrement;
new g_iHealthPerLevel;

new g_iMaxDropLevel;
new g_iDropCostBase;
new g_iDropCostIncrement;
new g_iDropChanceBase;
new g_iDropChancePerLevel;

new g_iMaxVampLevel;
new g_iVampCostBase;
new g_iVampCostIncrement;
new g_iVampHPPerLevel;

new g_iMaxMultiplierLevel;
new g_iMultiplierCostBase;
new g_iMultiplierCostIncrement;
new g_iMultiplierPointsPerLevel;

new g_iMaxAmmoLevel;
new g_iAmmoCostBase;
new g_iAmmoCostIncrement;
new g_iAmmoPercentPerLevel;

public plugin_init() {
    register_plugin("Skills System", VERSION, "nb_team");
    
    register_clcmd("say /skills", "Cmd_Skills");
    register_clcmd("say_team /skills", "Cmd_Skills");
    register_clcmd("amx_skills", "Cmd_Skills");
    
    // === АДМИН КОМАНДЫ ДЛЯ ВЫДАЧИ ДОП. УРОВНЕЙ (Флаг t - ADMIN_LEVEL_H) ===
    register_concmd("amx_addhealth", "Cmd_AddExtraHealth", ADMIN_LEVEL_H, "<ник> <уровень> - выдать доп. уровень здоровья");
    register_concmd("amx_adddrop", "Cmd_AddExtraDrop", ADMIN_LEVEL_H, "<ник> <уровень> - выдать доп. уровень шанса дропа");
    register_concmd("amx_addvamp", "Cmd_AddExtraVamp", ADMIN_LEVEL_H, "<ник> <уровень> - выдать доп. уровень вампиризма");
    register_concmd("amx_addmult", "Cmd_AddExtraMult", ADMIN_LEVEL_H, "<ник> <уровень> - выдать доп. уровень множителя");
    register_concmd("amx_addammo", "Cmd_AddExtraAmmo", ADMIN_LEVEL_H, "<ник> <уровень> - выдать доп. уровень патронов");
    
    RegisterHookChain(RG_CBasePlayer_Spawn, "CBasePlayer_Spawn_Post", 1);
    RegisterHookChain(RG_CBasePlayer_Killed, "CBasePlayer_Killed_Post", 1);
    register_event("DeathMsg", "Event_DeathMsg", "a");
    
    register_menucmd(register_menuid(MENU_MAIN), KEYS_ALL, "Handle_MainMenu");
    register_menucmd(register_menuid(MENU_JUMP), KEYS_ALL, "Handle_JumpMenu");
    register_menucmd(register_menuid(MENU_HEALTH), KEYS_ALL, "Handle_HealthMenu");
    register_menucmd(register_menuid(MENU_DROP), KEYS_ALL, "Handle_DropMenu");
    register_menucmd(register_menuid(MENU_VAMP), KEYS_ALL, "Handle_VampMenu");
    register_menucmd(register_menuid(MENU_MULT), KEYS_ALL, "Handle_MultMenu");
    register_menucmd(register_menuid(MENU_AMMO), KEYS_ALL, "Handle_AmmoMenu");
    
    g_iMaxPlayers = get_member_game(m_nMaxPlayers);
    
    LoadConfig();
    LoadMenuSystemConfig();
}

public plugin_cfg() {
    set_task(3.0, "InitDatabase");
}

public plugin_end() {
    if(g_hDB != Empty_Handle) {
        SQL_FreeHandle(g_hDB);
        g_hDB = Empty_Handle;
    }
}

public plugin_natives() {
    register_native("sk_GetPlayerJumpLevel", "Native_GetPlayerJumpLevel");
    register_native("sk_GetPlayerHealthLevel", "Native_GetPlayerHealthLevel");
    register_native("sk_GetPlayerDropLevel", "Native_GetPlayerDropLevel");
    register_native("sk_GetPlayerVampLevel", "Native_GetPlayerVampLevel");
    register_native("sk_GetPlayerMultiplierLevel", "Native_GetPlayerMultiplierLevel");
    register_native("sk_GetPlayerAmmoLevel", "Native_GetPlayerAmmoLevel");
    
    register_native("sk_UpgradeJumpSkill", "Native_UpgradeJumpSkill");
    register_native("sk_UpgradeHealthSkill", "Native_UpgradeHealthSkill");
    register_native("sk_UpgradeDropSkill", "Native_UpgradeDropSkill");
    register_native("sk_UpgradeVampSkill", "Native_UpgradeVampSkill");
    register_native("sk_UpgradeMultiplierSkill", "Native_UpgradeMultiplierSkill");
    register_native("sk_UpgradeAmmoSkill", "Native_UpgradeAmmoSkill");
    
    register_native("sk_GetJumpSkillCost", "Native_GetJumpSkillCost");
    register_native("sk_GetHealthSkillCost", "Native_GetHealthSkillCost");
    register_native("sk_GetDropSkillCost", "Native_GetDropSkillCost");
    register_native("sk_GetVampSkillCost", "Native_GetVampSkillCost");
    register_native("sk_GetMultiplierSkillCost", "Native_GetMultiplierSkillCost");
    register_native("sk_GetAmmoSkillCost", "Native_GetAmmoSkillCost");

    // === НАТИВЫ ДЛЯ ДОП. УРОВНЕЙ ===
    register_native("sk_GetExtraJump", "Native_GetExtraJump");
    register_native("sk_GetExtraHealth", "Native_GetExtraHealth");
    register_native("sk_GetExtraDrop", "Native_GetExtraDrop");
    register_native("sk_GetExtraVamp", "Native_GetExtraVamp");
    register_native("sk_GetExtraMult", "Native_GetExtraMult");
    register_native("sk_GetExtraAmmo", "Native_GetExtraAmmo");

    register_native("sk_AddExtraJump", "Native_AddExtraJump");
    register_native("sk_AddExtraHealth", "Native_AddExtraHealth");
    register_native("sk_AddExtraDrop", "Native_AddExtraDrop");
    register_native("sk_AddExtraVamp", "Native_AddExtraVamp");
    register_native("sk_AddExtraMult", "Native_AddExtraMult");
    register_native("sk_AddExtraAmmo", "Native_AddExtraAmmo");

    register_native("sk_TakeExtraJump", "Native_TakeExtraJump");
    register_native("sk_TakeExtraHealth", "Native_TakeExtraHealth");
    register_native("sk_TakeExtraDrop", "Native_TakeExtraDrop");
    register_native("sk_TakeExtraVamp", "Native_TakeExtraVamp");
    register_native("sk_TakeExtraMult", "Native_TakeExtraMult");
    register_native("sk_TakeExtraAmmo", "Native_TakeExtraAmmo");
}

/* ============================================
   DATABASE
   ============================================ */

public InitDatabase() {
    if(g_hDB != Empty_Handle) {
        SQL_FreeHandle(g_hDB);
        g_hDB = Empty_Handle;
    }
    
    new h[64], u[64], p[64], d[64];
    get_cvar_string("amx_sql_host", h, 63);
    get_cvar_string("amx_sql_user", u, 63);
    get_cvar_string("amx_sql_pass", p, 63);
    get_cvar_string("amx_sql_db", d, 63);
    
    g_hDB = SQL_MakeDbTuple(h, u, p, d);
    
    new err[256], errCode;
    new Handle:hTest = SQL_Connect(g_hDB, errCode, err, charsmax(err));
    
    if(hTest == Empty_Handle) {
        log_amx("%s Ошибка подключения к БД: %s. Повтор через 10 сек...", PREFIX, err);
        g_bDBConnected = false;
        set_task(10.0, "InitDatabase");
        ProcessQueue(false);
        return;
    }
    
    SQL_FreeHandle(hTest);
    g_bDBConnected = true;
    log_amx("%s База данных подключена.", PREFIX);
    
    CreateTables();
    ProcessQueue(true);
}

public CreateTables() {
    new szQuery[512];
    
    formatex(szQuery, charsmax(szQuery), 
        "CREATE TABLE IF NOT EXISTS player_skills (authid VARCHAR(32) PRIMARY KEY, jump_level INT DEFAULT 0, health_level INT DEFAULT 0, drop_level INT DEFAULT 0, vamp_level INT DEFAULT 0, multiplier_level INT DEFAULT 0, ammo_level INT DEFAULT 0)");
    SQL_ThreadQuery(g_hDB, "Query_Void", szQuery);
    
    formatex(szQuery, charsmax(szQuery), "ALTER TABLE player_skills ADD COLUMN health_level INT DEFAULT 0");
    SQL_ThreadQuery(g_hDB, "Query_Void", szQuery);
    
    formatex(szQuery, charsmax(szQuery), "ALTER TABLE player_skills ADD COLUMN drop_level INT DEFAULT 0");
    SQL_ThreadQuery(g_hDB, "Query_Void", szQuery);
    
    formatex(szQuery, charsmax(szQuery), "ALTER TABLE player_skills ADD COLUMN vamp_level INT DEFAULT 0");
    SQL_ThreadQuery(g_hDB, "Query_Void", szQuery);
    
    formatex(szQuery, charsmax(szQuery), "ALTER TABLE player_skills ADD COLUMN multiplier_level INT DEFAULT 0");
    SQL_ThreadQuery(g_hDB, "Query_Void", szQuery);

    formatex(szQuery, charsmax(szQuery), "ALTER TABLE player_skills ADD COLUMN ammo_level INT DEFAULT 0");
    SQL_ThreadQuery(g_hDB, "Query_Void", szQuery);
}

ProcessQueue(bool:success) {
    for(new i = 1; i <= 32; i++) {
        if(g_bPlayerQueued[i] && is_user_connected(i)) {
            g_bPlayerQueued[i] = false;
            if(success && g_szPlayerAuth[i][0]) {
                CreatePlayerRecord(i);
                LoadPlayerSkills(i);
            } else {
                g_bPlayerLoaded[i] = true;
            }
        }
    }
}

public Query_Void(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt) {
    if(FailState != TQUERY_SUCCESS) {
        log_amx("%s Ошибка БД: %s", PREFIX, Error);
    }
}

/* ============================================
   CLIENT
   ============================================ */

public client_putinserver(id) {
    g_iPlayerJumpLevel[id] = 0;
    g_iPlayerHealthLevel[id] = 0;
    g_iPlayerDropLevel[id] = 0;
    g_iPlayerVampLevel[id] = 0;
    g_iPlayerMultiplierLevel[id] = 0;
    g_iPlayerAmmoLevel[id] = 0;
    
    // Сброс доп. уровней при входе
    g_iPlayerExtraJumpLevel[id] = 0;
    g_iPlayerExtraHealthLevel[id] = 0;
    g_iPlayerExtraDropLevel[id] = 0;
    g_iPlayerExtraVampLevel[id] = 0;
    g_iPlayerExtraMultiplierLevel[id] = 0;
    g_iPlayerExtraAmmoLevel[id] = 0;
    
    g_iPlayerMenuState[id] = 0;
    g_bPlayerLoaded[id] = false;
    g_bPlayerQueued[id] = false;
    g_szPlayerAuth[id][0] = 0;
    
    if(is_user_bot(id) || is_user_hltv(id)) {
        g_bPlayerLoaded[id] = true;
        return;
    }
    
    get_user_authid(id, g_szPlayerAuth[id], charsmax(g_szPlayerAuth[]));
    
    if(!g_szPlayerAuth[id][0] || equali(g_szPlayerAuth[id], "STEAM_ID_PENDING")) {
        g_szPlayerAuth[id][0] = 0;
        g_bPlayerLoaded[id] = true;
        return;
    }
    
    if(g_bDBConnected)
        LoadPlayerSkills(id);
    else
        g_bPlayerQueued[id] = true;
}

public client_disconnected(id) {
    if(g_szPlayerAuth[id][0] && g_bDBConnected && g_bPlayerLoaded[id]) {
        SavePlayerSkills(id);
    }
    
    g_bPlayerLoaded[id] = false;
    g_bPlayerQueued[id] = false;
    g_szPlayerAuth[id][0] = 0;
    g_iPlayerMenuState[id] = 0;
}

/* ============================================
   DB OPERATIONS
   ============================================ */

public CreatePlayerRecord(id) {
    if(!g_szPlayerAuth[id][0] || !g_bDBConnected) return;
    
    new szSafe[48], szQuery[512];
    copy(szSafe, charsmax(szSafe), g_szPlayerAuth[id]);
    replace_all(szSafe, charsmax(szSafe), "'", "''");
    
    formatex(szQuery, charsmax(szQuery), 
        "INSERT IGNORE INTO player_skills (authid, jump_level, health_level, drop_level, vamp_level, multiplier_level, ammo_level) VALUES ('%s', 0, 0, 0, 0, 0, 0)", szSafe);
    SQL_ThreadQuery(g_hDB, "Query_Void", szQuery);
}

public LoadPlayerSkills(id) {
    if(!g_szPlayerAuth[id][0]) {
        g_bPlayerLoaded[id] = true;
        return;
    }
    
    new szSafe[48], szQuery[512], iData[1];
    iData[0] = id;
    
    copy(szSafe, charsmax(szSafe), g_szPlayerAuth[id]);
    replace_all(szSafe, charsmax(szSafe), "'", "''");
    
    formatex(szQuery, charsmax(szQuery), 
        "SELECT jump_level, health_level, drop_level, vamp_level, multiplier_level, ammo_level FROM player_skills WHERE authid='%s'", 
        szSafe);
    SQL_ThreadQuery(g_hDB, "LoadPlayerSkillsCB", szQuery, iData, 1);
}

public LoadPlayerSkillsCB(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt) {
    new id = Data[0];
    if(!is_user_connected(id)) return;
    
    if(FailState != TQUERY_SUCCESS) {
        log_amx("%s Ошибка загрузки навыков: %s", PREFIX, Error);
        g_bPlayerLoaded[id] = true;
        return;
    }
    
    if(SQL_NumResults(Q) > 0) {
        g_iPlayerJumpLevel[id] = SQL_ReadResult(Q, 0);
        g_iPlayerHealthLevel[id] = SQL_ReadResult(Q, 1);
        g_iPlayerDropLevel[id] = SQL_ReadResult(Q, 2);
        g_iPlayerVampLevel[id] = SQL_ReadResult(Q, 3);
        g_iPlayerMultiplierLevel[id] = SQL_ReadResult(Q, 4);
        g_iPlayerAmmoLevel[id] = SQL_ReadResult(Q, 5);
    } else {
        CreatePlayerRecord(id);
    }
    
    g_bPlayerLoaded[id] = true;
}

public SavePlayerSkills(id) {
    if(!g_szPlayerAuth[id][0] || !g_bDBConnected) return;
    
    new szSafe[48], szQuery[512];
    copy(szSafe, charsmax(szSafe), g_szPlayerAuth[id]);
    replace_all(szSafe, charsmax(szSafe), "'", "''");
    
    formatex(szQuery, charsmax(szQuery), 
        "REPLACE INTO player_skills (authid, jump_level, health_level, drop_level, vamp_level, multiplier_level, ammo_level) VALUES ('%s', %d, %d, %d, %d, %d, %d)", 
        szSafe, g_iPlayerJumpLevel[id], g_iPlayerHealthLevel[id], g_iPlayerDropLevel[id], g_iPlayerVampLevel[id], g_iPlayerMultiplierLevel[id], g_iPlayerAmmoLevel[id]);
    SQL_ThreadQuery(g_hDB, "Query_Void", szQuery);
}

/* ============================================
   GAME EVENTS
   ============================================ */

public CBasePlayer_Spawn_Post(id) {
    if(!is_user_alive(id)) return HC_CONTINUE;
    
    new iTotalHealthLevel = g_iPlayerHealthLevel[id] + g_iPlayerExtraHealthLevel[id];
    if(iTotalHealthLevel <= 0) return HC_CONTINUE;
    
    new iBonus = iTotalHealthLevel * g_iHealthPerLevel;
    new iNewHealth = 100 + iBonus;
    
    if(iNewHealth > 100) {
        set_pev(id, pev_max_health, float(iNewHealth));
        set_pev(id, pev_health, float(iNewHealth));
    }
    
    return HC_CONTINUE;
}

public CBasePlayer_Killed_Post(const victim, const killer, const iGib) {
    if(!(1 <= victim <= g_iMaxPlayers) || !(1 <= killer <= g_iMaxPlayers) || victim == killer)
        return HC_CONTINUE;
    
    if(!is_user_alive(killer))
        return HC_CONTINUE;
    
    new iTotalVampLevel = g_iPlayerVampLevel[killer] + g_iPlayerExtraVampLevel[killer];
    if(iTotalVampLevel <= 0)
        return HC_CONTINUE;
    
    new Float:flKillerHp = Float:get_entvar(killer, var_health);
    new Float:fMaxHP = Float:get_entvar(killer, var_max_health);
    
    if(fMaxHP <= 0.0)
        fMaxHP = 100.0;
    
    new iHeal = iTotalVampLevel * g_iVampHPPerLevel;
    flKillerHp += float(iHeal);
    
    if(flKillerHp > fMaxHP)
        flKillerHp = fMaxHP;
    
    set_entvar(killer, var_health, flKillerHp);
    
    return HC_CONTINUE;
}

public Event_DeathMsg() {
    new killer = read_data(1);
    new victim = read_data(2);
    
    if(!is_user_connected(killer) || killer == victim || !is_user_connected(victim)) 
        return;
    
    if(!g_bPlayerLoaded[killer] || !g_szPlayerAuth[killer][0])
        return;
    
    if(!points_is_loaded(killer))
        return;
    
    new iPointsReward = 0;

    // 1. Проверяем шанс дропа очков. Если он НЕ прокул - дропаем 0 очков.
    new iTotalDropLevel = g_iPlayerDropLevel[killer] + g_iPlayerExtraDropLevel[killer];
    new iChance = g_iDropChanceBase + (iTotalDropLevel * g_iDropChancePerLevel);
    if(iChance > 100) iChance = 100;
    
    if(random_num(1, 100) <= iChance) {
        // Шанс прокнул! Выдаем базовую награду за дроп (1 очко)
        iPointsReward = 1;
        
        // 2. Прибавляем бонус от множителя (1 уровень = +1 очко, 2 уровня = +2 очка и т.д.)
        new iTotalMultLevel = g_iPlayerMultiplierLevel[killer] + g_iPlayerExtraMultiplierLevel[killer];
        if(iTotalMultLevel > 0) {
            iPointsReward += (iTotalMultLevel * g_iMultiplierPointsPerLevel);
        }
    }

    // 3. Выдаем очки, если они больше 0
    if(iPointsReward > 0) {
        new iCurrent = points_get(killer);
        points_set(killer, iCurrent + iPointsReward);
    }

    // 4. Бонусные патроны в обойму за убийство (работает независимо от дропа очков)
    new iTotalAmmoLevel = g_iPlayerAmmoLevel[killer] + g_iPlayerExtraAmmoLevel[killer];
    if(iTotalAmmoLevel > 0) {
        new iActiveItem = get_member(killer, m_pActiveItem);
        if(iActiveItem > 0) {
            new WeaponIdType:wId = WeaponIdType:get_member(iActiveItem, m_iId);
            // Игнорируем нож и гранаты
            if(wId != WEAPON_NONE && wId != WEAPON_KNIFE && wId != WEAPON_HEGRENADE && wId != WEAPON_FLASHBANG && wId != WEAPON_SMOKEGRENADE) {
                new iMaxClip = rg_get_iteminfo(iActiveItem, ItemInfo_iMaxClip);
                if(iMaxClip > 0) {
                    new iBonusPercent = iTotalAmmoLevel * g_iAmmoPercentPerLevel;
                    new iBonusAmmo = (iMaxClip * iBonusPercent) / 100;
                    
                    if(iBonusAmmo > 0) {
                        new iCurrentClip = get_member(iActiveItem, m_Weapon_iClip);
                        new iNewClip = iCurrentClip + iBonusAmmo;
                        
                        // Не даем выйти за пределы максимальной обоймы
                        if(iNewClip > iMaxClip) iNewClip = iMaxClip;
                        
                        if(iNewClip > iCurrentClip) {
                            set_member(iActiveItem, m_Weapon_iClip, iNewClip);
                        }
                    }
                }
            }
        }
    }
}

/* ============================================
   COMMANDS & MENU
   ============================================ */

public Cmd_Skills(id) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED;
    DisplaySkillsMenu(id);
    return PLUGIN_HANDLED;
}

public ShowSkillsMenu(id) {
    if(!is_user_connected(id)) return;
    DisplaySkillsMenu(id);
}

public CloseSkillsMenu(id) {
    if(id < 1 || id > 32) return;
    
    if(is_user_connected(id)) {
        show_menu(id, 0, "^n", 1, MENU_MAIN);
    }
    
    g_iPlayerMenuState[id] = 0;
}

// Возврат в главное меню сервера (команда из menuSystem.ini, по умолчанию chooseteam)
public OpenServerMainMenu(id) {
    if(!is_user_connected(id)) return;
    
    g_iPlayerMenuState[id] = 0;
    client_cmd(id, g_szMainMenuCmd);
}

/* ============================================
   ADMINS COMMANDS (EXTRA LEVELS)
   ============================================ */

public Cmd_AddExtraHealth(id, level, cid) {
    if(!cmd_access(id, level, cid, 3)) return PLUGIN_HANDLED;
    
    new szArg[32], szLvl[10];
    read_argv(1, szArg, charsmax(szArg));
    read_argv(2, szLvl, charsmax(szLvl));
    
    new target = cmd_target(id, szArg, CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS);
    if(!target) return PLUGIN_HANDLED;
    
    g_iPlayerExtraHealthLevel[target] = max(0, str_to_num(szLvl));
    client_print(id, print_console, "%s Установлен доп. уровень здоровья (%d) для игрока %n", PREFIX, g_iPlayerExtraHealthLevel[target], target);
    client_print_color(target, print_team_default, "%s ^3Вам установлен доп. уровень здоровья: %d", PREFIX, g_iPlayerExtraHealthLevel[target]);
    RefreshSkillsMenu(target);
    
    return PLUGIN_HANDLED;
}

public Cmd_AddExtraDrop(id, level, cid) {
    if(!cmd_access(id, level, cid, 3)) return PLUGIN_HANDLED;
    
    new szArg[32], szLvl[10];
    read_argv(1, szArg, charsmax(szArg));
    read_argv(2, szLvl, charsmax(szLvl));
    
    new target = cmd_target(id, szArg, CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS);
    if(!target) return PLUGIN_HANDLED;
    
    g_iPlayerExtraDropLevel[target] = max(0, str_to_num(szLvl));
    client_print(id, print_console, "%s Установлен доп. уровень дропа (%d) для игрока %n", PREFIX, g_iPlayerExtraDropLevel[target], target);
    client_print_color(target, print_team_default, "%s ^3Вам установлен доп. уровень дропа: %d", PREFIX, g_iPlayerExtraDropLevel[target]);
    RefreshSkillsMenu(target);
    
    return PLUGIN_HANDLED;
}

public Cmd_AddExtraVamp(id, level, cid) {
    if(!cmd_access(id, level, cid, 3)) return PLUGIN_HANDLED;
    
    new szArg[32], szLvl[10];
    read_argv(1, szArg, charsmax(szArg));
    read_argv(2, szLvl, charsmax(szLvl));
    
    new target = cmd_target(id, szArg, CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS);
    if(!target) return PLUGIN_HANDLED;
    
    g_iPlayerExtraVampLevel[target] = max(0, str_to_num(szLvl));
    client_print(id, print_console, "%s Установлен доп. уровень вампиризма (%d) для игрока %n", PREFIX, g_iPlayerExtraVampLevel[target], target);
    client_print_color(target, print_team_default, "%s ^3Вам установлен доп. уровень вампиризма: %d", PREFIX, g_iPlayerExtraVampLevel[target]);
    RefreshSkillsMenu(target);
    
    return PLUGIN_HANDLED;
}

public Cmd_AddExtraMult(id, level, cid) {
    if(!cmd_access(id, level, cid, 3)) return PLUGIN_HANDLED;
    
    new szArg[32], szLvl[10];
    read_argv(1, szArg, charsmax(szArg));
    read_argv(2, szLvl, charsmax(szLvl));
    
    new target = cmd_target(id, szArg, CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS);
    if(!target) return PLUGIN_HANDLED;
    
    g_iPlayerExtraMultiplierLevel[target] = max(0, str_to_num(szLvl));
    client_print(id, print_console, "%s Установлен доп. уровень множителя (%d) для игрока %n", PREFIX, g_iPlayerExtraMultiplierLevel[target], target);
    client_print_color(target, print_team_default, "%s ^3Вам установлен доп. уровень множителя: %d", PREFIX, g_iPlayerExtraMultiplierLevel[target]);
    RefreshSkillsMenu(target);
    
    return PLUGIN_HANDLED;
}

public Cmd_AddExtraAmmo(id, level, cid) {
    if(!cmd_access(id, level, cid, 3)) return PLUGIN_HANDLED;
    
    new szArg[32], szLvl[10];
    read_argv(1, szArg, charsmax(szArg));
    read_argv(2, szLvl, charsmax(szLvl));
    
    new target = cmd_target(id, szArg, CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS);
    if(!target) return PLUGIN_HANDLED;
    
    g_iPlayerExtraAmmoLevel[target] = max(0, str_to_num(szLvl));
    client_print(id, print_console, "%s Установлен доп. уровень патронов (%d) для игрока %n", PREFIX, g_iPlayerExtraAmmoLevel[target], target);
    client_print_color(target, print_team_default, "%s ^3Вам установлен доп. уровень патронов: %d", PREFIX, g_iPlayerExtraAmmoLevel[target]);
    RefreshSkillsMenu(target);
    
    return PLUGIN_HANDLED;
}

/* ============================================
   NATIVES
   ============================================ */

public Native_GetPlayerJumpLevel(plugin, argc) {
    new id = get_param(1);
    return g_iPlayerJumpLevel[id] + g_iPlayerExtraJumpLevel[id];
}

public Native_GetPlayerHealthLevel(plugin, argc) {
    new id = get_param(1);
    return g_iPlayerHealthLevel[id];
}

public Native_GetPlayerDropLevel(plugin, argc) {
    new id = get_param(1);
    return g_iPlayerDropLevel[id];
}

public Native_GetPlayerVampLevel(plugin, argc) {
    new id = get_param(1);
    return g_iPlayerVampLevel[id];
}

public Native_GetPlayerMultiplierLevel(plugin, argc) {
    new id = get_param(1);
    return g_iPlayerMultiplierLevel[id];
}

public Native_GetPlayerAmmoLevel(plugin, argc) {
    new id = get_param(1);
    return g_iPlayerAmmoLevel[id];
}

public Native_UpgradeJumpSkill(plugin, argc) {
    new id = get_param(1);
    return sk_UpgradeJumpSkill(id);
}

public Native_UpgradeHealthSkill(plugin, argc) {
    new id = get_param(1);
    return sk_UpgradeHealthSkill(id);
}

public Native_UpgradeDropSkill(plugin, argc) {
    new id = get_param(1);
    return sk_UpgradeDropSkill(id);
}

public Native_UpgradeVampSkill(plugin, argc) {
    new id = get_param(1);
    return sk_UpgradeVampSkill(id);
}

public Native_UpgradeMultiplierSkill(plugin, argc) {
    new id = get_param(1);
    return sk_UpgradeMultiplierSkill(id);
}

public Native_UpgradeAmmoSkill(plugin, argc) {
    new id = get_param(1);
    return sk_UpgradeAmmoSkill(id);
}

public Native_GetJumpSkillCost(plugin, argc) {
    new level = get_param(1);
    return GetJumpSkillCost(level);
}

public Native_GetHealthSkillCost(plugin, argc) {
    new level = get_param(1);
    return GetHealthSkillCost(level);
}

public Native_GetDropSkillCost(plugin, argc) {
    new level = get_param(1);
    return GetDropSkillCost(level);
}

public Native_GetVampSkillCost(plugin, argc) {
    new level = get_param(1);
    return GetVampSkillCost(level);
}

public Native_GetMultiplierSkillCost(plugin, argc) {
    new level = get_param(1);
    return GetMultiplierSkillCost(level);
}

public Native_GetAmmoSkillCost(plugin, argc) {
    new level = get_param(1);
    return GetAmmoSkillCost(level);
}

// === НАТИВЫ ДОП. УРОВНЕЙ ===
public Native_GetExtraJump(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    return g_iPlayerExtraJumpLevel[id];
}

public Native_GetExtraHealth(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    return g_iPlayerExtraHealthLevel[id];
}

public Native_GetExtraDrop(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    return g_iPlayerExtraDropLevel[id];
}

public Native_GetExtraVamp(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    return g_iPlayerExtraVampLevel[id];
}

public Native_GetExtraMult(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    return g_iPlayerExtraMultiplierLevel[id];
}

public Native_GetExtraAmmo(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    return g_iPlayerExtraAmmoLevel[id];
}

public Native_AddExtraJump(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    
    new amount = get_param(2);
    g_iPlayerExtraJumpLevel[id] = max(0, g_iPlayerExtraJumpLevel[id] + amount);
    
    RefreshSkillsMenu(id);
    return g_iPlayerExtraJumpLevel[id];
}

public Native_AddExtraHealth(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    
    new amount = get_param(2);
    g_iPlayerExtraHealthLevel[id] = max(0, g_iPlayerExtraHealthLevel[id] + amount);
    
    RefreshSkillsMenu(id);
    return g_iPlayerExtraHealthLevel[id];
}

public Native_AddExtraDrop(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    
    new amount = get_param(2);
    g_iPlayerExtraDropLevel[id] = max(0, g_iPlayerExtraDropLevel[id] + amount);
    
    RefreshSkillsMenu(id);
    return g_iPlayerExtraDropLevel[id];
}

public Native_AddExtraVamp(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    
    new amount = get_param(2);
    g_iPlayerExtraVampLevel[id] = max(0, g_iPlayerExtraVampLevel[id] + amount);
    
    RefreshSkillsMenu(id);
    return g_iPlayerExtraVampLevel[id];
}

public Native_AddExtraMult(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    
    new amount = get_param(2);
    g_iPlayerExtraMultiplierLevel[id] = max(0, g_iPlayerExtraMultiplierLevel[id] + amount);
    
    RefreshSkillsMenu(id);
    return g_iPlayerExtraMultiplierLevel[id];
}

public Native_AddExtraAmmo(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    
    new amount = get_param(2);
    g_iPlayerExtraAmmoLevel[id] = max(0, g_iPlayerExtraAmmoLevel[id] + amount);
    
    RefreshSkillsMenu(id);
    return g_iPlayerExtraAmmoLevel[id];
}

public Native_TakeExtraJump(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    
    new amount = get_param(2);
    g_iPlayerExtraJumpLevel[id] = max(0, g_iPlayerExtraJumpLevel[id] - amount);
    
    RefreshSkillsMenu(id);
    return g_iPlayerExtraJumpLevel[id];
}

public Native_TakeExtraHealth(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    
    new amount = get_param(2);
    g_iPlayerExtraHealthLevel[id] = max(0, g_iPlayerExtraHealthLevel[id] - amount);
    
    RefreshSkillsMenu(id);
    return g_iPlayerExtraHealthLevel[id];
}

public Native_TakeExtraDrop(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    
    new amount = get_param(2);
    g_iPlayerExtraDropLevel[id] = max(0, g_iPlayerExtraDropLevel[id] - amount);
    
    RefreshSkillsMenu(id);
    return g_iPlayerExtraDropLevel[id];
}

public Native_TakeExtraVamp(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    
    new amount = get_param(2);
    g_iPlayerExtraVampLevel[id] = max(0, g_iPlayerExtraVampLevel[id] - amount);
    
    RefreshSkillsMenu(id);
    return g_iPlayerExtraVampLevel[id];
}

public Native_TakeExtraMult(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    
    new amount = get_param(2);
    g_iPlayerExtraMultiplierLevel[id] = max(0, g_iPlayerExtraMultiplierLevel[id] - amount);
    
    RefreshSkillsMenu(id);
    return g_iPlayerExtraMultiplierLevel[id];
}

public Native_TakeExtraAmmo(plugin, argc) {
    new id = get_param(1);
    if(!is_user_connected(id)) return 0;
    
    new amount = get_param(2);
    g_iPlayerExtraAmmoLevel[id] = max(0, g_iPlayerExtraAmmoLevel[id] - amount);
    
    RefreshSkillsMenu(id);
    return g_iPlayerExtraAmmoLevel[id];
}

public sk_UpgradeJumpSkill(player) {
    if(g_iPlayerJumpLevel[player] >= g_iMaxJumpLevel) return 0;
    if(!points_is_loaded(player)) return 0;
    
    new iCost = GetJumpSkillCost(g_iPlayerJumpLevel[player]);
    new iPoints = points_get(player);
    if(iPoints < iCost) return 0;
    
    points_set(player, iPoints - iCost);
    g_iPlayerJumpLevel[player]++;
    
    if(g_bDBConnected && g_szPlayerAuth[player][0])
        SavePlayerSkills(player);
    
    RefreshSkillsMenu(player);
    return 1;
}

public sk_UpgradeHealthSkill(player) {
    if(g_iPlayerHealthLevel[player] >= g_iMaxHealthLevel) return 0;
    if(!points_is_loaded(player)) return 0;
    
    new iCost = GetHealthSkillCost(g_iPlayerHealthLevel[player]);
    new iPoints = points_get(player);
    if(iPoints < iCost) return 0;
    
    points_set(player, iPoints - iCost);
    g_iPlayerHealthLevel[player]++;
    
    if(g_bDBConnected && g_szPlayerAuth[player][0])
        SavePlayerSkills(player);
    
    RefreshSkillsMenu(player);
    return 1;
}

public sk_UpgradeDropSkill(player) {
    if(g_iPlayerDropLevel[player] >= g_iMaxDropLevel) return 0;
    if(!points_is_loaded(player)) return 0;
    
    new iCost = GetDropSkillCost(g_iPlayerDropLevel[player]);
    new iPoints = points_get(player);
    if(iPoints < iCost) return 0;
    
    points_set(player, iPoints - iCost);
    g_iPlayerDropLevel[player]++;
    
    if(g_bDBConnected && g_szPlayerAuth[player][0])
        SavePlayerSkills(player);
    
    RefreshSkillsMenu(player);
    return 1;
}

public sk_UpgradeVampSkill(player) {
    if(g_iPlayerVampLevel[player] >= g_iMaxVampLevel) return 0;
    if(!points_is_loaded(player)) return 0;
    
    new iCost = GetVampSkillCost(g_iPlayerVampLevel[player]);
    new iPoints = points_get(player);
    if(iPoints < iCost) return 0;
    
    points_set(player, iPoints - iCost);
    g_iPlayerVampLevel[player]++;
    
    if(g_bDBConnected && g_szPlayerAuth[player][0])
        SavePlayerSkills(player);
    
    RefreshSkillsMenu(player);
    return 1;
}

public sk_UpgradeMultiplierSkill(player) {
    if(g_iPlayerMultiplierLevel[player] >= g_iMaxMultiplierLevel) return 0;
    if(!points_is_loaded(player)) return 0;
    
    new iCost = GetMultiplierSkillCost(g_iPlayerMultiplierLevel[player]);
    new iPoints = points_get(player);
    if(iPoints < iCost) return 0;
    
    points_set(player, iPoints - iCost);
    g_iPlayerMultiplierLevel[player]++;
    
    if(g_bDBConnected && g_szPlayerAuth[player][0])
        SavePlayerSkills(player);
    
    RefreshSkillsMenu(player);
    return 1;
}

public sk_UpgradeAmmoSkill(player) {
    if(g_iPlayerAmmoLevel[player] >= g_iMaxAmmoLevel) return 0;
    if(!points_is_loaded(player)) return 0;
    
    new iCost = GetAmmoSkillCost(g_iPlayerAmmoLevel[player]);
    new iPoints = points_get(player);
    if(iPoints < iCost) return 0;
    
    points_set(player, iPoints - iCost);
    g_iPlayerAmmoLevel[player]++;
    
    if(g_bDBConnected && g_szPlayerAuth[player][0])
        SavePlayerSkills(player);
    
    RefreshSkillsMenu(player);
    return 1;
}

public GetJumpSkillCost(iLevel) {
    return g_iJumpCostBase + (iLevel * g_iJumpCostIncrement);
}

public GetHealthSkillCost(iLevel) {
    return g_iHealthCostBase + (iLevel * g_iHealthCostIncrement);
}

public GetDropSkillCost(iLevel) {
    return g_iDropCostBase + (iLevel * g_iDropCostIncrement);
}

public GetVampSkillCost(iLevel) {
    return g_iVampCostBase + (iLevel * g_iVampCostIncrement);
}

public GetMultiplierSkillCost(iLevel) {
    return g_iMultiplierCostBase + (iLevel * g_iMultiplierCostIncrement);
}

public GetAmmoSkillCost(iLevel) {
    return g_iAmmoCostBase + (iLevel * g_iAmmoCostIncrement);
}

public GetDropChance(iLevel) {
    new iChance = g_iDropChanceBase + (iLevel * g_iDropChancePerLevel);
    return iChance > 100 ? 100 : iChance;
}

/* ============================================
   MENU REFRESH
   ============================================ */

public RefreshSkillsMenu(id) {
    if(!is_user_connected(id)) return;
    
    switch(g_iPlayerMenuState[id]) {
        case 1: DisplaySkillsMenu(id);
        case 2: DisplayJumpSkillMenu(id);
        case 3: DisplayHealthSkillMenu(id);
        case 4: DisplayDropSkillMenu(id);
        case 5: DisplayVampSkillMenu(id);
        case 6: DisplayMultiplierSkillMenu(id);
        case 7: DisplayAmmoSkillMenu(id);
    }
}

/* ============================================
   MAIN MENU (выбор навыка)
   ============================================ */

public DisplaySkillsMenu(id) {
    if(!is_user_connected(id)) return;
    
    new iPoints = points_is_loaded(id) ? points_get(id) : 0;
    new szMenu[1024];
    new len = 0;
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\yПрокачка навыков \r[%d очков]^n^n", iPoints);
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r1. \wПрыжок^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r2. \wЗдоровье^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r3. \wШанс дропа очков^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r4. \wВампиризм^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r5. \wМножитель очков^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r6. \wПатроны^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n\r9. \wНазад^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r0. \wВыход");
    
    new keys = KEY_1 | KEY_2 | KEY_3 | KEY_4 | KEY_5 | KEY_6 | KEY_9 | KEY_0;
    show_menu(id, keys, szMenu, -1, MENU_MAIN);
    
    g_iPlayerMenuState[id] = 1;
}

public Handle_MainMenu(id, key) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED;
    
    switch(key) {
        case 0: DisplayJumpSkillMenu(id);
        case 1: DisplayHealthSkillMenu(id);
        case 2: DisplayDropSkillMenu(id);
        case 3: DisplayVampSkillMenu(id);
        case 4: DisplayMultiplierSkillMenu(id);
        case 5: DisplayAmmoSkillMenu(id);
        case 8: OpenServerMainMenu(id); 
        case 9: CloseSkillsMenu(id);    
    }
    
    return PLUGIN_HANDLED;
}

/* ============================================
   JUMP MENU
   ============================================ */

public DisplayJumpSkillMenu(id) {
    if(!is_user_connected(id)) return;
    
    new iLevel = g_iPlayerJumpLevel[id];
    new iExtra = g_iPlayerExtraJumpLevel[id];
    new iCost = GetJumpSkillCost(iLevel);
    new iPoints = points_is_loaded(id) ? points_get(id) : 0;
    
    new bool:bMax = (iLevel >= g_iMaxJumpLevel);
    new bool:bCanUpgrade = (!bMax && iPoints >= iCost);
    
    new iTotalLevel = iLevel + iExtra;
    
    new szMenu[1024];
    new len = 0;
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\yПрыжок \r[%d очков]^n^n", iPoints);
    
    if(iExtra > 0) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wУровень: \r%d \w/ \r%d \y(Доп: +%d)^n", iLevel, g_iMaxJumpLevel, iExtra);
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wУровень: \r%d \w/ \r%d^n", iLevel, g_iMaxJumpLevel);
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\wЭффект: \r%d \wдоп. прыжков^n", iTotalLevel);
    
    if(!bMax) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wСтоимость: \r%d \wочков^n", iCost);
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n");
    
    if(bMax) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d1. МАКС. УРОВЕНЬ^n");
    } else if(bCanUpgrade) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r1. \wУлучшить^n");
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d1. Улучшить (недостаточно очков)^n");
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n\r9. \wНазад^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r0. \wВыход");
    
    new keys = KEY_9 | KEY_0;
    if(bCanUpgrade) keys |= KEY_1;
    
    show_menu(id, keys, szMenu, -1, MENU_JUMP);
    g_iPlayerMenuState[id] = 2;
}

public Handle_JumpMenu(id, key) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED;
    
    switch(key) {
        case 0: {
            if(sk_UpgradeJumpSkill(id)) {
                client_print_color(id, print_team_default, "%s ^3Прыжок улучшен до уровня %d!", PREFIX, g_iPlayerJumpLevel[id]);
            } else {
                if(g_iPlayerJumpLevel[id] >= g_iMaxJumpLevel) {
                    client_print_color(id, print_team_default, "%s ^3Достигнут максимальный уровень!", PREFIX);
                } else {
                    new iCost = GetJumpSkillCost(g_iPlayerJumpLevel[id]);
                    client_print_color(id, print_team_default, "%s ^3Недостаточно очков! Нужно %d очков.", PREFIX, iCost);
                }
                DisplayJumpSkillMenu(id);
            }
        }
        case 8: DisplaySkillsMenu(id);  
        case 9: CloseSkillsMenu(id);    
    }
    
    return PLUGIN_HANDLED;
}

/* ============================================
   HEALTH MENU
   ============================================ */

public DisplayHealthSkillMenu(id) {
    if(!is_user_connected(id)) return;
    
    new iLevel = g_iPlayerHealthLevel[id];
    new iExtra = g_iPlayerExtraHealthLevel[id];
    new iCost = GetHealthSkillCost(iLevel);
    new iPoints = points_is_loaded(id) ? points_get(id) : 0;
    
    new bool:bMax = (iLevel >= g_iMaxHealthLevel);
    new bool:bCanUpgrade = (!bMax && iPoints >= iCost);
    
    new iTotalLevel = iLevel + iExtra;
    new iBonus = iTotalLevel * g_iHealthPerLevel;
    new iMaxHP = 100 + iBonus;
    
    new szMenu[1024];
    new len = 0;
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\yЗдоровье \r[%d очков]^n^n", iPoints);
    
    if(iExtra > 0) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wУровень: \r%d \w/ \r%d \y(Доп: +%d)^n", iLevel, g_iMaxHealthLevel, iExtra);
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wУровень: \r%d \w/ \r%d^n", iLevel, g_iMaxHealthLevel);
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\wЭффект: +\r%d \wHP (Макс: \r%d)^n", iBonus, iMaxHP);
    
    if(!bMax) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wСтоимость: \r%d \wочков^n", iCost);
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n");
    
    if(bMax) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d1. МАКС. УРОВЕНЬ^n");
    } else if(bCanUpgrade) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r1. \wУлучшить^n");
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d1. Улучшить (недостаточно очков)^n");
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n\r9. \wНазад^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r0. \wВыход");
    
    new keys = KEY_9 | KEY_0;
    if(bCanUpgrade) keys |= KEY_1;
    
    show_menu(id, keys, szMenu, -1, MENU_HEALTH);
    g_iPlayerMenuState[id] = 3;
}

public Handle_HealthMenu(id, key) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED;
    
    switch(key) {
        case 0: {
            if(sk_UpgradeHealthSkill(id)) {
                client_print_color(id, print_team_default, "%s ^3Здоровье улучшено до уровня %d!", PREFIX, g_iPlayerHealthLevel[id]);
            } else {
                if(g_iPlayerHealthLevel[id] >= g_iMaxHealthLevel) {
                    client_print_color(id, print_team_default, "%s ^3Достигнут максимальный уровень!", PREFIX);
                } else {
                    new iCost = GetHealthSkillCost(g_iPlayerHealthLevel[id]);
                    client_print_color(id, print_team_default, "%s ^3Недостаточно очков! Нужно %d очков.", PREFIX, iCost);
                }
                DisplayHealthSkillMenu(id);
            }
        }
        case 8: DisplaySkillsMenu(id);
        case 9: CloseSkillsMenu(id);
    }
    
    return PLUGIN_HANDLED;
}

/* ============================================
   DROP MENU
   ============================================ */

public DisplayDropSkillMenu(id) {
    if(!is_user_connected(id)) return;
    
    new iLevel = g_iPlayerDropLevel[id];
    new iExtra = g_iPlayerExtraDropLevel[id];
    new iCost = GetDropSkillCost(iLevel);
    new iTotalLevel = iLevel + iExtra;
    new iCurrentChance = GetDropChance(iTotalLevel);
    new iPoints = points_is_loaded(id) ? points_get(id) : 0;
    
    new bool:bMax = (iLevel >= g_iMaxDropLevel);
    new bool:bCanUpgrade = (!bMax && iPoints >= iCost);
    
    new szMenu[1024];
    new len = 0;
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\yШанс дропа очков \r[%d очков]^n^n", iPoints);
    
    if(iExtra > 0) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wУровень: \r%d \w/ \r%d \y(Доп: +%d)^n", iLevel, g_iMaxDropLevel, iExtra);
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wУровень: \r%d \w/ \r%d^n", iLevel, g_iMaxDropLevel);
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\wШанс дропа очков: \r%d%%^n", iCurrentChance);
    
    if(!bMax) {
        new iNextChance = GetDropChance(iTotalLevel + 1);
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wСлед. уровень: \r%d%%^n", iNextChance);
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wСтоимость: \r%d \wочков^n", iCost);
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n");
    
    if(bMax) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d1. МАКС. УРОВЕНЬ^n");
    } else if(bCanUpgrade) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r1. \wУлучшить^n");
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d1. Улучшить (недостаточно очков)^n");
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n\r9. \wНазад^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r0. \wВыход");
    
    new keys = KEY_9 | KEY_0;
    if(bCanUpgrade) keys |= KEY_1;
    
    show_menu(id, keys, szMenu, -1, MENU_DROP);
    g_iPlayerMenuState[id] = 4;
}

public Handle_DropMenu(id, key) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED;
    
    switch(key) {
        case 0: {
            if(sk_UpgradeDropSkill(id)) {
                client_print_color(id, print_team_default, "%s ^3Шанс дропа очков улучшен до уровня %d! (Теперь: %d%%)", PREFIX, g_iPlayerDropLevel[id], GetDropChance(g_iPlayerDropLevel[id] + g_iPlayerExtraDropLevel[id]));
            } else {
                if(g_iPlayerDropLevel[id] >= g_iMaxDropLevel) {
                    client_print_color(id, print_team_default, "%s ^3Достигнут максимальный уровень!", PREFIX);
                } else {
                    new iCost = GetDropSkillCost(g_iPlayerDropLevel[id]);
                    client_print_color(id, print_team_default, "%s ^3Недостаточно очков! Нужно %d очков.", PREFIX, iCost);
                }
                DisplayDropSkillMenu(id);
            }
        }
        case 8: DisplaySkillsMenu(id);
        case 9: CloseSkillsMenu(id);
    }
    
    return PLUGIN_HANDLED;
}

/* ============================================
   VAMP MENU
   ============================================ */

public DisplayVampSkillMenu(id) {
    if(!is_user_connected(id)) return;
    
    new iLevel = g_iPlayerVampLevel[id];
    new iExtra = g_iPlayerExtraVampLevel[id];
    new iCost = GetVampSkillCost(iLevel);
    new iPoints = points_is_loaded(id) ? points_get(id) : 0;
    
    new bool:bMax = (iLevel >= g_iMaxVampLevel);
    new bool:bCanUpgrade = (!bMax && iPoints >= iCost);
    
    new iTotalLevel = iLevel + iExtra;
    new iHeal = iTotalLevel * g_iVampHPPerLevel;
    
    new szMenu[1024];
    new len = 0;
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\yВампиризм \r[%d очков]^n^n", iPoints);
    
    if(iExtra > 0) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wУровень: \r%d \w/ \r%d \y(Доп: +%d)^n", iLevel, g_iMaxVampLevel, iExtra);
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wУровень: \r%d \w/ \r%d^n", iLevel, g_iMaxVampLevel);
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\wЭффект: +\r%d \wHP за убийство^n", iHeal);
    
    if(!bMax) {
        new iNextHeal = (iTotalLevel + 1) * g_iVampHPPerLevel;
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wСлед. уровень: +\r%d \wHP^n", iNextHeal);
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wСтоимость: \r%d \wочков^n", iCost);
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n");
    
    if(bMax) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d1. МАКС. УРОВЕНЬ^n");
    } else if(bCanUpgrade) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r1. \wУлучшить^n");
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d1. Улучшить (недостаточно очков)^n");
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n\r9. \wНазад^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r0. \wВыход");
    
    new keys = KEY_9 | KEY_0;
    if(bCanUpgrade) keys |= KEY_1;
    
    show_menu(id, keys, szMenu, -1, MENU_VAMP);
    g_iPlayerMenuState[id] = 5;
}

public Handle_VampMenu(id, key) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED;
    
    switch(key) {
        case 0: {
            if(sk_UpgradeVampSkill(id)) {
                client_print_color(id, print_team_default, "%s ^3Вампиризм улучшен до уровня %d! (+%d HP за убийство)", PREFIX, g_iPlayerVampLevel[id], (g_iPlayerVampLevel[id] + g_iPlayerExtraVampLevel[id]) * g_iVampHPPerLevel);
            } else {
                if(g_iPlayerVampLevel[id] >= g_iMaxVampLevel) {
                    client_print_color(id, print_team_default, "%s ^3Достигнут максимальный уровень!", PREFIX);
                } else {
                    new iCost = GetVampSkillCost(g_iPlayerVampLevel[id]);
                    client_print_color(id, print_team_default, "%s ^3Недостаточно очков! Нужно %d очков.", PREFIX, iCost);
                }
                DisplayVampSkillMenu(id);
            }
        }
        case 8: DisplaySkillsMenu(id);
        case 9: CloseSkillsMenu(id);
    }
    
    return PLUGIN_HANDLED;
}

/* ============================================
   MULTIPLIER MENU
   ============================================ */

public DisplayMultiplierSkillMenu(id) {
    if(!is_user_connected(id)) return;
    
    new iLevel = g_iPlayerMultiplierLevel[id];
    new iExtra = g_iPlayerExtraMultiplierLevel[id];
    new iCost = GetMultiplierSkillCost(iLevel);
    new iPoints = points_is_loaded(id) ? points_get(id) : 0;
    
    new bool:bMax = (iLevel >= g_iMaxMultiplierLevel);
    new bool:bCanUpgrade = (!bMax && iPoints >= iCost);
    
    new iTotalLevel = iLevel + iExtra;
    new iReward = iTotalLevel > 0 ? iTotalLevel : 1;
    
    new szMenu[1024];
    new len = 0;
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\yМножитель очков \r[%d очков]^n^n", iPoints);
    
    if(iExtra > 0) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wУровень: \r%d \w/ \r%d \y(Доп: +%d)^n", iLevel, g_iMaxMultiplierLevel, iExtra);
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wУровень: \r%d \w/ \r%d^n", iLevel, g_iMaxMultiplierLevel);
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\wНаграда: \r%d \wочков за убийство^n", iReward);
    
    if(!bMax) {
        new iNextReward = iTotalLevel + 1;
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wСлед. уровень: \r%d \wочков^n", iNextReward);
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wСтоимость: \r%d \wочков^n", iCost);
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n");
    
    if(bMax) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d1. МАКС. УРОВЕНЬ^n");
    } else if(bCanUpgrade) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r1. \wУлучшить^n");
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d1. Улучшить (недостаточно очков)^n");
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n\r9. \wНазад^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r0. \wВыход");
    
    new keys = KEY_9 | KEY_0;
    if(bCanUpgrade) keys |= KEY_1;
    
    show_menu(id, keys, szMenu, -1, MENU_MULT);
    g_iPlayerMenuState[id] = 6;
}

public Handle_MultMenu(id, key) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED;
    
    switch(key) {
        case 0: {
            if(sk_UpgradeMultiplierSkill(id)) {
                client_print_color(id, print_team_default, "%s ^3Множитель очков улучшен до уровня %d! (+%d очков за убийство)", PREFIX, g_iPlayerMultiplierLevel[id], g_iPlayerMultiplierLevel[id] + g_iPlayerExtraMultiplierLevel[id]);
            } else {
                if(g_iPlayerMultiplierLevel[id] >= g_iMaxMultiplierLevel) {
                    client_print_color(id, print_team_default, "%s ^3Достигнут максимальный уровень!", PREFIX);
                } else {
                    new iCost = GetMultiplierSkillCost(g_iPlayerMultiplierLevel[id]);
                    client_print_color(id, print_team_default, "%s ^3Недостаточно очков! Нужно %d очков.", PREFIX, iCost);
                }
                DisplayMultiplierSkillMenu(id);
            }
        }
        case 8: DisplaySkillsMenu(id);
        case 9: CloseSkillsMenu(id);
    }
    
    return PLUGIN_HANDLED;
}

/* ============================================
   AMMO MENU
   ============================================ */

public DisplayAmmoSkillMenu(id) {
    if(!is_user_connected(id)) return;
    
    new iLevel = g_iPlayerAmmoLevel[id];
    new iExtra = g_iPlayerExtraAmmoLevel[id];
    new iCost = GetAmmoSkillCost(iLevel);
    new iPoints = points_is_loaded(id) ? points_get(id) : 0;
    
    new bool:bMax = (iLevel >= g_iMaxAmmoLevel);
    new bool:bCanUpgrade = (!bMax && iPoints >= iCost);
    
    new iTotalLevel = iLevel + iExtra;
    new iPercent = iTotalLevel * g_iAmmoPercentPerLevel;
    
    new szMenu[1024];
    new len = 0;
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\yПатроны \r[%d очков]^n^n", iPoints);
    
    if(iExtra > 0) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wУровень: \r%d \w/ \r%d \y(Доп: +%d)^n", iLevel, g_iMaxAmmoLevel, iExtra);
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wУровень: \r%d \w/ \r%d^n", iLevel, g_iMaxAmmoLevel);
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\wЭффект: +\r%d%% \wот обоймы за убийство^n", iPercent);
    
    if(!bMax) {
        new iNextPercent = (iTotalLevel + 1) * g_iAmmoPercentPerLevel;
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wСлед. уровень: +\r%d%%^n", iNextPercent);
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\wСтоимость: \r%d \wочков^n", iCost);
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n");
    
    if(bMax) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d1. МАКС. УРОВЕНЬ^n");
    } else if(bCanUpgrade) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r1. \wУлучшить^n");
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d1. Улучшить (недостаточно очков)^n");
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n\r9. \wНазад^n");
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r0. \wВыход");
    
    new keys = KEY_9 | KEY_0;
    if(bCanUpgrade) keys |= KEY_1;
    
    show_menu(id, keys, szMenu, -1, MENU_AMMO);
    g_iPlayerMenuState[id] = 7;
}

public Handle_AmmoMenu(id, key) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED;
    
    switch(key) {
        case 0: {
            if(sk_UpgradeAmmoSkill(id)) {
                client_print_color(id, print_team_default, "%s ^3Патроны улучшены до уровня %d! (+%d%% в обойму)", PREFIX, g_iPlayerAmmoLevel[id], (g_iPlayerAmmoLevel[id] + g_iPlayerExtraAmmoLevel[id]) * g_iAmmoPercentPerLevel);
            } else {
                if(g_iPlayerAmmoLevel[id] >= g_iMaxAmmoLevel) {
                    client_print_color(id, print_team_default, "%s ^3Достигнут максимальный уровень!", PREFIX);
                } else {
                    new iCost = GetAmmoSkillCost(g_iPlayerAmmoLevel[id]);
                    client_print_color(id, print_team_default, "%s ^3Недостаточно очков! Нужно %d очков.", PREFIX, iCost);
                }
                DisplayAmmoSkillMenu(id);
            }
        }
        case 8: DisplaySkillsMenu(id);
        case 9: CloseSkillsMenu(id);
    }
    
    return PLUGIN_HANDLED;
}

/* ============================================ 
   CONFIG
   ============================================ */

public LoadConfig() {
    new szPath[256];
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
    formatex(szPath, charsmax(szPath), "%s/skills.cfg", szPath);
    
    if(!file_exists(szPath)) {
        new f = fopen(szPath, "w");
        if(f) {
            fputs(f, "// Skills System Configuration^n^n");
            fputs(f, "skills_jump_max_level ^"5^"^n");
            fputs(f, "skills_jump_cost_base ^"100^"^n");
            fputs(f, "skills_jump_cost_increment ^"50^"^n^n");
            fputs(f, "skills_health_max_level ^"5^"^n");
            fputs(f, "skills_health_cost_base ^"100^"^n");
            fputs(f, "skills_health_cost_increment ^"50^"^n");
            fputs(f, "skills_health_per_level ^"2^"^n^n");
            fputs(f, "skills_drop_max_level ^"8^"^n");
            fputs(f, "skills_drop_cost_base ^"100^"^n");
            fputs(f, "skills_drop_cost_increment ^"50^"^n");
            fputs(f, "skills_drop_chance_base ^"20^"^n");
            fputs(f, "skills_drop_chance_per_level ^"10^"^n^n");
            fputs(f, "skills_vamp_max_level ^"3^"^n");
            fputs(f, "skills_vamp_cost_base ^"150^"^n");
            fputs(f, "skills_vamp_cost_increment ^"75^"^n");
            fputs(f, "skills_vamp_hp_per_level ^"5^"^n^n");
            fputs(f, "skills_multiplier_max_level ^"5^"^n");
            fputs(f, "skills_multiplier_cost_base ^"100^"^n");
            fputs(f, "skills_multiplier_cost_increment ^"50^"^n");
            fputs(f, "skills_multiplier_per_level ^"1^"^n^n");
            fputs(f, "skills_ammo_max_level ^"3^"^n");
            fputs(f, "skills_ammo_cost_base ^"150^"^n");
            fputs(f, "skills_ammo_cost_increment ^"75^"^n");
            fputs(f, "skills_ammo_percent_per_level ^"10^"^n");
            fclose(f);
        }
    }
    
    g_iMaxJumpLevel = read_config_num(szPath, "skills_jump_max_level", 5);
    g_iJumpCostBase = read_config_num(szPath, "skills_jump_cost_base", 100);
    g_iJumpCostIncrement = read_config_num(szPath, "skills_jump_cost_increment", 50);
    
    g_iMaxHealthLevel = read_config_num(szPath, "skills_health_max_level", 5);
    g_iHealthCostBase = read_config_num(szPath, "skills_health_cost_base", 100);
    g_iHealthCostIncrement = read_config_num(szPath, "skills_health_cost_increment", 50);
    g_iHealthPerLevel = read_config_num(szPath, "skills_health_per_level", 2);
    
    g_iMaxDropLevel = read_config_num(szPath, "skills_drop_max_level", 8);
    g_iDropCostBase = read_config_num(szPath, "skills_drop_cost_base", 100);
    g_iDropCostIncrement = read_config_num(szPath, "skills_drop_cost_increment", 50);
    g_iDropChanceBase = read_config_num(szPath, "skills_drop_chance_base", 20);
    g_iDropChancePerLevel = read_config_num(szPath, "skills_drop_chance_per_level", 10);
    
    g_iMaxVampLevel = read_config_num(szPath, "skills_vamp_max_level", 3);
    g_iVampCostBase = read_config_num(szPath, "skills_vamp_cost_base", 150);
    g_iVampCostIncrement = read_config_num(szPath, "skills_vamp_cost_increment", 75);
    g_iVampHPPerLevel = read_config_num(szPath, "skills_vamp_hp_per_level", 5);
    
    g_iMaxMultiplierLevel = read_config_num(szPath, "skills_multiplier_max_level", 5);
    g_iMultiplierCostBase = read_config_num(szPath, "skills_multiplier_cost_base", 100);
    g_iMultiplierCostIncrement = read_config_num(szPath, "skills_multiplier_cost_increment", 50);
    g_iMultiplierPointsPerLevel = read_config_num(szPath, "skills_multiplier_per_level", 1);

    g_iMaxAmmoLevel = read_config_num(szPath, "skills_ammo_max_level", 3);
    g_iAmmoCostBase = read_config_num(szPath, "skills_ammo_cost_base", 150);
    g_iAmmoCostIncrement = read_config_num(szPath, "skills_ammo_cost_increment", 75);
    g_iAmmoPercentPerLevel = read_config_num(szPath, "skills_ammo_percent_per_level", 10);
}

stock read_config_num(const szFile[], const szKey[], iDefault) {
    new szData[128], szKeyRead[32], szValue[32];
    new f = fopen(szFile, "r");
    if(!f) return iDefault;
    
    while(!feof(f)) {
        fgets(f, szData, charsmax(szData));
        trim(szData);
        if(szData[0] == ';' || szData[0] == EOS) continue;
        
        if(parse(szData, szKeyRead, 31, szValue, 31) >= 2) {
            if(equali(szKeyRead, szKey)) {
                fclose(f);
                return str_to_num(szValue);
            }
        }
    }
    fclose(f);
    return iDefault;
}

/* ============================================
   MENU SYSTEM INI (чтение команды главного меню)
   ============================================ */

public LoadMenuSystemConfig() {
    copy(g_szMainMenuCmd, charsmax(g_szMainMenuCmd), "chooseteam");
    
    new szPath[256];
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
    formatex(szPath, charsmax(szPath), "%s/menuSystem.ini", szPath);
    
    if(!file_exists(szPath)) return;
    
    new f = fopen(szPath, "r");
    if(!f) return;
    
    new szLine[256];
    new bool:bInMainSection = false;
    
    while(!feof(f)) {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);
        
        if(szLine[0] == EOS) continue;
        
        if(szLine[0] == '[') {
            new close = contain(szLine, "]");
            if(close > 0) {
                szLine[close] = 0;
                bInMainSection = equal(szLine[1], "Главное меню") ? true : false;
            } else {
                bInMainSection = false;
            }
            continue;
        }
        
        if(szLine[0] == ';') continue;
        if(!bInMainSection) continue;
        
        new eq = contain(szLine, "=");
        if(eq <= 0) continue;
        
        new szKey[32], szVal[64];
        copy(szKey, charsmax(szKey), szLine);
        if(eq < charsmax(szKey)) szKey[eq] = 0;
        trim(szKey);
        
        copy(szVal, charsmax(szVal), szLine[eq + 1]);
        trim(szVal);
        
        if(equali(szKey, "cmd") && szVal[0]) {
            copy(g_szMainMenuCmd, charsmax(g_szMainMenuCmd), szVal);
        }
    }
    
    fclose(f);
}