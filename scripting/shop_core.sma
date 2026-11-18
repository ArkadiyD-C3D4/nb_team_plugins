#include <amxmodx>
#include <amxmisc>
#include <engine>
#include <colorchat>

#define PLUGIN "Universal Shop Core"
#define VERSION "1.5"
#define AUTHOR "nb_team"

#define MAX_SHOP_ITEMS 128
#define ITEMS_PER_PAGE 7

#define KEY_0 (1<<9)  // Кнопка 0
#define KEY_1 (1<<0)  // Кнопка 1
#define KEY_2 (1<<1)  // Кнопка 2
#define KEY_3 (1<<2)  // Кнопка 3
#define KEY_4 (1<<3)  // Кнопка 4
#define KEY_5 (1<<4)  // Кнопка 5
#define KEY_6 (1<<5)  // Кнопка 6
#define KEY_7 (1<<6)  // Кнопка 7
#define KEY_8 (1<<7)  // Кнопка 8
#define KEY_9 (1<<8)  // Кнопка 9

new const MENU_SHOP[] = "ShopMenu";

native points_get(id)
native points_set(id, amount)
native points_is_loaded(id)

new g_szItemName[MAX_SHOP_ITEMS][64]
new g_iItemCost[MAX_SHOP_ITEMS]
new g_szItemCommand[MAX_SHOP_ITEMS][128]
new g_iTotalItems = 0

new g_szMainMenuCmd[64]
new g_iShopPage[33]

public plugin_natives()
{
    register_native("shop_register_item", "Native_RegisterItem")
    register_native("shop_clear_items", "Native_ClearItems")
}

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)
    register_clcmd("say /shop", "Cmd_Shop")
    register_clcmd("say_team /shop", "Cmd_Shop")
    register_clcmd("say /anew", "Cmd_Shop")
    register_clcmd("say_team /anew", "Cmd_Shop")
    
    register_menucmd(register_menuid(MENU_SHOP), 1023, "Handle_ShopMenu")
    
    LoadMenuSystemConfig()
}

public LoadMenuSystemConfig()
{
    copy(g_szMainMenuCmd, charsmax(g_szMainMenuCmd), "chooseteam")
    
    new szPath[256]
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath))
    formatex(szPath, charsmax(szPath), "%s/menuSystem.ini", szPath)
    
    if(!file_exists(szPath)) return
    
    new f = fopen(szPath, "r")
    if(!f) return
    
    new szLine[256]
    new bool:bInMainSection = false
    
    while(!feof(f))
    {
        fgets(f, szLine, charsmax(szLine))
        trim(szLine)
        
        if(szLine[0] == EOS) continue
        
        if(szLine[0] == '[')
        {
            new close = contain(szLine, "]")
            if(close > 0)
            {
                szLine[close] = 0
                bInMainSection = equal(szLine[1], "Главное меню") ? true : false
            }
            else
            {
                bInMainSection = false
            }
            continue
        }
        
        if(szLine[0] == ';') continue
        if(!bInMainSection) continue
        
        new eq = contain(szLine, "=")
        if(eq <= 0) continue
        
        new szKey[32], szVal[64]
        copy(szKey, charsmax(szKey), szLine)
        if(eq < charsmax(szKey)) szKey[eq] = 0
        trim(szKey)
        
        copy(szVal, charsmax(szVal), szLine[eq + 1])
        trim(szVal)
        
        if(equali(szKey, "cmd") && szVal[0])
        {
            copy(g_szMainMenuCmd, charsmax(g_szMainMenuCmd), szVal)
        }
    }
    
    fclose(f)
}

public Native_RegisterItem(iPlugin, iParams)
{
    if (g_iTotalItems >= MAX_SHOP_ITEMS) {
        log_amx("[SHOP CORE] Достигнут лимит предметов (%d)!", MAX_SHOP_ITEMS)
        return -1
    }
    
    new szName[64], szCmd[128]
    get_string(1, szName, charsmax(szName))
    new cost = get_param(2)
    get_string(3, szCmd, charsmax(szCmd))
    
    copy(g_szItemName[g_iTotalItems], charsmax(g_szItemName[]), szName)
    g_iItemCost[g_iTotalItems] = cost
    copy(g_szItemCommand[g_iTotalItems], charsmax(g_szItemCommand[]), szCmd)
    
    return g_iTotalItems++
}

public Native_ClearItems(iPlugin, iParams)
{
    g_iTotalItems = 0
    return 1
}

stock bool:IsItemBlocked(id, iIndex)
{
    if (equal(g_szItemCommand[iIndex], "buy_speed")) {
        new Float:fSpeed = entity_get_float(id, EV_FL_maxspeed)
        if (fSpeed >= 320.0) return true
    }
    
    if (equal(g_szItemCommand[iIndex], "buy_gravity")) {
        new Float:fGravity = entity_get_float(id, EV_FL_gravity)
        if (fGravity < 1.0) return true
    }
    
    return false
}

