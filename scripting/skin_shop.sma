#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <colorchat>

native skin_core_get_count()
native skin_core_get_info(index, name[], namelen, &price, &teams)
native skin_core_get_points(id)
native skin_core_is_owned(id, const name[])
native skin_core_buy_skin(id, const name[])
native skin_core_get_selected(id, output[], maxlen)
native skin_core_set_selected(id, const name[])
native skin_core_reset_selected(id)
native skin_core_apply_model(id)
native skin_core_is_ready(id)
native skin_core_can_access(id, const name[])
native skin_core_is_buyable(id, const name[])
native skin_core_get_flag(index)

#define PLUGIN "Skin Shop Menu"
#define VERSION "1.9-PREFIX"
#define AUTHOR "nb_team"

#define MAX_MODEL_LEN 32
#define ITEMS_PER_PAGE 7

#define MAX_PREFIXES 32
#define MAX_PREFIX_LEN 32

enum _:PrefixData {
    PrefixFlags,
    PrefixPriority,
    PrefixString[MAX_PREFIX_LEN]
}

new g_ePrefixes[MAX_PREFIXES][PrefixData]
new g_iPrefixCount

#define KEY_0 (1<<9)
#define KEY_1 (1<<0)
#define KEY_2 (1<<1)
#define KEY_3 (1<<2)
#define KEY_4 (1<<3)
#define KEY_5 (1<<4)
#define KEY_6 (1<<5)
#define KEY_7 (1<<6)
#define KEY_8 (1<<7)
#define KEY_9 (1<<8)

new const MENU_SKIN_SHOP[] = "SkinShopMenu";

new g_szPending[MAX_PLAYERS+1][MAX_MODEL_LEN]
new g_iShopPage[33]
new g_szMainMenuCmd[64]
new g_pCvarEnable

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)
    
    register_clcmd("say /skinshop", "Cmd_Skin_Shop")
    register_clcmd("say_team /skinshop", "Cmd_Skin_Shop")
    register_clcmd("say /models", "Cmd_Skin_Shop")
    register_clcmd("say_team /models", "Cmd_Skin_Shop")
    
    register_menucmd(register_menuid(MENU_SKIN_SHOP), 1023, "ShopH")
    g_pCvarEnable = get_cvar_pointer("skin_core_enable")
    
    LoadMenuSystemConfig()
    LoadPrefixConfig()
}

/* ============================================
   ЧТЕНИЕ menuSystem.ini
   ============================================ */
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
                bInMainSection = bool:equal(szLine[1], "Главное меню")
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

/* ============================================
   ЧТЕНИЕ prefix_system.ini
   ============================================ */
public LoadPrefixConfig()
{
    g_iPrefixCount = 0
    
    new szPath[256]
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath))
    formatex(szPath, charsmax(szPath), "%s/prefix_system.ini", szPath)
    
    if(!file_exists(szPath)) return
    
    new f = fopen(szPath, "r")
    if(!f) return
    
    new szLine[256]
    new bool:bInPrefixSection = false
    
    while(!feof(f))
    {
        fgets(f, szLine, charsmax(szLine))
        trim(szLine)
        
        if(szLine[0] == EOS || szLine[0] == ';') continue
        
        if(szLine[0] == '[')
        {
            new close = contain(szLine, "]")
            if(close > 0)
            {
                szLine[close] = 0
                bInPrefixSection = bool:equal(szLine[1], "FLAG_PREFIXES")
            }
            else
            {
                bInPrefixSection = false
            }
            continue
        }
        
        if(!bInPrefixSection) continue
        
        new eq_pos = contain(szLine, "=")
        if(eq_pos > 0)
        {
            new szPriority[8]
            copy(szPriority, eq_pos, szLine)
            trim(szPriority)
            new priority = str_to_num(szPriority)
            
            new szRight[128]
            copy(szRight, charsmax(szRight), szLine[eq_pos + 1])
            trim(szRight)
            
            new pipe_pos = contain(szRight, "|")
            if(pipe_pos > 0)
            {
                new szFlags[16], szPrefix[MAX_PREFIX_LEN]
                
                copy(szFlags, pipe_pos, szRight)
                trim(szFlags)
                
                copy(szPrefix, charsmax(szPrefix), szRight[pipe_pos + 1])
                trim(szPrefix)
                remove_quotes(szPrefix)
                
                if(g_iPrefixCount < MAX_PREFIXES && szFlags[0] && szPrefix[0])
                {
                    g_ePrefixes[g_iPrefixCount][PrefixFlags] = read_flags(szFlags)
                    g_ePrefixes[g_iPrefixCount][PrefixPriority] = priority
                    copy(g_ePrefixes[g_iPrefixCount][PrefixString], charsmax(g_ePrefixes[][PrefixString]), szPrefix)
                    g_iPrefixCount++
                }
            }
        }
    }
    fclose(f)
}

