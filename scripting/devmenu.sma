#include <amxmodx>
#include <reapi> 

#define ACCESS_FLAG ADMIN_LEVEL_H

native points_get(id);
native points_set(id, points);

new bool:g_bGodmode[MAX_PLAYERS + 1];
new g_iTargetID[MAX_PLAYERS + 1];
new g_iEditAction[MAX_PLAYERS + 1];

new g_iRanksAction[MAX_PLAYERS + 1];
new bool:g_bRanksPluginLoaded = false;

public plugin_init() {
    register_plugin("Developer Menu Structured", "2.6", "nb_team");
    
    register_clcmd("say /develop", "CmdShowDevMenu");
    register_clcmd("dev_points_input", "HandlePointsInput");
    register_clcmd("dev_ranks_input",  "HandleRanksInput");
    
    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn", 1);
    
    set_task(2.0, "CheckRanksPlugin");
}

public CheckRanksPlugin() {
    if (get_cvar_pointer("rank_xp_kill") != 0) {
        g_bRanksPluginLoaded = true;
        server_print("[DEV] Ranks plugin detected.");
    } else {
        g_bRanksPluginLoaded = false;
        server_print("[DEV] Ranks plugin NOT detected.");
    }
}

public OnPlayerSpawn(id) {
    if (!is_user_alive(id)) return;
    g_bGodmode[id] = false;
    set_entvar(id, var_takedamage, DAMAGE_AIM);
}

public CmdShowDevMenu(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (!(get_user_flags(id) & ACCESS_FLAG)) {
        client_print(id, print_chat, "* У вас нет доступа к меню разработчика!");
        return PLUGIN_HANDLED;
    }
    ShowMainDevMenu(id);
    return PLUGIN_HANDLED;
}

public ShowMainDevMenu(id) {
    new menu = menu_create("\rМеню разработчика", "MainDevMenuHandler");

    menu_additem(menu, "\wРедактировать очки игроков", "1", 0);
    menu_additem(menu, "\wВсякое", "2", 0);
    
    if (g_bRanksPluginLoaded) {
        menu_additem(menu, "\wУправление званиями", "3", 0);
    } else {
        menu_additem(menu, "\dУправление званиями [плагин не загружен]", "3", 0);
    }

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public MainDevMenuHandler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }

    new data[4], szName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), szName, charsmax(szName), callback);
    menu_destroy(menu);

    switch (str_to_num(data)) {
        case 1: ShowPlayerListMenu(id);
        case 2: ShowWeaponMenu(id);
        case 3: {
            if (!g_bRanksPluginLoaded) {
                client_print(id, print_chat, "* Плагин званий не загружен!");
                ShowMainDevMenu(id);
                return PLUGIN_HANDLED;
            }
            ShowRanksMainMenu(id);
        }
    }
    return PLUGIN_HANDLED;
}

// ============================================================================
// УПРАВЛЕНИЕ ЗВАНИЯМИ
// ============================================================================

public ShowRanksMainMenu(id) {
    new menu = menu_create("\y[\r Ranks Manager \y] \wУправление званиями:", "RanksMainMenuHandler");

    menu_additem(menu, "\yУстановить уровень игроку", "1", 0);
    menu_additem(menu, "\yУстановить опыт игроку",    "2", 0);
    menu_additem(menu, "\yПерезагрузить звания (rank_reload)", "3", 0);

    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public RanksMainMenuHandler(id, menu, item) {
    if (item == MENU_EXIT) { 
        menu_destroy(menu); 
        ShowMainDevMenu(id); 
        return PLUGIN_HANDLED; 
    }

    new data[4], szName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), szName, charsmax(szName), callback);
    menu_destroy(menu);

    new action = str_to_num(data);
    
    if (action == 3) {
        server_cmd("rank_reload");
        server_exec();
        client_print(id, print_chat, "* Звания перезагружены.");
        ShowRanksMainMenu(id);
        return PLUGIN_HANDLED;
    }
    
    g_iRanksAction[id] = action;
    ShowRanksPlayerList(id);
    return PLUGIN_HANDLED;
}

