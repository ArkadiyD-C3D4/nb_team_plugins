#include <amxmodx>
#include <amxmisc>
#include <fakemeta>

#define PLUGIN "Admin Screamer Instant"
#define VERSION "2.1"
#define AUTHOR "nb_team"

new const SCARE_SOUND[] = "misc/scare.wav"
new const SCARE_SPRITE[] = "sprites/scare.spr"

// ========================================================
// НАСТРОЙКИ СПРАЙТА:
const Float:SPRITE_DISTANCE = 80.0 
const Float:SPRITE_SCALE = 1.1      
const MAX_FRAMES = 28               
const Float:ANIM_SPEED = 2.0       
// ========================================================

new bool:g_bIsScared[33]
new Float:g_flLockedAngles[33][3]
new g_iScareEnt[33]
new g_msgSetFOV

#define TASK_SCARE_SHAKE   3000
#define TASK_STOP_SCARE    4000

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    
    register_concmd("amx_screamer", "cmd_screamer", ADMIN_LEVEL_H, " - открыть меню скримера")
    
    register_forward(FM_PlayerPreThink, "fwd_PreThink")
    register_forward(FM_AddToFullPack, "fwd_AddToFullPack", 1)
    
    g_msgSetFOV = get_user_msgid("SetFOV")
    
    // ПРАВИЛЬНЫЙ ВАРИАНТ:
    register_forward(FM_Think, "Fwd_ScareSpriteThink")
}

public plugin_precache() {
    precache_sound(SCARE_SOUND)
    precache_model(SCARE_SPRITE)
}

