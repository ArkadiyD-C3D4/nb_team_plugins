#include <amxmodx>
#include <hamsandwich>
#include <fakemeta>
#include <sqlx>
#include <amxmisc>

#define PLUGIN "Advanced Stats MySQL"
#define VERSION "1.7"
#define AUTHOR "nb_team"

// Database
new Handle:g_SqlTuple = Empty_Handle
new bool:g_SqlConnected = false

// Player statistics
new g_Kills[33]
new g_Deaths[33]
new g_Headshots[33]
new g_Shots[33]
new g_Hits[33]
new g_Damage[33]
new g_Rounds[33]
new g_BombsPlanted[33]
new g_BombsDefused[33]
new g_BombsExploded[33]
new g_PlayTime[33]
new g_LastConnect[33]
new bool:g_IsConnected[33]
new bool:g_StatsLoaded[33]
new g_CtRounds[33]
new g_TtRounds[33]
new g_CtWins[33]
new g_TtWins[33]

// Shot tracking
new g_LastWeapon[33]
new g_LastAmmo[33]

// Bomb tracking
new g_BombCarrier
new g_Defuser

// Save task
new g_SaveTask

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)

    RegisterHam(Ham_TakeDamage, "player", "fwTakeDamage")
    RegisterHam(Ham_Item_Deploy, "weapon_c4", "fwItemDeployPost", 1)
    RegisterHam(Ham_Item_Deploy, "item_thighpack", "fwItemDeployPost", 1)

    register_event("CurWeapon", "EventCurWeapon", "be", "1=1")
    register_event("DeathMsg", "EventDeathMsg", "a")
    
    // Подсчет раундов и сброс бомбмейкера в начале раунда
    register_event("HLTV", "EventRoundStart", "a", "1=0", "2=0")
    
    register_logevent("EventBombPlanted", 3, "2=Planted_The_Bomb")
    register_logevent("EventBombDefused", 3, "2=Defused_The_Bomb")
    register_event("TextMsg", "EventBombExplode", "a", "2=#Target_Bombed")

    // Убран EventTextMsg, чтобы не было двойного подсчета побед
    register_event("SendAudio", "EventSendAudio", "a")

    initDatabase()

    // Автосохранение каждые 2 минуты
    g_SaveTask = set_task(120.0, "saveAllStats", _, _, _, "b")
}

public plugin_end()
{
    saveAllStats()
    remove_task(g_SaveTask)

    if(g_SqlTuple)
    {
        SQL_FreeHandle(g_SqlTuple)
        g_SqlTuple = Empty_Handle
    }
}

public client_putinserver(id)
{
    if(!is_user_connected(id) || is_user_bot(id))
        return

    g_IsConnected[id] = true
    g_StatsLoaded[id] = false
    g_LastConnect[id] = get_systime()

    // Сброс статистики сессии
    g_Kills[id] = 0
    g_Deaths[id] = 0
    g_Headshots[id] = 0
    g_Shots[id] = 0
    g_Hits[id] = 0
    g_Damage[id] = 0
    g_Rounds[id] = 0
    g_BombsPlanted[id] = 0
    g_BombsDefused[id] = 0
    g_BombsExploded[id] = 0
    g_PlayTime[id] = 0
    g_CtRounds[id] = 0
    g_TtRounds[id] = 0
    g_CtWins[id] = 0
    g_TtWins[id] = 0
    
    g_LastWeapon[id] = 0
    g_LastAmmo[id] = -1

    loadPlayerStats(id)
}

public client_disconnected(id)
{
    if(!g_IsConnected[id] || is_user_bot(id))
        return

    if(g_StatsLoaded[id])
    {
        savePlayerStats(id)
    }

    g_IsConnected[id] = false
    g_StatsLoaded[id] = false
}

// Функция спавна удалена за ненадобностью (раньше она дюпала раунды)
public EventCurWeapon(id)
{
    if(!is_user_alive(id) || !g_IsConnected[id])
        return

    new weapon = read_data(2)
    new ammo = read_data(3)

    if(weapon == CSW_KNIFE || weapon == CSW_C4 || weapon == CSW_FLASHBANG || weapon == CSW_HEGRENADE || weapon == CSW_SMOKEGRENADE)
    {
        g_LastWeapon[id] = weapon
        g_LastAmmo[id] = -1
        return
    }

    if(g_LastWeapon[id] == weapon && g_LastAmmo[id] != -1 && ammo > 0 && ammo < g_LastAmmo[id])
    {
        g_Shots[id] += (g_LastAmmo[id] - ammo)
    }
    
    g_LastWeapon[id] = weapon
    g_LastAmmo[id] = ammo
}