public ShowRanksPlayerList(id) {
    new szTitle[96];
    if (g_iRanksAction[id] == 1)
        formatex(szTitle, charsmax(szTitle), "\y[\r Ranks \y] \wУстановка УРОВНЯ - Выберите игрока:");
    else
        formatex(szTitle, charsmax(szTitle), "\y[\r Ranks \y] \wУстановка ОПЫТА - Выберите игрока:");
    
    new menu = menu_create(szTitle, "RanksPlayerListHandler");
    
    new szName[32], szData[8], szItem[96];
    for (new i = 1; i <= get_maxplayers(); i++) {
        if (!is_user_connected(i)) continue;
        
        get_user_name(i, szName, charsmax(szName));
        num_to_str(i, szData, charsmax(szData));
        
        formatex(szItem, charsmax(szItem), "\w%s", szName);
        menu_additem(menu, szItem, szData, 0);
    }
    
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public RanksPlayerListHandler(id, menu, item) {
    if (item == MENU_EXIT) { 
        menu_destroy(menu); 
        ShowRanksMainMenu(id); 
        return PLUGIN_HANDLED; 
    }
    
    new data[8], szName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), szName, charsmax(szName), callback);
    menu_destroy(menu);
    
    g_iTargetID[id] = str_to_num(data);
    ShowRanksActionMenu(id);
    return PLUGIN_HANDLED;
}

public ShowRanksActionMenu(id) {
    new target = g_iTargetID[id];
    if (!is_user_connected(target)) { 
        client_print(id, print_chat, "* Игрок отключился!"); 
        ShowRanksMainMenu(id);
        return PLUGIN_HANDLED; 
    }

    new szTargetName[32];
    get_user_name(target, szTargetName, charsmax(szTargetName));

    new szTitle[128];
    if (g_iRanksAction[id] == 1)
        formatex(szTitle, charsmax(szTitle), "\yИгрок: \w%s \y| Установка \rУРОВНЯ", szTargetName);
    else
        formatex(szTitle, charsmax(szTitle), "\yИгрок: \w%s \y| Установка \rОПЫТА", szTargetName);

    new menu = menu_create(szTitle, "RanksActionHandler");
    
    if (g_iRanksAction[id] == 1) {
        menu_additem(menu, "\yУстановить уровень: \w1",    "1",    0);
        menu_additem(menu, "\yУстановить уровень: \w5",    "5",    0);
        menu_additem(menu, "\yУстановить уровень: \w10",   "10",   0);
        menu_additem(menu, "\yУстановить уровень: \w25",   "25",   0);
        menu_additem(menu, "\yУстановить уровень: \w50",   "50",   0);
        menu_additem(menu, "\yУстановить уровень: \w100",  "100",  0);
        menu_additem(menu, "\yВвести своё значение...",    "0",    0);
    } else {
        menu_additem(menu, "\yДобавить опыта: \w+100",     "100",   0);
        menu_additem(menu, "\yДобавить опыта: \w+500",     "500",   0);
        menu_additem(menu, "\yДобавить опыта: \w+1000",    "1000",  0);
        menu_additem(menu, "\yДобавить опыта: \w+5000",    "5000",  0);
        menu_additem(menu, "\yДобавить опыта: \w+10000",   "10000", 0);
        menu_additem(menu, "\yУстановить опыт: \w0",       "-0",    0);
        menu_additem(menu, "\yВвести своё значение...",    "0",     0);
    }

    menu_setprop(menu, MPROP_EXITNAME, "Назад к списку");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);

    return PLUGIN_HANDLED;
}

public RanksActionHandler(id, menu, item) {
    if (item == MENU_EXIT) { 
        menu_destroy(menu); 
        ShowRanksPlayerList(id); 
        return PLUGIN_HANDLED; 
    }
    
    new data[16], szName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), szName, charsmax(szName), callback);
    menu_destroy(menu);
    
    new target = g_iTargetID[id];
    if (!is_user_connected(target)) { 
        client_print(id, print_chat, "* Игрок отключился!"); 
        ShowRanksMainMenu(id);
        return PLUGIN_HANDLED; 
    }
    
    new szTargetName[32];
    get_user_name(target, szTargetName, charsmax(szTargetName));
    
    if (equal(data, "0")) {
        client_cmd(id, "messagemode dev_ranks_input");
        if (g_iRanksAction[id] == 1)
            client_print(id, print_chat, "* Введите УРОВЕНЬ для %s в консоль чата:", szTargetName);
        else
            client_print(id, print_chat, "* Введите ОПЫТ для %s в консоль чата:", szTargetName);
        return PLUGIN_HANDLED;
    }
    
    new value = str_to_num(data);
    
    if (g_iRanksAction[id] == 2 && data[0] == '-') {
        value = 0;
    }
    
    ExecuteRanksCommand(id, target, value);
    
    ShowRanksActionMenu(id);
    return PLUGIN_HANDLED;
}

