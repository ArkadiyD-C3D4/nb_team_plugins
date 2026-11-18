#include <amxmodx>
#include <amxmisc>
#include <sqlx>

// Настройки времени
#define ONE_DAY_IN_SECONDS 86400
#define ONE_WEEK_IN_SECONDS 604800

// Флаг q (ADMIN_LEVEL_E)
#define TARGET_FLAG ADMIN_LEVEL_E

new Handle:g_SqlTuple;
new bool:g_DbConnected = false;

public plugin_init() {
    register_plugin("Test Privilege (1 day)", "1.3", "nb_team");

    // Команда для игроков
    register_clcmd("say /test", "Cmd_TestPrivilege");
    register_clcmd("say_team /test", "Cmd_TestPrivilege");

    // Команда для админов (выдача на 1 карту)
    register_concmd("amx_giveq", "Cmd_GiveMapFlag", ADMIN_LEVEL_H, "<name or #userid> - Выдать флаг q на карту");
}

public plugin_cfg() {
    new szHost[64], szUser[64], szPass[64], szDb[64];
    get_cvar_string("amx_sql_host", szHost, charsmax(szHost));
    get_cvar_string("amx_sql_user", szUser, charsmax(szUser));
    get_cvar_string("amx_sql_pass", szPass, charsmax(szPass));
    get_cvar_string("amx_sql_db", szDb, charsmax(szDb));

    g_SqlTuple = SQL_MakeDbTuple(szHost, szUser, szPass, szDb);

    // Пытаемся подключиться и создать таблицу
    TryConnectDb();
}

