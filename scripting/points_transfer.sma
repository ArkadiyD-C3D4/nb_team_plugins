#include <amxmodx>
#include <amxmisc>
#include <colorchat> // Добавлено для корректной работы client_print_color

#define PLUGIN "Points Transfer"
#define VERSION "2.1"
#define AUTHOR "nb_team"

// Подключаем нэйтивы из вашего Points Core
native points_get(id)
native points_set(id, amount)
native points_is_loaded(id)

// Глобальные переменные для хранения состояния перевода для каждого игрока
new g_iTransferTarget[33]
new g_iTransferAmount[33]

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)
    
    register_clcmd("say /transfer", "Cmd_Transfer")
    register_clcmd("say_team /transfer", "Cmd_Transfer")
    
    // Команда для перехвата ввода суммы через messagemode
    register_clcmd("transfer_amount_input", "Cmd_EnterAmount")
}

public client_disconnect(id)
{
    // Очищаем данные при выходе игрока, чтобы избежать багов
    g_iTransferTarget[id] = 0
    g_iTransferAmount[id] = 0
}

// ==========================================================
// ШАГ 1: Открытие меню выбора игрока
// ==========================================================
public Cmd_Transfer(id)
{
    if (!is_user_connected(id))
        return PLUGIN_HANDLED

    if (!points_is_loaded(id))
    {
        client_print_color(id, print_team_default, "^4[POINTS]^1 Ваши данные ещё загружаются, подождите.")
        return PLUGIN_HANDLED
    }

    new iSenderPoints = points_get(id)
    if (iSenderPoints <= 0)
    {
        client_print_color(id, print_team_default, "^4[POINTS]^1 У вас нет очков для перевода.")
        return PLUGIN_HANDLED
    }

    // Заголовок теперь жёлтый (\y)
    new menu = menu_create("\yПеревод очков^n\wВыберите игрока:", "Menu_Player_Handler")

    new szName[32], szData[4]
    new bHasPlayers = false

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && i != id)
        {
            get_user_name(i, szName, charsmax(szName))
            num_to_str(i, szData, charsmax(szData))
            menu_additem(menu, szName, szData)
            bHasPlayers = true
        }
    }

    if (!bHasPlayers)
    {
        menu_destroy(menu)
        client_print_color(id, print_team_default, "^4[POINTS]^1 На сервере нет других игроков для перевода.")
        return PLUGIN_HANDLED
    }

    // Устанавливаем русские названия кнопок
    menu_setprop(menu, MPROP_BACKNAME, "Назад")
    menu_setprop(menu, MPROP_NEXTNAME, "Далее")
    menu_setprop(menu, MPROP_EXITNAME, "Выход")

    menu_display(id, menu)
    return PLUGIN_HANDLED
}

// ==========================================================
// ОБРАБОТЧИК ШАГА 1: Выбор игрока и запрос суммы
// ==========================================================
public Menu_Player_Handler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu)
        return PLUGIN_HANDLED
    }

    new szData[4], iAccess, iCallback
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), _, _, iCallback)
    menu_destroy(menu)

    new iTarget = str_to_num(szData)

    if (!is_user_connected(iTarget))
    {
        client_print_color(id, print_team_default, "^4[POINTS]^1 Этот игрок только что покинул сервер.")
        return PLUGIN_HANDLED
    }

    if (!points_is_loaded(iTarget))
    {
        client_print_color(id, print_team_default, "^4[POINTS]^1 Данные этого игрока ещё загружаются.")
        return PLUGIN_HANDLED
    }

    // Сохраняем выбор игрока
    g_iTransferTarget[id] = iTarget

    // Запрашиваем ввод суммы через консоль/чат
    client_print_color(id, print_team_default, "^4[POINTS]^1 Введите количество очков для перевода в чат:")
    client_cmd(id, "messagemode transfer_amount_input")

    return PLUGIN_HANDLED
}