public fwTakeDamage(victim, inflictor, attacker, Float:damage, damage_type)
{
    if(attacker < 1 || attacker > 32)
        return HAM_IGNORED

    if(!is_user_connected(attacker) || !is_user_connected(victim))
        return HAM_IGNORED

    if(attacker == victim)
        return HAM_IGNORED

    if(!g_IsConnected[attacker] || !g_IsConnected[victim])
        return HAM_IGNORED

    g_Hits[attacker]++
    g_Damage[attacker] += floatround(damage)

    return HAM_IGNORED
}

public fwItemDeployPost(ent)
{
    if(!pev_valid(ent))
        return HAM_IGNORED

    new owner = pev(ent, pev_owner)
    if(owner > 0 && owner <= 32 && g_IsConnected[owner])
    {
        new classname[32]
        pev(ent, pev_classname, classname, charsmax(classname))

        if(equal(classname, "weapon_c4"))
        {
            g_BombCarrier = owner
        }
        else if(equal(classname, "item_thighpack"))
        {
            g_Defuser = owner
        }
    }
    return HAM_IGNORED
}

public EventDeathMsg()
{
    new killer = read_data(1)
    new victim = read_data(2)
    new headshot = read_data(3)

    if(is_user_connected(killer) && killer != victim && killer > 0 && g_IsConnected[killer])
    {
        g_Kills[killer]++
        if(headshot)
            g_Headshots[killer]++
    }

    if(is_user_connected(victim) && g_IsConnected[victim])
        g_Deaths[victim]++
}

public EventRoundStart()
{
    g_BombCarrier = 0
    g_Defuser = 0

    // ИСПРАВЛЕНИЕ: Раунды считаются только в начале раунда, а не на спавне!
    for(new i = 1; i <= get_maxplayers(); i++)
    {
        if(g_IsConnected[i])
        {
            g_Rounds[i]++
            
            new team = get_user_team(i)
            if(team == 1)
                g_TtRounds[i]++
            else if(team == 2)
                g_CtRounds[i]++
        }
    }
}

public EventBombPlanted()
{
    new loguser[64], name[32], id
    read_logargv(0, loguser, charsmax(loguser))
    parse_loguser(loguser, name, charsmax(name))
    id = get_user_index(name)

    if(id > 0 && is_user_connected(id) && g_IsConnected[id] && get_user_team(id) == 1)
    {
        g_BombsPlanted[id]++
    }
}

public EventBombDefused()
{
    new loguser[64], name[32], id
    read_logargv(0, loguser, charsmax(loguser))
    parse_loguser(loguser, name, charsmax(name))
    id = get_user_index(name)

    if(id > 0 && is_user_connected(id) && g_IsConnected[id] && get_user_team(id) == 2)
    {
        g_BombsDefused[id]++
    }
}

public EventBombExplode()
{
    for(new i = 1; i <= get_maxplayers(); i++)
    {
        if(g_IsConnected[i] && get_user_team(i) == 1)
        {
            g_BombsExploded[i]++
        }
    }
}

public EventSendAudio()
{
    new audio[32]
    read_data(2, audio, charsmax(audio))

    if(equal(audio, "%!MRAD_ctwin") || equal(audio, "events/ctwin.wav"))
    {
        for(new i = 1; i <= get_maxplayers(); i++)
        {
            if(g_IsConnected[i] && is_user_alive(i) && get_user_team(i) == 2)
            {
                g_CtWins[i]++
            }
        }
    }
    else if(equal(audio, "%!MRAD_terwin") || equal(audio, "events/terwin.wav"))
    {
        for(new i = 1; i <= get_maxplayers(); i++)
        {
            if(g_IsConnected[i] && is_user_alive(i) && get_user_team(i) == 1)
            {
                g_TtWins[i]++
            }
        }
    }
}

// ==================== DATABASE ====================

public initDatabase()
{
    if (g_SqlTuple != Empty_Handle)
    {
        SQL_FreeHandle(g_SqlTuple)
        g_SqlTuple = Empty_Handle
    }

    g_SqlConnected = false

    new host[64], user[64], pass[64], db[64]

    get_cvar_string("amx_sql_host", host, charsmax(host))
    get_cvar_string("amx_sql_user", user, charsmax(user))
    get_cvar_string("amx_sql_pass", pass, charsmax(pass))
    get_cvar_string("amx_sql_db", db, charsmax(db))

    if(host[0] == EOS || user[0] == EOS || db[0] == EOS)
    {
        server_print("[Stats] SQL cvars are empty! Check sql.cfg. Retrying in 10 seconds...")
        set_task(10.0, "initDatabase")
        return
    }

    g_SqlTuple = SQL_MakeDbTuple(host, user, pass, db)

    if(g_SqlTuple == Empty_Handle)
    {
        server_print("[Stats] Failed to create database tuple! Retrying in 10 seconds...")
        set_task(10.0, "initDatabase")
        return
    }

    new authData[192]
    formatex(authData, charsmax(authData), "[Stats] Host: %s | DB: %s | User: %s", host, db, user)

    SQL_ThreadQuery(g_SqlTuple, "SQL_InitCallback", "SELECT 1;", authData, charsmax(authData))
}