GetSkinPrefix(skinFlag, output[], len)
{
    new best_priority = -1
    new best_idx = -1
    
    if(skinFlag == 0) {
        copy(output, len, "")
        return 0
    }
    
    for(new i = 0; i < g_iPrefixCount; i++)
    {
        if(skinFlag & g_ePrefixes[i][PrefixFlags])
        {
            if(g_ePrefixes[i][PrefixPriority] > best_priority)
            {
                best_priority = g_ePrefixes[i][PrefixPriority]
                best_idx = i
            }
        }
    }
    
    if(best_idx != -1)
    {
        copy(output, len, g_ePrefixes[best_idx][PrefixString])
    }
    else
    {
        copy(output, len, "[VIP]")
    }
    return 1
}

public client_disconnected(id)
{
    g_iShopPage[id] = 0
    g_szPending[id][0] = 0
}

public Cmd_Skin_Shop(id)
{
    if(!is_user_connected(id)) return PLUGIN_HANDLED
    if(!skin_core_is_ready(id)) {
        client_print_color(id, print_team_default, "^1[^3SHOP^1] Данные загружаются, подождите...")
        return PLUGIN_HANDLED
    }
    if(g_pCvarEnable && get_pcvar_num(g_pCvarEnable) == 0) {
        client_print_color(id, print_team_default, "^1[^3SHOP^1] Магазин скинов временно отключен администрацией.")
        return PLUGIN_HANDLED
    }
    g_iShopPage[id] = 0
    ShowShop(id, 0)
    return PLUGIN_HANDLED
}

public RefreshShop(id)
{
    if(is_user_connected(id)) ShowShop(id, g_iShopPage[id])
}

