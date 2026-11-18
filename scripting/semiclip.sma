#include <amxmodx>
#include <fakemeta>

#define SEMICLIP_DISTANCE_SQ 19600.0 // Квадрат дистанции (140 * 140). Дистанция, на которой начинается прозрачность.

new g_pSemiclipEnabled;

public plugin_init()
{
    register_plugin("Team Semiclip", "1.1", "nb_team");

    // Включена ли функция (1 - вкл, 0 - выкл)
    g_pSemiclipEnabled = register_cvar("amx_semiclip", "1");

    // Перехватываем данные, отправляемые клиентам. 1 в конце означает POST (выполняется после движка)
    register_forward(FM_AddToFullPack, "Fwd_AddToFullPack", 1);
}

public Fwd_AddToFullPack(es_handle, e, ent, host, hostflags, player, pSet)
{
    // Если плагин выключен, или это не игрок
    if (!get_pcvar_num(g_pSemiclipEnabled) || !player)
        return FMRES_IGNORED;

    // Если игрок смотрит сам на себя, или кто-то из них мертв/не в игре
    if (host == ent || !is_user_alive(host) || !is_user_alive(ent))
        return FMRES_IGNORED;

    // Проверка: в одной ли команде игроки? (1 - T, 2 - CT)
    if (get_user_team(host) != get_user_team(ent))
        return FMRES_IGNORED;

    // Получаем координаты обоих игроков
    static Float:host_origin[3], Float:ent_origin[3];
    pev(host, pev_origin, host_origin);
    pev(ent, pev_origin, ent_origin);

    // Быстрая проверка дистанции без вычисления корня (для оптимизации)
    static Float:diff_x, Float:diff_y, Float:diff_z;
    diff_x = host_origin[0] - ent_origin[0];
    diff_y = host_origin[1] - ent_origin[1];
    diff_z = host_origin[2] - ent_origin[2];

    // Если игроки находятся достаточно близко, чтобы столкнуться
    if ((diff_x * diff_x) + (diff_y * diff_y) + (diff_z * diff_z) < SEMICLIP_DISTANCE_SQ)
    {
        // Убираем физическую блокировку на стороне клиента
        set_es(es_handle, ES_Solid, SOLID_NOT);

        // Делаем игрока полупрозрачным (kRenderTransAlpha работает корректнее, чем Texture)
        set_es(es_handle, ES_RenderMode, kRenderTransAlpha);
        set_es(es_handle, ES_RenderAmt, 85.0); // Прозрачность: 0 - невидимый, 255 - полностью видимый
    }

    return FMRES_IGNORED;
}