public SQL_InitCallback(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime)
{
    if (failstate == TQUERY_CONNECT_FAILED || failstate == TQUERY_QUERY_FAILED)
    {
        g_SqlConnected = false
        server_print("[Stats] DB connect failed: %s (error %d). Retrying in 10 seconds...", error, errnum)
        set_task(10.0, "initDatabase")
        return
    }

    if (!g_SqlConnected)
    {
        g_SqlConnected = true
        server_print("[Stats] MySQL Database initialized successfully via Thread Pool!")
        server_print("%s", data)

        new players[32], pnum
        get_players(players, pnum, "ch")
        for(new i = 0; i < pnum; i++)
        {
            g_StatsLoaded[players[i]] = false
            loadPlayerStats(players[i])
        }
    }

    new createQuery[2048]
    formatex(createQuery, charsmax(createQuery),
        "CREATE TABLE IF NOT EXISTS players (\
            id INT AUTO_INCREMENT PRIMARY KEY, \
            steamid VARCHAR(32) UNIQUE NOT NULL, \
            name VARCHAR(64) NOT NULL, \
            kills INT DEFAULT 0, \
            deaths INT DEFAULT 0, \
            headshots INT DEFAULT 0, \
            shots INT DEFAULT 0, \
            hits INT DEFAULT 0, \
            damage INT DEFAULT 0, \
            rounds INT DEFAULT 0, \
            bombs_planted INT DEFAULT 0, \
            bombs_defused INT DEFAULT 0, \
            bombs_exploded INT DEFAULT 0, \
            ct_rounds INT DEFAULT 0, \
            tt_rounds INT DEFAULT 0, \
            ct_wins INT DEFAULT 0, \
            tt_wins INT DEFAULT 0, \
            playtime INT DEFAULT 0, \
            last_seen INT DEFAULT 0, \
            created_at INT DEFAULT 0, \
            updated_at INT DEFAULT 0 \
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")

    SQL_ThreadQuery(g_SqlTuple, "SQL_StructureCallback", createQuery)
}

public SQL_StructureCallback(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime)
{
    if (failstate == TQUERY_CONNECT_FAILED || failstate == TQUERY_QUERY_FAILED)
    {
        server_print("[Stats Error] Failed to process database structure (Code: %d): %s", errnum, error)
        
        if (failstate == TQUERY_CONNECT_FAILED && g_SqlConnected)
        {
            g_SqlConnected = false
            server_print("[Stats] Connection lost during setup! Starting reconnect loop...")
            set_task(10.0, "initDatabase")
        }
    }
}

public loadPlayerStats(id)
{
    if(!g_SqlConnected || !is_user_connected(id))
        return

    new steamid[32]
    get_user_authid(id, steamid, charsmax(steamid))

    if(equal(steamid, "STEAM_ID_PENDING") || equal(steamid, ""))
    {
        set_task(2.0, "loadPlayerStats", id)
        return
    }

    new query[512]
    formatex(query, charsmax(query),
        "SELECT kills, deaths, headshots, shots, hits, damage, rounds, \
         bombs_planted, bombs_defused, bombs_exploded, \
         ct_rounds, tt_rounds, ct_wins, tt_wins, playtime \
         FROM players WHERE steamid = '%s'", steamid)

    new data[36]
    data[0] = id
    copy(data[1], 35, steamid)

    SQL_ThreadQuery(g_SqlTuple, "loadPlayerStatsHandler", query, data, sizeof(data))
}

public loadPlayerStatsHandler(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime)
{
    if(failstate)
    {
        server_print("[Stats] Load query failed: %s", error)
        return
    }

    new id = data[0]
    new loaded_steamid[32]
    copy(loaded_steamid, charsmax(loaded_steamid), data[1])

    if(!is_user_connected(id))
        return

    new current_steamid[32]
    get_user_authid(id, current_steamid, charsmax(current_steamid))

    if(!equal(loaded_steamid, current_steamid))
        return

    if(SQL_NumResults(query) > 0)
    {
        g_Kills[id] = SQL_ReadResult(query, 0)
        g_Deaths[id] = SQL_ReadResult(query, 1)
        g_Headshots[id] = SQL_ReadResult(query, 2)
        g_Shots[id] = SQL_ReadResult(query, 3)
        g_Hits[id] = SQL_ReadResult(query, 4)
        g_Damage[id] = SQL_ReadResult(query, 5)
        g_Rounds[id] = SQL_ReadResult(query, 6)
        g_BombsPlanted[id] = SQL_ReadResult(query, 7)
        g_BombsDefused[id] = SQL_ReadResult(query, 8)
        g_BombsExploded[id] = SQL_ReadResult(query, 9)
        g_CtRounds[id] = SQL_ReadResult(query, 10)
        g_TtRounds[id] = SQL_ReadResult(query, 11)
        g_CtWins[id] = SQL_ReadResult(query, 12)
        g_TtWins[id] = SQL_ReadResult(query, 13)
        g_PlayTime[id] = SQL_ReadResult(query, 14)
        
        g_StatsLoaded[id] = true
    }
    else
    {
        g_StatsLoaded[id] = true
        savePlayerStats(id)
    }
}

