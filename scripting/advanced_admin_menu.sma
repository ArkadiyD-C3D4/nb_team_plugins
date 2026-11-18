#include <amxmodx>
#include <amxmisc>
#include <sqlx>
#include <reapi>
#include <hamsandwich>
#include <engine>

#define PLUGIN "Advanced Admin Menu"
#define VERSION "2.7" // Версия обновлена
#define AUTHOR "nb_team"

#define ADMIN_FLAG ADMIN_LEVEL_B

// Глобальные переменные
new g_PlayerAction[33]
new g_PlayerTarget[33]

new Handle:g_DbTuple

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    
    // 1. Перехватываем чат (say и say_team)
    register_clcmd("say /admin", "cmd_admin_menu")
    register_clcmd("say_team /admin", "cmd_admin_menu")
    
    // 2. Перехватываем консольную команду. 
    // Мы НЕ указываем здесь флаг, чтобы перехватить команду ЛЮБОГО игрока, 
    // а проверку сделаем внутри функции вручную.
    register_clcmd("amx_admin", "cmd_admin_menu")
    
    log_amx("Admin Menu v2.7 loaded successfully")
}

public plugin_cfg() {
    new szHost[64], szUser[64], szPass[64], szDb[64]
    
    get_cvar_string("amx_sql_host", szHost, charsmax(szHost))
    get_cvar_string("amx_sql_user", szUser, charsmax(szUser))
    get_cvar_string("amx_sql_pass", szPass, charsmax(szPass))
    get_cvar_string("amx_sql_db", szDb, charsmax(szDb))
    
    g_DbTuple = SQL_MakeDbTuple(szHost, szUser, szPass, szDb)
    log_amx("Database connection initialized")
}

public plugin_end() {
    if(g_DbTuple != Empty_Handle) {
        SQL_FreeHandle(g_DbTuple)
    }
}

public client_disconnected(id) {
    g_PlayerAction[id] = 0
    g_PlayerTarget[id] = 0
}

// ========== ГЛАВНОЕ МЕНЮ ==========
public cmd_admin_menu(id, level, cid) {
    if (!(get_user_flags(id) & ADMIN_LEVEL_G)) {
        client_print(id, print_chat, "[Admin] Недостаточно прав для использования этой команды!")
        
        // ВАЖНО: Возвращаем PLUGIN_HANDLED, чтобы команда НЕ передавалась дальше другим плагинам
        return PLUGIN_HANDLED 
    }
    
    show_main_menu(id)
    return PLUGIN_HANDLED
}

public show_main_menu(id) {
    new menu = menu_create("\rАдмин Меню", "main_menu_handler")
    
    menu_additem(menu, "\wПереместить", "1", 0)
    menu_additem(menu, "\wУдарить", "2", 0)
    menu_additem(menu, "\wЗамутить", "3", 0)
    menu_additem(menu, "\wЗабанить", "4", 0)
    menu_additem(menu, "\wЗабанить вышедшего", "5", 0)  
    
    menu_display(id, menu, 0)
}

public main_menu_handler(id, menu, item) {
    if(item == MENU_EXIT) {
        menu_destroy(menu)
        return PLUGIN_HANDLED
    }
    
    new data[6], iaccess, callback
    menu_item_getinfo(menu, item, iaccess, data, charsmax(data), _, callback)
    
    new action = str_to_num(data)
    menu_destroy(menu)
    
    switch(action) {
        case 1: {
            g_PlayerAction[id] = 1
            show_player_list(id, 1) // Передаем действие 1 (все игроки)
        }
        case 2: {
            g_PlayerAction[id] = 2
            show_player_list(id, 2) // Передаем действие 2 (только живые)
        }
        case 3: {
            client_cmd(id, "amx_gagmenu")
        }
        case 4: {
            client_cmd(id, "fb_menu")
        }
        case 5: {
            client_cmd(id, "fb_offban")
        }
    }
    
    return PLUGIN_HANDLED
}