// Функция попытки подключения/создания таблицы
public TryConnectDb() {
    new szQuery[512];
    formatex(szQuery, charsmax(szQuery), "CREATE TABLE IF NOT EXISTS `test_privileges` (`authid` VARCHAR(64) NOT NULL, `claim_time` INT(10) NOT NULL, PRIMARY KEY (`authid`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
    
    SQL_ThreadQuery(g_SqlTuple, "Handle_TableCreate", szQuery);
}

public Handle_TableCreate(FailState, Handle:hQuery, error[], errcode, data[], datasize) {
    if (FailState == TQUERY_CONNECT_FAILED) {
        log_amx("[TEST] Ошибка подключения к БД. Переподключение через 15 секунд...");
        g_DbConnected = false;
        set_task(15.0, "TryConnectDb");
        return;
    }
    
    if (FailState == TQUERY_QUERY_FAILED) {
        log_amx("[TEST] Ошибка запроса создания таблицы: %s", error);
        g_DbConnected = false;
        return;
    }

    // Если ошибок нет, БД готова к работе
    g_DbConnected = true;
    log_amx("[TEST] Подключение к БД успешно установлено. Таблица готова.");
}

// Обработчик для запросов, где не нужен возврат данных
public Handle_IgnoreQuery(FailState, Handle:hQuery, error[], errcode, data[], datasize) {
    if (FailState == TQUERY_CONNECT_FAILED) {
        g_DbConnected = false;
        log_amx("[TEST] Потеряно соединение с БД. Переподключение через 15 секунд...");
        set_task(15.0, "TryConnectDb");
        return;
    }
    if (FailState == TQUERY_QUERY_FAILED) {
        log_amx("[TEST] Ошибка запроса к БД: %s", error);
        return;
    }
}

// Проверка при входе игрока
public client_authorized(id) {
    if (is_user_bot(id) || is_user_hltv(id)) return;
    if (!g_DbConnected) return;

    new szAuthid[64];
    new szQuery[256];
    new data[2];

    get_user_authid(id, szAuthid, charsmax(szAuthid));
    formatex(szQuery, charsmax(szQuery), "SELECT `claim_time` FROM `test_privileges` WHERE `authid` = '%s'", szAuthid);

    data[0] = id;
    data[1] = get_user_userid(id);

    SQL_ThreadQuery(g_SqlTuple, "Handle_ConnectQuery", szQuery, data, sizeof(data));
}

public Handle_ConnectQuery(FailState, Handle:hQuery, error[], errcode, data[], datasize) {
    if (FailState) {
        if (FailState == TQUERY_CONNECT_FAILED) {
            g_DbConnected = false;
            set_task(15.0, "TryConnectDb");
        }
        return;
    }

    new id = data[0];
    if (!is_user_connected(id) || get_user_userid(id) != data[1]) return;

    if (SQL_NumResults(hQuery) > 0) {
        new iClaimTime = SQL_ReadResult(hQuery, 0);
        new iCurrentTime = get_systime();

        // Если с момента выдачи прошло меньше 1 дня, выдаем флаг
        if ((iCurrentTime - iClaimTime) < ONE_DAY_IN_SECONDS) {
            set_user_flags(id, get_user_flags(id) | TARGET_FLAG);
        }
    }
}

// Команда /test
public Cmd_TestPrivilege(id) {
    // ПРОВЕРКА: Если у игрока уже есть флаг q, запрещаем использование
    if (get_user_flags(id) & TARGET_FLAG) {
        client_print(id, print_chat, "[TEST] У вас уже имеется привилегия с флагом 'q'.");
        return PLUGIN_HANDLED;
    }

    if (!g_DbConnected) {
        client_print(id, print_chat, "[TEST] База данных временно недоступна. Попробуйте позже.");
        return PLUGIN_HANDLED;
    }

    new szAuthid[64];
    new szQuery[256];
    new data[2];

    get_user_authid(id, szAuthid, charsmax(szAuthid));
    formatex(szQuery, charsmax(szQuery), "SELECT `claim_time` FROM `test_privileges` WHERE `authid` = '%s'", szAuthid);

    data[0] = id;
    data[1] = get_user_userid(id);

    SQL_ThreadQuery(g_SqlTuple, "Handle_TestQuery", szQuery, data, sizeof(data));

    client_print(id, print_chat, "[TEST] Проверка вашей возможности получить привилегию...");

    return PLUGIN_HANDLED;
}

public Handle_TestQuery(FailState, Handle:hQuery, error[], errcode, data[], datasize) {
    if (FailState) {
        if (FailState == TQUERY_CONNECT_FAILED) {
            g_DbConnected = false;
            set_task(15.0, "TryConnectDb");
            client_print(data[0], print_chat, "[TEST] Ошибка БД. Попробуйте позже.");
        }
        return;
    }

    new id = data[0];
    if (!is_user_connected(id) || get_user_userid(id) != data[1]) return;

    new iCurrentTime = get_systime();
    new szAuthid[64];
    // Переменные вынесены в начало функции, чтобы избежать бага компилятора
    new szQuery[256]; 
    
    get_user_authid(id, szAuthid, charsmax(szAuthid));

    if (SQL_NumResults(hQuery) > 0) {
        new iClaimTime = SQL_ReadResult(hQuery, 0);
        new iTimeDiff = iCurrentTime - iClaimTime;

        if (iTimeDiff < ONE_WEEK_IN_SECONDS) {
            new iRemainingTime = ONE_WEEK_IN_SECONDS - iTimeDiff;
            new iDays = iRemainingTime / 86400;
            new iHours = (iRemainingTime % 86400) / 3600;
            
            client_print(id, print_chat, "[TEST] Выдача доступна раз в неделю. Осталось ждать: %d дн. %d ч.", iDays, iHours);
            return;
        }

        // КД прошло, обновляем время в БД
        formatex(szQuery, charsmax(szQuery), "UPDATE `test_privileges` SET `claim_time` = %d WHERE `authid` = '%s'", iCurrentTime, szAuthid);
        SQL_ThreadQuery(g_SqlTuple, "Handle_IgnoreQuery", szQuery);

    } else {
        // Игрок впервые берет привилегию
        formatex(szQuery, charsmax(szQuery), "INSERT INTO `test_privileges` (`authid`, `claim_time`) VALUES ('%s', %d)", szAuthid, iCurrentTime);
        SQL_ThreadQuery(g_SqlTuple, "Handle_IgnoreQuery", szQuery);
    }

    // Выдаем флаг прямо сейчас
    set_user_flags(id, get_user_flags(id) | TARGET_FLAG);
    client_print(id, print_chat, "[TEST] Вы успешно получили флаг 'q' на 1 день!");
}

// Команда админа для выдачи флага только на карту
public Cmd_GiveMapFlag(id, level, cid) {
    if (!cmd_access(id, level, cid, 2)) {
        return PLUGIN_HANDLED;
    }

    new szTarget[32];
    read_argv(1, szTarget, charsmax(szTarget));

    new iPlayer = cmd_target(id, szTarget, CMDTARGET_NO_BOTS | CMDTARGET_ALLOW_SELF);
    
    if (!iPlayer) {
        return PLUGIN_HANDLED;
    }

    // ПРОВЕРКА: Если у игрока уже есть флаг q, отменяем выдачу
    if (get_user_flags(iPlayer) & TARGET_FLAG) {
        client_print(id, print_chat, "[TEST] У игрока уже есть флаг 'q'.");
        return PLUGIN_HANDLED;
    }

    // Выдаем флаг в память (не сохраняется в БД)
    set_user_flags(iPlayer, get_user_flags(iPlayer) | TARGET_FLAG);

    new szAdminName[32], szPlayerName[32];
    get_user_name(id, szAdminName, charsmax(szAdminName));
    get_user_name(iPlayer, szPlayerName, charsmax(szPlayerName));

    client_print(id, print_chat, "[TEST] Вы выдали флаг 'q' игроку %s до конца карты.", szPlayerName);
    client_print(iPlayer, print_chat, "[TEST] Админ %s выдал вам флаг 'q' до конца карты.", szAdminName);

    return PLUGIN_HANDLED;
}

public plugin_end() {
    if (g_SqlTuple != Empty_Handle) {
        SQL_FreeHandle(g_SqlTuple);
    }
}