public Cmd_Shop(id)
{
    if (!points_is_loaded(id)) {
        client_print_color(id, print_team_default, "^4[SHOP]^1 Данные об очках ещё загружаются, подождите...")
        return PLUGIN_HANDLED
    }

    if (g_iTotalItems == 0) {
        client_print_color(id, print_team_default, "^4[SHOP]^1 Магазин пуст. Обратитесь к администратору.")
        return PLUGIN_HANDLED
    }

    new page = g_iShopPage[id]
    new iStart = page * ITEMS_PER_PAGE
    new iEnd = iStart + ITEMS_PER_PAGE
    if (iEnd > g_iTotalItems) iEnd = g_iTotalItems
    
    new current_points = points_get(id)
    new szMenu[2048]
    new len = 0
    new keys = KEY_0  // Всегда есть кнопка 0 (Выход)
    
    // Проверяем, есть ли следующая страница
    new bool:hasNextPage = (iEnd < g_iTotalItems)
    
    // Заголовок: МАГАЗИН жёлтый, очки красные в скобках
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\yМагазин \r[%d очков]^n", current_points)
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\wВыберите предмет:^n^n")
    
    // Предметы (7 на странице)
    for (new i = iStart; i < iEnd; i++)
    {
        new key = i - iStart // 0-6
        new bool:bBlocked = IsItemBlocked(id, i)
        
        if (bBlocked) {
            len += formatex(szMenu[len], charsmax(szMenu) - len, "\d%d. %s [%d очков] (Активно)^n", key + 1, g_szItemName[i], g_iItemCost[i])
        } else if (current_points < g_iItemCost[i]) {
            len += formatex(szMenu[len], charsmax(szMenu) - len, "\d%d. %s [%d очков] (Не хватает)^n", key + 1, g_szItemName[i], g_iItemCost[i])
        } else {
            // Название белым, цена ПОЛНОСТЬЮ красная
            len += formatex(szMenu[len], charsmax(szMenu) - len, "\r%d. \w%s \r[%d очков]^n", key + 1, g_szItemName[i], g_iItemCost[i])
            keys |= (1 << key)
        }
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n")
    
    // Кнопка 8 - Назад по страницам (если не первая страница)
    if (page > 0) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r8. \wНазад^n")
        keys |= KEY_8
    }
    
    // Кнопка 9 - если есть следующая страница → "Вперед", иначе → "Назад" (в главное меню)
    if (hasNextPage) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r9. \wВперед^n")
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r9. \wНазад^n")
    }
    keys |= KEY_9
    
    // Кнопка 0 - Выход
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r0. \wВыход")
    
    show_menu(id, keys, szMenu, -1, MENU_SHOP)
    
    return PLUGIN_HANDLED
}

public Handle_ShopMenu(id, key)
{
    if (!is_user_connected(id)) return PLUGIN_HANDLED
    
    // key 9 = кнопка 0 - Выход (закрытие меню)
    if (key == 9)
    {
        show_menu(id, 0, "^n", 1, MENU_SHOP)
        return PLUGIN_HANDLED
    }
    
    // key 8 = кнопка 9 - Вперед (следующая страница) или Назад (в главное меню)
    if (key == 8)
    {
        new page = g_iShopPage[id]
        new iEnd = (page + 1) * ITEMS_PER_PAGE
        
        if (iEnd < g_iTotalItems) {
            // Есть следующая страница
            g_iShopPage[id]++
            Cmd_Shop(id)
        } else {
            // Нет следующей страницы - идём в главное меню
            client_cmd(id, g_szMainMenuCmd)
        }
        return PLUGIN_HANDLED
    }
    
    // key 7 = кнопка 8 - Назад (предыдущая страница)
    if (key == 7)
    {
        if (g_iShopPage[id] > 0) {
            g_iShopPage[id]--
            Cmd_Shop(id)
        }
        return PLUGIN_HANDLED
    }
    
    // key 0-6 = кнопки 1-7 - предметы
    new page = g_iShopPage[id]
    new iIndex = page * ITEMS_PER_PAGE + key
    
    if (iIndex < 0 || iIndex >= g_iTotalItems)
    {
        return PLUGIN_HANDLED
    }
    
    // Проверка блокировки
    if (IsItemBlocked(id, iIndex))
    {
        client_print_color(id, print_team_default, "^4[SHOP]^1 Этот баф уже активен!")
        Cmd_Shop(id)
        return PLUGIN_HANDLED
    }
    
    new current_points = points_get(id)
    new cost = g_iItemCost[iIndex]
    
    if (current_points < cost)
    {
        client_print_color(id, print_team_default, "^4[SHOP]^1 Недостаточно очков! Нужно: ^3%d^1, у вас: ^3%d^1", cost, current_points)
        Cmd_Shop(id)
        return PLUGIN_HANDLED
    }
    
    points_set(id, current_points - cost)
    
    client_print_color(id, print_team_default, "^4[SHOP]^1 Вы успешно купили: ^3%s^1! Списано ^3%d^1 очков.", g_szItemName[iIndex], cost)
    
    if (!equal(g_szItemCommand[iIndex], "NONE") && !equal(g_szItemCommand[iIndex], ""))
    {
        client_cmd(id, g_szItemCommand[iIndex])
    }
    
    set_task(0.5, "Cmd_Shop", id)
    
    return PLUGIN_HANDLED
}