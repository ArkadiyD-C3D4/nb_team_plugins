#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <sqlx>

// ============================================================================
//                              КОНСТАНТЫ
// ============================================================================
new const PLUGIN[]      = "Ranks System";
new const VERSION[]     = "2.4-RECONNECT";
new const AUTHOR[]      = "nb_team";
new const CONFIG_FILE[] = "ranks.ini";
new const SQL_TABLE[]   = "ranks_players";

// ============================================================================
//                              ПЕРЕМЕННЫЕ
// ============================================================================
new cvar_xp_kill, cvar_xp_hs, cvar_xp_knife, cvar_xp_round_win, cvar_xp_round_lose;
new cvar_max_level;
new cvar_hud_enable, cvar_hud_x, cvar_hud_y, cvar_hud_color;
new cvar_chat_levelup, cvar_chat_xp, cvar_save_on_round;

new Handle:g_dbTuple    = Empty_Handle;
new bool:g_dbReady      = false;
new g_iRetryCount       = 0;

// Ranks
enum _:RankData {
    RankName[64],
    RankXP
};
new g_ranks[128][RankData];
new g_rankCount = 0;

// Игроки
new g_playerLevel[33];
new g_playerXP[33];
new bool:g_playerLoaded[33];
new bool:g_playerNeedSave[33];
new g_playerLastHitGroup[33];
new bool:g_playerNeedLoad[33];

// --- Интеграция с points_core ---
native points_get(id);

new g_hudSync;

// ============================================================================
//                              ИНИЦИАЛИЗАЦИЯ
// ============================================================================
public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    cvar_xp_kill       = register_cvar("rank_xp_kill",       "10");
    cvar_xp_hs         = register_cvar("rank_xp_hs",         "5");
    cvar_xp_knife      = register_cvar("rank_xp_knife",      "5");
    cvar_xp_round_win  = register_cvar("rank_xp_round_win",  "10");
    cvar_xp_round_lose = register_cvar("rank_xp_round_lose", "3");
    cvar_max_level     = register_cvar("rank_max_level",     "0");

    cvar_hud_enable = register_cvar("rank_hud_enable", "1");
    cvar_hud_x      = register_cvar("rank_hud_x",     "-1.0");
    cvar_hud_y      = register_cvar("rank_hud_y",     "0.85"); 
    cvar_hud_color  = register_cvar("rank_hud_color", "0 255 0");

    cvar_chat_levelup  = register_cvar("rank_chat_levelup",  "1");
    cvar_chat_xp       = register_cvar("rank_chat_xp",       "1");
    cvar_save_on_round = register_cvar("rank_save_on_round", "1");

    RegisterHookChain(RG_CBasePlayer_Killed, "CBasePlayer_Killed_Post", true);
    RegisterHookChain(RG_CBasePlayer_TakeDamage, "CBasePlayer_TakeDamage_Post", true);
    RegisterHookChain(RG_RoundEnd, "RoundEnd_Post", true);

    register_clcmd("say /rank",      "CmdRank");
    register_clcmd("say /ranks",     "CmdRankList");
    register_clcmd("say /top",       "CmdTop10");
    register_clcmd("say_team /rank", "CmdRank");
    register_clcmd("say_team /ranks","CmdRankList");
    register_clcmd("say_team /top",  "CmdTop10");

    register_concmd("rank_reload",   "CmdReloadRanks", ADMIN_LEVEL_H);
    register_concmd("rank_setlevel", "CmdSetLevel",    ADMIN_LEVEL_H);
    register_concmd("rank_setxp",    "CmdSetXP",       ADMIN_LEVEL_H);

    g_hudSync = CreateHudSyncObj();

    LoadRanks();
}

public plugin_cfg()
{
    // Размазываем старт между плагинами
    set_task(random_float(2.0, 10.0), "InitDatabase");
    set_task(1.0, "TaskShowHUD", _, _, _, "b");
    set_task(300.0, "TaskAutoSave", _, _, _, "b");
}

public plugin_end()
{
    for(new id = 1; id <= MaxClients; id++)
    {
        if(is_user_connected(id) && g_playerLoaded[id] && g_playerNeedSave[id])
            SavePlayerData(id);
    }

    if(g_dbTuple != Empty_Handle)
    {
        SQL_FreeHandle(g_dbTuple);
        g_dbTuple = Empty_Handle;
    }
}

