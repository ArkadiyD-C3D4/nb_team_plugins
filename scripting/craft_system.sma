#include <amxmodx>
#include <amxmisc>
#include <fun>
#include <hamsandwich>
#include <sqlx>

// Нативы инвентаря
native api_get_resource_id(const szName[]);
native api_get_resource_name(resId, buffer[], len);
native api_get_resources_count();
native api_has_multiple_resources(id, arrResIds[], arrAmounts[], size);
native api_take_multiple_resources(id, arrResIds[], arrAmounts[], size);
native api_get_resource_amount(id, resId);

#define MAX_ITEMS 64
#define MAX_PROPS 16
#define MAX_RECIPE 8
#define MAX_PROP_NAME 32
#define MAX_ITEM_NAME 64

// --- РЕГИСТРАЦИЯ СВОЙСТВ ---
enum _:PropertyData {
    szPropName[MAX_PROP_NAME]
}
new g_eProperties[MAX_PROPS][PropertyData];
new g_iPropCount = 0;

// --- ДАННЫЕ ПРЕДМЕТОВ ---
new g_szItemName[MAX_ITEMS][MAX_ITEM_NAME];
new g_iItemType[MAX_ITEMS]; // 1 = Accessory
new g_iItemPropVals[MAX_ITEMS][MAX_PROPS];
new g_iItemRecipeRes[MAX_ITEMS][MAX_RECIPE];
new g_iItemRecipeAmt[MAX_ITEMS][MAX_RECIPE];
new g_iItemRecipeCount[MAX_ITEMS];
new g_iItemCount = 0;

// --- ДАННЫЕ ИГРОКОВ ---
new g_iActiveItem[33];     // Надетый предмет
new g_iPendingItem[33];    // Ожидает надевания в след. раунде
new bool:g_bOwnedItems[33][MAX_ITEMS]; // Владение предметами
new bool:g_bPlayerLoaded[33];
new g_szSteamId[33][35];

// --- ПЕРЕМЕННЫЕ ДЛЯ АДМИН-МЕНЮ ---
new g_iAdminEditingItem[33];
new g_iAdminEditingProp[33];
new g_iAdminEditingRes[33];
new g_iAdminTargetPlayer[33];

new g_szCraftFile[128];

// --- SQL ---
new Handle:g_SqlTuple;
new bool:g_bSqlConnected = false;

new g_iPlayerDamageResist[33];

public plugin_init() {
    register_plugin("Craft System Framework", "2.0", "nb_team");
    
    RegisterProperty("speed");
    RegisterProperty("gravity");
    RegisterProperty("health");
    RegisterProperty("armor");
    RegisterProperty("damage_resist");

    register_clcmd("say /craft", "Cmd_CraftMenu");
    register_clcmd("say_team /craft", "Cmd_CraftMenu");
    register_clcmd("say /craft_admin", "Cmd_CraftAdmin", ADMIN_LEVEL_H);
    
    register_clcmd("EnterItemName", "ClCmd_EnterItemName");
    register_clcmd("EnterPropValue", "ClCmd_EnterPropValue");
    register_clcmd("EnterRecipeAmount", "ClCmd_EnterRecipeAmount");

    RegisterHam(Ham_Spawn, "player", "Ham_PlayerSpawn_Post", 1);
    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");
    RegisterHam(Ham_TakeDamage, "player", "Ham_TakeDamage_Pre", 0);

    get_configsdir(g_szCraftFile, charsmax(g_szCraftFile));
    add(g_szCraftFile, charsmax(g_szCraftFile), "/craft_items.ini");
    LoadCraftItems();

    InitializeSql();
}

stock RegisterProperty(const szName[]) {
    if (g_iPropCount >= MAX_PROPS) return;
    copy(g_eProperties[g_iPropCount][szPropName], MAX_PROP_NAME - 1, szName);
    g_iPropCount++;
}