ShowShop(id, page)
{
    new pts = skin_core_get_points(id)
    new count = skin_core_get_count()
    
    new totalPages = (count + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE
    if (totalPages == 0) totalPages = 1
    
    new iStart = page * ITEMS_PER_PAGE
    new iEnd = iStart + ITEMS_PER_PAGE
    if (iEnd > count) iEnd = count
    
    new szMenu[2048]
    new len = 0
    new keys = KEY_0
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\yМеню моделей \r[%d очков] \y(%d/%d)^n^n", pts, page + 1, totalPages)
    
    if (page == 0) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r1. \wСброс модели^n")
        keys |= KEY_1
    }
    
    new name[MAX_MODEL_LEN], price, teams, status[48]
    new displayKey = (page == 0) ? 1 : 0
    
    for(new i = iStart; i < iEnd; i++) {
        if (displayKey >= ITEMS_PER_PAGE) break;
        
        skin_core_get_info(i, name, charsmax(name), price, teams)
        
        new bBuyable = skin_core_is_buyable(id, name)
        new bOwned = skin_core_is_owned(id, name)
        new skinFlag = skin_core_get_flag(i)
        
        if(!bBuyable && !bOwned) {
            // Скин не продается и не куплен
            len += formatex(szMenu[len], charsmax(szMenu) - len, "\d%d. %s^n", displayKey + 1, name)
        } else {
            if(!skin_core_can_access(id, name)) {
                // Нет доступа (нет флага) - показываем префикс
                new szPrefix[MAX_PREFIX_LEN]
                GetSkinPrefix(skinFlag, szPrefix, charsmax(szPrefix))
                formatex(status, charsmax(status), " \r%s", szPrefix)
            } else if(!bOwned) {
                // Доступ есть, но не куплен
                if(skinFlag > 0) {
                    // ИСПРАВЛЕНО: VIP-скин, ничего не пишем, просто название
                    formatex(status, charsmax(status), "")
                } else {
                    // Обычный скин за очки
                    formatex(status, charsmax(status), " \r%d очков", price)
                }
            } else {
                // ИСПРАВЛЕНО: Скин уже куплен/взят - ничего не пишем, просто название
                formatex(status, charsmax(status), "")
            }
            
            len += formatex(szMenu[len], charsmax(szMenu) - len, "\r%d. \w%s%s^n", displayKey + 1, name, status)
            keys |= (1 << displayKey)
        }
        displayKey++
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n")
    
    if (page == 0) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r8. \wНазад^n")
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r8. \wНазад^n")
        keys |= KEY_8
    }
    keys |= KEY_8
    
    new hasNextPage = (iEnd < count)
    if (hasNextPage) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r9. \wДалее^n")
        keys |= KEY_9
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\d9. Далее^n")
    }
    
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r0. \wВыход")
    show_menu(id, keys, szMenu, -1, MENU_SKIN_SHOP)
}

public ShopH(id, key)
{
    if(!is_user_connected(id)) return PLUGIN_HANDLED
    
    if (key == 9) {
        show_menu(id, 0, "^n", 1, MENU_SKIN_SHOP)
        return PLUGIN_HANDLED
    }
    if (key == 8) {
        new count = skin_core_get_count()
        new iEnd = (g_iShopPage[id] + 1) * ITEMS_PER_PAGE
        if (iEnd < count) {
            g_iShopPage[id]++
            ShowShop(id, g_iShopPage[id])
        }
        return PLUGIN_HANDLED
    }
    if (key == 7) {
        if (g_iShopPage[id] > 0) {
            g_iShopPage[id]--
            ShowShop(id, g_iShopPage[id])
        } else {
            client_cmd(id, g_szMainMenuCmd)
        }
        return PLUGIN_HANDLED
    }
    
    new count = skin_core_get_count()
    new isReset = (g_iShopPage[id] == 0 && key == 0)
    
    if (isReset) {
        skin_core_reset_selected(id)
        skin_core_apply_model(id)
        client_print_color(id, print_team_default, "^4[SHOP]^1 Скин сброшен")
        set_task(0.1, "RefreshShop", id)
        return PLUGIN_HANDLED
    }
    
    new itemIndex = (g_iShopPage[id] * ITEMS_PER_PAGE) + (key - (g_iShopPage[id] == 0 ? 1 : 0))
    if (itemIndex < 0 || itemIndex >= count) return PLUGIN_HANDLED
    
    new name[MAX_MODEL_LEN], price, teams
    skin_core_get_info(itemIndex, name, charsmax(name), price, teams)
    
    if(!skin_core_is_buyable(id, name) && !skin_core_is_owned(id, name)) {
        return PLUGIN_HANDLED
    }
    
    if(!skin_core_can_access(id, name)) {
        new skinFlag = skin_core_get_flag(itemIndex)
        new szPrefix[MAX_PREFIX_LEN]
        GetSkinPrefix(skinFlag, szPrefix, charsmax(szPrefix))
        client_print_color(id, print_team_default, "^1[^3SHOP^1] Этот скин доступен только ^3%s^1!", szPrefix)
        set_task(0.1, "RefreshShop", id)
        return PLUGIN_HANDLED
    }
    
    // Если скин уже куплен - просто применяем
    if(skin_core_is_owned(id, name)) {
        skin_core_set_selected(id, name)
        if(is_user_alive(id)) {
            skin_core_apply_model(id)
            client_print_color(id, print_team_default, "^4[SHOP]^2 Применено: ^3%s^1", name)
        } else {
            client_print_color(id, print_team_default, "^1[^3SHOP^1] Вы мертвы! Скин применится в следующем раунде.")
        }
        set_task(0.1, "RefreshShop", id)
        return PLUGIN_HANDLED
    }
    
    // ИСПРАВЛЕНО: Если это VIP-скин (есть флаг) и игрок имеет к нему доступ - выдаем мгновенно без меню
    new skinFlag = skin_core_get_flag(itemIndex)
    if(skinFlag > 0) {
        if(skin_core_buy_skin(id, name)) { // Ядро сделает его бесплатным
            skin_core_set_selected(id, name)
            if(is_user_alive(id)) {
                skin_core_apply_model(id)
                client_print_color(id, print_team_default, "^4[SHOP]^2 Получен и применен: ^3%s^1!", name)
            } else {
                client_print_color(id, print_team_default, "^4[SHOP]^2 Получен: ^3%s^1! Применится при возрождении.", name)
            }
        } else {
            client_print_color(id, print_team_default, "^1[^3SHOP^1] Ошибка получения скина.")
        }
        set_task(0.1, "RefreshShop", id)
        return PLUGIN_HANDLED
    }
    
    // Для обычных скинов - проверяем баланс и показываем меню подтверждения
    new pts = skin_core_get_points(id)
    if (pts < price) {
        client_print_color(id, print_team_default, "^1[^3SHOP^1] Нужно ^3%d^1, у вас ^3%d^1", price, pts)
        set_task(0.1, "RefreshShop", id)
        return PLUGIN_HANDLED
    }
    
    copy(g_szPending[id], MAX_MODEL_LEN-1, name)
    ShowConfirmMenu(id, price)
    return PLUGIN_HANDLED
}

