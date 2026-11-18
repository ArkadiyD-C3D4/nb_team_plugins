#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <hamsandwich>
#include <sqlx>
#include <fakemeta>

#define PLUGIN "Skin Core Pro"
#define VERSION "2.4-BUYABLE"
#define AUTHOR "nb_team"

#define MAX_SKINS 32
#define MAX_SKIN_NAME_LEN 48
#define MAX_AUTH_LEN 24
#define MAX_PLAYERS 32
#define MAX_MODEL_PATH 96

#define SKIN_TYPE_SPLIT 0
#define SKIN_TYPE_SHARED 1

enum _:SKIN_DATA {
    SKIN_NAME[MAX_SKIN_NAME_LEN],
    SKIN_PRICE,
    SKIN_TYPE,
    SKIN_MODEL_CT[MAX_MODEL_PATH],
    SKIN_MODEL_TT[MAX_MODEL_PATH],
    SKIN_BODY_CT,
    SKIN_BODY_TT,
    SKIN_SKIN_CT,
    SKIN_SKIN_TT,
    SKIN_FLAG,
    SKIN_BUYABLE // НОВОЕ: 1 = можно купить, 0 = нельзя купить
}

new g_eSkins[MAX_SKINS][SKIN_DATA]
new g_iSkinCount

new g_szPlayerAuth[MAX_PLAYERS + 1][MAX_AUTH_LEN]
new g_bPlayerOwned[MAX_PLAYERS + 1][MAX_SKINS]
new g_szPlayerSelected[MAX_PLAYERS + 1][MAX_SKIN_NAME_LEN]
new bool:g_bPlayerLoaded[MAX_PLAYERS + 1]
new bool:g_bPlayerQueued[MAX_PLAYERS + 1]

new Handle:g_hDB
new bool:g_bDBConnected
new g_iRetryCount
new bool:g_bReconnecting
new g_szConfigPath[256]
new g_hFwdPlayerLoaded

new g_iPendingBody[MAX_PLAYERS + 1]
new g_iPlayerBody[MAX_PLAYERS + 1]
new g_iPlayerSkin[MAX_PLAYERS + 1]
new bool:g_bPlayerCustomModel[MAX_PLAYERS + 1]

// --- ПЕРЕМЕННЫЕ ДЛЯ АВТО-РЕКОННЕКТА И ЗАЩИТЫ ОТ ПОДВИСАНИЙ ---
new Float:g_fLastDBSuccess = 0.0
new g_iPendingQueryType[MAX_PLAYERS + 1]
new Float:g_fPendingQueryTime[MAX_PLAYERS + 1]

new g_pCvarEnable

native points_get(id)
native points_set(id, amount)
native points_is_loaded(id)

public plugin_natives()
{
    register_native("skin_core_register", "_skin_core_register")
    register_native("skin_core_get_count", "_skin_core_get_count")
    register_native("skin_core_get_info", "_skin_core_get_info")
    register_native("skin_core_find", "_skin_core_find")
    register_native("skin_core_get_points", "_skin_core_get_points")
    register_native("skin_core_set_points", "_skin_core_set_points")
    register_native("skin_core_add_points", "_skin_core_add_points")
    register_native("skin_core_is_owned", "_skin_core_is_owned")
    register_native("skin_core_buy_skin", "_skin_core_buy_skin")
    register_native("skin_core_get_selected", "_skin_core_get_selected")
    register_native("skin_core_set_selected", "_skin_core_set_selected")
    register_native("skin_core_reset_selected", "_skin_core_reset_selected")
    register_native("skin_core_apply_model", "_skin_core_apply_model")
    register_native("skin_core_force_save", "_skin_core_force_save")
    register_native("skin_core_is_ready", "_skin_core_is_ready")
    register_native("skin_core_reload_config", "_skin_core_reload_config")
    register_native("skin_core_can_access", "_skin_core_can_access")
    register_native("skin_core_is_buyable", "_skin_core_is_buyable") // НОВЫЙ НАТИВ
        register_native("skin_core_get_flag", "_skin_core_get_flag")
}