// ============================================================================
//                              НАТИВЫ
// ============================================================================
public plugin_natives()
{
    register_library("ranks_system");
    register_native("ranks_get_level",    "native_get_level");
    register_native("ranks_get_xp",       "native_get_xp");
    register_native("ranks_get_rankname", "native_get_rankname");
    register_native("ranks_add_xp",       "native_add_xp");
}

public native_get_level(id)
{
    if(!is_user_connected(id)) return 0;
    return g_playerLevel[id];
}

public native_get_xp(id)
{
    if(!is_user_connected(id)) return 0;
    return g_playerXP[id];
}

public native_get_rankname(id, buffer[], len)
{
    new target = get_param(1);
    new buf_len = get_param(3);
    
    if(!is_user_connected(target))
    {
        set_string(2, "", buf_len);
        return 0;
    }
    
    if(!g_playerLoaded[target])
    {
        set_string(2, "...", buf_len);
        return 0;
    }
    
    new szRankName[64];
    GetRankName(g_playerLevel[target], szRankName, charsmax(szRankName));
    
    set_string(2, szRankName, buf_len);
    
    return 1;
}

// ============================================================================
//                              НОВЫЙ НАТИВ: ranks_add_xp
// ============================================================================
public native_add_xp()
{
    new id = get_param(1);
    new amount = get_param(2);

    if(!is_user_connected(id))
        return 0;

    if(!g_playerLoaded[id])
        return 0;

    if(amount <= 0)
        return 0;

    AddXP(id, amount);
    return 1;
}

// ============================================================================
//                              ЗАГРУЗКА КОНФИГА ЗВАНИЙ
// ============================================================================
public LoadRanks()
{
    new filePath[256];
    get_localinfo("amxx_configsdir", filePath, charsmax(filePath));
    format(filePath, charsmax(filePath), "%s/%s", filePath, CONFIG_FILE);

    if(!file_exists(filePath))
    {
        server_print("[RANKS] Файл %s не найден. Используются стандартные звания.", CONFIG_FILE);
        SetDefaultRanks();
        return;
    }

    new file = fopen(filePath, "rt");
    if(!file)
    {
        server_print("[RANKS] Ошибка открытия %s. Используются стандартные звания.", filePath);
        SetDefaultRanks();
        return;
    }

    g_rankCount = 0;
    new line[256], len, rankName[64], xpStr[16];

    while(!feof(file))
    {
        fgets(file, line, charsmax(line));
        trim(line);
        len = strlen(line);

        if(len == 0 || line[0] == ';' || line[0] == '/')
            continue;

        new pos = contain(line, "|");
        if(pos != -1)
        {
            copyc(rankName, charsmax(rankName), line, '|');
            copy(xpStr, charsmax(xpStr), line[pos + 1]);
            trim(rankName);
            trim(xpStr);

            if(g_rankCount < sizeof(g_ranks))
            {
                copy(g_ranks[g_rankCount][RankName], charsmax(g_ranks[][RankName]), rankName);
                g_ranks[g_rankCount][RankXP] = str_to_num(xpStr);
                g_rankCount++;
            }
        }
    }
    fclose(file);

    if(g_rankCount == 0)
    {
        server_print("[RANKS] Конфиг пуст! Используются стандартные звания.");
        SetDefaultRanks();
    }
    else
    {
        server_print("[RANKS] Загружено %d званий из конфига.", g_rankCount);
    }
}

public SetDefaultRanks()
{
    new const defaultNames[11][] = {
        "Новобранец", "Рядовой", "Ефрейтор", "Сержант", "Старшина",
        "Прапорщик", "Лейтенант", "Капитан", "Майор", "Полковник", "Генерал"
    };
    new const defaultXP[11] = { 0, 100, 250, 500, 800, 1200, 1700, 2500, 4000, 6500, 10000 };

    g_rankCount = 11;
    for(new i = 0; i < g_rankCount; i++)
    {
        copy(g_ranks[i][RankName], charsmax(g_ranks[][RankName]), defaultNames[i]);
        g_ranks[i][RankXP] = defaultXP[i];
    }
}

