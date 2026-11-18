#include <amxmodx>
#include <reapi>

#define PLUGIN_VERSION "2.9-SmartBalance"

// === НАСТРОЙКИ БАЛАНСА ===
#define MIN_PLAYERS_TO_BALANCE 4   // Минимальное количество игроков (КТ+ТТ) для работы автобаланса
#define ROUNDS_STREAK_TO_BALANCE 5 // Сколько раундов подряд должна побеждать команда, чтобы сработал баланс по скиллу
#define BALANCE_COOLDOWN_ROUNDS 3 // Кулдаун (в раундах) между балансировками
// =========================

new g_iRoundNum = 0;
new g_iWinStreak[2]; // 0 = TT, 1 = CT
new g_iLastBalancedRound = 0;
new g_msgScreenFade;

public plugin_init()
{
    register_plugin("Chat Team Changer (ReAPI)", PLUGIN_VERSION, "nb_team")

    // Кешируем сообщение для подсветки экрана
    g_msgScreenFade = get_user_msgid("ScreenFade")

    // Команды чата
    register_clcmd("say /ct", "cmd_ct")
    register_clcmd("say /tt", "cmd_t")
    register_clcmd("say /spec", "cmd_spec")
    register_clcmd("say /autoteam", "cmd_autoteam")

    // Блокировка стандартного меню выбора команды
    register_clcmd("jointeam", "cmd_join_team")

    // Стандартный отлов конца раунда (замена ReAPI хука, чтобы не было ошибок при компиляции)
    register_event("SendAudio", "OnRoundEnd", "a", "2=%!MRAD_terwin", "2=%!MRAD_ctwin", "2=%!MRAD_rounddraw")

    // Событие начала раунда (для баланса по количеству)
    register_event("HLTV", "Event_RoundStart", "a", "1=0", "2=0")
}

// ================= ХУКИ РАУНДОВ =================

public OnRoundEnd()
{
    new arg[32]
    read_argv(2, arg, charsmax(arg))
    
    if (containi(arg, "terwin") != -1)
    {
        g_iWinStreak[0]++; // TT победили
        g_iWinStreak[1] = 0; 
    } 
    else if (containi(arg, "ctwin") != -1)
    {
        g_iWinStreak[1]++; // CT победили
        g_iWinStreak[0] = 0;
    } 
    else 
    {
        // Ничья или рестарт - сбрасываем серии
        g_iWinStreak[0] = 0;
        g_iWinStreak[1] = 0;
    }
}

public Event_RoundStart()
{
    g_iRoundNum++;
    
    // Запускаем проверку баланса с задержкой в 1 секунду
    set_task(1.0, "CheckBalancing");
}

// ================= ЛОГИКА БАЛАНСА =================

public CheckBalancing()
{
    new t_count, ct_count;
    get_team_counts(t_count, ct_count);

    new total_players = t_count + ct_count;

    // Проверка на минимальный онлайн
    if (total_players < MIN_PLAYERS_TO_BALANCE)
        return;

    // Проверка кулдауна
    new bool:bCanBalance = (g_iRoundNum - g_iLastBalancedRound >= BALANCE_COOLDOWN_ROUNDS);

    // Баланс по количеству (Разница больше 1 человека)
    if (abs(t_count - ct_count) > 1)
    {
        if (!bCanBalance) return;

        if (t_count > ct_count) 
            MoveWorstPlayer(TEAM_TERRORIST, TEAM_CT);
        else 
            MoveWorstPlayer(TEAM_CT, TEAM_TERRORIST);

        g_iLastBalancedRound = g_iRoundNum;
        return; 
    }

    // Баланс по скиллу (Если кто-то доминирует)
    if (bCanBalance)
    {
        if (g_iWinStreak[0] >= ROUNDS_STREAK_TO_BALANCE) 
        {
            SwapPlayers(TEAM_TERRORIST, TEAM_CT);
            g_iLastBalancedRound = g_iRoundNum;
            g_iWinStreak[0] = 0;
        }
        else if (g_iWinStreak[1] >= ROUNDS_STREAK_TO_BALANCE) 
        {
            SwapPlayers(TEAM_CT, TEAM_TERRORIST);
            g_iLastBalancedRound = g_iRoundNum;
            g_iWinStreak[1] = 0;
        }
    }
}

