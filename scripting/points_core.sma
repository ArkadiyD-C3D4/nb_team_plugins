#include <amxmodx>
#include <sqlx>

#define PLUGIN "Points Core"
#define VERSION "1.5-SMARTSAVE"
#define AUTHOR "nb_team"

#define MAX_PLAYERS 32

#define POINTS_PER_KILL 1
#define KILL_CHANCE_PERCENT 20
#define DEFAULT_POINTS 0

new Handle:g_hDB
new bool:g_bDBConnected
new g_iRetryCount

new g_iPoints[MAX_PLAYERS+1]
new bool:g_bPointsLoaded[MAX_PLAYERS+1]
new g_szAuth[MAX_PLAYERS+1][64]
new bool:g_bPlayerQueued[MAX_PLAYERS+1]

// Флажок "нужно сохранить"
new bool:g_bNeedsSave[MAX_PLAYERS+1]

public plugin_natives()
{
    register_native("points_get", "Native_GetPoints")
    register_native("points_set", "Native_SetPoints")
    register_native("points_is_loaded", "Native_IsPointsLoaded")
    register_native("points_load", "Native_LoadPoints")
    register_native("points_set_loaded", "Native_SetLoadedFlag")
}

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)
    register_clcmd("say /points", "Cmd_Points")
    register_clcmd("say_team /points", "Cmd_Points")
    
    // Умный автосейв: проверяем флажки каждые 5.0 секунд
    set_task(5.0, "Task_SmartSave", .flags = "b")
}

public plugin_cfg()
{
    set_task(random_float(2.0, 8.0), "InitDatabase")
}

public plugin_end()
{
    if(g_hDB != Empty_Handle) {
        SQL_FreeHandle(g_hDB)
        g_hDB = Empty_Handle
    }
}

// ---------- БД — ПЕРЕПОДКЛЮЧЕНИЕ ----------
public InitDatabase()
{
    if(g_bDBConnected) return
    
    if(g_hDB != Empty_Handle) {
        SQL_FreeHandle(g_hDB)
        g_hDB = Empty_Handle
    }
    
    new host[64], user[64], pass[64], db[64]
    get_cvar_string("amx_sql_host", host, 63)
    get_cvar_string("amx_sql_user", user, 63)
    get_cvar_string("amx_sql_pass", pass, 63)
    get_cvar_string("amx_sql_db", db, 63)

    g_hDB = SQL_MakeDbTuple(host, user, pass, db)
    SQL_ThreadQuery(g_hDB, "CheckDBConnection", "SELECT 1")
}

public CheckDBConnection(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt)
{
    if(FailState != TQUERY_SUCCESS) {
        g_iRetryCount++
        if(g_iRetryCount < 30) {
            log_amx("[POINTS] DB not ready (%s), retry #%d in 10s...", Error, g_iRetryCount)
            set_task(10.0, "InitDatabase")
        } else {
            log_amx("[POINTS] DB connection failed permanently after 30 attempts.")
        }
        return
    }
    
    g_bDBConnected = true
    g_iRetryCount = 0
    log_amx("[POINTS] Database connected via thread.")

    new q[512]
    formatex(q, charsmax(q),
        "CREATE TABLE IF NOT EXISTS player_data ( \
            authid VARCHAR(64) PRIMARY KEY, \
            point INT DEFAULT %d, \
            owned TEXT, \
            weapon_owned TEXT, \
            selected_skins TEXT \
        )", DEFAULT_POINTS)
    SQL_ThreadQuery(g_hDB, "VoidQuery", q)
    
    ProcessQueue(true)
}

ProcessQueue(bool:success)
{
    for(new i = 1; i <= MAX_PLAYERS; i++) {
        if(g_bPlayerQueued[i] && is_user_connected(i)) {
            g_bPlayerQueued[i] = false
            if(success && g_szAuth[i][0]) {
                LoadPoints(i)
            } else {
                g_bPointsLoaded[i] = true
            }
        }
    }
}

public VoidQuery(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt)
{
    if(FailState != TQUERY_SUCCESS) {
        log_amx("[POINTS] SQL Error: %s (code %d)", Error, Errcode)
        
        if(Errcode == 2003 || Errcode == 2006 || Errcode == 2013) {
            log_amx("[POINTS] Connection lost, restarting...")
            g_bDBConnected = false
            if(g_hDB != Empty_Handle) {
                SQL_FreeHandle(g_hDB)
                g_hDB = Empty_Handle
            }
            g_iRetryCount = 0
            set_task(5.0, "InitDatabase")
        }
    }
}

// ---------- КЛИЕНТЫ ----------
public client_putinserver(id)
{
    g_iPoints[id] = DEFAULT_POINTS
    g_bPointsLoaded[id] = false
    g_bPlayerQueued[id] = false
    g_bNeedsSave[id] = false
    g_szAuth[id][0] = 0
    
    if(is_user_bot(id) || is_user_hltv(id)) {
        g_bPointsLoaded[id] = true
        return
    }
    
    get_user_authid(id, g_szAuth[id], charsmax(g_szAuth[]))
    
    if(!g_szAuth[id][0] || equali(g_szAuth[id], "STEAM_ID_PENDING")) {
        g_szAuth[id][0] = 0
        g_bPointsLoaded[id] = true
        return
    }
    
    if(g_bDBConnected)
        LoadPoints(id)
    else
        g_bPlayerQueued[id] = true
}