public HandleRanksInput(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    
    new args[32];
    read_argv(1, args, charsmax(args));
    trim(args);
    
    if (args[0] == 0 || !is_str_num(args)) {
        client_print(id, print_chat, "* Ошибка: Введено не число или пустая строка!");
        ShowRanksActionMenu(id);
        return PLUGIN_HANDLED;
    }
    
    new value = str_to_num(args);
    new target = g_iTargetID[id];
    
    if (!is_user_connected(target)) { 
        client_print(id, print_chat, "* Игрок отключился!"); 
        ShowRanksMainMenu(id);
        return PLUGIN_HANDLED; 
    }
    
    ExecuteRanksCommand(id, target, value);
    ShowRanksActionMenu(id);
    return PLUGIN_HANDLED;
}

public ExecuteRanksCommand(id, target, value)
{
    new szTargetName[32];
    get_user_name(target, szTargetName, charsmax(szTargetName));
    
    new userid = get_user_userid(target);
    
    if (g_iRanksAction[id] == 1) {
        if (value < 1) value = 1;
        server_cmd("rank_setlevel #%d %d", userid, value);
        server_exec();
        client_print(id, print_chat, "* Установлен уровень %d для игрока %s", value, szTargetName);
    } else {
        if (value < 0) value = 0;
        server_cmd("rank_setxp #%d %d", userid, value);
        server_exec();
        client_print(id, print_chat, "* Установлен опыт %d для игрока %s", value, szTargetName);
    }
    
    set_task(0.2, "RefreshRanksMenu", id);
}

public RefreshRanksMenu(id)
{
    if (is_user_connected(id))
        ShowRanksActionMenu(id);
}

// ============================================================================
// РЕДАКТИРОВАНИЕ ОЧКОВ (через points_get / points_set)
// ============================================================================

public ShowPlayerListMenu(id) {
    new menu = menu_create("\y[\r Dev Menu \y] \wВыберите игрока:", "PlayerListHandler");
    
    new szName[32], szData[8], szItem[64];
    for (new i = 1; i <= get_maxplayers(); i++) {
        if (!is_user_connected(i)) continue;
        
        get_user_name(i, szName, charsmax(szName));
        num_to_str(i, szData, charsmax(szData));
        
        new iPoints = points_get(i);
        formatex(szItem, charsmax(szItem), "\w%s \y[\r%d очков\y]", szName, iPoints);
        menu_additem(menu, szItem, szData, 0);
    }
    
    menu_setprop(menu, MPROP_EXITNAME, "Назад к списку");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public PlayerListHandler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowMainDevMenu(id); return PLUGIN_HANDLED; }
    
    new data[8], szName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), szName, charsmax(szName), callback);
    menu_destroy(menu);
    
    g_iTargetID[id] = str_to_num(data);
    ShowPointsActionMenu(id);
    return PLUGIN_HANDLED;
}

public ShowPointsActionMenu(id) {
    new target = g_iTargetID[id];
    if (!is_user_connected(target)) { 
        client_print(id, print_chat, "* Игрок отключился!"); 
        return PLUGIN_HANDLED; 
    }

    new szTargetName[32];
    get_user_name(target, szTargetName, charsmax(szTargetName));
    new iPoints = points_get(target);

    new szTitle[96];
    formatex(szTitle, charsmax(szTitle), "\yИгрок: \w%s \y[\r%d\y]", szTargetName, iPoints);

    new menu = menu_create(szTitle, "PointsActionHandler");
    menu_additem(menu, "\yДобавить очки (+)", "1", 0);
    menu_additem(menu, "\yУбавить очки (-)", "2", 0);
    menu_additem(menu, "\yУстановить значение (=)", "3", 0);

    menu_setprop(menu, MPROP_EXITNAME, "Назад к списку");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);

    return PLUGIN_HANDLED;
}

