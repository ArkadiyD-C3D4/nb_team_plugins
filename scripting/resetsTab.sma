#include <amxmodx>
#include <fun>
#include <fakemeta>

#define PLUGIN "Reset Score"
#define VERSION "1.1"
#define AUTHOR "nb_team"

// Смещение (offset) для получения и изменения количества смертей игрока
#define OFFSET_DEATHS 444

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    
    // Регистрация команд в чате
    register_clcmd("say /rs", "cmd_resetscore")
    register_clcmd("say_team /rs", "cmd_resetscore")
    register_clcmd("say !rs", "cmd_resetscore")
    register_clcmd("say_team !rs", "cmd_resetscore")
}

public cmd_resetscore(id) {
    if (!is_user_connected(id))
        return PLUGIN_HANDLED

    // Обнуление фрагов через модуль fun
    set_user_frags(id, 0)
    
    // Обнуление смертей через модуль fakemeta (pdata)
    set_pdata_int(id, OFFSET_DEATHS, 0)

    // Принудительное мгновенное обновление таблицы TAB для всех
    message_begin(MSG_BROADCAST, get_user_msgid("ScoreInfo"))
    write_byte(id)
    write_short(0) // Фраги
    write_short(0) // Смерти
    write_short(0) // Класс
    write_short(get_user_team(id))
    message_end()

    // Цветное уведомление игроку в чат
    client_print_color(id, print_team_default, "^4[RS] ^1Вы успешно ^3сбросили ^1свой счет!")
    
    return PLUGIN_HANDLED
}