// ========== МЕНЮ ВЫБОРА ИГРОКА ==========
public show_player_list(id, action) {
    new menu = menu_create("\rВыберите игрока", "player_list_handler")
    
    new players[32], num
    new flags[3]
    
    if (action == 2) {
        copy(flags, charsmax(flags), "ah")
    } else {
        copy(flags, charsmax(flags), "h")
    }
    
    get_players(players, num, flags)
    
    if(num == 0) {
        client_print(id, print_chat, "[Admin] Нет подходящих игроков на сервере!")
        menu_destroy(menu)
        show_main_menu(id)
        return PLUGIN_HANDLED
    }
    
    new count = 0
    for(new i = 0; i < num; i++) {
        new player = players[i]
        
        if(!is_user_connected(player)) continue
        
        new name[32]
        get_user_name(player, name, charsmax(name))
        
        if (action != 2) {
            if (!is_user_alive(player)) {
                new team = get_user_team(player)
                if (team == 1 || team == 2) {
                    format(name, charsmax(name), "\d%s [Мертв]\w", name)
                } else if (team == 3) {
                    format(name, charsmax(name), "\y%s [Спек]\w", name)
                }
            }
        }
        
        new data[16]
        num_to_str(player, data, charsmax(data))
        
        menu_additem(menu, name, data, 0)
        count++
    }
    
    if(count == 0) {
        client_print(id, print_chat, "[Admin] Нет доступных игроков!")
        menu_destroy(menu)
        show_main_menu(id)
        return PLUGIN_HANDLED
    }
    
    menu_display(id, menu, 0)
    return PLUGIN_HANDLED
}

public player_list_handler(id, menu, item) {
    if(item == MENU_EXIT) {
        menu_destroy(menu)
        show_main_menu(id)
        return PLUGIN_HANDLED
    }
    
    new data[16], iaccess, callback
    menu_item_getinfo(menu, item, iaccess, data, charsmax(data), _, callback)
    
    new target = str_to_num(data)
    
    if(!is_user_connected(target)) {
        client_print(id, print_chat, "[Admin] Игрок вышел из игры!")
        menu_destroy(menu)
        show_main_menu(id)
        return PLUGIN_HANDLED
    }
    
    g_PlayerTarget[id] = target
    menu_destroy(menu)
    
    switch(g_PlayerAction[id]) {
        case 1: show_team_options(id)
        case 2: show_punish_options(id)     
    }
    
    return PLUGIN_HANDLED
}

// ========== МЕНЮ НАКАЗАНИЯ ==========
public show_punish_options(id) {
    new target = g_PlayerTarget[id]
    new target_name[32]
    get_user_name(target, target_name, charsmax(target_name))
    
    new title[64]
    formatex(title, charsmax(title), "\rНаказать: %s", target_name)
    
    new menu = menu_create(title, "punish_options_handler")
    
    menu_additem(menu, "\w0 HP (без урона)", "0", 0)
    menu_additem(menu, "\w10 HP", "10", 0)
    menu_additem(menu, "\w25 HP", "25", 0)
    menu_additem(menu, "\w50 HP", "50", 0)
    menu_additem(menu, "\w100 HP", "100", 0)
    menu_additem(menu, "\yУБИТЬ", "999", 0)
    
    menu_display(id, menu, 0)
}

public punish_options_handler(id, menu, item) {
    if(item == MENU_EXIT) {
        menu_destroy(menu)
        show_main_menu(id)
        return PLUGIN_HANDLED
    }
    
    new data[16], iaccess, callback
    menu_item_getinfo(menu, item, iaccess, data, charsmax(data), _, callback)
    
    new damage = str_to_num(data)
    menu_destroy(menu)
    
    execute_punish(id, damage)
    return PLUGIN_HANDLED
}