ShowConfirmMenu(id, price)
{
    new szMenu[256]
    formatex(szMenu, charsmax(szMenu), "\yПодтверждение покупки^n^n\wКупить \y%s \wза \r%d \wочков?", g_szPending[id], price)
    new menu = menu_create(szMenu, "ConfH")
    menu_additem(menu, "\gДа, купить", "1", 0)
    menu_additem(menu, "\rНет, отмена", "0", 0)
    menu_setprop(menu, MPROP_BACKNAME, "Назад")
    menu_setprop(menu, MPROP_NEXTNAME, "Далее")
    menu_setprop(menu, MPROP_EXITNAME, "Выход")
    menu_display(id, menu, 0)
}

public ConfH(id, menu, item)
{
    if(!is_user_connected(id)) { menu_destroy(menu); return PLUGIN_HANDLED; }
    if(item == MENU_EXIT) { menu_destroy(menu); set_task(0.1, "RefreshShop", id); return PLUGIN_HANDLED; }
    
    new data[6], name[32], access, callback
    menu_item_getinfo(menu, item, access, data, 5, name, 31, callback)
    
    if(equal(data, "1")) {
        if(g_szPending[id][0] != 0) {
            if(skin_core_buy_skin(id, g_szPending[id])) {
                skin_core_set_selected(id, g_szPending[id])
                if(is_user_alive(id)) {
                    skin_core_apply_model(id)
                    client_print_color(id, print_team_default, "^4[SHOP]^2 Успешно куплено и применено: ^3%s^1!", g_szPending[id])
                } else {
                    client_print_color(id, print_team_default, "^4[SHOP]^2 Успешно куплено: ^3%s^1! Применится при возрождении.", g_szPending[id])
                }
            } else {
                client_print_color(id, print_team_default, "^1[^3SHOP^1] Не удалось купить скин. Проверьте баланс.")
            }
        }
    }
    g_szPending[id][0] = 0
    menu_destroy(menu)
    set_task(0.1, "RefreshShop", id)
    return PLUGIN_HANDLED
}