// ==========================================
// РАБОТА С БАЗОЙ ДАННЫХ
// ==========================================
InitializeSql() {
    new szHost[64], szUser[64], szPass[64], szDb[64];
    get_cvar_string("amx_sql_host", szHost, charsmax(szHost));
    get_cvar_string("amx_sql_user", szUser, charsmax(szUser));
    get_cvar_string("amx_sql_pass", szPass, charsmax(szPass));
    get_cvar_string("amx_sql_db", szDb, charsmax(szDb));

    g_SqlTuple = SQL_MakeDbTuple(szHost, szUser, szPass, szDb);

    SQL_ThreadQuery(g_SqlTuple, "Query_IgnoreHandle", "CREATE TABLE IF NOT EXISTS `res_craft_owned` (`steamid` VARCHAR(35) NOT NULL, `item_id` INT NOT NULL, PRIMARY KEY (`steamid`, `item_id`));");
    SQL_ThreadQuery(g_SqlTuple, "Query_Connect", "CREATE TABLE IF NOT EXISTS `res_craft_equip` (`steamid` VARCHAR(35) NOT NULL, `slot` INT NOT NULL, `item_id` INT NOT NULL DEFAULT -1, PRIMARY KEY (`steamid`, `slot`));");
}

public Query_Connect(failstate, Handle:query, error[], errcode, data[], datasize, Float:queuetime) {
    if (failstate == TQUERY_CONNECT_FAILED || failstate == TQUERY_QUERY_FAILED) {
        log_amx("[Craft] SQL Error: %s", error);
        g_bSqlConnected = false;
        set_task(15.0, "Task_Reconnect");
        return;
    }

    g_bSqlConnected = true;
    log_amx("[Craft] SQL Connected.");

    for (new id = 1; id <= MaxClients; id++) {
        if (is_user_connected(id) && !g_bPlayerLoaded[id]) {
            LoadPlayerCraftData(id);
        }
    }
}

public Task_Reconnect() {
    if (!g_bSqlConnected) {
        SQL_ThreadQuery(g_SqlTuple, "Query_Connect", "SELECT 1");
    }
}

public client_putinserver(id) {
    g_iActiveItem[id] = -1;
    g_iPendingItem[id] = -1;
    arrayset(g_bOwnedItems[id], false, MAX_ITEMS);
    g_bPlayerLoaded[id] = false;
    g_iPlayerDamageResist[id] = 0;
    get_user_authid(id, g_szSteamId[id], charsmax(g_szSteamId[]));

    if (g_bSqlConnected) {
        LoadPlayerCraftData(id);
    }
}

public client_disconnected(id) {
    // Если данные не загрузились, мы ничего не сохраняем, 
    // чтобы не перезаписать базу пустыми слотами (защита от гонки запросов)
    if (g_bPlayerLoaded[id]) {
        if (g_iPendingItem[id] != -1) {
            SavePlayerEquip(id);
        }
    }
    g_bPlayerLoaded[id] = false;
}

LoadPlayerCraftData(id) {
    if (!g_szSteamId[id][0]) return;

    new szQuery[256], data[1];
    data[0] = id;

    // Шаг 1: Грузим надетые предметы. Коллбэк Query_LoadEquip вызовет загрузку скрафченных.
    formatex(szQuery, charsmax(szQuery), "SELECT `slot`, `item_id` FROM `res_craft_equip` WHERE `steamid`='%s';", g_szSteamId[id]);
    SQL_ThreadQuery(g_SqlTuple, "Query_LoadEquip", szQuery, data, sizeof(data));
}

public Query_LoadOwned(failstate, Handle:query, error[], errcode, data[], datasize, Float:queuetime) {
    new id = data[0];
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    
    if (failstate) { 
        log_amx("[Craft] Load Owned Error: %s", error); 
        return PLUGIN_HANDLED; 
    }

    while (SQL_MoreResults(query)) {
        new itemId = SQL_ReadResult(query, 0);
        if (itemId >= 0 && itemId < MAX_ITEMS) {
            g_bOwnedItems[id][itemId] = true;
        }
        SQL_NextRow(query);
    }
    
    // Шаг 3: Обе таблицы загружены. Разрешаем игроку использовать крафт.
    g_bPlayerLoaded[id] = true;
    
    return PLUGIN_HANDLED;
}