public client_disconnected(id)
{
    // При выходе проверяем флажок. Если были изменения - сохраняем.
    if(g_bDBConnected && g_bPointsLoaded[id] && g_szAuth[id][0] && g_bNeedsSave[id])
        SavePoints(id)
    
    g_bPointsLoaded[id] = false
    g_bPlayerQueued[id] = false
    g_bNeedsSave[id] = false
    g_szAuth[id][0] = 0
}

// ---------- ЗАГРУЗКА / СОХРАНЕНИЕ ----------
LoadPoints(id)
{
    if(!g_szAuth[id][0] || !g_bDBConnected) return
    
    new szSafe[64], q[256], data[1]
    data[0] = id
    
    copy(szSafe, charsmax(szSafe), g_szAuth[id])
    replace_all(szSafe, charsmax(szSafe), "'", "''")
    
    formatex(q, charsmax(q), "SELECT point FROM player_data WHERE authid='%s'", szSafe)
    SQL_ThreadQuery(g_hDB, "LoadPointsCB", q, data, sizeof(data))
}

public LoadPointsCB(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt)
{
    new id = Data[0]
    if(!is_user_connected(id)) return
    if(FailState != TQUERY_SUCCESS) {
        log_amx("[POINTS] Load error: %s", Error)
        g_bPointsLoaded[id] = true
        return
    }

    if(SQL_NumResults(Q) > 0) {
        g_iPoints[id] = SQL_ReadResult(Q, 0)
    } else {
        new szSafe[64], insQ[256]
        copy(szSafe, charsmax(szSafe), g_szAuth[id])
        replace_all(szSafe, charsmax(szSafe), "'", "''")
        
        formatex(insQ, charsmax(insQ),
            "INSERT INTO player_data (authid, point) VALUES ('%s', %d) \
            ON DUPLICATE KEY UPDATE authid=authid",
            szSafe, DEFAULT_POINTS)
        SQL_ThreadQuery(g_hDB, "VoidQuery", insQ)
    }
    g_bPointsLoaded[id] = true
}

SavePoints(id)
{
    if(!g_szAuth[id][0] || !g_bPointsLoaded[id] || !g_bDBConnected) return
    
    new szSafe[64], q[256]
    copy(szSafe, charsmax(szSafe), g_szAuth[id])
    replace_all(szSafe, charsmax(szSafe), "'", "''")
    
    formatex(q, charsmax(q),
        "INSERT INTO player_data (authid, point) VALUES ('%s', %d) \
        ON DUPLICATE KEY UPDATE point=%d",
        szSafe, g_iPoints[id], g_iPoints[id])
    SQL_ThreadQuery(g_hDB, "VoidQuery", q)
    
    g_bNeedsSave[id] = false
}

// Умный автосейв
public Task_SmartSave()
{
    if(!g_bDBConnected) return

    for(new i = 1; i <= MAX_PLAYERS; i++)
    {
        if(g_bNeedsSave[i] && is_user_connected(i) && g_bPointsLoaded[i])
        {
            SavePoints(i)
        }
    }
}

public Cmd_Points(id)
{
    if(!is_user_connected(id)) return PLUGIN_HANDLED
    if(!g_bPointsLoaded[id]) {
        client_print_color(id, print_team_default, "^4[POINTS]^1 Данные ещё загружаются...")
        return PLUGIN_HANDLED
    }
    client_print_color(id, print_team_default, "^4[POINTS]^1 Ваши очки: ^3%d^1", g_iPoints[id])
    return PLUGIN_HANDLED
}

// ==========================================================
// НАТИВЫ
// ==========================================================

public Native_GetPoints(iPlugin, iParams)
{
    new id = get_param(1)
    if(id < 1 || id > MAX_PLAYERS) return 0
    return g_iPoints[id]
}

public Native_SetPoints(iPlugin, iParams)
{
    new id = get_param(1)
    new amount = get_param(2)
    
    if(id < 1 || id > MAX_PLAYERS || !is_user_connected(id))
        return 0

    if(!g_bPointsLoaded[id])
        return 0

    if(amount < 0) amount = 0
    g_iPoints[id] = amount
    
    // Вместо запроса в БД, просто ставим флажок, что нужно сохранить
    g_bNeedsSave[id] = true

    return 1
}

public Native_IsPointsLoaded(iPlugin, iParams)
{
    new id = get_param(1)
    if(id < 1 || id > MAX_PLAYERS) return 0
    return g_bPointsLoaded[id] ? 1 : 0
}

public Native_LoadPoints(iPlugin, iParams)
{
    new id = get_param(1)
    if(id < 1 || id > MAX_PLAYERS || !is_user_connected(id))
        return 0
    if(!g_bDBConnected || !g_szAuth[id][0])
        return 0
    LoadPoints(id)
    return 1
}

public Native_SetLoadedFlag(iPlugin, iParams)
{
    new id = get_param(1)
    if(id < 1 || id > MAX_PLAYERS) return 0
    g_bPointsLoaded[id] = true
    return 1
}