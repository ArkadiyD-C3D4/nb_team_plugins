#include <amxmodx>
#include <amxmisc>

// Подключаем API основного плагина
native api_get_resource_id(const szName[]);
native api_give_resource(id, resId, amount);
native api_get_resource_amount(id, resId);
native api_get_resources_count();
native api_get_resource_name(resId, buffer[], len);

// Массив для хранения выбранной цели (ID игрока) для каждого админа
new g_iTargetPlayer[33];

public plugin_init() {
    register_plugin("Dev Resource Menu", "1.0", "nb_team");
    
    // Команда /devres для админов с флагом "t" (ADMIN_LEVEL_H)
    register_clcmd("say /devres", "Cmd_DevRes", ADMIN_LEVEL_H);
    register_clcmd("say_team /devres", "Cmd_DevRes", ADMIN_LEVEL_H);
}

public Cmd_DevRes(id, level, cid) {
    if (!cmd_access(id, level, cid, 1)) {
        return PLUGIN_HANDLED;
    }
    
    // Открываем меню выбора игрока
    ShowPlayerMenu(id);
    return PLUGIN_HANDLED;
}

// ==========================================
// МЕНЮ 1: ВЫБОР ИГРОКА
// ==========================================
ShowPlayerMenu(id) {
    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\r[DEV] \yВыберите игрока:");
    new menu = menu_create(szTitle, "Handler_PlayerMenu");

    new szName[32], szUserId[6];
    new iPlayers[32], iNum;
    
    // Получаем список всех игроков на сервере
    get_players(iPlayers, iNum);
    
    for (new i = 0; i < iNum; i++) {
        new player = iPlayers[i];
        get_user_name(player, szName, charsmax(szName));
        
        // Используем UserID в качестве инфо, чтобы меню не ломалось, если игрок выйдет
        num_to_str(get_user_userid(player), szUserId, charsmax(szUserId));
        
        menu_additem(menu, szName, szUserId);
    }

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public Handler_PlayerMenu(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[6], szName[32], access, callback;
    menu_item_getinfo(menu, item, access, szData, charsmax(szData), szName, charsmax(szName), callback);

    new iTarget = find_player("k", str_to_num(szData)); // k - search by userid
    
    if (!iTarget) {
        client_print(id, print_chat, "[DEV] Ошибка: Игрок не найден или покинул сервер.");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    // Сохраняем выбранного игрока для этого админа
    g_iTargetPlayer[id] = iTarget;
    
    // Переходим к меню выдачи ресурсов
    ShowResourceMenu(id);

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// ==========================================
// МЕНЮ 2: ВЫБОР РЕСУРСА
// ==========================================
ShowResourceMenu(id) {
    new iTarget = g_iTargetPlayer[id];
    
    if (!iTarget || !is_user_connected(iTarget)) {
        client_print(id, print_chat, "[DEV] Игрок отключился. Возврат в главное меню.");
        ShowPlayerMenu(id);
        return;
    }

    new szTargetName[32], szTitle[128];
    get_user_name(iTarget, szTargetName, charsmax(szTargetName));
    formatex(szTitle, charsmax(szTitle), "\r[DEV] \yВыдать: %s^n\dКлик = +10 шт", szTargetName);
    
    new menu = menu_create(szTitle, "Handler_ResourceMenu");

    new iCount = api_get_resources_count();
    new szResName[64], szItem[128], iAmount;
    new szResIdStr[6];

    // Перебираем все ресурсы из базы
    for (new i = 0; i < iCount; i++) {
        api_get_resource_name(i, szResName, charsmax(szResName));
        iAmount = api_get_resource_amount(iTarget, i);

        // Форматируем строку меню: "Обломок белого железа [Текуще: 15]"
        formatex(szItem, charsmax(szItem), "%s \y[Текуще: %d]", szResName, iAmount);
        
        // Сохраняем индекс ресурса как строку
        num_to_str(i, szResIdStr, charsmax(szResIdStr));
        menu_additem(menu, szItem, szResIdStr);
    }

    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public Handler_ResourceMenu(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        ShowPlayerMenu(id); // Возврат в меню игроков
        return PLUGIN_HANDLED;
    }

    new iTarget = g_iTargetPlayer[id];
    
    if (!iTarget || !is_user_connected(iTarget)) {
        client_print(id, print_chat, "[DEV] Игрок отключился.");
        menu_destroy(menu);
        ShowPlayerMenu(id);
        return PLUGIN_HANDLED;
    }

    new szData[6], szName[64], access, callback;
    menu_item_getinfo(menu, item, access, szData, charsmax(szData), szName, charsmax(szName), callback);

    new resId = str_to_num(szData);
    new amount = 10; // Выдаем по 10 штук за клик

    // Выдаем ресурс
    api_give_resource(iTarget, resId, amount);
    
    // Выводим сообщение админу
    new szResName[64];
    api_get_resource_name(resId, szResName, charsmax(szResName));
    client_print(id, print_chat, "[DEV] Выдано %d шт. '%s' игроку.", amount, szResName);

    // Обновляем меню ресурсов, чтобы увидеть новое количество
    menu_destroy(menu);
    ShowResourceMenu(id);

    return PLUGIN_HANDLED;
}