// Обработка команды админа
public cmd_screamer(id, level, cid) {
    if(!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED

    new arg[32]
    read_argv(1, arg, charsmax(arg))

    // Если админ не ввел аргумент - показываем меню
    if(arg[0] == EOS) {
        ShowScareMenu(id)
        return PLUGIN_HANDLED
    }

    // Если ввел @ALL - пугаем всех
    if(equali(arg, "@ALL")) {
        new players[32], pnum
        get_players(players, pnum, "c")
        for(new i = 0; i < pnum; i++) {
            TriggerScare(players[i])
        }
        client_print(id, print_chat, "[Скример] Вы мгновенно напугали всех игроков!")
        return PLUGIN_HANDLED
    }

    // Если ввел ник - пугаем конкретного игрока
    new player = cmd_target(id, arg, CMDTARGET_NO_BOTS)
    if(!player)
        return PLUGIN_HANDLED

    TriggerScare(player)
    
    new name[32]
    get_user_name(player, name, charsmax(name))
    client_print(id, print_chat, "[Скример] Вы мгновенно напугали %s!", name)

    return PLUGIN_HANDLED
}

// СОЗДАНИЕ МЕНЮ ИГРОКОВ
ShowScareMenu(id) {
    new menu = menu_create("\rВыберите жертву для скримера:", "MenuHandler")
    
    new players[32], pnum, info[3], name[32]
    get_players(players, pnum, "c") // Только живые
    
    for(new i = 0; i < pnum; i++) {
        get_user_name(players[i], name, charsmax(name))
        num_to_str(players[i], info, charsmax(info)) // Сохраняем ID игрока в инфо
        
        menu_additem(menu, name, info)
    }
    
    menu_setprop(menu, MPROP_EXITNAME, "Выход")
    menu_display(id, menu, 0)
}

// ОБРАБОТКА ВЫБОРА В МЕНЮ
public MenuHandler(id, menu, item) {
    if(item == MENU_EXIT) {
        menu_destroy(menu)
        return PLUGIN_HANDLED
    }
    
    new data[3], access, callback
    menu_item_getinfo(menu, item, access, data, charsmax(data), _, _, callback)
    
    new target = str_to_num(data)
    
    if(is_user_alive(target)) {
        TriggerScare(target)
        
        new name[32]
        get_user_name(target, name, charsmax(name))
        client_print(id, print_chat, "[Скример] Вы мгновенно напугали %s!", name)
    } else {
        client_print(id, print_chat, "[Скример] Игрок не найден или мертв.")
    }
    
    menu_destroy(menu)
    return PLUGIN_HANDLED
}

// МГНОВЕННЫЙ СКРИМЕР
TriggerScare(id) {
    if(!is_user_alive(id)) return

    // Очищаем старые задачи
    remove_task(id + TASK_SCARE_SHAKE)
    remove_task(id + TASK_STOP_SCARE)
    remove_task(id + 5000) // Очистка задачи спавна спрайта

    // Удаляем старый спрайт если был
    if(pev_valid(g_iScareEnt[id])) {
        engfunc(EngFunc_RemoveEntity, g_iScareEnt[id])
        g_iScareEnt[id] = 0
    }

    // 1. ВКЛЮЧАЕМ ЗАМОРОЗКУ И ПОВОРОТ В НЕБО (ПЕРВЫМ ДЕЛОМ!)
    g_bIsScared[id] = true
    new Float:up_angle[3]
    pev(id, pev_v_angle, up_angle)
    up_angle[0] = -89.0 // Смотреть максимально вверх
    up_angle[2] = 0.0
    g_flLockedAngles[id] = up_angle

    // Прячем оружие
    message_begin(MSG_ONE, get_user_msgid("HideWeapon"), _, id)
    write_byte(1<<5) 
    message_end()

    // 2. Звук (мгновенно)
      client_cmd(id, "spk %s", SCARE_SOUND)

    // 3. Резкая вспышка экрана (КРАСНОТА УМЕНЬШЕНА)
    message_begin(MSG_ONE, get_user_msgid("ScreenFade"), _, id)
    write_short((1<<12)*1) 
    write_short((1<<12)*1) 
    write_short(0x0001) 
    write_byte(150)     // Красный (было 200) - теперь более тусклый
    write_byte(0)
    write_byte(0)
    write_byte(80)      // Прозрачность (было 200, стало 80) - еле заметная красная пелена
    message_end()

    // 4. Бешеная тряска (мгновенно, каждые 0.2 сек, 12 раз)
    set_task(0.2, "ScareShake", id + TASK_SCARE_SHAKE, _, _, "a", 12)
    
    // 5. ОТКЛАДЫВАЕМ СПАВН СПРАЙТА НА 0.1 СЕКУНДЫ
    // Это дает камере время реально повернуться вверх, чтобы игрок увидел спрайт в небе
    set_task(0.1, "SpawnScareSprite", id + 5000)
    
    // 6. Снятие эффекта через 2.6 секунды (добавили 0.1 сек к старому времени)
    set_task(2.6, "StopScare", id + TASK_STOP_SCARE)
}

// ФУНКЦИЯ СПАВНА СПРАЙТА (Вызывается через 0.1 сек после начала)
// ФУНКЦИЯ СПАВНА СПРАЙТА
public SpawnScareSprite(taskid) {
    new id = taskid - 5000
    if(!is_user_alive(id) || !g_bIsScared[id]) return

    new Float:origin[3], Float:dir[3], Float:angles[3]
    pev(id, pev_origin, origin)
    angles = g_flLockedAngles[id]

    angle_vector(angles, ANGLEVECTOR_FORWARD, dir)
    origin[0] += dir[0] * SPRITE_DISTANCE
    origin[1] += dir[1] * SPRITE_DISTANCE
    origin[2] += dir[2] * SPRITE_DISTANCE

    new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "env_sprite"))
    if(pev_valid(ent)) {
        g_iScareEnt[id] = ent
        set_pev(ent, pev_classname, "scare_spr")
        set_pev(ent, pev_iuser1, 666)
        
        engfunc(EngFunc_SetModel, ent, SCARE_SPRITE)
        set_pev(ent, pev_origin, origin)
        
        new Float:fix_angles[3]
        fix_angles[0] = 0.0
        fix_angles[1] = 0.0
        fix_angles[2] = 180.0 
        set_pev(ent, pev_angles, fix_angles)
        
        set_pev(ent, pev_rendermode, kRenderNormal) 
        set_pev(ent, pev_renderamt, 255.0)
        
        set_pev(ent, pev_spawnflags, 1)
        set_pev(ent, pev_framerate, 15.0)
        set_pev(ent, pev_frame, 0.0)
        set_pev(ent, pev_animtime, get_gametime())
        
        dllfunc(DLLFunc_Spawn, ent)
        set_pev(ent, pev_scale, SPRITE_SCALE) 
        
        // ВКЛЮЧАЕМ "МЫШЛЕНИЕ" СПРАЙТА (запускаем анимацию)
        set_pev(ent, pev_nextthink, get_gametime() + 0.05)
    }
}

