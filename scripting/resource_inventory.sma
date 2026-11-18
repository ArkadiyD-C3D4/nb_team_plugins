#include <amxmodx>
#include <amxmisc>
#include <sqlx>

#define PLUGIN "Resource Inventory System"
#define VERSION "2.1"
#define AUTHOR "nb_team"

#define MAX_RESOURCES 64
#define MAX_PLAYERS 32
#define SAVE_INTERVAL 120.0

#define MAX_RES_NAME_LEN 64
#define MAX_STEAMID_LEN 35

enum _:ResourceData {
    res_Name[MAX_RES_NAME_LEN],
    res_DbId
}

enum _:PlayerData {
    pdSteamId[MAX_STEAMID_LEN],
    bool:pdLoaded,
    pdResources[MAX_RESOURCES]
}

new g_eResources[MAX_RESOURCES][ResourceData];
new g_iResourceCount = 0;

new g_ePlayers[MAX_PLAYERS + 1][PlayerData];
new Trie:g_tResourceNameToId;

new Handle:g_SqlTuple;
new bool:g_bSqlConnected = false;

new g_szResourcesFile[128];

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    g_tResourceNameToId = TrieCreate();

    get_configsdir(g_szResourcesFile, charsmax(g_szResourcesFile));
    add(g_szResourcesFile, charsmax(g_szResourcesFile), "/resources.ini");

    LoadResourcesFromIni();
    InitializeSql();

    set_task(SAVE_INTERVAL, "Task_AutoSave", .flags="b");
}

public plugin_end() {
    if (g_SqlTuple) {
        SQL_FreeHandle(g_SqlTuple);
    }
    TrieDestroy(g_tResourceNameToId);
}

// ==========================================
// РАБОТА С INI ФАЙЛОМ
// ==========================================

LoadResourcesFromIni() {
    if (!file_exists(g_szResourcesFile)) {
        new f = fopen(g_szResourcesFile, "w");
        if (f) {
            fputs(f, "; Файл ресурсов. Формат: ^"Название^" Цена^n");
            fputs(f, "^"Обломок белого железа^" 50^n");
            fputs(f, "^"Древесина^" 10^n");
            fclose(f);
        }
    }

    new f = fopen(g_szResourcesFile, "r");
    if (!f) return;

    new szLine[128], szName[MAX_RES_NAME_LEN], szPrice[16];
    while (!feof(f) && g_iResourceCount < MAX_RESOURCES) {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);

        if (!szLine[0] || szLine[0] == ';' || szLine[0] == '/') continue;

        // Парсим строку: "Название" Цена
        parse(szLine, szName, charsmax(szName), szPrice, charsmax(szPrice));

        copy(g_eResources[g_iResourceCount][res_Name], MAX_RES_NAME_LEN - 1, szName);
        g_eResources[g_iResourceCount][res_DbId] = 0;
        
        strtolower(szName);
        TrieSetCell(g_tResourceNameToId, szName, g_iResourceCount);
        
        g_iResourceCount++;
    }
    fclose(f);
    log_amx("[Resources] Loaded %d resources from INI file.", g_iResourceCount);
}

// ==========================================
// РАБОТА С БАЗОЙ ДАННЫХ (SQL)
// ==========================================

InitializeSql() {
    new szHost[64], szUser[64], szPass[64], szDb[64];
    get_cvar_string("amx_sql_host", szHost, charsmax(szHost));
    get_cvar_string("amx_sql_user", szUser, charsmax(szUser));
    get_cvar_string("amx_sql_pass", szPass, charsmax(szPass));
    get_cvar_string("amx_sql_db", szDb, charsmax(szDb));

    g_SqlTuple = SQL_MakeDbTuple(szHost, szUser, szPass, szDb);

    // РАЗДЕЛЯЕМ СОЗДАНИЕ ТАБЛИЦ НА РАЗНЫЕ ЗАПРОСЫ!
    SQL_ThreadQuery(g_SqlTuple, "Query_IgnoreHandle", "CREATE TABLE IF NOT EXISTS `res_inv_items` (`id` INT AUTO_INCREMENT PRIMARY KEY, `name` VARCHAR(64) NOT NULL UNIQUE);");
    
    // Вторую таблицу отправляем с коллбэком Query_Connect, чтобы начать синхронизацию после ее создания
    SQL_ThreadQuery(g_SqlTuple, "Query_Connect", "CREATE TABLE IF NOT EXISTS `res_inv_data` (`steamid` VARCHAR(35) NOT NULL, `item_id` INT NOT NULL, `amount` INT NOT NULL DEFAULT 0, PRIMARY KEY (`steamid`, `item_id`));");
}

