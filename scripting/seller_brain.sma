#include <amxmodx>
#include <amxmisc>
#include <reapi> // Подключаем ReAPI для работы с деньгами напрямую в памяти

// Подключаем нативы главного плагина (триггеры)
native cm_register_action(const szName[], const szHandler[]);

// Подключаем нативы системы очков
native points_get(id);
native points_set(id, amount);
native points_is_loaded(id);

// Подключаем нативы инвентаря ресурсов
native api_get_resource_id(const szName[]);
native api_give_resource(id, resId, amount);
native api_get_resource_amount(id, resId);
native api_get_resources_count();
native api_get_resource_name(resId, buffer[], len);

#define MAX_RES 64
#define MAX_NAME_LEN 64

// Массивы для хранения цен и названий, прочитанных из INI
new g_szResNames[MAX_RES][MAX_NAME_LEN];
new g_iResPrices[MAX_RES];
new g_iLoadedResCount = 0;

// Курс конвертации
#define EXCHANGE_RATE 2000

public plugin_init() {
    register_plugin("Seller Brain", "3.0", "nb_team");
    
    // Регистрируем команду для ввода своей суммы обмена
    register_clcmd("amx_enter_exchange", "Handle_ExchangeInput");
    
    // Загружаем названия и цены из INI файла
    LoadPricesFromIni();
    
    // Регистрируем действия в главном плагине с задержкой
    set_task(1.0, "RegisterSellerActions");
}

// ==========================================
// ЧТЕНИЕ ЦЕН ИЗ INI
// ==========================================
LoadPricesFromIni() {
    new szFile[128];
    get_configsdir(szFile, charsmax(szFile));
    add(szFile, charsmax(szFile), "/resources.ini");
    
    if (!file_exists(szFile)) return;

    new f = fopen(szFile, "r");
    if (!f) return;

    new szLine[128], szName[MAX_NAME_LEN], szPrice[16];
    while (!feof(f) && g_iLoadedResCount < MAX_RES) {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);

        if (!szLine[0] || szLine[0] == ';') continue;

        parse(szLine, szName, charsmax(szName), szPrice, charsmax(szPrice));
        
        copy(g_szResNames[g_iLoadedResCount], MAX_NAME_LEN - 1, szName);
        g_iResPrices[g_iLoadedResCount] = str_to_num(szPrice);
        
        g_iLoadedResCount++;
    }
    fclose(f);
}

public RegisterSellerActions() {
    cm_register_action("Продавец: Открыть меню", "Action_SellerOpen");
    cm_register_action("Продавец: Закрыть меню", "Action_SellerClose");
}

// ==========================================
// ВЗАИМОДЕЙСТВИЕ С ТРИГГЕРАМИ
// ==========================================

public Action_SellerOpen(id, iTrigID) {
    if (!is_user_alive(id)) return;
    
    if (!points_is_loaded(id)) {
        client_print(id, print_chat, "[Продавец] Ваши очки еще загружаются, подождите...");
        return;
    }
    
    ShowMainMenu(id);
}

public Action_SellerClose(id, iTrigID) {
    if (!is_user_connected(id)) return;
    show_menu(id, 0, "^0", 0);
}

// ==========================================
// 1. ОСНОВНОЕ МЕНЮ
// ==========================================

ShowMainMenu(id) {
    new szTitle[256];
    new iPoints = points_get(id);
    new iMoney = get_member(id, m_iAccount); // Получаем деньги через ReAPI
    
    formatex(szTitle, charsmax(szTitle), "\rПродавец^n\yВаши очки: %d^n\yВаши деньги: %d$^n\dЧто желаете сделать?", iPoints, iMoney);
    
    new menu = menu_create(szTitle, "MainMenu_Handler");

    menu_additem(menu, "Купить ресурсы", "1");
    menu_additem(menu, "Обменять деньги на очки", "2");
    
    menu_setprop(menu, MPROP_EXITNAME, "Уйти");
    menu_display(id, menu, 0);
}

public MainMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);
    
    menu_destroy(menu);

    if (iChoice == 1) {
        ShowResourcesMenu(id);
    } else if (iChoice == 2) {
        ShowExchangeMenu(id);
    }
    
    return PLUGIN_HANDLED;
}

// ==========================================
// 2. МЕНЮ ПОКУПКИ РЕСУРСОВ
// ==========================================