// ============================================================================
//                              ПОДКЛЮЧЕНИЕ К БД (НЕБЛОКИРУЮЩЕЕ)
// ============================================================================
public InitDatabase()
{
    if(g_dbReady) return;
    
    if(g_dbTuple != Empty_Handle)
    {
        SQL_FreeHandle(g_dbTuple);
        g_dbTuple = Empty_Handle;
    }
    
    new host[64], user[64], pass[64], dbname[64];
    get_cvar_string("amx_sql_host", host, charsmax(host));
    get_cvar_string("amx_sql_user", user, charsmax(user));
    get_cvar_string("amx_sql_pass", pass, charsmax(pass));
    get_cvar_string("amx_sql_db", dbname, charsmax(dbname));

    if(!host[0] || !dbname[0])
    {
        server_print("[RANKS] Ошибка: amx_sql_host или amx_sql_db не заданы в sql.cfg!");
        set_task(10.0, "InitDatabase");
        return;
    }

    g_dbTuple = SQL_MakeDbTuple(host, user, pass, dbname);
    
    // НЕТ блокирующего SQL_Connect — проверяем в фоновом потоке
    SQL_ThreadQuery(g_dbTuple, "CheckDBConnection", "SELECT 1");
}

public CheckDBConnection(failstate, Handle:query, error[], errcode, data[], datasize)
{
    if(failstate != TQUERY_SUCCESS)
    {
        g_iRetryCount++;
        if(g_iRetryCount < 30)
        {
            log_amx("[RANKS] DB not ready (%s), retry #%d in 10s...", error, g_iRetryCount);
            set_task(10.0, "InitDatabase");
        }
        else
        {
            log_amx("[RANKS] DB connection failed permanently after 30 attempts.");
            ProcessQueue(false);
        }
        return;
    }
    
    g_dbReady = true;
    g_iRetryCount = 0;
    log_amx("[RANKS] Database connected via thread.");
    
    CreateTable();
    ProcessQueue(true);
}

ProcessQueue(bool:success)
{
    for(new id = 1; id <= MaxClients; id++)
    {
        if(g_playerNeedLoad[id] && is_user_connected(id) && !is_user_bot(id) && !is_user_hltv(id))
        {
            g_playerNeedLoad[id] = false;
            if(success)
                LoadPlayerData(id);
            else
                g_playerLoaded[id] = true;   // работаем без БД
        }
    }
}

public CreateTable()
{
    new query[512];
    formatex(query, charsmax(query),
        "CREATE TABLE IF NOT EXISTS `%s` ( \
        `steamid` VARCHAR(32) NOT NULL PRIMARY KEY, \
        `name` VARCHAR(64) NOT NULL DEFAULT '', \
        `level` INT NOT NULL DEFAULT 1, \
        `experience` INT NOT NULL DEFAULT 0, \
        `last_played` INT NOT NULL DEFAULT 0 \
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8;", SQL_TABLE);

    SQL_ThreadQuery(g_dbTuple, "QueryCreateTable", query);
}

// ============================================================================
//                              РАБОТА С ИГРОКАМИ
// ============================================================================
public client_putinserver(id)
{
    g_playerLevel[id]        = 1;
    g_playerXP[id]           = 0;
    g_playerLoaded[id]       = false;
    g_playerNeedSave[id]     = false;
    g_playerLastHitGroup[id] = 0;
    g_playerNeedLoad[id]     = false;

    if(is_user_bot(id) || is_user_hltv(id))
    {
        g_playerLoaded[id] = true;
        return;
    }

    if(g_dbReady)
    {
        LoadPlayerData(id);
    }
    else
    {
        g_playerNeedLoad[id] = true;
        server_print("[RANKS] DB not ready yet, queuing load for %N", id);
    }
}

public client_disconnected(id)
{
    if(g_dbReady && g_playerLoaded[id] && g_playerNeedSave[id])
        SavePlayerData(id);

    g_playerLoaded[id]   = false;
    g_playerNeedSave[id] = false;
    g_playerNeedLoad[id] = false;
}