public plugin_precache()
{
    get_configsdir(g_szConfigPath, charsmax(g_szConfigPath))
    add(g_szConfigPath, charsmax(g_szConfigPath), "/skin_core.ini")
    LoadConfig()
}

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)
    g_pCvarEnable = register_cvar("skin_core_enable", "1")
    RegisterHam(Ham_Spawn, "player", "Fwd_PlayerSpawn_Post", 1)
    g_hFwdPlayerLoaded = CreateMultiForward("skin_core_player_loaded", ET_IGNORE, FP_CELL)
    register_forward(FM_PlayerPostThink, "Fwd_PlayerPostThink")
    set_task(5.0, "Task_DBWatchdog", _, _, _, "b")
}

public plugin_cfg()
{
    set_task(random_float(2.0, 10.0), "InitDatabase")
}

public plugin_end()
{
    if(g_hDB != Empty_Handle) {
        SQL_FreeHandle(g_hDB)
        g_hDB = Empty_Handle
    }
}

bool:IsConnectionError(const Error[], Errcode)
{
    if(Errcode == 2006 || Errcode == 2013 || Errcode == 2003) return true
    if(containi(Error, "Lost connection") != -1) return true
    if(containi(Error, "gone away") != -1) return true
    if(containi(Error, "Can't connect") != -1) return true
    if(containi(Error, "server has gone away") != -1) return true
    return false
}

public ForceReconnect()
{
    if(g_bReconnecting) return
    g_bReconnecting = true
    
    if(g_hDB != Empty_Handle) {
        SQL_FreeHandle(g_hDB)
        g_hDB = Empty_Handle
    }
    g_bDBConnected = false
    log_amx("[SKIN CORE] Connection lost or hanging. Forcing database reconnection...")
    set_task(1.0, "InitDatabase")
}

public Task_DBWatchdog()
{
    if(!g_bDBConnected) return
    new Float:now = get_gametime()
    new bool:need_reconnect = false
    
    for(new i = 1; i <= MAX_PLAYERS; i++) {
        if(g_iPendingQueryType[i] != 0) {
            if(now - g_fPendingQueryTime[i] > 20.0) {
                log_amx("[SKIN CORE] Query for player %d hanging for >20s. Forcing reconnect.", i)
                g_iPendingQueryType[i] = 0
                g_fPendingQueryTime[i] = 0.0
                need_reconnect = true
            }
        }
    }
    if(need_reconnect) ForceReconnect()
}

public InitDatabase()
{
    if(g_bDBConnected) return
    if(g_hDB != Empty_Handle) {
        SQL_FreeHandle(g_hDB)
        g_hDB = Empty_Handle
    }
    new h[64], u[64], p[64], d[64]
    get_cvar_string("amx_sql_host", h, 63)
    get_cvar_string("amx_sql_user", u, 63)
    get_cvar_string("amx_sql_pass", p, 63)
    get_cvar_string("amx_sql_db", d, 63)
    g_hDB = SQL_MakeDbTuple(h, u, p, d)
    g_bReconnecting = true
    SQL_ThreadQuery(g_hDB, "CheckDBConnection", "SELECT 1")
}

public CheckDBConnection(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt)
{
    g_bReconnecting = false
    if(FailState != TQUERY_SUCCESS) {
        g_iRetryCount++
        if(g_iRetryCount < 30) {
            log_amx("[SKIN CORE] DB not ready (%s), retry #%d in 10s...", Error, g_iRetryCount)
            set_task(10.0, "InitDatabase")
        } else {
            log_amx("[SKIN CORE] DB connection failed permanently after 30 attempts.")
            ProcessQueue(false)
        }
        return
    }
    g_bDBConnected = true
    g_iRetryCount = 0
    g_fLastDBSuccess = get_gametime()
    log_amx("[SKIN CORE] Database connected via thread.")
    new q[256]
    formatex(q, charsmax(q), "CREATE TABLE IF NOT EXISTS skin_core_data (authid VARCHAR(32) PRIMARY KEY, owned VARCHAR(%d) DEFAULT '', selected VARCHAR(%d) DEFAULT '')", MAX_SKINS, MAX_SKIN_NAME_LEN)
    SQL_ThreadQuery(g_hDB, "Query_Void", q)
    ProcessQueue(true)
}

ProcessQueue(bool:success)
{
    for(new i = 1; i <= MAX_PLAYERS; i++) {
        if(g_bPlayerQueued[i] && is_user_connected(i)) {
            g_bPlayerQueued[i] = false
            if(success && g_szPlayerAuth[i][0]) LoadPlayerData(i)
            else TrySetLoaded(i)
        }
    }
}