ShowResourcesMenu(id) {
    new szTitle[256];
    new iPoints = points_get(id);
    formatex(szTitle, charsmax(szTitle), "\rПокупка ресурсов^n\yВаши очки: %d^n\dВыберите предмет:", iPoints);
    
    new menu = menu_create(szTitle, "ResourcesMenu_Handler");

    new szItem[128], szApiName[MAX_NAME_LEN], iPrice;
    new count = api_get_resources_count();
    
    for (new i = 0; i < count; i++) {
        api_get_resource_name(i, szApiName, charsmax(szApiName));
        
        iPrice = -1;
        for (new j = 0; j < g_iLoadedResCount; j++) {
            if (equali(szApiName, g_szResNames[j])) {
                iPrice = g_iResPrices[j];
                break;
            }
        }
        
        if (iPrice <= 0) continue;
        
        formatex(szItem, charsmax(szItem), "%s \y[%d очков]", szApiName, iPrice);
        
        new szInfo[6];
        num_to_str(i, szInfo, charsmax(szInfo)); 
        
        menu_additem(menu, szItem, szInfo);
    }

    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public ResourcesMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        ShowMainMenu(id); // Возвращаемся в главное меню
        return PLUGIN_HANDLED;
    }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    
    new resApiId = str_to_num(data);
    
    new szResName[MAX_NAME_LEN];
    api_get_resource_name(resApiId, szResName, charsmax(szResName));
    
    new iPrice = -1;
    for (new j = 0; j < g_iLoadedResCount; j++) {
        if (equali(szResName, g_szResNames[j])) {
            iPrice = g_iResPrices[j];
            break;
        }
    }

    if (iPrice <= 0) {
        client_print(id, print_chat, "[Продавец] Ошибка: цена не найдена.");
        menu_destroy(menu);
        ShowResourcesMenu(id); // НЕ закрываем меню
        return PLUGIN_HANDLED;
    }

    new iPoints = points_get(id);
    
    if (iPoints >= iPrice) {
        points_set(id, iPoints - iPrice);
        api_give_resource(id, resApiId, 1);
        
        client_print(id, print_chat, "[Продавец] Вы купили 1 шт. %s за %d очков!", szResName, iPrice);
    } else {
        client_print(id, print_chat, "[Продавец] Недостаточно очков! Нужно: %d, У вас: %d", iPrice, iPoints);
    }

    menu_destroy(menu);
    ShowResourcesMenu(id); // НЕ закрываем меню после покупки
    
    return PLUGIN_HANDLED;
}

// ==========================================
// 3. МЕНЮ ОБМЕНА ВАЛЮТЫ
// ==========================================

ShowExchangeMenu(id) {
    new szTitle[256];
    new iPoints = points_get(id);
    new iMoney = get_member(id, m_iAccount); // Получаем деньги через ReAPI
    
    formatex(szTitle, charsmax(szTitle), "\rОбмен валюты^n\yВаши деньги: %d$^n\yВаши очки: %d^n\dКурс: %d$ = 1 очко", iMoney, iPoints, EXCHANGE_RATE);
    
    new menu = menu_create(szTitle, "ExchangeMenu_Handler");

    menu_additem(menu, "Обменять ВСЕ деньги", "1");
    menu_additem(menu, "Обменять определенную сумму", "2");
    
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public ExchangeMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        ShowMainMenu(id); // Возвращаемся в главное меню
        return PLUGIN_HANDLED;
    }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);
    
    menu_destroy(menu);

    if (iChoice == 1) {
        // Обменять всё
        ConvertAllMoney(id);
        ShowExchangeMenu(id); // НЕ закрываем меню
    } else if (iChoice == 2) {
        // Ввести сумму
        client_print(id, print_chat, "[Продавец] Введите в чат сумму денег для обмена (округлится в меньшую сторону до %d$):", EXCHANGE_RATE);
        client_cmd(id, "messagemode amx_enter_exchange"); // Открывает ввод строки внизу экрана
        // Меню временно скрывается, чтобы игрок мог напечатать сумму
    }
    
    return PLUGIN_HANDLED;
}

// Обработчик ввода суммы для обмена
public Handle_ExchangeInput(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    
    new szArg[16], iInputMoney, iCurrentMoney;
    read_args(szArg, charsmax(szArg));
    remove_quotes(szArg);
    
    iInputMoney = str_to_num(szArg);
    
    if (iInputMoney <= 0) {
        client_print(id, print_chat, "[Продавец] Неверная сумма.");
        ShowExchangeMenu(id);
        return PLUGIN_HANDLED;
    }
    
    iCurrentMoney = get_member(id, m_iAccount);
    
    // Если ввел больше, чем есть, приравниваем к текущему балансу
    if (iInputMoney > iCurrentMoney) {
        iInputMoney = iCurrentMoney;
    }
    
    // Считаем очки (округление в меньшую сторону)
    new iPointsToGive = iInputMoney / EXCHANGE_RATE;
    
    if (iPointsToGive <= 0) {
        client_print(id, print_chat, "[Продавец] Слишком малая сумма. Нужно минимум %d$.", EXCHANGE_RATE);
    } else {
        // Считаем, сколько реально спишется денег (с учетом округления очков)
        new iMoneyToTake = iPointsToGive * EXCHANGE_RATE;
        
        // Списываем деньги через ReAPI и выдаем очки
        set_member(id, m_iAccount, iCurrentMoney - iMoneyToTake);
        points_set(id, points_get(id) + iPointsToGive);
        
        client_print(id, print_chat, "[Продавец] Вы обменяли %d$ на %d очков!", iMoneyToTake, iPointsToGive);
    }
    
    // Возвращаем игрока в меню обмена
    ShowExchangeMenu(id);
    
    return PLUGIN_HANDLED;
}

// Функция обмена всех денег
ConvertAllMoney(id) {
    new iCurrentMoney = get_member(id, m_iAccount);
    
    if (iCurrentMoney < EXCHANGE_RATE) {
        client_print(id, print_chat, "[Продавец] У вас недостаточно денег для обмена. Нужно минимум %d$.", EXCHANGE_RATE);
        return;
    }
    
    new iPointsToGive = iCurrentMoney / EXCHANGE_RATE;
    new iMoneyToTake = iPointsToGive * EXCHANGE_RATE;
    
    // Списываем деньги и выдаем очки
    set_member(id, m_iAccount, iCurrentMoney - iMoneyToTake);
    points_set(id, points_get(id) + iPointsToGive);
    
    client_print(id, print_chat, "[Продавец] Вы обменяли %d$ на %d очков!", iMoneyToTake, iPointsToGive);
}