// ==========================================================
// ШАГ 2: Обработка введенной суммы и показ подтверждения
// ==========================================================
public Cmd_EnterAmount(id)
{
    new szArg[32]
    read_argv(1, szArg, charsmax(szArg))

    new iAmount = str_to_num(szArg)

    // Сбрасываем состояние, если ввод некорректен
    if (iAmount <= 0)
    {
        client_print_color(id, print_team_default, "^4[POINTS]^1 Неверное количество. Перевод отменен.")
        g_iTransferTarget[id] = 0
        return PLUGIN_HANDLED
    }

    new iTarget = g_iTransferTarget[id]

    // Проверяем, не вышел ли игрок, пока мы вводили сумму
    if (!is_user_connected(iTarget))
    {
        client_print_color(id, print_team_default, "^4[POINTS]^1 Игрок покинул сервер во время ввода. Перевод отменен.")
        g_iTransferTarget[id] = 0
        return PLUGIN_HANDLED
    }

    new iSenderPoints = points_get(id)
    if (iSenderPoints < iAmount)
    {
        client_print_color(id, print_team_default, "^4[POINTS]^1 У вас недостаточно очков. У вас: ^3%d^1, вы пытаетесь перевести: ^3%d^1.", iSenderPoints, iAmount)
        g_iTransferTarget[id] = 0
        return PLUGIN_HANDLED
    }

    // Сохраняем сумму и переходим к подтверждению
    g_iTransferAmount[id] = iAmount
    ShowConfirmMenu(id)

    return PLUGIN_HANDLED
}

// ==========================================================
// ШАГ 3: Меню подтверждения с деталями
// ==========================================================
ShowConfirmMenu(id)
{
    new iTarget = g_iTransferTarget[id]
    new iAmount = g_iTransferAmount[id]
    
    new szTargetName[32]
    get_user_name(iTarget, szTargetName, charsmax(szTargetName))

    new iSenderPoints = points_get(id)
    new iRemaining = iSenderPoints - iAmount

    new szMenu[512]
    // Заголовок жёлтый (\y), данные выделены жёлтым (\y), остальное белое (\w)
    formatex(szMenu, charsmax(szMenu), "\yПодтверждение перевода^n^n\
    \wИгрок: \y%s^n\
    \wОтправляете: \y%d^n\
    \wОстанется у вас: \y%d^n^n\
    \wВыполнить перевод?", szTargetName, iAmount, iRemaining)

    new menu = menu_create(szMenu, "Menu_Confirm_Handler")
    menu_additem(menu, "\gДа, перевести", "1")
    menu_additem(menu, "\rНет, отмена", "0")
    
    // Устанавливаем русские названия кнопок
    menu_setprop(menu, MPROP_BACKNAME, "Назад")
    menu_setprop(menu, MPROP_NEXTNAME, "Далее")
    menu_setprop(menu, MPROP_EXITNAME, "Выход")
    
    menu_display(id, menu)
}

// ==========================================================
// ОБРАБОТЧИК ШАГА 3: Финальное выполнение или отмена
// ==========================================================
public Menu_Confirm_Handler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu)
        CancelTransfer(id)
        return PLUGIN_HANDLED
    }

    new szData[2], iAccess, iCallback
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), _, _, iCallback)
    menu_destroy(menu)

    if (szData[0] == '0') // Нажата кнопка "Нет, отмена"
    {
        CancelTransfer(id)
        return PLUGIN_HANDLED
    }

    // === ВЫПОЛНЕНИЕ ПЕРЕВОДА ===
    new iTarget = g_iTransferTarget[id]
    new iAmount = g_iTransferAmount[id]

    if (!is_user_connected(iTarget))
    {
        client_print_color(id, print_team_default, "^4[POINTS]^1 Игрок покинул сервер. Перевод отменен.")
        CancelTransfer(id)
        return PLUGIN_HANDLED
    }

    new iSenderPoints = points_get(id)
    new iTargetPoints = points_get(iTarget)

    // Используем ваши нэйтивы (они сами сохранят данные в БД)
    points_set(id, iSenderPoints - iAmount)
    points_set(iTarget, iTargetPoints + iAmount)

    new szSenderName[32], szTargetName[32]
    get_user_name(id, szSenderName, charsmax(szSenderName))
    get_user_name(iTarget, szTargetName, charsmax(szTargetName))

    // Уведомления
    client_print_color(id, print_team_default, "^4[POINTS]^1 Вы успешно перевели ^3%d^1 очков игроку ^3%s^1.", iAmount, szTargetName)
    client_print_color(iTarget, print_team_default, "^4[POINTS]^1 Игрок ^3%s^1 перевел вам ^3%d^1 очков.", szSenderName, iAmount)

    // Очищаем состояние
    g_iTransferTarget[id] = 0
    g_iTransferAmount[id] = 0

    return PLUGIN_HANDLED
}

// Вспомогательная функция для отмены
CancelTransfer(id)
{
    client_print_color(id, print_team_default, "^4[POINTS]^1 Перевод отменен.")
    g_iTransferTarget[id] = 0
    g_iTransferAmount[id] = 0
}