public Query_Connect(failstate, Handle:query, error[], errcode, data[], datasize, Float:queuetime) {
    if (failstate == TQUERY_CONNECT_FAILED || failstate == TQUERY_QUERY_FAILED) {
        log_amx("[Resources] SQL Connection Failed: %s", error);
        g_bSqlConnected = false;
        set_task(15.0, "Task_Reconnect");
        return;
    }

    g_bSqlConnected = true;
    log_amx("[Resources] SQL Connected successfully. Syncing resources...");

    SyncResourcesToDb();
}

public Task_Reconnect() {
    if (!g_bSqlConnected) {
        log_amx("[Resources] Attempting to reconnect to database...");
        SQL_ThreadQuery(g_SqlTuple, "Query_Connect", "SELECT 1");
    }
}

// Ручное экранирование строк (надежнее, чем SQL_QuoteString с Tuple)
EscapeString(const src[], dest[], len) {
    copy(dest, len, src);
    replace_string(dest, len, "\\", "\\\\", false);
    replace_string(dest, len, "'", "\\'", false);
}

SyncResourcesToDb() {
    if (!g_bSqlConnected) return;

    new szQuery[128];
    formatex(szQuery, charsmax(szQuery), "SELECT `id`, `name` FROM `res_inv_items`;");
    
    new data[1];
    data[0] = 0; // 0 - первая загрузка
    SQL_ThreadQuery(g_SqlTuple, "Query_LoadAllItems", szQuery, data, sizeof(data));
}

public Query_LoadAllItems(failstate, Handle:query, error[], errcode, data[], datasize, Float:queuetime) {
    if (failstate) {
        log_amx("[Resources] Failed to load items: %s", error);
        return;
    }

    new isRetry = data[0];
    new szName[MAX_RES_NAME_LEN], szLowName[MAX_RES_NAME_LEN], iId, resIdx;
    new bool:needsInsert = false;

    while (SQL_MoreResults(query)) {
        iId = SQL_ReadResult(query, 0);
        SQL_ReadResult(query, 1, szName, charsmax(szName));

        copy(szLowName, charsmax(szLowName), szName);
        strtolower(szLowName);

        if (TrieGetCell(g_tResourceNameToId, szLowName, resIdx)) {
            g_eResources[resIdx][res_DbId] = iId;
        }
        SQL_NextRow(query);
    }

    for (new i = 0; i < g_iResourceCount; i++) {
        if (g_eResources[i][res_DbId] == 0) {
            needsInsert = true;
            break;
        }
    }

    if (needsInsert && !isRetry) {
        new szInsertQuery[256], szEscName[128];
        
        // Вставляем каждый недостающий ресурс отдельным запросом
        for (new i = 0; i < g_iResourceCount; i++) {
            if (g_eResources[i][res_DbId] == 0) {
                EscapeString(g_eResources[i][res_Name], szEscName, charsmax(szEscName));
                formatex(szInsertQuery, charsmax(szInsertQuery), "INSERT IGNORE INTO `res_inv_items` (`name`) VALUES ('%s');", szEscName);
                SQL_ThreadQuery(g_SqlTuple, "Query_IgnoreHandle", szInsertQuery);
            }
        }

        // Запрашиваем список заново, чтобы получить ID новых ресурсов
        new szQuery[128];
        formatex(szQuery, charsmax(szQuery), "SELECT `id`, `name` FROM `res_inv_items`;");
        
        new retryData[1];
        retryData[0] = 1; // Помечаем, что это повторная загрузка
        SQL_ThreadQuery(g_SqlTuple, "Query_LoadAllItems", szQuery, retryData, sizeof(retryData));
    } else {
        log_amx("[Resources] All resources synced with DB. Total: %d", g_iResourceCount);
        
        for (new id = 1; id <= MaxClients; id++) {
            if (is_user_connected(id) && !g_ePlayers[id][pdLoaded]) {
                LoadPlayerData(id);
            }
        }
    }
}

// ==========================================
// ЗАГРУЗКА, СОХРАНЕНИЕ ИГРОКА И МГНОВЕННОЕ СОХРАНЕНИЕ
// ==========================================

public client_putinserver(id) {
    g_ePlayers[id][pdLoaded] = false;
    arrayset(g_ePlayers[id][pdResources], 0, MAX_RESOURCES);
    get_user_authid(id, g_ePlayers[id][pdSteamId], MAX_STEAMID_LEN - 1);

    if (g_bSqlConnected && g_iResourceCount > 0 && g_eResources[0][res_DbId] != 0) {
        LoadPlayerData(id);
    }
}

