#include <amxmodx>
#include <reapi>
#include <engine>

new pFallSpeed = 300

new bool:g_is_alive[33]
new Float:g_flOldGravity[33] // Переменная для сохранения оригинальной гравитации

public plugin_init()
{
    register_plugin("Parachute for ALL [ReAPI]", "3.1", "Leo_[BH] & nb_team")

    RegisterHookChain(RG_CBasePlayer_PreThink, "RG_client_PreThink");
    
    RegisterHookChain(RG_CBasePlayer_Killed, "RG_Player_Killed", 0);
    RegisterHookChain(RG_CBasePlayer_Spawn, "RG_Spawn_Post", 1);
}

public RG_client_PreThink(id)
{
    if(!g_is_alive[id]) return;

    new Float:fallspeed = pFallSpeed * -1.0

    new button = get_entvar(id, EntVars:var_button);
    new oldbutton = get_entvar(id, EntVars:var_oldbuttons);
    new Float:flCurrentGrav = get_entvar(id, EntVars:var_gravity);

    // Если игрок застрял с гравитацией парашюта (например, после спавна), восстанавливаем сохраненную
    if (flCurrentGrav == 0.1 && !(button & IN_USE)) {
        new Float:flRestore = (g_flOldGravity[id] <= 0.0) ? 1.0 : g_flOldGravity[id];
        set_entvar(id, EntVars:var_gravity, flRestore);
    }

    if (button & IN_USE) 
    {
        new Float:velocity[3]
        entity_get_vector(id, EV_VEC_velocity, velocity)

        if (velocity[2] < 0.0) 
        {
            // Сохраняем оригинальную гравитацию, если парашют только раскрывается
            if (flCurrentGrav != 0.1) {
                g_flOldGravity[id] = (flCurrentGrav == 0.0) ? 1.0 : flCurrentGrav;
                set_entvar(id, EntVars:var_gravity, 0.1)
            }

            // Анимации падения
            entity_set_int(id, EV_INT_sequence, 3)
            entity_set_int(id, EV_INT_gaitsequence, 1)
            entity_set_float(id, EV_FL_frame, 1.0)
            entity_set_float(id, EV_FL_framerate, 1.0)

            velocity[2] = (velocity[2] + 40.0 < fallspeed) ? velocity[2] + 40.0 : fallspeed
            entity_set_vector(id, EV_VEC_velocity, velocity)
        }
        else if (flCurrentGrav == 0.1) {
            // Если игрок использует USE, но уже не падает (стоит на земле)
            new Float:flRestore = (g_flOldGravity[id] <= 0.0) ? 1.0 : g_flOldGravity[id];
            set_entvar(id, EntVars:var_gravity, flRestore);
        }
    }
    else if ((oldbutton & IN_USE) && flCurrentGrav == 0.1) 
    {
        // Игрок отпустил кнопку USE - возвращаем сохраненную гравитацию
        new Float:flRestore = (g_flOldGravity[id] <= 0.0) ? 1.0 : g_flOldGravity[id];
        set_entvar(id, EntVars:var_gravity, flRestore);
    }
}

public RG_Spawn_Post(id)
{
    if(is_user_alive(id))
    {
        g_is_alive[id] = true
        // Сбрасываем сохраненную гравитацию при возрождении
        g_flOldGravity[id] = 1.0
    }
}

public RG_Player_Killed(victim, attacker)
{
    g_is_alive[victim] = false
}

public client_disconnect(id)
{
    g_is_alive[id] = false
}