public execute_punish(id, damage) {
    new target = g_PlayerTarget[id]
    
    if(!is_user_connected(target)) {
        client_print(id, print_chat, "[Admin] Игрок вышел из игры!")
        show_main_menu(id)
        return PLUGIN_HANDLED
    }
    
    // ПРОВЕРКА: Если у цели есть флаг 't', а у админа его нет - блокируем действие
    if ((get_user_flags(target) & read_flags("t")) && !(get_user_flags(id) & read_flags("t"))) {
        client_print(id, print_chat, "Недостаточно прав!")
        show_main_menu(id)
        return PLUGIN_HANDLED
    }
    
    new target_name[32], admin_name[32]
    get_user_name(target, target_name, charsmax(target_name))
    get_user_name(id, admin_name, charsmax(admin_name))
    
    new command[128]
    if(damage == 999) {
        formatex(command, charsmax(command), "amx_slay ^"%s^"", target_name)
        server_cmd(command)
        server_exec()
        
        client_print(0, print_chat, "[Admin] %s убил %s", admin_name, target_name)
        
        show_main_menu(id)
    } else {
        formatex(command, charsmax(command), "amx_slap ^"%s^" %d", target_name, damage)
        server_cmd(command)
        server_exec()
        
        client_print(0, print_chat, "[Admin] %s ударил %s на %d HP", admin_name, target_name, damage)
        
        show_punish_options(id)
    }
    
    return PLUGIN_HANDLED
}

// ========== МЕНЮ ПЕРЕМЕЩЕНИЯ ==========
public show_team_options(id) {
    new target = g_PlayerTarget[id]
    new target_name[32]
    get_user_name(target, target_name, charsmax(target_name))
    
    new title[64]
    formatex(title, charsmax(title), "\rПереместить: %s", target_name)
    
    new menu = menu_create(title, "team_options_handler")
    
    menu_additem(menu, "\wТеррористы (T)", "1", 0)
    menu_additem(menu, "\wСпецназ (CT)", "2", 0)
    menu_additem(menu, "\wСпектратор", "3", 0)
    
    menu_display(id, menu, 0)
}

public team_options_handler(id, menu, item) {
    if(item == MENU_EXIT) {
        menu_destroy(menu)
        show_main_menu(id)
        return PLUGIN_HANDLED
    }
    
    new data[16], iaccess, callback
    menu_item_getinfo(menu, item, iaccess, data, charsmax(data), _, callback)
    
    new team_choice = str_to_num(data)
    menu_destroy(menu)
    
    execute_team_change(id, team_choice)
    return PLUGIN_HANDLED
}

public execute_team_change(id, team_choice) {
    new target = g_PlayerTarget[id]
    
    if(!is_user_connected(target)) {
        client_print(id, print_chat, "[Admin] Игрок вышел из игры!")
        show_main_menu(id)
        return PLUGIN_HANDLED
    }
    
    // ПРОВЕРКА: Если у цели есть флаг 't', а у админа его нет - блокируем действие
    if ((get_user_flags(target) & read_flags("t")) && !(get_user_flags(id) & read_flags("t"))) {
        client_print(id, print_chat, "Недостаточно прав!")
        show_main_menu(id)
        return PLUGIN_HANDLED
    }
    
    new target_name[32], admin_name[32]
    get_user_name(target, target_name, charsmax(target_name))
    get_user_name(id, admin_name, charsmax(admin_name))
    
    new TeamName:new_team
    
    switch(team_choice) {
        case 1: {
            new_team = TEAM_TERRORIST
            client_print(0, print_chat, "[Admin] %s переместил %s в Террористы", admin_name, target_name)
        }
        case 2: {
            new_team = TEAM_CT
            client_print(0, print_chat, "[Admin] %s переместил %s в Спецназ", admin_name, target_name)
        }
        case 3: {
            new_team = TEAM_SPECTATOR
            client_print(0, print_chat, "[Admin] %s переместил %s в Спектраторы", admin_name, target_name)
        }
    }
    
    // Перемещаем игрока
    rg_set_user_team(target, new_team)
    
    // Убиваем игрока при любом перемещении (включая спектаторы)
    ExecuteHamB(Ham_Killed, target, target, 0)
    
    show_main_menu(id)
    return PLUGIN_HANDLED
}