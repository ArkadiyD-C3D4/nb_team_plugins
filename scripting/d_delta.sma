#include <amxmodx>
#include <amxmisc>

// Нативы из внешнего плагина очков
native points_get(id);
native points_set(id, points);
native ranks_add_xp(id, amount);

// === НАТИВЫ ИЗ skills_system.sma ===
native sk_AddExtraDrop(id, amount);
native sk_TakeExtraDrop(id, amount);
native sk_GetExtraDrop(id);

// Константы
#define PLUGIN_NAME     "Delta Menu System"
#define PLUGIN_VERSION  "2.8"
#define PLUGIN_AUTHOR   "nb_team"

#define MENU_TITLE      "\r[Delta System]^n\wВыберите бонус:"
#define COOLDOWN_TIME   600.0  // Время ожидания (10 минут в секундах)
#define POINTS_BONUS    20    // Бонус очков для Delta
#define EXP_BONUS       20    // Бонус опыта для Delta

// Максимальное количество записей в кэше для защиты от абуза перезаходов
#define MAX_CACHE_SIZE  64

// Структура для хранения кулдаунов вышедших игроков (ИСПРАВЛЕНО: добавлен размер для AuthID)
enum _:CacheData
{
    Cache_AuthID[32],
    Cache_PointsTime,
    Cache_ExpTime
}

new g_eCooldownCache[MAX_CACHE_SIZE][CacheData];
new g_iCacheCount = 0;

// Текущие переменные кулдаунов игроков на сервере
new g_iPointsReadyTime[33];
new g_iExpReadyTime[33];

// === ПЕРЕМЕННАЯ ДЛЯ НЕЗАВИСИМОЙ ВЫДАЧИ ШАНСА ДРОПА ===
// Хранит UserID игрока, которому КОНКРЕТНЫЙ админ выдал бонус (-1 если никому)
new g_iDropTarget[33];

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
    
    register_clcmd("say /delta", "Cmd_DeltaMenu");
    register_clcmd("say_team /delta", "Cmd_DeltaMenu");
    
    register_event("TextMsg", "Event_GameRestart", "a", "2&=Game_Commencing", "2&=Game_Will_Restart_In");
}

public client_putinserver(id)
{
    if (is_user_bot(id))
        return;

    // Инициализация личной переменной выдачи
    g_iDropTarget[id] = -1;

    new iNow = get_systime();
    
    // По умолчанию при входе игроку нужно ждать 10 минут
    g_iPointsReadyTime[id] = iNow + floatround(COOLDOWN_TIME);
    g_iExpReadyTime[id] = iNow + floatround(COOLDOWN_TIME);

    // Проверяем, заходил ли этот игрок ранее (сохранение кулдауна при перезаходе)
    new szAuthID[32];
    get_user_authid(id, szAuthID, charsmax(szAuthID));

    if (equal(szAuthID, "STEAM_ID_LAN") || equal(szAuthID, "VALVE_ID_LAN") || equal(szAuthID, ""))
    {
        get_user_ip(id, szAuthID, charsmax(szAuthID), 1);
    }

    for (new i = 0; i < g_iCacheCount; i++)
    {
        if (equal(g_eCooldownCache[i][Cache_AuthID], szAuthID))
        {
            if (g_eCooldownCache[i][Cache_PointsTime] > iNow)
                g_iPointsReadyTime[id] = g_eCooldownCache[i][Cache_PointsTime];

            if (g_eCooldownCache[i][Cache_ExpTime] > iNow)
                g_iExpReadyTime[id] = g_eCooldownCache[i][Cache_ExpTime];

            ArrayRemoveRow(i);
            break;
        }
    }
}