public Query_LoadEquip(failstate, Handle:query, error[], errcode, data[], datasize, Float:queuetime) {
    new id = data[0];
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    
    if (failstate) { 
        log_amx("[Craft] Load Equip Error: %s", error); 
        return PLUGIN_HANDLED; 
    }

    while (SQL_MoreResults(query)) {
        new slot = SQL_ReadResult(query, 0);
        new itemId = SQL_ReadResult(query, 1);
        
        // slot 5 = Аксессуар (задел на будущее для брони)
        if (slot == 5 && itemId >= 0) {
            g_iActiveItem[id] = itemId;
            g_iPendingItem[id] = itemId;
        }
        SQL_NextRow(query);
    }
    
    // Шаг 2: Запускаем загрузку скрафченных предметов
    new szQuery[256], data2[1];
    data2[0] = id;
    formatex(szQuery, charsmax(szQuery), "SELECT `item_id` FROM `res_craft_owned` WHERE `steamid`='%s';", g_szSteamId[id]);
    SQL_ThreadQuery(g_SqlTuple, "Query_LoadOwned", szQuery, data2, sizeof(data2));
    
    return PLUGIN_HANDLED;
}
SavePlayerEquip(id) {
    if (!g_bSqlConnected || !g_szSteamId[id][0]) return;

    new szQuery[256];
    new itemId = (g_iPendingItem[id] != -1) ? g_iPendingItem[id] : g_iActiveItem[id];
    
    formatex(szQuery, charsmax(szQuery), "REPLACE INTO `res_craft_equip` (`steamid`, `slot`, `item_id`) VALUES ('%s', 5, %d);", g_szSteamId[id], itemId);
    SQL_ThreadQuery(g_SqlTuple, "Query_IgnoreHandle", szQuery);
}

SavePlayerOwned(id, itemId) {
    if (!g_bSqlConnected || !g_szSteamId[id][0]) return;

    new szQuery[256];
    formatex(szQuery, charsmax(szQuery), "INSERT IGNORE INTO `res_craft_owned` (`steamid`, `item_id`) VALUES ('%s', %d);", g_szSteamId[id], itemId);
    SQL_ThreadQuery(g_SqlTuple, "Query_IgnoreHandle", szQuery);
}

public Query_IgnoreHandle(failstate, Handle:query, error[], errcode, data[], datasize, Float:queuetime) {
    if (failstate) log_amx("[Craft] SQL Error: %s", error);
}

// ==========================================
// ЧТЕНИЕ ИЗ INI
// ==========================================
LoadCraftItems() {
    if (!file_exists(g_szCraftFile)) return;
    new f = fopen(g_szCraftFile, "r");
    if (!f) return;

    new szLine[128], szKey[64], szValue[64];
    new bool:bInSection = false;

    while (!feof(f) && g_iItemCount < MAX_ITEMS) {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);
        if (!szLine[0] || szLine[0] == ';') continue;

        if (szLine[0] == '[') {
            if (bInSection) g_iItemCount++;
            new len = strlen(szLine);
            szLine[len-1] = 0;
            copy(g_szItemName[g_iItemCount], MAX_ITEM_NAME - 1, szLine[1]);
            
            g_iItemType[g_iItemCount] = 0;
            arrayset(g_iItemPropVals[g_iItemCount], 0, MAX_PROPS);
            g_iItemRecipeCount[g_iItemCount] = 0;
            bInSection = true;
        } else if (bInSection) {
            split(szLine, szKey, charsmax(szKey), szValue, charsmax(szValue), "=");
            trim(szKey); trim(szValue);

            if (equali(szKey, "type")) {
                g_iItemType[g_iItemCount] = str_to_num(szValue);
            } else if (contain(szKey, "res_") == 0) {
                new resName[64];
                copy(resName, charsmax(resName), szKey[4]);
                new resId = api_get_resource_id(resName);
                if (resId != -1 && g_iItemRecipeCount[g_iItemCount] < MAX_RECIPE) {
                    new idx = g_iItemRecipeCount[g_iItemCount];
                    g_iItemRecipeRes[g_iItemCount][idx] = resId;
                    g_iItemRecipeAmt[g_iItemCount][idx] = str_to_num(szValue);
                    g_iItemRecipeCount[g_iItemCount]++;
                }
            } else {
                for (new p = 0; p < g_iPropCount; p++) {
                    if (equali(szKey, g_eProperties[p][szPropName])) {
                        g_iItemPropVals[g_iItemCount][p] = str_to_num(szValue);
                        break;
                    }
                }
            }
        }
    }
    if (bInSection) g_iItemCount++;
    fclose(f);
}

