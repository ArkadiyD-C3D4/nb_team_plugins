#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <engine>
#include <hamsandwich>
#include <colorchat>

// Нативы из магазина
native shop_register_item(const name[], cost, const command[]);
native points_get(id);
native points_set(id, amount);

// Нативы из HealthNade
#include <healthnade>

#define SHOP_ITEMS_COUNT 5

// Предметы магазина
new g_szShopItems[SHOP_ITEMS_COUNT][64] = {
    "Лечебная граната",
    "МегаДигл (120% урона)",
    "МегаГраната (120% урона)",
    "Ускорение",
    "Гравитация"
};

// Команды для вызова
new g_szShopCommands[SHOP_ITEMS_COUNT][32] = {
    "buy_healthnade",
    "buy_megadeagle",
    "buy_megahegrenade",
    "buy_speed",
    "buy_gravity"
};

// МАССИВ ЦЕН ДЛЯ КАЖДОГО ПРЕДМЕТА
new g_iShopCosts[SHOP_ITEMS_COUNT] = {
    3,    // 0: Цена Лечебной гранаты
    1,    // 1: Цена МегаДигла
    1,    // 2: Цена МегаГранаты
    1,    // 3: Цена Ускорения
    1     // 4: Цена Гравитации
};

// Бафы
new bool:g_bHasSpeed[33];
new bool:g_bHasGravity[33];
new bool:g_bMegaDeagle[33];
new bool:g_bMegaGrenade[33];

public plugin_init() {
    register_plugin("Shop: Extended", "1.5", "nb_team");

    register_clcmd("buy_megadeagle", "CmdBuyMegaDeagle");
    register_clcmd("buy_megahegrenade", "CmdBuyMegaGrenade");
    register_clcmd("buy_speed", "CmdBuySpeed");
    register_clcmd("buy_gravity", "CmdBuyGravity");
    register_clcmd("buy_healthnade", "CmdBuyHealthNade");

    register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");
    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");

    // Хук урона для МегаДигла и МегаГранаты
    RegisterHam(Ham_TakeDamage, "player", "Fwd_TakeDamage_Player", 0);

    set_task(0.1, "RegisterShopItems");
}

public RegisterShopItems() {
    for (new i = 0; i < SHOP_ITEMS_COUNT; i++) {
        if (shop_register_item(g_szShopItems[i], g_iShopCosts[i], g_szShopCommands[i]) == -1) {
            log_amx("[Shop] Ошибка регистрации товара: %s!", g_szShopItems[i]);
        }
    }
}

// Новый раунд — сброс всех бафов
public Event_NewRound() {
    for (new id = 1; id <= 32; id++) {
        if (!is_user_connected(id)) continue;

        if (g_bHasSpeed[id]) {
            entity_set_float(id, EV_FL_maxspeed, 250.0);
            g_bHasSpeed[id] = false;
        }
        if (g_bHasGravity[id]) {
            entity_set_float(id, EV_FL_gravity, 1.0);
            g_bHasGravity[id] = false;
        }
        g_bMegaDeagle[id] = false;
        g_bMegaGrenade[id] = false;
    }
}

public Event_CurWeapon(id) {
    if (!is_user_connected(id)) return;

    if (g_bHasSpeed[id]) {
        entity_set_float(id, EV_FL_maxspeed, 320.0);
    }
    if (g_bHasGravity[id]) {
        entity_set_float(id, EV_FL_gravity, 0.75);
    }
}

stock bool:HasHEGrenade(id) {
    new weapons[32], num;
    get_user_weapons(id, weapons, num);
    
    for (new i = 0; i < num; i++) {
        if (weapons[i] == CSW_HEGRENADE) {
            return true;
        }
    }
    return false;
}

// ================= ВЫДАЧА ПРЕДМЕТОВ =================

public CmdBuyMegaDeagle(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    rg_remove_item(id, "weapon_glock18", true);
    rg_remove_item(id, "weapon_usp", true);
    rg_remove_item(id, "weapon_p228", true);
    rg_remove_item(id, "weapon_deagle", true);
    rg_remove_item(id, "weapon_elite", true);
    rg_remove_item(id, "weapon_fiveseven", true);

    rg_give_item(id, "weapon_deagle", GT_APPEND);
    g_bMegaDeagle[id] = true;

    client_print_color(id, print_team_default, "^4[SHOP]^1 Вы купили ^3МегаДигл^1 с повышенным уроном!");
    return PLUGIN_HANDLED;
}

public CmdBuyMegaGrenade(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    // Если у игрока уже есть граната, возвращаем очки (индекс 2 в массиве)
    if (HasHEGrenade(id)) {
        client_print_color(id, print_team_default, "^4[SHOP]^1 У вас уже есть HE граната. Очки возвращены.");
        points_set(id, points_get(id) + g_iShopCosts[2]); 
        return PLUGIN_HANDLED;
    }

    rg_give_item(id, "weapon_hegrenade", GT_APPEND);
    g_bMegaGrenade[id] = true;

    client_print_color(id, print_team_default, "^4[SHOP]^1 Вы купили ^3МегаГранату^1 с повышенным уроном!");
    return PLUGIN_HANDLED;
}

public CmdBuySpeed(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    entity_set_float(id, EV_FL_maxspeed, 320.0);
    g_bHasSpeed[id] = true;

    client_print_color(id, print_team_default, "^4[SHOP]^1 Активировано ^3ускорение^1 (320 юнитов/сек) на 1 раунд!");
    return PLUGIN_HANDLED;
}

public CmdBuyGravity(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    entity_set_float(id, EV_FL_gravity, 0.75);
    g_bHasGravity[id] = true;

    client_print_color(id, print_team_default, "^4[SHOP]^1 Активирована ^3низкая гравитация^1 на 1 раунд!");
    return PLUGIN_HANDLED;
}

public CmdBuyHealthNade(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    // Если уже есть граната, возвращаем очки (индекс 0 в массиве)
    if (HealthNade_HasNade(id)) {
        client_print_color(id, print_team_default, "^4[SHOP]^1 У вас уже есть лечебная граната. Очки возвращены.");
        points_set(id, points_get(id) + g_iShopCosts[0]); 
        return PLUGIN_HANDLED;
    }

    new item = HealthNade_GiveNade(id, 1, 1);
    if (item == 0) {
        client_print_color(id, print_team_default, "^4[SHOP]^1 Не удалось выдать лечебную гранату. Очки возвращены.");
        points_set(id, points_get(id) + g_iShopCosts[0]); 
    }

    return PLUGIN_HANDLED;
}

// Перехват урона от МегаДигла и МегаГранаты
public Fwd_TakeDamage_Player(this, idinflictor, idattacker, Float:damage, damagebits) {
    if (!is_user_connected(idattacker) || this == idattacker) return HAM_IGNORED;

    if (g_bMegaDeagle[idattacker]) {
        new pActiveItem = get_member(idattacker, m_pActiveItem);
        if (pActiveItem && get_member(pActiveItem, m_iId) == WEAPON_DEAGLE) {
            SetHamParamFloat(4, damage * 1.2);
            return HAM_HANDLED;
        }
    }

    if (g_bMegaGrenade[idattacker]) {
        if (idinflictor > 0) {
            new classname[32];
            entity_get_string(idinflictor, EV_SZ_classname, classname, charsmax(classname));
            if (equal(classname, "grenade")) {
                SetHamParamFloat(4, damage * 1.2);
                return HAM_HANDLED;
            }
        }
    }

    return HAM_IGNORED;
}