public Query_Void(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt)
{
    if(FailState != TQUERY_SUCCESS) {
        log_amx("[SKIN CORE] DB Error: %s", Error)
        if(IsConnectionError(Error, Errcode)) {
            g_bDBConnected = false
            log_amx("[SKIN CORE] Connection lost during query. Reconnecting...")
            ForceReconnect()
        }
    } else {
        g_fLastDBSuccess = get_gametime()
    }
}

public Query_SavePlayer(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt)
{
    new id = Data[0]
    g_iPendingQueryType[id] = 0
    g_fPendingQueryTime[id] = 0.0
    if(FailState != TQUERY_SUCCESS) {
        log_amx("[SKIN CORE] Save error: %s", Error)
        if(IsConnectionError(Error, Errcode)) {
            g_bDBConnected = false
            log_amx("[SKIN CORE] Connection lost during save. Reconnecting...")
            ForceReconnect()
        }
    } else {
        g_fLastDBSuccess = get_gametime()
    }
}

bool:IsValidAuthID(const auth[])
{
    if(!auth[0]) return false
    if(equal(auth, "HLTV")) return false
    return true
}

public client_putinserver(id)
{
    g_iPlayerBody[id] = -1
    g_iPlayerSkin[id] = -1
    g_bPlayerCustomModel[id] = false
    g_iPendingBody[id] = -1
    
    g_szPlayerAuth[id][0] = 0
    for(new i = 0; i < MAX_SKINS; i++) g_bPlayerOwned[id][i] = 0
    g_szPlayerSelected[id][0] = 0
    g_bPlayerLoaded[id] = false
    g_bPlayerQueued[id] = false
    
    if(!is_user_bot(id) && !is_user_hltv(id)) {
        get_user_authid(id, g_szPlayerAuth[id], charsmax(g_szPlayerAuth[]))
        if(!IsValidAuthID(g_szPlayerAuth[id])) {
            g_szPlayerAuth[id][0] = 0
            g_bPlayerLoaded[id] = true
            return
        }
        if(g_bDBConnected) LoadPlayerData(id)
        else g_bPlayerQueued[id] = true
    } else {
        g_bPlayerLoaded[id] = true
    }
}

public client_disconnected(id)
{
    g_iPlayerBody[id] = -1
    g_iPlayerSkin[id] = -1
    g_bPlayerCustomModel[id] = false
    g_iPendingBody[id] = -1
    if(g_szPlayerAuth[id][0] && g_bDBConnected && g_bPlayerLoaded[id]) SavePlayerData(id)
    g_szPlayerAuth[id][0] = 0
    g_bPlayerLoaded[id] = false
    g_bPlayerQueued[id] = false
    if(g_iPendingQueryType[id] != 0) {
        g_iPendingQueryType[id] = 0
        g_fPendingQueryTime[id] = 0.0
    }
}

public Fwd_PlayerSpawn_Post(id)
{
    if(!is_user_alive(id) || is_user_bot(id) || is_user_hltv(id)) return
    if(!g_bPlayerLoaded[id]) return
    set_task(0.1, "Task_ApplySpawnModel", id)
}

public Task_ApplySpawnModel(id)
{
    if(is_user_connected(id) && is_user_alive(id)) ApplySelectedModel(id)
}

public Fwd_PlayerPostThink(id)
{
    if(!is_user_alive(id) || !g_bPlayerCustomModel[id]) return FMRES_IGNORED
    if(g_iPlayerBody[id] >= 0) set_pev(id, pev_body, g_iPlayerBody[id])
    if(g_iPlayerSkin[id] >= 0) set_pev(id, pev_skin, g_iPlayerSkin[id])
    return FMRES_IGNORED
}

LoadPlayerData(id)
{
    if(!g_szPlayerAuth[id][0]) return
    new q[256], data[1]
    data[0] = id
    new szSafe[48]
    copy(szSafe, charsmax(szSafe), g_szPlayerAuth[id])
    replace_all(szSafe, charsmax(szSafe), "'", "''")
    formatex(q, charsmax(q), "SELECT owned, selected FROM skin_core_data WHERE authid='%s'", szSafe)
    g_iPendingQueryType[id] = 1
    g_fPendingQueryTime[id] = get_gametime()
    SQL_ThreadQuery(g_hDB, "Query_LoadPlayer", q, data, sizeof(data))
}

