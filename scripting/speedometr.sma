#include <amxmodx>
#include <reapi>

new bool:g_bPlayerShowSpeed[MAX_PLAYERS + 1];
new g_iHudSyncObj;

public plugin_init() {
    register_plugin("ReAPI Speedometer", "1.3", "nb_team");
    register_clcmd("amx_speed", "Cmd_ToggleSpeed");
    register_clcmd("say /speed", "Cmd_ToggleSpeed");
    g_iHudSyncObj = CreateHudSyncObj();
}

public client_putinserver(id) {
    g_bPlayerShowSpeed[id] = false;
}

public client_disconnect(id) {
    g_bPlayerShowSpeed[id] = false;
}

// === НОВАЯ ФУНКЦИЯ ДЛЯ МЕНЮ ===
public GetSpeedometerStatus(id) {
    if (!is_user_connected(id))
        return 0;
    return g_bPlayerShowSpeed[id] ? 1 : 0;
}
// ================================

public Cmd_ToggleSpeed(id) {
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    g_bPlayerShowSpeed[id] = !g_bPlayerShowSpeed[id];

    client_print(id, print_chat, "[Speedometer] Спидометр: %s", 
        g_bPlayerShowSpeed[id] ? "ВКЛЮЧЕН" : "ВЫКЛЮЧЕН");

    if (!g_bPlayerShowSpeed[id]) {
        ClearSyncHud(id, g_iHudSyncObj);
    }
    return PLUGIN_HANDLED;
}

public plugin_cfg() {
    set_task(0.1, "Task_UpdateSpeed", _, _, _, "b");
}

public Task_UpdateSpeed() {
    new Float:vecVelocity[3];
    new Float:flSpeed;
    new szMessage[64];

    for (new id = 1; id <= MaxClients; id++) {
        if (!is_user_alive(id) || !g_bPlayerShowSpeed[id]) continue;

        get_entvar(id, var_velocity, vecVelocity);
        flSpeed = floatsqroot(vecVelocity[0] * vecVelocity[0] + vecVelocity[1] * vecVelocity[1]);
        formatex(szMessage, charsmax(szMessage), "Скорость: %.0f u/s", flSpeed);

        set_hudmessage(0, 255, 0, -1.0, 0.80, 0, 0.0, 0.15, 0.0, 0.0);
        ShowSyncHudMsg(id, g_iHudSyncObj, szMessage);
    }
}