// Перемещение слабейшего игрока (для баланса по кол-ву)
stock MoveWorstPlayer(TeamName:from_team, TeamName:to_team)
{
    new players[MAX_PLAYERS], pnum;
    get_players(players, pnum, "ch");

    new worst_id = 0;
    new Float:worst_score = 99999.0;

    for (new i = 0; i < pnum; i++)
    {
        new id = players[i];
        if (get_user_flags(id) & ADMIN_IMMUNITY) continue;
        if (get_member(id, m_iTeam) != from_team) continue;

        new Float:score = float(get_user_frags(id)) - float(get_user_deaths(id));
        if (score < worst_score) 
        {
            worst_score = score;
            worst_id = id;
        }
    }

    if (worst_id) 
    {
        change_player_team(worst_id, _:to_team, true);
    }
}

// Обмен сильного на слабого (для баланса по скиллу)
stock SwapPlayers(TeamName:strong_team, TeamName:weak_team)
{
    new players[MAX_PLAYERS], pnum;
    get_players(players, pnum, "ch");

    new best_id = 0, worst_id = 0;
    new Float:best_score = -99999.0;
    new Float:worst_score = 99999.0;

    for (new i = 0; i < pnum; i++)
    {
        new id = players[i];
        if (get_user_flags(id) & ADMIN_IMMUNITY) continue;

        new TeamName:team = get_member(id, m_iTeam);
        new Float:score = float(get_user_frags(id)) - float(get_user_deaths(id));

        if (team == strong_team && score > best_score) 
        {
            best_score = score;
            best_id = id;
        } 
        else if (team == weak_team && score < worst_score) 
        {
            worst_score = score;
            worst_id = id;
        }
    }

    // Меняем местами
    if (best_id && worst_id) 
    {
        change_player_team(best_id, _:weak_team, true);
        change_player_team(worst_id, _:strong_team, true);

        new name1[32], name2[32];
        get_user_name(best_id, name1, 31);
        get_user_name(worst_id, name2, 31);

        // Сообщение в чат как и просили
        client_print(0, print_chat, "[БАЛАНС] Сильного игрока %s меняют на слабого %s", name1, name2);
    } 
    else if (best_id) 
    {
        change_player_team(best_id, _:weak_team, true);
    }
}

// ================= БЛОКИРОВКА ВСТУПЛЕНИЯ В КОМАНДУ =================

public cmd_join_team(id)
{
    new arg[2];
    read_argv(1, arg, charsmax(arg));
    new team = str_to_num(arg);

    // 1 = TT, 2 = CT
    if (team == 1 || team == 2)
    {
        new t_count, ct_count;
        get_team_counts(t_count, ct_count);

        // Проверяем, не сломает ли переход баланс (разница будет > 1)
        if (team == 1 && (t_count + 1) - ct_count > 1) return PLUGIN_HANDLED;
        if (team == 2 && (ct_count + 1) - t_count > 1) return PLUGIN_HANDLED;
    }
    
    return PLUGIN_CONTINUE;
}

// ================= КОМАНДЫ ЧАТА =================

public cmd_ct(id)
{
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (get_member(id, m_iTeam) == TEAM_CT) return PLUGIN_HANDLED;

    new t_count, ct_count;
    get_team_counts(t_count, ct_count);

    // Блокировка перехода через чат-команду
    if ((ct_count + 1) - t_count > 1) return PLUGIN_HANDLED;

    change_player_team(id, _:TEAM_CT, false)
    return PLUGIN_HANDLED;
}