SaveCraftItems() {
    new f = fopen(g_szCraftFile, "w");
    if (!f) return;

    for (new i = 0; i < g_iItemCount; i++) {
        fprintf(f, "[%s]^n", g_szItemName[i]);
        fprintf(f, "type = %d^n", g_iItemType[i]);
        
        for (new p = 0; p < g_iPropCount; p++) {
            if (g_iItemPropVals[i][p] != 0) {
                fprintf(f, "%s = %d^n", g_eProperties[p][szPropName], g_iItemPropVals[i][p]);
            }
        }
        
        for (new r = 0; r < g_iItemRecipeCount[i]; r++) {
            new szResName[64];
            api_get_resource_name(g_iItemRecipeRes[i][r], szResName, charsmax(szResName));
            fprintf(f, "res_%s = %d^n", szResName, g_iItemRecipeAmt[i][r]);
        }
        fprintf(f, "^n");
    }
    fclose(f);
}

// ==========================================
// ПРИМЕНЕНИЕ СТАТОВ
// ==========================================
ApplyItemStats(id, itemId) {
    set_user_gravity(id, 1.0);
    set_user_maxspeed(id, 250.0);
    g_iPlayerDamageResist[id] = 0;
    
    if (itemId == -1) return;

    for (new p = 0; p < g_iPropCount; p++) {
        new val = g_iItemPropVals[itemId][p];
        if (val == 0) continue;

        if (equali(g_eProperties[p][szPropName], "health")) {
            set_user_health(id, get_user_health(id) + val);
        } else if (equali(g_eProperties[p][szPropName], "armor")) {
            set_user_armor(id, get_user_armor(id) + val);
        } else if (equali(g_eProperties[p][szPropName], "gravity")) {
            set_user_gravity(id, float(val) / 1000.0);
        } else if (equali(g_eProperties[p][szPropName], "damage_resist")) {
            g_iPlayerDamageResist[id] = val;
        } else if (equali(g_eProperties[p][szPropName], "speed")) {
            set_user_maxspeed(id, float(val));
        }
    }
}

public Task_ApplyStats(id) {
    if (!is_user_alive(id)) return;
    ApplyItemStats(id, g_iActiveItem[id]);
}

public Ham_TakeDamage_Pre(victim, inflictor, attacker, Float:damage, damagebits) {
    if (g_iPlayerDamageResist[victim] > 0) {
        new Float:newDmg = damage * (1.0 - (float(g_iPlayerDamageResist[victim]) / 100.0));
        SetHamParamFloat(4, newDmg);
    }
    return HAM_HANDLED;
}

public Ham_PlayerSpawn_Post(id) {
    if (!is_user_alive(id)) return HAM_IGNORED;

    if (g_iPendingItem[id] != -1) {
        g_iActiveItem[id] = g_iPendingItem[id];
        g_iPendingItem[id] = -1;
        client_print(id, print_chat, "[Craft] Ваш новый аксессуар активирован!");
    }
    
    set_task(0.5, "Task_ApplyStats", id);
    return HAM_IGNORED;
}

public Event_CurWeapon(id) {
    if (!is_user_alive(id)) return;
    if (g_iActiveItem[id] == -1) return;

    new itemId = g_iActiveItem[id];
    for (new p = 0; p < g_iPropCount; p++) {
        if (equali(g_eProperties[p][szPropName], "speed") && g_iItemPropVals[itemId][p] > 0) {
            set_user_maxspeed(id, float(g_iItemPropVals[itemId][p]));
            break;
        }
    }
}