public Query_LoadPlayer(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt)
{
    new id = Data[0]
    g_iPendingQueryType[id] = 0
    g_fPendingQueryTime[id] = 0.0
    if(!is_user_connected(id)) return
    if(FailState != TQUERY_SUCCESS) {
        log_amx("[SKIN CORE] Load error: %s", Error)
        if(IsConnectionError(Error, Errcode)) {
            g_bDBConnected = false
            log_amx("[SKIN CORE] Connection lost during load. Reconnecting...")
            ForceReconnect()
        }
        TrySetLoaded(id)
        return
    }
    g_fLastDBSuccess = get_gametime()
    if(SQL_NumResults(Q) > 0) {
        new szOwned[48]
        SQL_ReadResult(Q, 0, szOwned, charsmax(szOwned))
        DeserializeOwned(id, szOwned)
        SQL_ReadResult(Q, 1, g_szPlayerSelected[id], charsmax(g_szPlayerSelected[]))
    } else {
        new ins[256], szSafe[48]
        copy(szSafe, charsmax(szSafe), g_szPlayerAuth[id])
        replace_all(szSafe, charsmax(szSafe), "'", "''")
        formatex(ins, charsmax(ins), "REPLACE INTO skin_core_data (authid, owned, selected) VALUES ('%s', '', '')", szSafe)
        SQL_ThreadQuery(g_hDB, "Query_Void", ins)
    }
    TrySetLoaded(id)
}

public TrySetLoaded(id)
{
    if(!is_user_connected(id)) return
    if(g_bPlayerLoaded[id]) return
    if(!points_is_loaded(id)) {
        set_task(0.3, "TrySetLoaded", id)
        return
    }
    g_bPlayerLoaded[id] = true
    new ret
    ExecuteForward(g_hFwdPlayerLoaded, ret, id)
}

SavePlayerData(id)
{
    if(!g_szPlayerAuth[id][0] || !g_bDBConnected) return
    new szSafe[48], szOwned[48], szSel[48], szQuery[256], data[1]
    data[0] = id
    copy(szSafe, charsmax(szSafe), g_szPlayerAuth[id])
    replace_all(szSafe, charsmax(szSafe), "'", "''")
    SerializeOwned(id, szOwned, charsmax(szOwned))
    copy(szSel, charsmax(szSel), g_szPlayerSelected[id])
    replace_all(szSel, charsmax(szSel), "'", "''")
    formatex(szQuery, charsmax(szQuery), "REPLACE INTO skin_core_data (authid, owned, selected) VALUES ('%s', '%s', '%s')", szSafe, szOwned, szSel)
    g_iPendingQueryType[id] = 2
    g_fPendingQueryTime[id] = get_gametime()
    SQL_ThreadQuery(g_hDB, "Query_SavePlayer", szQuery, data, sizeof(data))
}

SerializeOwned(id, output[], maxlen)
{
    new i, len = 0
    for(i = 0; i < g_iSkinCount && len < maxlen - 1; i++)
        output[len++] = g_bPlayerOwned[id][i] ? '1' : '0'
    output[len] = 0
    return len
}

DeserializeOwned(id, const input[])
{
    new i, inputLen = strlen(input)
    for(i = 0; i < MAX_SKINS; i++) {
        if(i < inputLen && i < g_iSkinCount) g_bPlayerOwned[id][i] = (input[i] == '1') ? 1 : 0
        else g_bPlayerOwned[id][i] = 0
    }
}