// ФУНКЦИЯ АНИМАЦИИ (ВЫЗЫВАЕТСЯ ДВИЖКОМ)
public Fwd_ScareSpriteThink(ent) {
    if(!pev_valid(ent)) return FMRES_IGNORED
    
    // Проверяем: если это НЕ наш спрайт — выходим, не трогаем другие объекты
    static classname[32]
    pev(ent, pev_classname, classname, charsmax(classname))
    if(!equal(classname, "scare_spr")) return FMRES_IGNORED
    
    new Float:cur_frame = pev(ent, pev_frame)
    cur_frame += 1.0 // Увеличиваем кадр на 1
    
    // Если дошли до конца (28 кадров) - зацикливаем
    if(cur_frame >= float(MAX_FRAMES)) {
        cur_frame = 0.0
    }
    
    set_pev(ent, pev_frame, cur_frame)
    set_pev(ent, pev_animtime, get_gametime()) 
    
    // Вызываем эту же функцию через 0.05 секунд (20 кадров в секунду)
    set_pev(ent, pev_nextthink, get_gametime() + 0.05)
    
    return FMRES_IGNORED
}

public ScareShake(taskid) {
    new id = taskid - TASK_SCARE_SHAKE
    if(!is_user_connected(id)) return

    message_begin(MSG_ONE, get_user_msgid("ScreenShake"), {0,0,0}, id)
    write_short(255 << 12)
    write_short(5 << 12)
    write_short(255 << 12)
    message_end()
}

public fwd_PreThink(id) {
    if(!is_user_alive(id)) return FMRES_IGNORED
    
    if(g_bIsScared[id]) {
        // Заморозка и удержание камеры в небе
        set_pev(id, pev_velocity, Float:{0.0, 0.0, 0.0})
        set_pev(id, pev_maxspeed, 0.0)
        set_pev(id, pev_v_angle, g_flLockedAngles[id])
        set_pev(id, pev_angles, g_flLockedAngles[id])
        set_pev(id, pev_fixangle, 1)
        set_pev(id, pev_button, 0)
        set_pev(id, pev_oldbuttons, 0)
        
        // БЛОК АНИМАЦИИ УБРАН ОТСЮДА
    }
    return FMRES_IGNORED
}

public fwd_AddToFullPack(es, e, ent, host, hostflags, player, pSet) {
    if(!pev_valid(ent)) return FMRES_IGNORED
    if(pev(ent, pev_iuser1) == 666) {
        if(ent != g_iScareEnt[host]) {
            set_es(es, ES_Effects, get_es(es, ES_Effects) | EF_NODRAW)
        }
    }
    return FMRES_IGNORED
}

public StopScare(taskid) {
    new id = taskid - TASK_STOP_SCARE
    g_bIsScared[id] = false
    
    // Останавливаем звук
    client_cmd(id, "stopsound")
    
    // Удаляем спрайт
    if(pev_valid(g_iScareEnt[id])) {
        engfunc(EngFunc_RemoveEntity, g_iScareEnt[id])
        g_iScareEnt[id] = 0
    }
    
    // Возвращаем оружие
    message_begin(MSG_ONE, get_user_msgid("HideWeapon"), _, id)
    write_byte(0) 
    message_end()

    // Полностью очищаем экран от эффектов
    message_begin(MSG_ONE, get_user_msgid("ScreenFade"), _, id)
    write_short((1<<12)*2)
    write_short(0)
    write_short(0x0001)
    write_byte(0)
    write_byte(0)
    write_byte(0)
    write_byte(0)
    message_end()

    // Возвращаем скорость
    set_pev(id, pev_maxspeed, 250.0)
}