// ==========================================
// МЕНЮ ИГРОКА
// ==========================================
public Cmd_CraftMenu(id) {
    // Защита от гонки запросов: ждем пока БД отдаст данные о крафте
    if (!g_bPlayerLoaded[id]) {
        client_print(id, print_chat, "[Craft] Ваши данные еще загружаются, подождите пару секунд...");
        return PLUGIN_HANDLED;
    }

    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\rМеню Крафта^n\yВыберите слот:");
    new menu = menu_create(szTitle, "Handler_CraftMain");

    menu_additem(menu, "Шлем \r[Закрыто]", "0");
    menu_additem(menu, "Нагрудник \r[Закрыто]", "0");
    menu_additem(menu, "Поножи \r[Закрыто]", "0");
    menu_additem(menu, "Обувь \r[Закрыто]", "0");
    menu_additem(menu, "\yАксессуар \w[Открыто]", "1");

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public Handler_CraftMain(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[16], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    if (str_to_num(data) == 1) ShowAccessoriesMenu(id);
    else menu_destroy(menu);
    return PLUGIN_HANDLED;
}

ShowAccessoriesMenu(id) {
    new szTitle[128], szPending[64] = "Нет";
    if (g_iPendingItem[id] != -1) {
        copy(szPending, charsmax(szPending), g_szItemName[g_iPendingItem[id]]);
    } else if (g_iActiveItem[id] != -1) {
        copy(szPending, charsmax(szPending), g_szItemName[g_iActiveItem[id]]);
    }
    formatex(szTitle, charsmax(szTitle), "\rКрафт: \yАксессуары^n\dНадет/Ожидает: %s", szPending);
    new menu = menu_create(szTitle, "Handler_Accessories");

    new szItem[128], szInfo[16], iCount;
    for (new i = 0; i < g_iItemCount; i++) {
        if (g_iItemType[i] == 1) {
            if (g_bOwnedItems[id][i]) {
                // Владеет
                if (g_iActiveItem[id] == i || g_iPendingItem[id] == i) {
                    formatex(szItem, charsmax(szItem), "\y%s \w[Надет]", g_szItemName[i]);
                } else {
                    formatex(szItem, charsmax(szItem), "\w%s \y[Надеть]", g_szItemName[i]);
                }
            } else {
                // Не владеет
                formatex(szItem, charsmax(szItem), "\r%s \w[Крафт]", g_szItemName[i]);
            }
            num_to_str(i, szInfo, charsmax(szInfo));
            menu_additem(menu, szItem, szInfo);
            iCount++;
        }
    }
    if (iCount == 0) { 
        menu_destroy(menu); 
        client_print(id, print_chat, "[Craft] Нет доступных предметов."); 
        return; 
    }
    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public Handler_Accessories(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); Cmd_CraftMenu(id); return PLUGIN_HANDLED; }
    new data[16], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new itemId = str_to_num(data);
    menu_destroy(menu);

    if (g_bOwnedItems[id][itemId]) {
        // Если уже владеем - просто надеваем
        if (g_iActiveItem[id] == itemId) {
            client_print(id, print_chat, "[Craft] Этот предмет уже надет.");
        } else {
            g_iPendingItem[id] = itemId;
            SavePlayerEquip(id);
            client_print(id, print_chat, "[Craft] '%s' будет надет в следующем раунде.", g_szItemName[itemId]);
        }
        ShowAccessoriesMenu(id);
    } else {
        // Если не владеем - открываем меню крафта
        ShowCraftConfirmMenu(id, itemId);
    }
    return PLUGIN_HANDLED;
}