public LoadConfig()
{
    g_iSkinCount = 0
    if(!file_exists(g_szConfigPath)) {
        log_amx("[SKIN CORE] Config not found, creating default.")
        CreateDefaultConfig()
        return
    }
    new file = fopen(g_szConfigPath, "r")
    if(!file) {
        log_amx("[SKIN CORE] Failed to open config.")
        return
    }
    // Увеличено до 11 параметров
    new line[256], parsed[11][64]
    while(!feof(file)) {
        fgets(file, line, charsmax(line))
        trim(line)
        if(line[0] == ';' || line[0] == '/' || line[0] == '#' || !line[0]) continue
            
        new count = parse(line, parsed[0], 63, parsed[1], 63, parsed[2], 63, 
                          parsed[3], 63, parsed[4], 63, parsed[5], 63, parsed[6], 63, 
                          parsed[7], 63, parsed[8], 63, parsed[9], 63, parsed[10], 63)
        if(count < 3) continue
        
        for(new i = 0; i < count; i++) {
            remove_quotes(parsed[i])
            trim(parsed[i])
        }
        if(!parsed[0][0]) continue
        
        new type = -1
        if(equali(parsed[2], "split")) {
            type = SKIN_TYPE_SPLIT
            if(count < 5) continue
        } else if(equali(parsed[2], "shared")) {
            type = SKIN_TYPE_SHARED
            if(count < 6) continue
        } else {
            continue
        }
        
        new adminFlag = ADMIN_ALL
        new buyable = 1 // По умолчанию можно купить
        
        if(type == SKIN_TYPE_SHARED) {
            if(count >= 9) {
                adminFlag = read_flags(parsed[8])
                if(count >= 10) buyable = str_to_num(parsed[9]) // НОВОЕ
            } else if(count >= 7) {
                adminFlag = read_flags(parsed[6])
                if(count >= 8) buyable = str_to_num(parsed[7]) // НОВОЕ
            }
            
            new skin_ct = -1, skin_tt = -1
            if(count >= 8) {
                skin_ct = str_to_num(parsed[6]) - 1
                skin_tt = str_to_num(parsed[7]) - 1
            }
            RegisterSkin(parsed[0], str_to_num(parsed[1]), type, parsed[3], parsed[4], parsed[5], skin_ct, skin_tt, adminFlag, buyable)
        } else {
            if(count >= 6) {
                adminFlag = read_flags(parsed[5])
                if(count >= 7) buyable = str_to_num(parsed[6]) // НОВОЕ
            }
            RegisterSkin(parsed[0], str_to_num(parsed[1]), type, parsed[3], parsed[4], "", -1, -1, adminFlag, buyable)
        }
    }
    fclose(file)
    log_amx("[SKIN CORE] Loaded %d skins.", g_iSkinCount)
}

CreateDefaultConfig()
{
    new file = fopen(g_szConfigPath, "w")
    if(!file) return
    fputs(file, "; Skin Core Pro^n")
    fputs(file, "; Format: ^"Name^" ^"Price^" ^"split/shared^" ^"params...^" ^"flag^" ^"buyable(1/0)^"^n")
    fputs(file, "; split: ^"name^" ^"price^" ^"split^" ^"ct.mdl^" ^"tt.mdl^" ^"flag^" ^"buyable^"^n")
    fputs(file, "; shared (old): ^"name^" ^"price^" ^"shared^" ^"model.mdl^" ^"body_ct^" ^"body_tt^" ^"flag^" ^"buyable^"^n")
    fputs(file, "; shared (new): add ^"skin_ct^" ^"skin_tt^" (1-based from HLMV) ^"flag^" ^"buyable^"^n^n")
    fputs(file, "^"Desert Warrior^" ^"100^" ^"split^" ^"models/player/desert/ct.mdl^" ^"models/player/desert/tt.mdl^" ^"^" ^"1^"^n")
    fputs(file, "^"Gold Armor^" ^"200^" ^"shared^" ^"models/player/gold/armor.mdl^" ^"1^" ^"4^" ^"t^" ^"1^"^n")
    fputs(file, "^"Yoda^" ^"500^" ^"shared^" ^"models/player/yoda/yoda.mdl^" ^"0^" ^"0^" ^"1^" ^"2^" ^"t^" ^"0^"^n")
    fclose(file)
    LoadConfig()
}