public client_disconnected(id)
{
    if (is_user_bot(id))
        return;

    // 1. Если выходит АДМИН: забираем его выданный бонус у игрока и очищаем лимит админа
    if (g_iDropTarget[id] != -1)
    {
        new target = find_player("k", g_iDropTarget[id]);
        if (target)
        {
            sk_TakeExtraDrop(target, 1);
            client_print(target, print_chat, "[Delta] Бонус шанса дропа снят, так как админ покинул сервер.");
        }
        g_iDropTarget[id] = -1;
    }

    // 2. Если выходит ИГРОК, у которого есть бонус: находим админа, который ему выдал, и освобождаем лимит
    new iDisconnectedUserID = get_user_userid(id);
    new iPlayers[32], iNum, iAdminID;
    get_players(iPlayers, iNum, "ch"); // ch - проверяем всех людей без ботов
    
    for (new i = 0; i < iNum; i++)
    {
        iAdminID = iPlayers[i];
        // Если мы находим админа, который держал лимит на этом вышедшем игроке
        if (g_iDropTarget[iAdminID] == iDisconnectedUserID)
        {
            g_iDropTarget[iAdminID] = -1; // Освобождаем лимит админа
            client_print(iAdminID, print_chat, "[Delta] Игрок с вашим бонусом шанса дропа вышел. Лимит освобожден.");
        }
    }

    new iNow = get_systime();

    if (g_iPointsReadyTime[id] <= iNow && g_iExpReadyTime[id] <= iNow)
        return;

    new szAuthID[32];
    get_user_authid(id, szAuthID, charsmax(szAuthID));

    if (equal(szAuthID, "STEAM_ID_LAN") || equal(szAuthID, "VALVE_ID_LAN") || equal(szAuthID, ""))
    {
        get_user_ip(id, szAuthID, charsmax(szAuthID), 1);
    }

    // Очистка старых записей кэша
    for (new i = 0; i < g_iCacheCount; i++)
    {
        if (g_eCooldownCache[i][Cache_PointsTime] <= iNow && g_eCooldownCache[i][Cache_ExpTime] <= iNow)
        {
            ArrayRemoveRow(i);
            i--;
        }
    }

    if (g_iCacheCount >= MAX_CACHE_SIZE)
    {
        ArrayRemoveRow(0);
    }

    new iIndex = g_iCacheCount;
    copy(g_eCooldownCache[iIndex][Cache_AuthID], 31, szAuthID);
    g_eCooldownCache[iIndex][Cache_PointsTime] = g_iPointsReadyTime[id];
    g_eCooldownCache[iIndex][Cache_ExpTime] = g_iExpReadyTime[id];
    g_iCacheCount++;
}