public cmd_t(id)
{
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (get_member(id, m_iTeam) == TEAM_TERRORIST) return PLUGIN_HANDLED;

    new t_count, ct_count;
    get_team_counts(t_count, ct_count);

    // Блокировка перехода через чат-команду
    if ((t_count + 1) - ct_count > 1) return PLUGIN_HANDLED;

    change_player_team(id, _:TEAM_TERRORIST, false)
    return PLUGIN_HANDLED;
}

public cmd_spec(id)
{
    if (!is_user_connected(id)) return PLUGIN_HANDLED;
    if (get_member(id, m_iTeam) == TEAM_SPECTATOR) return PLUGIN_HANDLED;

    change_player_team(id, _:TEAM_SPECTATOR, false)
    return PLUGIN_HANDLED;
}

public cmd_autoteam(id)
{
    if (!is_user_connected(id)) return PLUGIN_HANDLED;

    new t_count, ct_count
    get_team_counts(t_count, ct_count)

    new target_team
    if (t_count < ct_count)
        target_team = _:TEAM_TERRORIST
    else if (ct_count < t_count)
        target_team = _:TEAM_CT
    else
        target_team = _:TEAM_TERRORIST

    if (get_member(id, m_iTeam) == target_team)
        return PLUGIN_HANDLED;

    change_player_team(id, target_team, false)
    return PLUGIN_HANDLED;
}

// ================= СТОКИ =================

stock change_player_team(id, team, bool:bSkipEmptyCheck = false)
{
    new t_before, ct_before
    get_team_counts(t_before, ct_before)

    if (is_user_alive(id))
    {
        user_silentkill(id);
    }

    rg_set_user_team(id, TeamName:team, MODEL_AUTO, true);

    // Подсветка экрана в зависимости от команды (Уменьшенная длительность)
    if (team == _:TEAM_CT) 
    {
        // Синий цвет
        message_begin(MSG_ONE_UNRELIABLE, g_msgScreenFade, _, id)
        write_short(1<<12)       // Длительность (1 секунда)
        write_short(1<<11)      // Задержка затухания (0.5 секунды)
        write_short(0x0000)     // Флаги
        write_byte(0)          // R
        write_byte(0)          // G
        write_byte(255)        // B
        write_byte(150)        // Прозрачность
        message_end()
    } 
    else if (team == _:TEAM_TERRORIST) 
    {
        // Красный цвет
        message_begin(MSG_ONE_UNRELIABLE, g_msgScreenFade, _, id)
        write_short(1<<12)       // Длительность (1 секунда)
        write_short(1<<11)      // Задержка затухания (0.5 секунды)
        write_short(0x0000)
        write_byte(255)
        write_byte(0)
        write_byte(0)
        write_byte(150)
        message_end()
    }

    // Принудительный рестарт раунда, если игрок первый на сервере
    if (!bSkipEmptyCheck && (team == _:TEAM_CT || team == _:TEAM_TERRORIST))
    {
        if ((t_before == 0 && ct_before == 0) || (team == _:TEAM_CT && ct_before == 0) || (team == _:TEAM_TERRORIST && t_before == 0))
        {
            if (get_member_game(m_iRoundWinStatus) == WINSTATUS_NONE)
            {
                rg_round_end(2.0, WINSTATUS_NONE, ROUND_GAME_COMMENCE, "Game Commence", .trigger = true);
            }
        }
    }
}

stock get_team_counts(&t_count, &ct_count)
{
    t_count = 0
    ct_count = 0

    new players[MAX_PLAYERS], pnum
    get_players(players, pnum, "ch")

    for (new i = 0; i < pnum; i++)
    {
        new player = players[i]
        switch (get_member(player, m_iTeam))
        {
            case TEAM_TERRORIST: t_count++
            case TEAM_CT: ct_count++
        }
    }
}