ShowCraftConfirmMenu(id, itemId) {
    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\rКрафт: \y%s^n\dТребуемые ресурсы:", g_szItemName[itemId]);
    new menu = menu_create(szTitle, "Handler_CraftConfirm");

    new szItem[128], szResName[64], iNeeded, iHave;
    
    for (new r = 0; r < g_iItemRecipeCount[itemId]; r++) {
        api_get_resource_name(g_iItemRecipeRes[itemId][r], szResName, charsmax(szResName));
        iNeeded = g_iItemRecipeAmt[itemId][r];
        iHave = api_get_resource_amount(id, g_iItemRecipeRes[itemId][r]);

        if (iHave >= iNeeded) {
            formatex(szItem, charsmax(szItem), "%s \y[\w%d / %d\y]", szResName, iHave, iNeeded);
        } else {
            formatex(szItem, charsmax(szItem), "%s \r[\w%d / %d\r]", szResName, iHave, iNeeded);
        }
        menu_additem(menu, szItem, "info", ADMIN_ALL);
    }

    if (api_has_multiple_resources(id, g_iItemRecipeRes[itemId], g_iItemRecipeAmt[itemId], g_iItemRecipeCount[itemId])) {
        new szInfo[16];
        num_to_str(itemId, szInfo, charsmax(szInfo));
        menu_additem(menu, "\y[ Скрафтить ]", szInfo);
    }

    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public Handler_CraftConfirm(id, menu, item) {
    if (item == MENU_EXIT) { 
        menu_destroy(menu); 
        ShowAccessoriesMenu(id); 
        return PLUGIN_HANDLED; 
    }
    
    new data[16], iName[64], access, callback; 
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    
    if (equal(data, "info")) {
        menu_destroy(menu);
        ShowAccessoriesMenu(id);
        return PLUGIN_HANDLED;
    }

    new itemId = str_to_num(data);
    menu_destroy(menu);

    if (itemId >= 0 && itemId < g_iItemCount) {
        if (api_has_multiple_resources(id, g_iItemRecipeRes[itemId], g_iItemRecipeAmt[itemId], g_iItemRecipeCount[itemId])) {
            api_take_multiple_resources(id, g_iItemRecipeRes[itemId], g_iItemRecipeAmt[itemId], g_iItemRecipeCount[itemId]);
            
            // Выдаем владельцу и сохраняем
            g_bOwnedItems[id][itemId] = true;
            SavePlayerOwned(id, itemId);
            
            g_iPendingItem[id] = itemId;
            SavePlayerEquip(id);
            
            client_print(id, print_chat, "[Craft] Вы скрафтили '%s'. Он будет надет в след. раунде!", g_szItemName[itemId]);
        } else {
            client_print(id, print_chat, "[Craft] Недостаточно ресурсов!");
        }
    }

    ShowAccessoriesMenu(id);
    return PLUGIN_HANDLED;
}

// ==========================================
// АДМИНСКОЕ МЕНЮ
// ==========================================
public Cmd_CraftAdmin(id, level, cid) {
    if (!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    ShowAdminMainMenu(id);
    return PLUGIN_HANDLED;
}

ShowAdminMainMenu(id) {
    new menu = menu_create("\r[ADMIN] \yУправление крафтом:", "Handler_AdminMain");
    menu_additem(menu, "Создать новый предмет", "new");
    menu_additem(menu, "Редактировать существующий", "edit");
    menu_additem(menu, "Выдать предмет игроку", "give");
    menu_additem(menu, "Сохранить в INI", "save");
    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public Handler_AdminMain(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[16], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    menu_destroy(menu);

    if (equal(data, "new")) {
        client_cmd(id, "messagemode EnterItemName");
        client_print(id, print_chat, "[ADMIN] Введите название нового предмета в чат:");
    } else if (equal(data, "edit")) {
        ShowAdminItemList(id);
    } else if (equal(data, "give")) {
        ShowAdminPlayerList(id);
    } else if (equal(data, "save")) {
        SaveCraftItems();
        client_print(id, print_chat, "[ADMIN] Предметы сохранены в craft_items.ini");
        ShowAdminMainMenu(id);
    }
    return PLUGIN_HANDLED;
}

public ClCmd_EnterItemName(id) {
    new szName[64]; read_args(szName, charsmax(szName)); remove_quotes(szName); trim(szName);
    if (!szName[0]) return PLUGIN_HANDLED;
    
    if (g_iItemCount < MAX_ITEMS) {
        copy(g_szItemName[g_iItemCount], MAX_ITEM_NAME - 1, szName);
        g_iItemType[g_iItemCount] = 1;
        arrayset(g_iItemPropVals[g_iItemCount], 0, MAX_PROPS);
        g_iItemRecipeCount[g_iItemCount] = 0;
        
        g_iAdminEditingItem[id] = g_iItemCount;
        g_iItemCount++;
        
        client_print(id, print_chat, "[ADMIN] Предмет '%s' создан. Открываю редактор.", szName);
        ShowAdminEditMenu(id);
    }
    return PLUGIN_HANDLED;
}

ShowAdminItemList(id) {
    new menu = menu_create("\r[ADMIN] \yВыберите предмет:", "Handler_AdminItemList");
    new szItem[64], szInfo[16];
    for (new i = 0; i < g_iItemCount; i++) {
        formatex(szItem, charsmax(szItem), "%s", g_szItemName[i]);
        num_to_str(i, szInfo, charsmax(szInfo));
        menu_additem(menu, szItem, szInfo);
    }
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public Handler_AdminItemList(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowAdminMainMenu(id); return PLUGIN_HANDLED; }
    new data[16], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    g_iAdminEditingItem[id] = str_to_num(data);
    menu_destroy(menu);
    ShowAdminEditMenu(id);
    return PLUGIN_HANDLED;
}

ShowAdminEditMenu(id) {
    new itemId = g_iAdminEditingItem[id];
    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\r[ADMIN] \yРедактор: %s", g_szItemName[itemId]);
    new menu = menu_create(szTitle, "Handler_AdminEdit");

    menu_additem(menu, "Изменить свойства", "props");
    menu_additem(menu, "Изменить рецепт (цена)", "recipe");
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public Handler_AdminEdit(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowAdminItemList(id); return PLUGIN_HANDLED; }
    new data[16], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    menu_destroy(menu);

    if (equal(data, "props")) ShowAdminPropsMenu(id);
    else if (equal(data, "recipe")) ShowAdminRecipeMenu(id);
    return PLUGIN_HANDLED;
}

ShowAdminPropsMenu(id) {
    new itemId = g_iAdminEditingItem[id];
    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\r[ADMIN] \yСвойства: %s", g_szItemName[itemId]);
    new menu = menu_create(szTitle, "Handler_AdminProps");

    new szItem[128], szInfo[16];
    for (new p = 0; p < g_iPropCount; p++) {
        formatex(szItem, charsmax(szItem), "%s \y[Текуще: %d]", g_eProperties[p][szPropName], g_iItemPropVals[itemId][p]);
        num_to_str(p, szInfo, charsmax(szInfo));
        menu_additem(menu, szItem, szInfo);
    }
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public Handler_AdminProps(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowAdminEditMenu(id); return PLUGIN_HANDLED; }
    new data[16], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    
    g_iAdminEditingProp[id] = str_to_num(data);
    menu_destroy(menu);
    
    client_cmd(id, "messagemode EnterPropValue");
    client_print(id, print_chat, "[ADMIN] Введите значение для '%s' (0 - отключить):", g_eProperties[g_iAdminEditingProp[id]][szPropName]);
    return PLUGIN_HANDLED;
}

public ClCmd_EnterPropValue(id) {
    if (g_iAdminEditingItem[id] == -1) return PLUGIN_HANDLED;
    new szVal[16]; read_args(szVal, charsmax(szVal)); remove_quotes(szVal); trim(szVal);
    new val = str_to_num(szVal);
    
    g_iItemPropVals[g_iAdminEditingItem[id]][g_iAdminEditingProp[id]] = val;
    client_print(id, print_chat, "[ADMIN] Свойство '%s' установлено на %d", g_eProperties[g_iAdminEditingProp[id]][szPropName], val);
    ShowAdminPropsMenu(id);
    return PLUGIN_HANDLED;
}

ShowAdminRecipeMenu(id) {
    new iTotalRes = api_get_resources_count();
    if (iTotalRes == 0) {
        client_print(id, print_chat, "[ADMIN] Ошибка: В системе нет ресурсов! Добавьте их в resources.ini и перезапустите сервер.");
        ShowAdminEditMenu(id);
        return;
    }

    new itemId = g_iAdminEditingItem[id];
    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\r[ADMIN] \yРецепт: %s", g_szItemName[itemId]);
    new menu = menu_create(szTitle, "Handler_AdminRecipe");

    new szItem[128], szInfo[16];
    new szResName[64], iAmount;
    
    for (new r = 0; r < iTotalRes; r++) {
        api_get_resource_name(r, szResName, charsmax(szResName));
        iAmount = 0;
        
        for (new i = 0; i < g_iItemRecipeCount[itemId]; i++) {
            if (g_iItemRecipeRes[itemId][i] == r) {
                iAmount = g_iItemRecipeAmt[itemId][i];
                break;
            }
        }
        
        formatex(szItem, charsmax(szItem), "%s \y[Нужно: %d]", szResName, iAmount);
        num_to_str(r, szInfo, charsmax(szInfo));
        menu_additem(menu, szItem, szInfo);
    }
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public Handler_AdminRecipe(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowAdminEditMenu(id); return PLUGIN_HANDLED; }
    new data[16], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    
    g_iAdminEditingRes[id] = str_to_num(data);
    menu_destroy(menu);
    
    client_cmd(id, "messagemode EnterRecipeAmount");
    client_print(id, print_chat, "[ADMIN] Введите требуемое количество (0 - убрать из рецепта):");
    return PLUGIN_HANDLED;
}

public ClCmd_EnterRecipeAmount(id) {
    if (g_iAdminEditingItem[id] == -1) return PLUGIN_HANDLED;
    new szVal[16]; read_args(szVal, charsmax(szVal)); remove_quotes(szVal); trim(szVal);
    new val = str_to_num(szVal);
    
    new itemId = g_iAdminEditingItem[id];
    new resId = g_iAdminEditingRes[id];
    
    new foundIdx = -1;
    for (new i = 0; i < g_iItemRecipeCount[itemId]; i++) {
        if (g_iItemRecipeRes[itemId][i] == resId) {
            foundIdx = i;
            break;
        }
    }

    if (val > 0) {
        if (foundIdx == -1) {
            if (g_iItemRecipeCount[itemId] < MAX_RECIPE) {
                new idx = g_iItemRecipeCount[itemId]++;
                g_iItemRecipeRes[itemId][idx] = resId;
                g_iItemRecipeAmt[itemId][idx] = val;
            }
        } else {
            g_iItemRecipeAmt[itemId][foundIdx] = val;
        }
    } else {
        if (foundIdx != -1) {
            for (new i = foundIdx; i < g_iItemRecipeCount[itemId] - 1; i++) {
                g_iItemRecipeRes[itemId][i] = g_iItemRecipeRes[itemId][i+1];
                g_iItemRecipeAmt[itemId][i] = g_iItemRecipeAmt[itemId][i+1];
            }
            g_iItemRecipeCount[itemId]--;
        }
    }

    ShowAdminRecipeMenu(id);
    return PLUGIN_HANDLED;
}

ShowAdminPlayerList(id) {
    new menu = menu_create("\r[ADMIN] \yКому выдать?", "Handler_AdminPlayerList");
    new szName[32], szUserId[16];
    new iPlayers[32], iNum;
    get_players(iPlayers, iNum);
    for (new i = 0; i < iNum; i++) {
        new player = iPlayers[i];
        get_user_name(player, szName, charsmax(szName));
        num_to_str(get_user_userid(player), szUserId, charsmax(szUserId));
        menu_additem(menu, szName, szUserId);
    }
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public Handler_AdminPlayerList(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowAdminMainMenu(id); return PLUGIN_HANDLED; }
    new szData[16], szName[32], access, callback;
    menu_item_getinfo(menu, item, access, szData, charsmax(szData), szName, charsmax(szName), callback);
    new iTarget = find_player("k", str_to_num(szData));
    menu_destroy(menu);
    if (iTarget) {
        g_iAdminTargetPlayer[id] = iTarget;
        ShowAdminGiveMenu(id);
    }
    return PLUGIN_HANDLED;
}

ShowAdminGiveMenu(id) {
    new iTarget = g_iAdminTargetPlayer[id];
    new szTargetName[32], szTitle[128];
    get_user_name(iTarget, szTargetName, charsmax(szTargetName));
    formatex(szTitle, charsmax(szTitle), "\r[ADMIN] \yВыдать: %s", szTargetName);
    new menu = menu_create(szTitle, "Handler_AdminGive");

    new szItem[64], szInfo[16];
    for (new i = 0; i < g_iItemCount; i++) {
        formatex(szItem, charsmax(szItem), "%s", g_szItemName[i]);
        num_to_str(i, szInfo, charsmax(szInfo));
        menu_additem(menu, szItem, szInfo);
    }
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public Handler_AdminGive(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowAdminPlayerList(id); return PLUGIN_HANDLED; }
    new data[16], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new itemId = str_to_num(data);
    menu_destroy(menu);

    new iTarget = g_iAdminTargetPlayer[id];
    
    // Админ выдает предмет в постоянное владение
    g_bOwnedItems[iTarget][itemId] = true;
    SavePlayerOwned(iTarget, itemId);
    
    g_iPendingItem[iTarget] = itemId;
    SavePlayerEquip(iTarget);
    
    client_print(id, print_chat, "[ADMIN] Вы выдали '%s'. Применится в след. раунде.", g_szItemName[itemId]);
    client_print(iTarget, print_chat, "[CRAFT] Админ выдал вам '%s'. Применится в след. раунде.", g_szItemName[itemId]);
    
    ShowAdminGiveMenu(id);
    return PLUGIN_HANDLED;
}