public PointsActionHandler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowPlayerListMenu(id); return PLUGIN_HANDLED; }
    
    new data[4], szName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), szName, charsmax(szName), callback);
    g_iEditAction[id] = str_to_num(data);
    
    client_cmd(id, "messagemode dev_points_input");
    client_print(id, print_chat, "* Введите количество очков в консоль чата:");
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public HandlePointsInput(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    
    new args[32];
    read_argv(1, args, charsmax(args));
    trim(args);
    
    if (args[0] == 0 || !is_str_num(args)) {
        client_print(id, print_chat, "* Ошибка: Введено не число или пустая строка!");
        ShowPointsActionMenu(id);
        return PLUGIN_HANDLED;
    }
    
    new amount = str_to_num(args);
    new target = g_iTargetID[id];
    
    if (!is_user_connected(target)) { 
        client_print(id, print_chat, "* Игрок отключился!"); 
        return PLUGIN_HANDLED; 
    }
    
    new current = points_get(target);
    new final_points = current;
    
    switch(g_iEditAction[id]) {
        case 1: final_points = current + amount;
        case 2: final_points = current - amount;
        case 3: final_points = amount;
    }
    
    if (final_points < 0) final_points = 0;
    
    points_set(target, final_points);
    
    new szTargetName[32];
    get_user_name(target, szTargetName, charsmax(szTargetName));
    client_print(id, print_chat, "* Готово! У %s теперь %d очков.", szTargetName, final_points);
    
    ShowPlayerListMenu(id);
    return PLUGIN_HANDLED;
}

// ============================================================================
// ОРУЖЕЙНОЕ МЕНЮ
// ============================================================================

public ShowWeaponMenu(id) {
    new menu = menu_create("\w[\w Оружие и Годмод\w]", "WeaponMenuHandler");
    menu_additem(menu, "\yAK-47 \w+ патроны", "1", 0);
    menu_additem(menu, "\yM4A1 \w+ патроны", "2", 0);
    menu_additem(menu, "\yAWP \w+ патроны", "3", 0);
    menu_additem(menu, "\yDEAGLE \w+ патроны", "4", 0);
    
    new szGodmode[64];
    formatex(szGodmode, charsmax(szGodmode), "\yБессмертие: %s", g_bGodmode[id] ? "\rВКЛ" : "\dВЫКЛ");
    menu_additem(menu, szGodmode, "5", 0);

    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public WeaponMenuHandler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowMainDevMenu(id); return PLUGIN_HANDLED; }

    new data[6], szName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), szName, charsmax(szName), callback);

    new key = str_to_num(data);
    
    if (key == 5) {
        g_bGodmode[id] = !g_bGodmode[id];
        set_entvar(id, var_takedamage, g_bGodmode[id] ? DAMAGE_NO : DAMAGE_AIM);
        menu_destroy(menu); ShowWeaponMenu(id); 
        return PLUGIN_HANDLED;
    }

    new szWeapon[32], WeaponIdType:csw_id;
    switch (key) {
        case 1: { copy(szWeapon, charsmax(szWeapon), "weapon_ak47"); csw_id = WEAPON_AK47; }
        case 2: { copy(szWeapon, charsmax(szWeapon), "weapon_m4a1"); csw_id = WEAPON_M4A1; }
        case 3: { copy(szWeapon, charsmax(szWeapon), "weapon_awp"); csw_id = WEAPON_AWP; }
        case 4: { copy(szWeapon, charsmax(szWeapon), "weapon_deagle"); csw_id = WEAPON_DEAGLE; }
    }

    new weapon_ent = rg_give_item(id, szWeapon, GT_APPEND);
    if (weapon_ent > 0) {
        new iMaxClip = rg_get_iteminfo(weapon_ent, ItemInfo_iMaxClip);
        set_member(weapon_ent, m_Weapon_iClip, iMaxClip);
        
        new iMaxBpAmmo = rg_get_iteminfo(weapon_ent, ItemInfo_iMaxAmmo1);
        rg_set_user_bpammo(id, csw_id, iMaxBpAmmo);
    }

    client_print(id, print_chat, "* Вы получили %s!", szWeapon);
    menu_destroy(menu); ShowWeaponMenu(id); 
    return PLUGIN_HANDLED;
}