RegisterSkin(const name[], price, type, const param1[], const param2[], const param3[], skin_ct, skin_tt, adminFlag, buyable)
{
    if(g_iSkinCount >= MAX_SKINS) {
        log_amx("[SKIN CORE] Max skins reached, skipping: %s", name)
        return -1
    }
    if(strlen(name) >= MAX_SKIN_NAME_LEN) {
        log_amx("[SKIN CORE] Name too long: %s", name)
        return -1
    }
    new i
    for(i = 0; i < g_iSkinCount; i++) {
        if(equal(g_eSkins[i][SKIN_NAME], name)) {
            log_amx("[SKIN CORE] Duplicate: %s", name)
            return -1
        }
    }
    
    copy(g_eSkins[g_iSkinCount][SKIN_NAME], charsmax(g_eSkins[][SKIN_NAME]), name)
    g_eSkins[g_iSkinCount][SKIN_PRICE] = price
    g_eSkins[g_iSkinCount][SKIN_TYPE] = type
    g_eSkins[g_iSkinCount][SKIN_FLAG] = adminFlag
    g_eSkins[g_iSkinCount][SKIN_BUYABLE] = buyable // НОВОЕ
    
    if(type == SKIN_TYPE_SPLIT) {
        copy(g_eSkins[g_iSkinCount][SKIN_MODEL_CT], charsmax(g_eSkins[][SKIN_MODEL_CT]), param1)
        copy(g_eSkins[g_iSkinCount][SKIN_MODEL_TT], charsmax(g_eSkins[][SKIN_MODEL_TT]), param2)
        g_eSkins[g_iSkinCount][SKIN_BODY_CT] = 0
        g_eSkins[g_iSkinCount][SKIN_BODY_TT] = 0
        g_eSkins[g_iSkinCount][SKIN_SKIN_CT] = -1
        g_eSkins[g_iSkinCount][SKIN_SKIN_TT] = -1
        if(file_exists(param1)) precache_model(param1)
        if(file_exists(param2)) precache_model(param2)
    } else {
        copy(g_eSkins[g_iSkinCount][SKIN_MODEL_CT], charsmax(g_eSkins[][SKIN_MODEL_CT]), param1)
        copy(g_eSkins[g_iSkinCount][SKIN_MODEL_TT], charsmax(g_eSkins[][SKIN_MODEL_TT]), param1)
        g_eSkins[g_iSkinCount][SKIN_BODY_CT] = str_to_num(param2)
        g_eSkins[g_iSkinCount][SKIN_BODY_TT] = str_to_num(param3)
        g_eSkins[g_iSkinCount][SKIN_SKIN_CT] = skin_ct
        g_eSkins[g_iSkinCount][SKIN_SKIN_TT] = skin_tt
        if(file_exists(param1)) precache_model(param1)
    }
    g_iSkinCount++
    return g_iSkinCount - 1
}

FindSkin(const name[])
{
    new i
    for(i = 0; i < g_iSkinCount; i++)
        if(equal(g_eSkins[i][SKIN_NAME], name)) return i
    return -1
}

bool:IsSkinOwned(id, const name[])
{
    new idx = FindSkin(name)
    if(idx == -1) return false
    return g_bPlayerOwned[id][idx] ? true : false
}

AddSkinToOwned(id, const name[])
{
    new idx = FindSkin(name)
    if(idx != -1) g_bPlayerOwned[id][idx] = 1
}

ExtractModelKey(const path[], output[], len)
{
    new pos = strlen(path) - 1
    new start = 0
    for(new i = pos; i >= 0; i--) {
        if(path[i] == '/' || path[i] == 92) {
            start = i + 1
            break
        }
    }
    new end = strlen(path)
    if(end >= 4 && path[end-4] == '.' && path[end-3] == 'm' && path[end-2] == 'd' && path[end-1] == 'l')
        end -= 4
    new j = 0
    for(new i = start; i < end && j < len - 1; i++)
        output[j++] = path[i]
    output[j] = 0
    return 1
}

ApplySelectedModel(id)
{
    if(!is_user_alive(id)) return false
    if(get_pcvar_num(g_pCvarEnable) == 0) {
        ResetToDefault(id)
        return true
    }
    new team = get_user_team(id)
    if(team < 1 || team > 2) return false
    new base[MAX_SKIN_NAME_LEN]
    copy(base, charsmax(base), g_szPlayerSelected[id])
    if(!base[0]) {
        ResetToDefault(id)
        return true
    }
    new skinIdx = FindSkin(base)
    if(skinIdx == -1) {
        ResetToDefault(id)
        return false
    }
    if(g_eSkins[skinIdx][SKIN_FLAG] != ADMIN_ALL && !(get_user_flags(id) & g_eSkins[skinIdx][SKIN_FLAG])) {
        ResetToDefault(id)
        return false
    }
    if(g_eSkins[skinIdx][SKIN_FLAG] != ADMIN_ALL && !(get_user_flags(id) & g_eSkins[skinIdx][SKIN_FLAG])) {
        ResetToDefault(id)
        return false
    }
    new modelPath[MAX_MODEL_PATH], modelKey[48], body = 0, skin = -1
    if(g_eSkins[skinIdx][SKIN_TYPE] == SKIN_TYPE_SPLIT) {
        g_bPlayerCustomModel[id] = false
        g_iPlayerBody[id] = -1
        g_iPlayerSkin[id] = -1
        if(team == 2) copy(modelPath, charsmax(modelPath), g_eSkins[skinIdx][SKIN_MODEL_CT])
        else copy(modelPath, charsmax(modelPath), g_eSkins[skinIdx][SKIN_MODEL_TT])
    } else {
        g_bPlayerCustomModel[id] = true
        copy(modelPath, charsmax(modelPath), g_eSkins[skinIdx][SKIN_MODEL_CT])
        body = (team == 2) ? g_eSkins[skinIdx][SKIN_BODY_CT] : g_eSkins[skinIdx][SKIN_BODY_TT]
        skin = (team == 2) ? g_eSkins[skinIdx][SKIN_SKIN_CT] : g_eSkins[skinIdx][SKIN_SKIN_TT]
        g_iPlayerBody[id] = body
        g_iPlayerSkin[id] = skin
    }
    if(!file_exists(modelPath)) {
        ResetToDefault(id)
        return false
    }
    ExtractModelKey(modelPath, modelKey, charsmax(modelKey))
    rg_set_user_model(id, modelKey, true)
    if(g_bPlayerCustomModel[id]) {
        if(g_iPlayerBody[id] >= 0) set_pev(id, pev_body, g_iPlayerBody[id])
        if(g_iPlayerSkin[id] >= 0) set_pev(id, pev_skin, g_iPlayerSkin[id])
    }
    return true
}

