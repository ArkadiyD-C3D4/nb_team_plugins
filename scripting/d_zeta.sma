#include <amxmodx>
#include <amxmisc>

// Нативы из внешнего плагина очков
native points_get(id);
native points_set(id, points);
native ranks_add_xp(id, amount);

// === НАТИВЫ ИЗ skills_system.sma ===
native sk_AddExtraMult(id, amount);
native sk_TakeExtraMult(id, amount);
native sk_GetExtraMult(id);

// Константы
#define PLUGIN_NAME     "Zeta Menu System"
#define PLUGIN_VERSION  "2.8"
#define PLUGIN_AUTHOR   "nb_team"

#define MENU_TITLE      "\r[Zeta System]^n\wВыберите бонус:"
#define COOLDOWN_TIME   600.0  // Время ожидания (10 минут в секундах)
#define POINTS_BONUS    30    // Бонус очков для Zeta
#define EXP_BONUS       30    // Бонус опыта для Zeta

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

// === ПЕРЕМЕННАЯ ДЛЯ НЕЗАВИСИМОЙ ВЫДАЧИ МНОЖИТЕЛЯ ===
// Хранит UserID игрока, которому КОНКРЕТНЫЙ админ выдал бонус (-1 если никому)
new g_iMultTarget[33];

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
    
    register_clcmd("say /zeta", "Cmd_ZetaMenu");
    register_clcmd("say_team /zeta", "Cmd_ZetaMenu");
    
    register_event("TextMsg", "Event_GameRestart", "a", "2&=Game_Commencing", "2&=Game_Will_Restart_In");
}

public client_putinserver(id)
{
    if (is_user_bot(id))
        return;

    // Инициализация личной переменной выдачи
    g_iMultTarget[id] = -1;

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
    if (g_iMultTarget[id] != -1)
    {
        new target = find_player("k", g_iMultTarget[id]);
        if (target)
        {
            sk_TakeExtraMult(target, 1);
            client_print(target, print_chat, "[Zeta] Бонус множителя снят, так как админ покинул сервер.");
        }
        g_iMultTarget[id] = -1;
    }

    // 2. Если выходит ИГРОК, у которого есть бонус: находим админа, который ему выдал, и освобождаем лимит
    new iDisconnectedUserID = get_user_userid(id);
    new iPlayers[32], iNum, iAdminID;
    get_players(iPlayers, iNum, "ch"); // ch - проверяем всех людей без ботов
    
    for (new i = 0; i < iNum; i++)
    {
        iAdminID = iPlayers[i];
        // Если мы находим админа, который держал лимит на этом вышедшем игроке
        if (g_iMultTarget[iAdminID] == iDisconnectedUserID)
        {
            g_iMultTarget[iAdminID] = -1; // Освобождаем лимит админа
            client_print(iAdminID, print_chat, "[Zeta] Игрок с вашим бонусом множителя вышел. Лимит освобожден.");
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

public Cmd_ZetaMenu(id)
{
     if (!is_user_connected(id))
        return PLUGIN_CONTINUE;

    if (!(get_user_flags(id) & ADMIN_RCON))
    {
        client_print(id, print_chat, "[Zeta] У вас нет доступа к этому меню!");
        return PLUGIN_HANDLED;
    }
    
    new menu = menu_create(MENU_TITLE, "Handler_ZetaMenu");
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

    // ===== КНОПКА 3: УПРАВЛЕНИЕ МНОЖИТЕЛЕМ (Выдача/Забирание) =====
    menu_additem(menu, "\wУправление \yдоп. Множителем", "3");
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public Handler_ZetaMenu(id, menu, item)
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
                client_print(id, print_chat, "[Zeta] Очки еще не готовы для взятия!");
                Cmd_ZetaMenu(id);
                return PLUGIN_HANDLED;
            }
            
            new current = points_get(id);
            new final_points = current + POINTS_BONUS;
            points_set(id, final_points);
            
            client_print(id, print_chat, "[Zeta] Вы успешно забрали +%d очков! (Всего: %d)", POINTS_BONUS, final_points);
            g_iPointsReadyTime[id] = iNow + floatround(COOLDOWN_TIME);
            Cmd_ZetaMenu(id);
        }
        case 2:
        {
            if (g_iExpReadyTime[id] > iNow)
            {
                client_print(id, print_chat, "[Zeta] Опыт еще не готов для взятия!");
                Cmd_ZetaMenu(id);
                return PLUGIN_HANDLED;
            }
            
            ranks_add_xp(id, EXP_BONUS);
            
            client_print(id, print_chat, "[Zeta] Вы успешно забрали +%d Опыта!", EXP_BONUS);
            g_iExpReadyTime[id] = iNow + floatround(COOLDOWN_TIME);
            Cmd_ZetaMenu(id);
        }
        case 3:
        {
            // Открыть меню управления множителем
            ShowMultTargetMenu(id);
        }
    }
    
    return PLUGIN_HANDLED;
}