public client_disconnected(id) {
    if (g_ePlayers[id][pdLoaded]) {
        SavePlayerData(id);
    }
}

LoadPlayerData(id) {
    if (!g_ePlayers[id][pdSteamId][0]) return;

    new szQuery[256];
    formatex(szQuery, charsmax(szQuery), "SELECT `item_id`, `amount` FROM `res_inv_data` WHERE `steamid`='%s';", g_ePlayers[id][pdSteamId]);
    
    new data[1];
    data[0] = id;
    SQL_ThreadQuery(g_SqlTuple, "Query_LoadPlayer", szQuery, data, sizeof(data));
}

public Query_LoadPlayer(failstate, Handle:query, error[], errcode, data[], datasize, Float:queuetime) {
    new id = data[0];
    if (!is_user_connected(id)) return;

    if (failstate) {
        log_amx("[Resources] Load failed for %s: %s", g_ePlayers[id][pdSteamId], error);
        return;
    }

    new iItemId, iAmount;
    while (SQL_MoreResults(query)) {
        iItemId = SQL_ReadResult(query, 0);
        iAmount = SQL_ReadResult(query, 1);

        for (new i = 0; i < g_iResourceCount; i++) {
            if (g_eResources[i][res_DbId] == iItemId) {
                g_ePlayers[id][pdResources][i] = iAmount;
                break;
            }
        }
        SQL_NextRow(query);
    }

    g_ePlayers[id][pdLoaded] = true;
}

// Полное сохранение (при выходе и автосейве)
SavePlayerData(id) {
    if (!g_ePlayers[id][pdLoaded] || !g_bSqlConnected) return;

    new szQuery[512], szSteamId[MAX_STEAMID_LEN];
    copy(szSteamId, charsmax(szSteamId), g_ePlayers[id][pdSteamId]);

    for (new i = 0; i < g_iResourceCount; i++) {
        new amount = g_ePlayers[id][pdResources][i];
        new dbId = g_eResources[i][res_DbId];

        if (dbId != 0) {
            if (amount > 0) {
                formatex(szQuery, charsmax(szQuery), "INSERT INTO `res_inv_data` (`steamid`, `item_id`, `amount`) VALUES ('%s', %d, %d) ON DUPLICATE KEY UPDATE `amount`=%d;", szSteamId, dbId, amount, amount);
            } else {
                formatex(szQuery, charsmax(szQuery), "DELETE FROM `res_inv_data` WHERE `steamid`='%s' AND `item_id`=%d;", szSteamId, dbId);
            }
            SQL_ThreadQuery(g_SqlTuple, "Query_IgnoreHandle", szQuery);
        }
    }
}

// МГНОВЕННОЕ СОХРАНЕНИЕ КОНКРЕТНОГО РЕСУРСА (Вызывается из нативов)
SaveSingleResource(id, resIdx) {
    if (!g_ePlayers[id][pdLoaded] || !g_bSqlConnected) return;

    new dbId = g_eResources[resIdx][res_DbId];
    if (dbId == 0) {
        log_amx("[Resources] Error: Resource DB ID is 0. Cannot save.");
        return;
    }

    new szQuery[256], szSteamId[MAX_STEAMID_LEN];
    copy(szSteamId, charsmax(szSteamId), g_ePlayers[id][pdSteamId]);
    new amount = g_ePlayers[id][pdResources][resIdx];

    if (amount > 0) {
        formatex(szQuery, charsmax(szQuery), "INSERT INTO `res_inv_data` (`steamid`, `item_id`, `amount`) VALUES ('%s', %d, %d) ON DUPLICATE KEY UPDATE `amount`=%d;", szSteamId, dbId, amount, amount);
    } else {
        formatex(szQuery, charsmax(szQuery), "DELETE FROM `res_inv_data` WHERE `steamid`='%s' AND `item_id`=%d;", szSteamId, dbId);
    }
    
    SQL_ThreadQuery(g_SqlTuple, "Query_IgnoreHandle", szQuery);
}

public Task_AutoSave() {
    for (new id = 1; id <= MaxClients; id++) {
        if (is_user_connected(id) && g_ePlayers[id][pdLoaded]) {
            SavePlayerData(id);
        }
    }
}

public Query_IgnoreHandle(failstate, Handle:query, error[], errcode, data[], datasize, Float:queuetime) {
    if (failstate) {
        log_amx("[Resources] SQL Error: %s", error);
    }
}