ResetToDefault(id)
{
    if(!is_user_alive(id)) return false
    new team = get_user_team(id)
    new def[16]
    if(team == 1) copy(def, charsmax(def), "terror")
    else copy(def, charsmax(def), "urban")
    rg_set_user_model(id, def, true)
    g_bPlayerCustomModel[id] = false
    g_iPlayerBody[id] = -1
    g_iPlayerSkin[id] = -1
    return true
}

public _skin_core_register(plugin, params) { return -1; }
public _skin_core_get_count(plugin, params) { return g_iSkinCount; }

public _skin_core_get_info(plugin, params)
{
    if(params != 5) return 0
    new index = get_param(1)
    if(index < 0 || index >= g_iSkinCount) return 0
    set_string(2, g_eSkins[index][SKIN_NAME], get_param(3))
    set_param_byref(4, g_eSkins[index][SKIN_PRICE])
    set_param_byref(5, g_eSkins[index][SKIN_TYPE])
    return 1
}

public _skin_core_find(plugin, params)
{
    if(params != 1) return -1
    new name[MAX_SKIN_NAME_LEN]
    get_string(1, name, charsmax(name))
    return FindSkin(name)
}

public _skin_core_get_points(plugin, params)
{
    if(params != 1) return 0
    new id = get_param(1)
    if(!is_user_connected(id)) return 0
    return points_get(id)
}

public _skin_core_set_points(plugin, params)
{
    if(params != 2) return 0
    new id = get_param(1)
    if(!is_user_connected(id)) return 0
    points_set(id, get_param(2))
    return 1
}

public _skin_core_add_points(plugin, params)
{
    if(params != 2) return 0
    new id = get_param(1)
    if(!is_user_connected(id)) return 0
    new cur = points_get(id)
    points_set(id, cur + get_param(2))
    return points_get(id)
}

public _skin_core_is_owned(plugin, params)
{
    if(params != 2) return false
    new id = get_param(1)
    if(!is_user_connected(id)) return false
    new name[MAX_SKIN_NAME_LEN]
    get_string(2, name, charsmax(name))
    return IsSkinOwned(id, name)
}

public _skin_core_can_access(plugin, params)
{
    if(params != 2) return false
    new id = get_param(1)
    if(!is_user_connected(id)) return false
    new name[MAX_SKIN_NAME_LEN]
    get_string(2, name, charsmax(name))
    new idx = FindSkin(name)
    if(idx == -1) return false
    if(g_eSkins[idx][SKIN_FLAG] == ADMIN_ALL) return true
    return (get_user_flags(id) & g_eSkins[idx][SKIN_FLAG]) ? true : false
}

// НОВЫЙ НАТИВ: Проверка, можно ли купить скин
public _skin_core_is_buyable(plugin, params)
{
    if(params != 2) return false
    new id = get_param(1)
    if(!is_user_connected(id)) return false
    new name[MAX_SKIN_NAME_LEN]
    get_string(2, name, charsmax(name))
    new idx = FindSkin(name)
    if(idx == -1) return false
    return g_eSkins[idx][SKIN_BUYABLE] ? true : false
}