// Встроенное безопасное экранирование (замена SQL_QuoteString)
stock SafeEscapeString(const source[], dest[], len)
{
    new i = 0, j = 0
    new c
    
    while(source[i] != EOS && j < len - 1)
    {
        c = source[i]
        
        // Экранируем: ' (39), \ (92), " (34), ` (96)
        if(c == 39 || c == 92 || c == 34 || c == 96)
        {
            if(j + 1 >= len - 1)
            {
                break
            }
            dest[j++] = 92 // backslash
        }
        
        dest[j++] = c
        i++
    }
    
    dest[j] = EOS
}

public savePlayerStats(id)
{
    if(!g_SqlConnected || g_SqlTuple == Empty_Handle || !g_IsConnected[id] || !g_StatsLoaded[id])
        return

    new steamid[32], name[64]
    get_user_authid(id, steamid, charsmax(steamid))

    if(equal(steamid, "STEAM_ID_PENDING") || equal(steamid, ""))
        return

    get_user_name(id, name, charsmax(name))
    
    // Используем наше собственное экранирование, чтобы избежать крашей SQL_QuoteString
    new safeName[129]
    SafeEscapeString(name, safeName, charsmax(safeName))

    new now = get_systime()
    new total_playtime = g_PlayTime[id] + (now - g_LastConnect[id])

    new query[2048]
    formatex(query, charsmax(query),
        "INSERT INTO players (steamid, name, kills, deaths, headshots, shots, hits, damage, \
         rounds, bombs_planted, bombs_defused, bombs_exploded, \
         ct_rounds, tt_rounds, ct_wins, tt_wins, playtime, last_seen, created_at, updated_at) \
         VALUES ('%s', '%s', %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d) \
         ON DUPLICATE KEY UPDATE \
         name = VALUES(name), kills = VALUES(kills), deaths = VALUES(deaths), headshots = VALUES(headshots), \
         shots = VALUES(shots), hits = VALUES(hits), damage = VALUES(damage), rounds = VALUES(rounds), \
         bombs_planted = VALUES(bombs_planted), bombs_defused = VALUES(bombs_defused), bombs_exploded = VALUES(bombs_exploded), \
         ct_rounds = VALUES(ct_rounds), tt_rounds = VALUES(tt_rounds), ct_wins = VALUES(ct_wins), tt_wins = VALUES(tt_wins), \
         playtime = VALUES(playtime), last_seen = VALUES(last_seen), updated_at = VALUES(updated_at)",
         steamid, safeName,
         g_Kills[id], g_Deaths[id], g_Headshots[id], g_Shots[id],
         g_Hits[id], g_Damage[id], g_Rounds[id],
         g_BombsPlanted[id], g_BombsDefused[id], g_BombsExploded[id],
         g_CtRounds[id], g_TtRounds[id], g_CtWins[id], g_TtWins[id],
         total_playtime, now, now, now)

    new data[1]
    data[0] = id
    
    SQL_ThreadQuery(g_SqlTuple, "savePlayerStatsHandler", query, data, 1)
}

public savePlayerStatsHandler(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime)
{
    check_sql_connection(failstate)
    
    if(failstate)
    {
        server_print("[Stats] Save query failed: %s (Error code: %d)", error, errnum)
    }
}

public saveAllStats()
{
    for(new i = 1; i <= get_maxplayers(); i++)
    {
        if(g_IsConnected[i] && !is_user_bot(i))
        {
            savePlayerStats(i)
        }
    }
}

check_sql_connection(failstate)
{
    if (failstate == TQUERY_CONNECT_FAILED)
    {
        if (g_SqlConnected)
        {
            server_print("[Stats] SQL Connection lost! Starting reconnection cycle...")
            g_SqlConnected = false
            
            for(new i = 1; i <= get_maxplayers(); i++)
            {
                g_StatsLoaded[i] = false
            }

            remove_task(1001) 
            set_task(10.0, "initDatabase", 1001)
        }
    }
}