public LoadPlayerData(id)
{
    if(!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
        return;

    if(!g_dbReady)
    {
        g_playerNeedLoad[id] = true;
        return;
    }

    new steamid[32];
    get_user_authid(id, steamid, charsmax(steamid));

    if(equal(steamid, "STEAM_ID_LAN") || equal(steamid, "BOT") || equal(steamid, "HLTV"))
    {
        g_playerLevel[id]  = 1;
        g_playerXP[id]     = 0;
        g_playerLoaded[id] = true;
        return;
    }

    new query[256];
    formatex(query, charsmax(query),
        "SELECT `level`, `experience` FROM `%s` WHERE `steamid` = '%s';",
        SQL_TABLE, steamid);

    new data[1];
    data[0] = id;
    SQL_ThreadQuery(g_dbTuple, "QueryLoadPlayer", query, data, sizeof(data));
}

public SavePlayerData(id)
{
    if(!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
        return;

    if(!g_dbReady)
        return;

    new steamid[32], name[64], query[512];
    get_user_authid(id, steamid, charsmax(steamid));
    get_user_name(id, name, charsmax(name));
    
    // Ручное экранирование вместо SQL_QuoteString (не требует блокирующего соединения)
    replace_all(name, charsmax(name), "'", "''");
    replace_all(name, charsmax(name), "\\", "\\\\");

    if(equal(steamid, "STEAM_ID_LAN") || equal(steamid, "BOT"))
        return;

    formatex(query, charsmax(query),
        "INSERT INTO `%s` (`steamid`, `name`, `level`, `experience`, `last_played`) \
        VALUES ('%s', '%s', %d, %d, %d) \
        ON DUPLICATE KEY UPDATE \
        `name` = VALUES(`name`), `level` = VALUES(`level`), \
        `experience` = VALUES(`experience`), `last_played` = VALUES(`last_played`);",
        SQL_TABLE, steamid, name, g_playerLevel[id], g_playerXP[id], get_systime());

    SQL_ThreadQuery(g_dbTuple, "QuerySavePlayer", query);
    g_playerNeedSave[id] = false;
}

public QuerySavePlayer(failstate, Handle:query, error[], errcode, data[], datasize)
{
    if(failstate != TQUERY_SUCCESS)
    {
        log_amx("[RANKS] SavePlayer error: %s (%d)", error, errcode);
        
        // Если соединение оборвалось — перезапускаем
        if(errcode == 2003 || errcode == 2006 || errcode == 2013 || errcode == 0)
        {
            log_amx("[RANKS] Connection lost during save, restarting...");
            RestartDBConnection();
        }
        return;
    }
}

// ============================================================================
//                              ОТСЛЕЖИВАНИЕ ХЕДШОТОВ
// ============================================================================
public CBasePlayer_TakeDamage_Post(const victim, const inflictor, const attacker, const Float:damage, const damagebits)
{
    if(!is_user_connected(attacker) || attacker == victim)
        return HC_CONTINUE;

    if(damagebits & DMG_BULLET)
        g_playerLastHitGroup[attacker] = get_member(victim, m_LastHitGroup);

    return HC_CONTINUE;
}

// ============================================================================
//                              НАЧИСЛЕНИЕ ОПЫТА
// ============================================================================
public CBasePlayer_Killed_Post(const victim, const killer, const shouldGib)
{
    if(!is_user_connected(killer) || killer == victim)
        return HC_CONTINUE;

    if(!g_playerLoaded[killer])
        return HC_CONTINUE;

    if(is_user_bot(victim) || is_user_hltv(victim))
        return HC_CONTINUE;

    if(get_member(killer, m_iTeam) == get_member(victim, m_iTeam))
        return HC_CONTINUE;

    new xp = get_pcvar_num(cvar_xp_kill);

    if(g_playerLastHitGroup[killer] == HIT_HEAD)
        xp += get_pcvar_num(cvar_xp_hs);

    new activeWeapon = get_member(killer, m_pActiveItem);
    if(activeWeapon > 0)
    {
        new weaponId = get_member(activeWeapon, m_iId);
        if(weaponId == WEAPON_KNIFE)
            xp += get_pcvar_num(cvar_xp_knife);
    }

    AddXP(killer, xp);
    return HC_CONTINUE;
}

public RoundEnd_Post(WinStatus:winStatus, _:ScenarioEventEndRound, const Float:delay)
{
    if(get_pcvar_num(cvar_save_on_round))
    {
        for(new id = 1; id <= MaxClients; id++)
        {
            if(is_user_connected(id) && g_playerLoaded[id] && g_playerNeedSave[id])
                SavePlayerData(id);
        }
    }

    new xpWin  = get_pcvar_num(cvar_xp_round_win);
    new xpLose = get_pcvar_num(cvar_xp_round_lose);

    for(new id = 1; id <= MaxClients; id++)
    {
        if(!is_user_connected(id) || !g_playerLoaded[id])
            continue;
        if(is_user_bot(id) || is_user_hltv(id))
            continue;

        new TeamName:team = get_member(id, m_iTeam);
        new xp = 0;

        if(winStatus == WINSTATUS_CTS && team == TEAM_CT)
            xp = xpWin;
        else if(winStatus == WINSTATUS_TERRORISTS && team == TEAM_TERRORIST)
            xp = xpWin;
        else if(winStatus == WINSTATUS_DRAW)
            xp = xpLose;
        else
            xp = xpLose;

        if(xp > 0)
            AddXP(id, xp);
    }
}

// ============================================================================
//                              ДОБАВЛЕНИЕ ОПЫТА
// ============================================================================
public AddXP(id, amount)
{
    if(!is_user_connected(id) || amount <= 0)
        return;

    new oldLevel = g_playerLevel[id];
    g_playerXP[id] += amount;
    g_playerNeedSave[id] = true;

    CheckLevelUp(id, oldLevel);

    if(g_playerLevel[id] > oldLevel)
        SavePlayerData(id);

    if(get_pcvar_num(cvar_chat_xp))
    {
        client_print_color(id, print_team_default,
            "^x04[RANKS]^x01 Получено^x04 %d^x01 XP. Всего:^x03 %d XP",
            amount, g_playerXP[id]);
    }
}

// ============================================================================
//                              ПРОВЕРКА ПОВЫШЕНИЯ УРОВНЯ
// ============================================================================
public CheckLevelUp(id, oldLevel)
{
    new newLevel = 1;
    new playerXP = g_playerXP[id];
    new maxLevel = get_pcvar_num(cvar_max_level);

    for(new i = 0; i < g_rankCount; i++)
    {
        if(playerXP >= g_ranks[i][RankXP])
            newLevel = i + 1;
        else
            break;
    }

    if(maxLevel > 0 && newLevel > maxLevel)
        newLevel = maxLevel;

    g_playerLevel[id] = newLevel;

    if(newLevel > oldLevel && get_pcvar_num(cvar_chat_levelup))
    {
        new rankName[64];
        GetRankName(newLevel, rankName, charsmax(rankName));

        client_print_color(0, print_team_default,
            "^x04[RANKS]^x03 %n^x01 получил звание^x04 %s^x01 (уровень^x03 %d^x01)!",
            id, rankName, newLevel);

        client_cmd(id, "spk ^"buttons/bell1.wav^"");
    }
}

// ============================================================================
//                              ПОЛУЧЕНИЕ ЗВАНИЯ
// ============================================================================
public GetRankName(level, buffer[], len)
{
    if(g_rankCount == 0)
    {
        copy(buffer, len, "Новобранец");
        return;
    }

    new rankIndex = level - 1;
    if(rankIndex < 0)
        rankIndex = 0;

    if(rankIndex >= g_rankCount)
    {
        // Если уровень превышает количество рангов — просто показываем последний ранг без дубля уровня
        copy(buffer, len, g_ranks[g_rankCount - 1][RankName]);
    }
    else
    {
        copy(buffer, len, g_ranks[rankIndex][RankName]);
    }
}

// ============================================================================
//                              HUD
// ============================================================================
public TaskShowHUD()
{
    if(!get_pcvar_num(cvar_hud_enable))
        return;

    new colorStr[32];
    get_pcvar_string(cvar_hud_color, colorStr, charsmax(colorStr));

    new colors[3][8], part[8];
    new pos = 0, c = 0, k;

    while(c < 3 && colorStr[pos])
    {
        while(colorStr[pos] == ' ') pos++;
        k = 0;
        while(colorStr[pos] && colorStr[pos] != ' ')
            part[k++] = colorStr[pos++];
        part[k] = 0;
        copy(colors[c], charsmax(colors[]), part);
        c++;
    }

    new r = str_to_num(colors[0]);
    new g = str_to_num(colors[1]);
    new b = str_to_num(colors[2]);

    new Float:x = get_pcvar_float(cvar_hud_x);
    new Float:y = get_pcvar_float(cvar_hud_y);

    for(new id = 1; id <= MaxClients; id++)
    {
        if(!is_user_connected(id))
            continue;

        new target = id;

        if(!is_user_alive(id))
        {
            new iMode = get_entvar(id, var_iuser1);
            
            if(iMode == 4 || iMode == 5)
            {
                new iTarget = get_entvar(id, var_iuser2);
                
                if(1 <= iTarget <= MaxClients && is_user_connected(iTarget) && g_playerLoaded[iTarget])
                {
                    target = iTarget;
                }
            }
        }

        if(!g_playerLoaded[target])
        {
            if(g_playerLoaded[id])
                target = id;
            else
                continue;
        }

        new rankName[64];
        GetRankName(g_playerLevel[target], rankName, charsmax(rankName));
        new points = points_get(target);

        new nextIndex = g_playerLevel[target];
        new nextRankXP = 0;
        
        if(nextIndex < g_rankCount) {
            nextRankXP = g_ranks[nextIndex][RankXP];
        } else {
            nextRankXP = g_ranks[g_rankCount - 1][RankXP]; 
        }

        set_hudmessage(r, g, b, x, y, 0, 0.0, 1.1, 0.0, 0.0, -1);

        if(target != id)
        {
            new targetName[32];
            get_user_name(target, targetName, charsmax(targetName));
            
            if(nextIndex >= g_rankCount) {
                ShowSyncHudMsg(id, g_hudSync,
                    "[%s]^nОчки: %d^nРанг: %s | Ур: %d | Опыт: %d/MAX",
                    targetName, points, rankName, g_playerLevel[target], g_playerXP[target]);
            } else {
                ShowSyncHudMsg(id, g_hudSync,
                    "[%s]^nОчки: %d^nРанг: %s | Ур: %d | Опыт: %d/%d",
                    targetName, points, rankName, g_playerLevel[target], g_playerXP[target], nextRankXP);
            }
        }
        else
        {
            if(nextIndex >= g_rankCount) {
                ShowSyncHudMsg(id, g_hudSync,
                    "Очки: %d^nРанг: %s | Ур: %d | Опыт: %d/MAX",
                    points, rankName, g_playerLevel[id], g_playerXP[id]);
            } else {
                ShowSyncHudMsg(id, g_hudSync,
                    "Очки: %d^nРанг: %s | Ур: %d | Опыт: %d/%d",
                    points, rankName, g_playerLevel[id], g_playerXP[id], nextRankXP);
            }
        }
    }
}

// ============================================================================
//                              КОМАНДА /rank
// ============================================================================
public CmdRank(id)
{
    if(!is_user_connected(id))
        return PLUGIN_HANDLED;

    if(!g_playerLoaded[id])
    {
        client_print_color(id, print_team_default,
            "^x04[RANKS]^x01 Ваши данные ещё загружаются...");
        return PLUGIN_HANDLED;
    }

    new rankName[64];
    GetRankName(g_playerLevel[id], rankName, charsmax(rankName));

    new nextIndex = g_playerLevel[id];
    new xpToNext = 0;

    if(nextIndex < g_rankCount) {
        xpToNext = g_ranks[nextIndex][RankXP] - g_playerXP[id];
        if(xpToNext < 0) xpToNext = 0;
    }

    client_print_color(id, print_team_default,
        "^x04[RANKS]^x01 Звание:^x04 %s^x01 | Уровень:^x03 %d",
        rankName, g_playerLevel[id]);

    if(nextIndex >= g_rankCount) {
        client_print_color(id, print_team_default,
            "^x04[RANKS]^x01 Вы достигли максимального уровня! Общий опыт:^x03 %d",
            g_playerXP[id]);
    } else {
        client_print_color(id, print_team_default,
            "^x04[RANKS]^x01 Опыт:^x03 %d^x01 | До следующего ранга:^x03 %d XP",
            g_playerXP[id], xpToNext);
    }

    return PLUGIN_HANDLED;
}

// ============================================================================
//                              ОСТАЛЬНЫЕ КОМАНДЫ
// ============================================================================
public CmdRankList(id)
{
    if(!is_user_connected(id))
        return PLUGIN_HANDLED;

    new text[1500], pos = 0;
    pos += formatex(text[pos], charsmax(text) - pos, "\yСписок званий^n^n");

    for(new i = 0; i < g_rankCount; i++)
    {
        new marker = ' ';
        if(i + 1 == g_playerLevel[id])
            marker = '>';

        pos += formatex(text[pos], charsmax(text) - pos, "\w%c%d. \r%s \w- \y%d XP^n",
            marker, i + 1, g_ranks[i][RankName], g_ranks[i][RankXP]);

        if(pos > 1400)
            break;
    }

    show_menu(id, (1<<9), text, -1);
    return PLUGIN_HANDLED;
}

public CmdTop10(id)
{
    if(!is_user_connected(id) || !g_dbReady)
        return PLUGIN_HANDLED;

    new query[256];
    formatex(query, charsmax(query),
        "SELECT `name`, `level`, `experience` FROM `%s` ORDER BY `experience` DESC LIMIT 10;",
        SQL_TABLE);

    new data[1];
    data[0] = id;
    SQL_ThreadQuery(g_dbTuple, "QueryTop10", query, data, sizeof(data));

    return PLUGIN_HANDLED;
}

public QueryTop10(failstate, Handle:query, error[], errcode, data[], datasize)
{
    new id = data[0];
    if(!is_user_connected(id))
        return;

    if(failstate != TQUERY_SUCCESS)
    {
        client_print_color(id, print_team_default, "^x04[RANKS]^x01 Ошибка запроса к БД.");
        
        // Если соединение оборвалось — перезапускаем
        if(errcode == 2003 || errcode == 2006 || errcode == 2013 || errcode == 0)
        {
            log_amx("[RANKS] Connection lost during top10, restarting...");
            RestartDBConnection();
        }
        return;
    }

    new text[1024], pos = 0;
    pos += formatex(text[pos], charsmax(text) - pos, "\yТоп-10 игроков^n^n");

    if(!SQL_NumResults(query))
    {
        pos += formatex(text[pos], charsmax(text) - pos, "\wНет данных.");
    }
    else
    {
        new rank = 1;
        new name[64], level, xp;
        while(SQL_MoreResults(query))
        {
            SQL_ReadResult(query, 0, name, charsmax(name));
            level = SQL_ReadResult(query, 1);
            xp    = SQL_ReadResult(query, 2);

            pos += formatex(text[pos], charsmax(text) - pos,
                "\w%d. \r%s \w- \yУр. %d \w(\g%d XP\w)^n",
                rank, name, level, xp);

            rank++;
            SQL_NextRow(query);
        }
    }

    show_menu(id, (1<<9), text, -1);
}

// ============================================================================
//                              ADMIN КОМАНДЫ
// ============================================================================
public CmdReloadRanks(id, level, cid)
{
    if(!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    LoadRanks();

    for(new i = 1; i <= MaxClients; i++)
    {
        if(is_user_connected(i) && g_playerLoaded[i])
        {
            new oldLevel = g_playerLevel[i];
            CheckLevelUp(i, oldLevel);
        }
    }

    console_print(id, "[RANKS] Звания перезагружены. Всего: %d", g_rankCount);
    return PLUGIN_HANDLED;
}

public CmdSetLevel(id, level, cid)
{
    if(!cmd_access(id, level, cid, 3))
        return PLUGIN_HANDLED;

    new arg1[32], arg2[8];
    read_argv(1, arg1, charsmax(arg1));
    read_argv(2, arg2, charsmax(arg2));

    new target = cmd_target(id, arg1, CMDTARGET_ALLOW_SELF);
    if(!target)
    {
        console_print(id, "Игрок не найден.");
        return PLUGIN_HANDLED;
    }

    new newLevel = str_to_num(arg2);
    if(newLevel < 1) newLevel = 1;

    new rankIndex = newLevel - 1;
    if(rankIndex >= g_rankCount)
        rankIndex = g_rankCount - 1;

    g_playerLevel[target]    = newLevel;
    g_playerXP[target]       = g_ranks[rankIndex][RankXP];
    g_playerNeedSave[target] = true;
    g_playerLoaded[target]   = true;

    SavePlayerData(target);

    console_print(id, "Уровень %N установлен на %d", target, newLevel);
    return PLUGIN_HANDLED;
}

public CmdSetXP(id, level, cid)
{
    if(!cmd_access(id, level, cid, 3))
        return PLUGIN_HANDLED;

    new arg1[32], arg2[16];
    read_argv(1, arg1, charsmax(arg1));
    read_argv(2, arg2, charsmax(arg2));

    new target = cmd_target(id, arg1, CMDTARGET_ALLOW_SELF);
    if(!target)
    {
        console_print(id, "Игрок не найден.");
        return PLUGIN_HANDLED;
    }

    new newXP = str_to_num(arg2);
    if(newXP < 0) newXP = 0;

    new oldLevel = g_playerLevel[target];
    g_playerXP[target]     = newXP;
    g_playerNeedSave[target] = true;
    g_playerLoaded[target]   = true;

    CheckLevelUp(target, oldLevel);

    SavePlayerData(target);

    console_print(id, "Опыт %N установлен на %d", target, newXP);
    return PLUGIN_HANDLED;
}

// ============================================================================
//                              АВТОСОХРАНЕНИЕ
// ============================================================================
public TaskAutoSave()
{
    for(new id = 1; id <= MaxClients; id++)
    {
        if(is_user_connected(id) && g_playerLoaded[id] && g_playerNeedSave[id])
            SavePlayerData(id);
    }
}

// ============================================================================
//                              ЗАПРОСЫ С АВТО-РЕКОННЕКТОМ
// ============================================================================
public QueryCreateTable(failstate, Handle:query, error[], errcode, data[], datasize)
{
    if(failstate != TQUERY_SUCCESS)
    {
        log_amx("[RANKS] Ошибка создания таблицы: %s (%d)", error, errcode);
        
        // Если соединение оборвалось — перезапускаем
        if(errcode == 2003 || errcode == 2006 || errcode == 2013 || errcode == 0)
        {
            log_amx("[RANKS] Connection lost during CREATE TABLE, restarting...");
            RestartDBConnection();
        }
        else
        {
            g_dbReady = false;
            set_task(10.0, "InitDatabase");
        }
        return;
    }

    log_amx("[RANKS] Таблица `%s` готова к работе.", SQL_TABLE);
}

public QueryLoadPlayer(failstate, Handle:query, error[], errcode, data[], datasize)
{
    new id = data[0];

    if(failstate != TQUERY_SUCCESS)
    {
        log_amx("[RANKS] LoadPlayer error: %s (%d)", error, errcode);
        g_playerLevel[id]  = 1;
        g_playerXP[id]     = 0;
        g_playerLoaded[id] = true;
        
        // Если соединение оборвалось — перезапускаем
        if(errcode == 2003 || errcode == 2006 || errcode == 2013 || errcode == 0)
        {
            log_amx("[RANKS] Connection lost during load, restarting...");
            RestartDBConnection();
        }
        return;
    }

    if(!SQL_NumResults(query))
    {
        g_playerLevel[id]  = 1;
        g_playerXP[id]     = 0;
        server_print("[RANKS] Новый игрок %N, создаём запись в БД", id);
        SavePlayerData(id);
    }
    else
    {
        g_playerLevel[id] = SQL_ReadResult(query, 0);
        g_playerXP[id]    = SQL_ReadResult(query, 1);
        server_print("[RANKS] Загружены данные %N: уровень=%d, опыт=%d", id, g_playerLevel[id], g_playerXP[id]);
        CheckLevelUp(id, 0);
    }

    g_playerLoaded[id] = true;
}


// ============================================================================
//                              ПЕРЕЗАПУСК СОЕДИНЕНИЯ
// ============================================================================
public RestartDBConnection()
{
    g_dbReady = false;
    if(g_dbTuple != Empty_Handle)
    {
        SQL_FreeHandle(g_dbTuple);
        g_dbTuple = Empty_Handle;
    }
    g_iRetryCount = 0;
    set_task(5.0, "InitDatabase");
}