public Cmd_DeltaMenu(id)
{
     if (!is_user_connected(id))
        return PLUGIN_CONTINUE;

    // ПРОВЕРКА ФЛАГА: Если у игрока НЕТ флага ADMIN_LEVEL_B (n)
    if (!(get_user_flags(id) & ADMIN_LEVEL_B))
    {
        client_print(id, print_chat, "[Delta] У вас нет доступа к этому меню!");
        return PLUGIN_HANDLED;
    }
    
    new menu = menu_create(MENU_TITLE, "Handler_DeltaMenu");
    new iNow = get_systime();
    
    // ===== КНОПКА 1: ОЧКИ =====
    new szPoints[64];
    if (g_iPointsReadyTime[id] > iNow)
    {
        new iLeft = g_iPointsReadyTime[id] - iNow;
        formatex(szPoints, charsmax(szPoints), "\dОчки \r[Ждать %d сек]", iLeft);
        menu_additem(menu, szPoints, "1", ADMIN_ADMIN); 
    }
    else
    {
        formatex(szPoints, charsmax(szPoints), "\wОчки \y[Забрать +%d]", POINTS_BONUS);
        menu_additem(menu, szPoints, "1");
    }
    
    // ===== КНОПКА 2: ОПЫТ =====
    new szExp[64];
    if (g_iExpReadyTime[id] > iNow)
    {
        new iLeft = g_iExpReadyTime[id] - iNow;
        formatex(szExp, charsmax(szExp), "\dОпыт \r[Ждать %d сек]", iLeft);
        menu_additem(menu, szExp, "2", ADMIN_ADMIN); 
    }
    else
    {
        formatex(szExp, charsmax(szExp), "\wОпыт \y[Забрать +%d]", EXP_BONUS);
        menu_additem(menu, szExp, "2");
    }

    // ===== КНОПКА 3: УПРАВЛЕНИЕ ШАНСОМ ДРОПА (Выдача/Забирание) =====
    menu_additem(menu, "\wУправление \yдоп. Шансом дропа", "3");
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public Handler_DeltaMenu(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new szData[6], szName[64];
    new iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    
    new iChoice = str_to_num(szData);
    menu_destroy(menu);
    
    new iNow = get_systime();
    
    switch (iChoice)
    {
        case 1:
        {
            if (g_iPointsReadyTime[id] > iNow)
            {
                client_print(id, print_chat, "[Delta] Очки еще не готовы для взятия!");
                Cmd_DeltaMenu(id);
                return PLUGIN_HANDLED;
            }
            
            new current = points_get(id);
            new final_points = current + POINTS_BONUS;
            points_set(id, final_points);
            
            client_print(id, print_chat, "[Delta] Вы успешно забрали +%d очков! (Всего: %d)", POINTS_BONUS, final_points);
            g_iPointsReadyTime[id] = iNow + floatround(COOLDOWN_TIME);
            Cmd_DeltaMenu(id);
        }
        case 2:
        {
            if (g_iExpReadyTime[id] > iNow)
            {
                client_print(id, print_chat, "[Delta] Опыт еще не готов для взятия!");
                Cmd_DeltaMenu(id);
                return PLUGIN_HANDLED;
            }
            
            ranks_add_xp(id, EXP_BONUS);
            
            client_print(id, print_chat, "[Delta] Вы успешно забрали +%d Опыта!", EXP_BONUS);
            g_iExpReadyTime[id] = iNow + floatround(COOLDOWN_TIME);
            Cmd_DeltaMenu(id);
        }
        case 3:
        {
            // Открыть меню управления шансом дропа
            ShowDropTargetMenu(id);
        }
    }
    
    return PLUGIN_HANDLED;
}

// === МЕНЮ ВЫБОРА ИГРОКА ДЛЯ ШАНСА ДРОПА (НЕЗАВИСИМАЯ ВЫДАЧА) ===
public ShowDropTargetMenu(id)
{
    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\r[Delta]^n\wУправление доп. Шансом дропа:");
    
    new menu = menu_create(szTitle, "Handler_DropTargetMenu");
    new callback = menu_makecallback("Callback_DisabledItem");
    
    new iPlayers[32], iNum, iTempId;
    new szName[32], szUserId[10], szItem[96];
    
    get_players(iPlayers, iNum, "ch");
    
    for (new i; i < iNum; i++)
    {
        iTempId = iPlayers[i];
        get_user_name(iTempId, szName, charsmax(szName));
        
        new iTargetUserID = get_user_userid(iTempId);
        formatex(szUserId, charsmax(szUserId), "%d", iTargetUserID);
        
        if (g_iDropTarget[id] == -1)
        {
            // ЭТОТ админ еще никому не выдавал бонус — все ники активны
            formatex(szItem, charsmax(szItem), "\w%s \r[Выдать 1 ур.]", szName);
            menu_additem(menu, szItem, szUserId);
        }
        else if (g_iDropTarget[id] == iTargetUserID)
        {
            // ЭТОТ админ выдал бонус данному игроку — ник активен (забрать)
            formatex(szItem, charsmax(szItem), "\w%s \y[Забрать 1 ур.]", szName);
            menu_additem(menu, szItem, szUserId);
        }
        else
        {
            // ЭТОТ админ уже занял свой лимит выдачей другому — все остальные серые
            formatex(szItem, charsmax(szItem), "\d%s [Недоступно]", szName);
            menu_additem(menu, szItem, szUserId, _, callback);
        }
    }
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public Callback_DisabledItem(id, menu, item)
    return ITEM_DISABLED;

public Handler_DropTargetMenu(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        Cmd_DeltaMenu(id);
        return PLUGIN_HANDLED;
    }
    
    new szData[16], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    
    new iUserId = str_to_num(szData);
    new target = find_player("k", iUserId);
    
    if (!target)
    {
        client_print(id, print_chat, "[Delta] Игрок не найден или вышел с сервера!");
        // Если цель вышла, очищаем лимит админа, чтобы он мог выдать другому
        if (g_iDropTarget[id] == iUserId)
            g_iDropTarget[id] = -1;
    }
    else
    {
        if (g_iDropTarget[id] == -1)
        {
            // Выдаем выбранному
            sk_AddExtraDrop(target, 1);
            g_iDropTarget[id] = iUserId; // Запоминаем за этим админом
            
            client_print(id, print_chat, "[Delta] Вы выдали 1 уровень шанса дропа игроку %n", target);
            client_print(target, print_chat, "[Delta] Вам выдали 1 уровень шанса дропа!");
        }
        else if (g_iDropTarget[id] == iUserId)
        {
            // Забираем у того, кому выдали
            sk_TakeExtraDrop(target, 1);
            g_iDropTarget[id] = -1; // Освобождаем лимит админа
            
            client_print(id, print_chat, "[Delta] Вы забрали 1 уровень шанса дропа у игрока %n", target);
            client_print(target, print_chat, "[Delta] У вас забрали 1 уровень шанса дропа!");
        }
        else
        {
            client_print(id, print_chat, "[Delta] Вы уже заняли свой лимит выдачи! Сначала заберите шанс дропа.");
        }
    }
    
    menu_destroy(menu);
    ShowDropTargetMenu(id);
    
    return PLUGIN_HANDLED;
}

public Event_GameRestart()
{
    g_iCacheCount = 0;
    new iNow = get_systime();
    new maxplayers = get_maxplayers();
    
    for (new i = 1; i <= maxplayers; i++)
    {
        // Сбрасываем выданные бонусы шанса дропа при рестарте игры
        if (g_iDropTarget[i] != -1)
        {
            new target = find_player("k", g_iDropTarget[i]);
            if (target)
            {
                sk_TakeExtraDrop(target, 1);
                client_print(target, print_chat, "[Delta] Бонус шанса дропа снят из-за рестарта игры.");
            }
            g_iDropTarget[i] = -1;
        }

        g_iPointsReadyTime[i] = iNow + floatround(COOLDOWN_TIME);
        g_iExpReadyTime[i] = iNow + floatround(COOLDOWN_TIME);
    }
}

ArrayRemoveRow(row)
{
    for (new i = row; i < g_iCacheCount - 1; i++)
    {
        g_eCooldownCache[i] = g_eCooldownCache[i + 1];
    }
    g_iCacheCount--;
}