// ==========================================
// API (Нативы для других плагинов)
// ==========================================

public plugin_natives() {
    register_native("api_get_resource_id", "Native_GetResourceId");
    register_native("api_give_resource", "Native_GiveResource");
    register_native("api_take_resource", "Native_TakeResource");
    register_native("api_get_resource_amount", "Native_GetResourceAmount");
    register_native("api_has_multiple_resources", "Native_HasMultipleResources");
    register_native("api_take_multiple_resources", "Native_TakeMultipleResources");
    
    register_native("api_get_resources_count", "Native_GetResourcesCount");
    register_native("api_get_resource_name", "Native_GetResourceName");
}

public Native_GetResourcesCount(plugin, params) {
    return g_iResourceCount;
}

public Native_GetResourceName(plugin, params) {
    new resIdx = get_param(1);
    new len = get_param(3);
    
    if (resIdx < 0 || resIdx >= g_iResourceCount) return 0;
    
    set_string(2, g_eResources[resIdx][res_Name], len);
    return 1;
}

public Native_GetResourceId(plugin, params) {
    new szName[MAX_RES_NAME_LEN];
    get_string(1, szName, charsmax(szName));
    strtolower(szName);

    new resIdx;
    if (TrieGetCell(g_tResourceNameToId, szName, resIdx)) {
        return resIdx;
    }
    return -1;
}

public Native_GiveResource(plugin, params) {
    new id = get_param(1);
    new resIdx = get_param(2);
    new amount = get_param(3);

    if (id < 1 || id > MaxClients || !is_user_connected(id)) return 0;
    if (resIdx < 0 || resIdx >= g_iResourceCount) return 0;
    if (amount <= 0) return 0;

    g_ePlayers[id][pdResources][resIdx] += amount;
    
    // МГНОВЕННОЕ СОХРАНЕНИЕ
    SaveSingleResource(id, resIdx);
    
    return 1;
}

public Native_TakeResource(plugin, params) {
    new id = get_param(1);
    new resIdx = get_param(2);
    new amount = get_param(3);

    if (id < 1 || id > MaxClients || !is_user_connected(id)) return 0;
    if (resIdx < 0 || resIdx >= g_iResourceCount) return 0;
    if (amount <= 0) return 0;

    if (g_ePlayers[id][pdResources][resIdx] >= amount) {
        g_ePlayers[id][pdResources][resIdx] -= amount;
        
        // МГНОВЕННОЕ СОХРАНЕНИЕ
        SaveSingleResource(id, resIdx);
        
        return 1;
    }
    return 0;
}

public Native_GetResourceAmount(plugin, params) {
    new id = get_param(1);
    new resIdx = get_param(2);

    if (id < 1 || id > MaxClients || !is_user_connected(id)) return 0;
    if (resIdx < 0 || resIdx >= g_iResourceCount) return 0;

    return g_ePlayers[id][pdResources][resIdx];
}

public Native_HasMultipleResources(plugin, params) {
    new id = get_param(1);
    new arrResIds[32], arrAmounts[32];
    new size = get_param(4);

    if (size > 32) size = 32;
    get_array(2, arrResIds, size);
    get_array(3, arrAmounts, size);

    if (id < 1 || id > MaxClients || !is_user_connected(id)) return 0;

    for (new i = 0; i < size; i++) {
        new resIdx = arrResIds[i];
        if (resIdx < 0 || resIdx >= g_iResourceCount) return 0;
        if (g_ePlayers[id][pdResources][resIdx] < arrAmounts[i]) {
            return 0;
        }
    }
    return 1;
}

public Native_TakeMultipleResources(plugin, params) {
    new id = get_param(1);
    new arrResIds[32], arrAmounts[32];
    new size = get_param(4);

    if (size > 32) size = 32;
    get_array(2, arrResIds, size);
    get_array(3, arrAmounts, size);

    if (id < 1 || id > MaxClients || !is_user_connected(id)) return 0;

    for (new i = 0; i < size; i++) {
        new resIdx = arrResIds[i];
        if (resIdx < 0 || resIdx >= g_iResourceCount) return 0;
        if (g_ePlayers[id][pdResources][resIdx] < arrAmounts[i]) {
            return 0;
        }
    }

    for (new i = 0; i < size; i++) {
        new resIdx = arrResIds[i];
        g_ePlayers[id][pdResources][resIdx] -= arrAmounts[i];
        
        // МГНОВЕННОЕ СОХРАНЕНИЕ для каждого ресурса в крафте
        SaveSingleResource(id, resIdx);
    }
    
    return 1;
}