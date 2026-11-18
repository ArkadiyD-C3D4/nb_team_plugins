#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <hamsandwich>

#define PLUGIN "Graphics Settings"
#define VERSION "1.7_no_cstrike"
#define AUTHOR "nb_team"

enum {
    SETTING_WATER,
    SETTING_HANDS,
    SETTING_SPECTATORS,
    SETTING_TEAMMATES,
    SETTING_MAX
}

new g_bPlayerSetting[33][SETTING_MAX]
new g_iHudSyncObj

// Offset m_pActiveItem в CBasePlayer для CS 1.6 (стандартный)
#define OFFSET_ACTIVE_ITEM 373

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    
    register_clcmd("say /water",        "Cmd_ToggleWater")
    register_clcmd("say /hands",        "Cmd_ToggleHands")
    register_clcmd("say /specs",        "Cmd_ToggleSpectators")
    register_clcmd("say /spectators",   "Cmd_ToggleSpectators")
    register_clcmd("say /team",         "Cmd_ToggleTeammates")
    
    register_forward(FM_PlayerPreThink, "Fwd_PlayerPreThink")
    register_forward(FM_AddToFullPack,  "Fwd_AddToFullPack", 1)
    
    g_iHudSyncObj = CreateHudSyncObj()
    set_task(1.0, "Task_ShowSpectators", _, _, _, "b")
}

public client_putinserver(id) {
    for (new i = 0; i < SETTING_MAX; i++)
        g_bPlayerSetting[id][i] = 1
}

/* ===== PUBLIC для menuSystem (callfunc) ===== */
public GetWaterSetting(id) {
    if (!is_user_connected(id)) return 0
    return g_bPlayerSetting[id][SETTING_WATER]
}

public GetHandsSetting(id) {
    if (!is_user_connected(id)) return 0
    return g_bPlayerSetting[id][SETTING_HANDS]
}

public GetSpectatorsSetting(id) {
    if (!is_user_connected(id)) return 0
    return g_bPlayerSetting[id][SETTING_SPECTATORS]
}

public GetTeammatesSetting(id) {
    if (!is_user_connected(id)) return 0
    return g_bPlayerSetting[id][SETTING_TEAMMATES]
}

/* ===== КОМАНДЫ ===== */
public Cmd_ToggleWater(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED
    g_bPlayerSetting[id][SETTING_WATER] = !g_bPlayerSetting[id][SETTING_WATER]
    client_cmd(id, "r_drawwater %d", g_bPlayerSetting[id][SETTING_WATER])
    client_print(id, print_chat, "[Графика] Вода: %s", g_bPlayerSetting[id][SETTING_WATER] ? "ВКЛ" : "ВЫКЛ")
    return PLUGIN_HANDLED
}

public Cmd_ToggleHands(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED
    g_bPlayerSetting[id][SETTING_HANDS] = !g_bPlayerSetting[id][SETTING_HANDS]
    
    if (g_bPlayerSetting[id][SETTING_HANDS]) {
        // ВКЛ руки — серверно вызываем Deploy текущего оружия
        new weaponEnt = get_pdata_cbase(id, OFFSET_ACTIVE_ITEM)
        if (pev_valid(weaponEnt)) {
            ExecuteHamB(Ham_Item_Deploy, weaponEnt)
        }
    }
    // Если ВЫКЛ — PreThink сам обнулит pev_viewmodel2 каждый кадр
    
    client_print(id, print_chat, "[Графика] Руки: %s", g_bPlayerSetting[id][SETTING_HANDS] ? "ВКЛ" : "ВЫКЛ")
    return PLUGIN_HANDLED
}

public Cmd_ToggleSpectators(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED
    g_bPlayerSetting[id][SETTING_SPECTATORS] = !g_bPlayerSetting[id][SETTING_SPECTATORS]
    client_cmd(id, "cl_speclist %d", g_bPlayerSetting[id][SETTING_SPECTATORS])
    client_print(id, print_chat, "[Графика] Наблюдатели: %s", g_bPlayerSetting[id][SETTING_SPECTATORS] ? "ВКЛ" : "ВЫКЛ")
    return PLUGIN_HANDLED
}

public Cmd_ToggleTeammates(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED
    g_bPlayerSetting[id][SETTING_TEAMMATES] = !g_bPlayerSetting[id][SETTING_TEAMMATES]
    client_print(id, print_chat, "[Графика] Тимейты: %s", g_bPlayerSetting[id][SETTING_TEAMMATES] ? "ВКЛ" : "ВЫКЛ")
    return PLUGIN_HANDLED
}

/* ===== БЕЗОПАСНЫЙ ФОРВАРД ДЛЯ РУК ===== */
public Fwd_PlayerPreThink(id) {
    if (!is_user_alive(id)) return FMRES_IGNORED
    
    if (!g_bPlayerSetting[id][SETTING_HANDS]) {
        set_pev(id, pev_viewmodel2, 0)
    }
    
    return FMRES_IGNORED
}

/* ===== ТИМЕЙТЫ ===== */
public Fwd_AddToFullPack(es, e, ent, host, hostflags, player, pSet) {
    if (!player) return FMRES_IGNORED
    if (ent == host) return FMRES_IGNORED
    if (!is_user_alive(host)) return FMRES_IGNORED
    
    if (g_bPlayerSetting[host][SETTING_TEAMMATES])
        return FMRES_IGNORED
    
    if (!pev_valid(ent)) return FMRES_IGNORED
    
    new hostTeam = get_user_team(host)
    new entTeam = get_user_team(ent)
    
    if (hostTeam != 0 && hostTeam == entTeam) {
        set_es(es, ES_ModelIndex, 0)
        set_es(es, ES_RenderMode, kRenderTransTexture)
        set_es(es, ES_RenderAmt, 0)
        return FMRES_HANDLED
    }
    
    return FMRES_IGNORED
}

/* ===== СПИСОК НАБЛЮДАТЕЛЕЙ ===== */
public Task_ShowSpectators() {
    new szList[256], szName[32]
    new iMaxPlayers = get_maxplayers()
    
    for (new target = 1; target <= iMaxPlayers; target++) {
        if (!is_user_connected(target)) continue
        if (!g_bPlayerSetting[target][SETTING_SPECTATORS]) continue
        
        szList[0] = 0
        
        for (new spec = 1; spec <= iMaxPlayers; spec++) {
            if (!is_user_connected(spec)) continue
            if (spec == target) continue
            
            new iMode = get_entvar(spec, var_iuser1)
            if (iMode == 0 || iMode == 3) continue
            
            new iTarget = get_entvar(spec, var_iuser2)
            if (iTarget != target) continue
            
            get_user_name(spec, szName, charsmax(szName))
            if (szList[0]) add(szList, charsmax(szList), ", ")
            add(szList, charsmax(szList), szName)
        }
        
        if (szList[0]) {
            set_hudmessage(255, 255, 255, 0.78, 0.18, 0, 0.0, 1.1, 0.0, 0.0)
            ShowSyncHudMsg(target, g_iHudSyncObj, "Наблюдатели: %s", szList)
        } else {
            ClearSyncHud(target, g_iHudSyncObj)
        }
    }
}