// === МЕНЮ ВЫБОРА ИГРОКА ДЛЯ МНОЖИТЕЛЯ (НЕЗАВИСИМАЯ ВЫДАЧА) ===
public ShowMultTargetMenu(id)
{
    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\r[Zeta]^n\wУправление доп. Множителем:");
    
    new menu = menu_create(szTitle, "Handler_MultTargetMenu");
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
        
        if (g_iMultTarget[id] == -1)
        {
            // ЭТОТ админ еще никому не выдавал бонус — все ники активны
            formatex(szItem, charsmax(szItem), "\w%s \r[Выдать 1 ур.]", szName);
            menu_additem(menu, szItem, szUserId);
        }
        else if (g_iMultTarget[id] == iTargetUserID)
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

public Handler_MultTargetMenu(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        Cmd_ZetaMenu(id);
        return PLUGIN_HANDLED;
    }
    
    new szData[16], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    
    new iUserId = str_to_num(szData);
    new target = find_player("k", iUserId);
    
    if (!target)
    {
        client_print(id, print_chat, "[Zeta] Игрок не найден или вышел с сервера!");
        // Если цель вышла, очищаем лимит админа, чтобы он мог выдать другому
        if (g_iMultTarget[id] == iUserId)
            g_iMultTarget[id] = -1;
    }
    else
    {
        if (g_iMultTarget[id] == -1)
        {
            // Выдаем выбранному
            sk_AddExtraMult(target, 1);
            g_iMultTarget[id] = iUserId; // Запоминаем за этим админом
            
            client_print(id, print_chat, "[Zeta] Вы выдали 1 уровень множителя игроку %n", target);
            client_print(target, print_chat, "[Zeta] Вам выдали 1 уровень множителя!");
        }
        else if (g_iMultTarget[id] == iUserId)
        {
            // Забираем у того, кому выдали
            sk_TakeExtraMult(target, 1);
            g_iMultTarget[id] = -1; // Освобождаем лимит админа
            
            client_print(id, print_chat, "[Zeta] Вы забрали 1 уровень множителя у игрока %n", target);
            client_print(target, print_chat, "[Zeta] У вас забрали 1 уровень множителя!");
        }
        else
        {
            client_print(id, print_chat, "[Zeta] Вы уже заняли свой лимит выдачи! Сначала заберите множитель.");
        }
    }
    
    menu_destroy(menu);
    ShowMultTargetMenu(id);
    
    return PLUGIN_HANDLED;
}

public Event_GameRestart()
{
    g_iCacheCount = 0;
    new iNow = get_systime();
    new maxplayers = get_maxplayers();
    
    for (new i = 1; i <= maxplayers; i++)
    {
        // Сбрасываем выданные множители при рестарте игры
        if (g_iMultTarget[i] != -1)
        {
            new target = find_player("k", g_iMultTarget[i]);
            if (target)
            {
                sk_TakeExtraMult(target, 1);
                client_print(target, print_chat, "[Zeta] Бонус множителя снят из-за рестарта игры.");
            }
            g_iMultTarget[i] = -1;
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