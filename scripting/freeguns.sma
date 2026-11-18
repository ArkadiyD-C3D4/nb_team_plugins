#include <amxmodx>
#include <reapi>

#define PLUGIN "Respawn Weapon Menu + Armor & Nades"
#define VERSION "1.1"
#define AUTHOR "nb_team"

new g_iMenu[33];

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    RegisterHookChain(RG_CBasePlayer_Spawn, "player_spawn_post", 1);
    RegisterHookChain(RG_CBasePlayer_Killed, "player_killed", 1);
}

public player_spawn_post(id)
{
    if (!is_user_alive(id))
        return;

    // Закрываем старое меню, если висело
    if (g_iMenu[id] != 0)
    {
        menu_destroy(g_iMenu[id]);
        g_iMenu[id] = 0;
    }

    // Полная очистка инвентаря
    rg_remove_all_items(id);

    // 1. Нож
    rg_give_item(id, "weapon_knife", GT_APPEND);

    // 2. Desert Eagle с полным боекомплектом
    new deagleEnt = rg_give_item(id, "weapon_deagle", GT_APPEND);
    if (deagleEnt > 0)
    {
        new iMaxClip = rg_get_iteminfo(deagleEnt, ItemInfo_iMaxClip);
        set_member(deagleEnt, m_Weapon_iClip, iMaxClip);
        new iMaxBPAmmo = rg_get_iteminfo(deagleEnt, ItemInfo_iMaxAmmo1);
        rg_set_user_bpammo(id, WEAPON_DEAGLE, iMaxBPAmmo);
    }

    // 3. Броня 2-го уровня (бронежилет + шлем, 100 единиц)
    rg_set_user_armor(id, 100, ARMOR_VESTHELM);

    // 4. Одна HE-граната
    new heEnt = rg_give_item(id, "weapon_hegrenade", GT_APPEND);
    if (heEnt > 0)
    {
        // У HE нет магазина, но bpammo = 1 (максимум одна)
        rg_set_user_bpammo(id, WEAPON_HEGRENADE, 1);
    }

    // 5. Две флеш-гранаты (одна в руке, вторая в запасе)
    new flashEnt = rg_give_item(id, "weapon_flashbang", GT_APPEND);
    if (flashEnt > 0)
    {
        // Ставим запасные патроны: 2 (максимум для флешек)
        rg_set_user_bpammo(id, WEAPON_FLASHBANG, 2);
        // В руке автоматически будет 1 флешка, вторая в запасе
    }

    // 6. Меню выбора основной винтовки
    new menu = menu_create("Выбери оружие:", "menu_handler");

    menu_additem(menu, "M4A4", "m4a1", 0);
    menu_additem(menu, "AK47", "ak47", 0);
    menu_additem(menu, "AWP", "awp", 0);

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);

    g_iMenu[id] = menu;
}

public menu_handler(id, menu, item)
{
    if (!is_user_alive(id))
    {
        menu_destroy(menu);
        g_iMenu[id] = 0;
        return PLUGIN_HANDLED;
    }

    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        g_iMenu[id] = 0;
        return PLUGIN_HANDLED;
    }

    new szKey[6], szName[64], access, callback;
    menu_item_getinfo(menu, item, access, szKey, charsmax(szKey), szName, charsmax(szName), callback);

    new WeaponIdType:weaponId;
    new weapName[32];

    if (equal(szKey, "m4a1"))
    {
        weaponId = WEAPON_M4A1;
        copy(weapName, charsmax(weapName), "weapon_m4a1");
    }
    else if (equal(szKey, "ak47"))
    {
        weaponId = WEAPON_AK47;
        copy(weapName, charsmax(weapName), "weapon_ak47");
    }
    else if (equal(szKey, "awp"))
    {
        weaponId = WEAPON_AWP;
        copy(weapName, charsmax(weapName), "weapon_awp");
    }

    new weaponEnt = rg_give_item(id, weapName, GT_APPEND);
    if (weaponEnt > 0)
    {
        new iMaxClip = rg_get_iteminfo(weaponEnt, ItemInfo_iMaxClip);
        set_member(weaponEnt, m_Weapon_iClip, iMaxClip);
        new iMaxBPAmmo = rg_get_iteminfo(weaponEnt, ItemInfo_iMaxAmmo1);
        rg_set_user_bpammo(id, weaponId, iMaxBPAmmo);
    }

    menu_destroy(menu);
    g_iMenu[id] = 0;
    return PLUGIN_HANDLED;
}

public player_killed(id)
{
    if (g_iMenu[id] != 0)
    {
        menu_destroy(g_iMenu[id]);
        g_iMenu[id] = 0;
    }
}

public client_disconnect(id)
{
    if (g_iMenu[id] != 0)
    {
        menu_destroy(g_iMenu[id]);
        g_iMenu[id] = 0;
    }
}