public _skin_core_buy_skin(plugin, params)
{
    if(get_pcvar_num(g_pCvarEnable) == 0) return false
    if(params != 2) return false
    new id = get_param(1)
    if(!is_user_connected(id) || !g_bPlayerLoaded[id]) return false
    
    new name[MAX_SKIN_NAME_LEN]
    get_string(2, name, charsmax(name))
    new idx = FindSkin(name)
    if(idx == -1) return false
    
    // Проверка на возможность покупки
    if(!g_eSkins[idx][SKIN_BUYABLE]) return false
    
    // Проверка флага
    if(g_eSkins[idx][SKIN_FLAG] != ADMIN_ALL && !(get_user_flags(id) & g_eSkins[idx][SKIN_FLAG])) return false
    if(IsSkinOwned(id, name)) return false
    
    new price = g_eSkins[idx][SKIN_PRICE]
    
    // НОВОЕ: Если у скина есть флаг и у игрока он есть - скин БЕСПЛАТНЫЙ
    if(g_eSkins[idx][SKIN_FLAG] != ADMIN_ALL && (get_user_flags(id) & g_eSkins[idx][SKIN_FLAG])) {
        price = 0
    }
    
    new pts = points_get(id)
    if(pts < price) return false
    
    if(price > 0) points_set(id, pts - price) // Списываем очки только если цена > 0
    AddSkinToOwned(id, name)
    if(g_bDBConnected) SavePlayerData(id)
    return true
}

public _skin_core_get_selected(plugin, params)
{
    if(params != 3) return 0
    new id = get_param(1)
    if(!is_user_connected(id)) return 0
    set_string(2, g_szPlayerSelected[id], get_param(3))
    return 1
}

public _skin_core_set_selected(plugin, params)
{
    if(get_pcvar_num(g_pCvarEnable) == 0) return 0
    if(params != 2) return 0
    new id = get_param(1)
    if(!is_user_connected(id)) return 0
    new name[MAX_SKIN_NAME_LEN]
    get_string(2, name, charsmax(name))
    if(!IsSkinOwned(id, name)) return 0
    new idx = FindSkin(name)
    if(idx != -1 && g_eSkins[idx][SKIN_FLAG] != ADMIN_ALL && !(get_user_flags(id) & g_eSkins[idx][SKIN_FLAG])) return 0
    copy(g_szPlayerSelected[id], charsmax(g_szPlayerSelected[]), name)
    if(g_bDBConnected) SavePlayerData(id)
    return 1
}

public _skin_core_reset_selected(plugin, params)
{
    if(params != 1) return 0
    new id = get_param(1)
    if(!is_user_connected(id)) return 0
    g_szPlayerSelected[id][0] = 0
    if(g_bDBConnected) SavePlayerData(id)
    return 1
}

public _skin_core_apply_model(plugin, params)
{
    if(params != 1) return 0
    new id = get_param(1)
    if(!is_user_connected(id)) return 0
    return ApplySelectedModel(id)
}

public _skin_core_force_save(plugin, params)
{
    if(params != 1) return 0
    new id = get_param(1)
    if(!is_user_connected(id) || !g_bDBConnected) return 0
    SavePlayerData(id)
    return 1
}

public _skin_core_is_ready(plugin, params)
{
    if(params != 1) return 0
    new id = get_param(1)
    if(!is_user_connected(id)) return 0
    return g_bPlayerLoaded[id] && points_is_loaded(id)
}

public _skin_core_reload_config(plugin, params)
{
    LoadConfig()
    for(new i = 1; i <= MAX_PLAYERS; i++) {
        if(is_user_connected(i) && !is_user_bot(i) && !is_user_hltv(i) && g_bDBConnected && g_szPlayerAuth[i][0]) {
            for(new j = 0; j < MAX_SKINS; j++) g_bPlayerOwned[i][j] = 0
            g_szPlayerSelected[i][0] = 0
            g_bPlayerLoaded[i] = false
            g_bPlayerQueued[i] = false
            LoadPlayerData(i)
        }
    }
    return g_iSkinCount
}

public _skin_core_get_flag(plugin, params)
{
    if(params != 1) return 0
    new index = get_param(1)
    if(index < 0 || index >= g_iSkinCount) return 0
    return g_eSkins[index][SKIN_FLAG]
}