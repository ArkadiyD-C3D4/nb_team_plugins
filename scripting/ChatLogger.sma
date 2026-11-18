/*
 * ChatLogger.sma
 * AMX Mod X 1.8.x / 1.9.x compatible
 *
 * No cstrike include.
 * SQL settings are read from addons/amxmodx/configs/sql.cfg:
 *
 * amx_sql_host "127.0.0.1"
 * amx_sql_user "chatlogger"
 * amx_sql_pass "password"
 * amx_sql_db   "counterstrike"
 *
 * Optional:
 * chatlog_table "chat_messages"
 * chatlog_server_id "server_01"
 *
 * v1.3 FIX: russian text is no longer stored as double-encoded mojibake:
 *   1) SET NAMES utf8mb4 (fallback: utf8) is sent right after connecting,
 *      so MySQL does not treat incoming UTF-8 bytes as latin1;
 *   2) every message/name is normalized to UTF-8 inside the plugin:
 *      if the text is not valid UTF-8 (old non-Steam clients send CP1251),
 *      it is converted CP1251 -> UTF-8 before being stored.
 */

#include <amxmodx>
#include <sqlx>

// SendQueueLine() keeps ~18000 stack/heap cells alive (default is 4096).
// Without this the plugin compiles but dies with "run time error 3: stack error".
#pragma dynamic 32768

#define PLUGIN_NAME       "Chat Logger"
#define PLUGIN_VERSION    "1.3"
#define PLUGIN_AUTHOR     "nb_team"

#define MAX_PLAYERS       32
#define MAX_MESSAGE_LEN   191
#define MAX_NAME_LEN      63
#define MAX_STEAMID_LEN   34
#define MAX_IP_LEN        31
#define MAX_QUEUE_LINE    2047
#define MAX_QUEUE_FIELDS  12
#define MAX_FIELD_LEN     512

#define QUEUE_FILE        "chatlogger_queue.txt"
#define ERROR_LOG_FILE    "chatlogger_error.log"

#define FLUSH_INTERVAL    1.0
#define RETRY_INTERVAL    10.0
#define MAX_BATCH_SIZE    8

new Handle:g_SqlTuple = Empty_Handle
new Handle:g_SqlConnection = Empty_Handle

// Plain 0/1 flags instead of bool: - the old 1.8.2 compiler
// throws "warning 213: tag mismatch" on "!boolvar"
new g_SqlReady
new g_FlushRunning

new g_QueueFile[192]
new g_ErrorLogFile[192]
new g_TableName[64]
new g_ServerId[128]
new g_MapName[64]

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR)

    register_clcmd("say", "CmdSay")
    register_clcmd("say_team", "CmdSayTeam")

    get_mapname(g_MapName, charsmax(g_MapName))

    new configsDir[128]
    get_localinfo("amxx_configsdir", configsDir, charsmax(configsDir))

    formatex(g_QueueFile, charsmax(g_QueueFile), "%s/%s", configsDir, QUEUE_FILE)
    formatex(g_ErrorLogFile, charsmax(g_ErrorLogFile), "%s/%s", configsDir, ERROR_LOG_FILE)

    copy(g_TableName, charsmax(g_TableName), "chat_messages")
    copy(g_ServerId, charsmax(g_ServerId), "server_01")

    LoadSQLConfig()

    set_task(FLUSH_INTERVAL, "TaskFlushQueue", 10001, "", 0, "b")
    set_task(RETRY_INTERVAL, "TaskReconnectSQL", 10002, "", 0, "b")

    log_amx("[%s] started. Queue: %s", PLUGIN_NAME, g_QueueFile)
}

public plugin_end()
{
    if (g_SqlConnection != Empty_Handle)
    {
        SQL_FreeHandle(g_SqlConnection)
        g_SqlConnection = Empty_Handle
    }

    if (g_SqlTuple != Empty_Handle)
    {
        SQL_FreeHandle(g_SqlTuple)
        g_SqlTuple = Empty_Handle
    }
}

LoadSQLConfig()
{
    new configsDir[128]
    get_localinfo("amxx_configsdir", configsDir, charsmax(configsDir))

    new file[192]
    formatex(file, charsmax(file), "%s/sql.cfg", configsDir)

    if (!file_exists(file))
    {
        WriteError("sql.cfg not found: %s", file)
        return
    }

    new fp = fopen(file, "rt")
    if (!fp)
    {
        WriteError("Cannot open sql.cfg: %s", file)
        return
    }

    new line[256]
    new key[64]
    new value[160]

    new host[128]
    new user[64]
    new pass[128]
    new db[64]

    while (!feof(fp))
    {
        if (!fgets(fp, line, charsmax(line)))
            break

        trim(line)

        if (!line[0])
            continue

        if (line[0] == ';' || line[0] == '#')
            continue

        if (line[0] == '/' && line[1] == '/')
            continue

        ParseConfigLine(line, key, charsmax(key), value, charsmax(value))

        if (!key[0])
            continue

        if (equali(key, "amx_sql_host"))
            copy(host, charsmax(host), value)
        else if (equali(key, "amx_sql_user"))
            copy(user, charsmax(user), value)
        else if (equali(key, "amx_sql_pass"))
            copy(pass, charsmax(pass), value)
        else if (equali(key, "amx_sql_db"))
            copy(db, charsmax(db), value)
        else if (equali(key, "chatlog_table"))
            copy(g_TableName, charsmax(g_TableName), value)
        else if (equali(key, "chatlog_server_id"))
            copy(g_ServerId, charsmax(g_ServerId), value)
    }

    fclose(fp)

    SanitizeIdentifier(g_TableName, charsmax(g_TableName))

    // chatlog_server_id may be typed in Russian: normalize it to UTF-8 too
    new serverUtf8[128]
    NormalizeToUtf8(g_ServerId, serverUtf8, charsmax(serverUtf8))
    copy(g_ServerId, charsmax(g_ServerId), serverUtf8)

    if (!host[0] || !user[0] || !db[0])
    {
        WriteError("sql.cfg is missing amx_sql_host/amx_sql_user/amx_sql_db")
        return
    }

    g_SqlTuple = SQL_MakeDbTuple(host, user, pass, db)

    ConnectSQL()
}

ParseConfigLine(const line[], key[], keyLen, value[], valueLen)
{
    key[0] = 0
    value[0] = 0

    new len = strlen(line)
    new pos = -1

    for (new i = 0; i < len; i++)
    {
        if (line[i] == ' ' || line[i] == '^t')
        {
            pos = i
            break
        }
    }

    if (pos == -1)
        return

    copy(key, keyLen, line)
    key[pos] = 0
    trim(key)

    copy(value, valueLen, line[pos + 1])
    trim(value)
    remove_quotes(value)
}

SanitizeIdentifier(string[], maxLen)
{
    new len = strlen(string)

    if (!len)
        return

    new out[64]
    new pos

    for (new i = 0; i < len && pos < maxLen; i++)
    {
        if ((string[i] >= 'a' && string[i] <= 'z') ||
            (string[i] >= 'A' && string[i] <= 'Z') ||
            (string[i] >= '0' && string[i] <= '9') ||
            string[i] == '_')
        {
            out[pos++] = string[i]
        }
    }

    out[pos] = 0

    if (!out[0])
        copy(out, maxLen, "chat_messages")

    copy(string, maxLen, out)
}

ConnectSQL()
{
    if (g_SqlTuple == Empty_Handle)
        return

    g_SqlReady = 0

    if (g_SqlConnection != Empty_Handle)
    {
        SQL_FreeHandle(g_SqlConnection)
        g_SqlConnection = Empty_Handle
    }

    new error[256]
    new errorCode

    g_SqlConnection = SQL_Connect(g_SqlTuple, errorCode, error, charsmax(error))

    if (g_SqlConnection == Empty_Handle)
    {
        WriteError("SQL connection failed [%d]: %s", errorCode, error)
        return
    }

    // FIX: must be done before any INSERT, see SetDbCharset()
    SetDbCharset()

    if (!CreateTable())
    {
        WriteError("Cannot create/check table `%s`", g_TableName)

        SQL_FreeHandle(g_SqlConnection)
        g_SqlConnection = Empty_Handle
        return
    }

    g_SqlReady = 1

    log_amx("[%s] MySQL connection established", PLUGIN_NAME)
}

// Выполняет запрос, не возвращающий строк. Возвращает 1 при успехе, 0 при ошибке.
// silent = 1 — не писать ошибку в лог (нужно для тихого фолбэка utf8mb4 -> utf8)
RunSimpleQuery(const sql[], silent = 0)
{
    new error[256]
    new errorCode

    new Handle:query = SQL_PrepareQuery(g_SqlConnection, sql, errorCode, error, charsmax(error))

    if (query == Empty_Handle)
    {
        if (!silent)
            WriteError("Query prepare failed [%d]: %s", errorCode, error)

        return 0
    }

    // SQL_Execute is untagged on 1.8.x: do not assign it to a bool: variable
    new success = SQL_Execute(query)

    if (!success)
    {
        SQL_QueryError(query, error, charsmax(error))

        if (!silent)
            WriteError("Query execute failed: %s", error)
    }

    SQL_FreeHandle(query)

    return success
}

// ---------------------------------------------------------------------------
// FIX for the mojibake: tell MySQL that this connection speaks UTF-8.
// The sqlx module has no one-shot SQL_Query() native, so the query goes
// through SQL_PrepareQuery() + SQL_Execute() + SQL_FreeHandle().
// ---------------------------------------------------------------------------
SetDbCharset()
{
    // utf8mb4 (MySQL 5.5.3+); on older servers fall back to utf8 silently
    if (RunSimpleQuery("SET NAMES utf8mb4", 1))
    {
        log_amx("[%s] Connection charset: utf8mb4", PLUGIN_NAME)
        return 1
    }

    // Plain utf8 is enough for Russian text
    if (RunSimpleQuery("SET NAMES utf8"))
    {
        log_amx("[%s] Connection charset: utf8 (server is too old for utf8mb4)", PLUGIN_NAME)
        return 1
    }

    WriteError("Could not set connection charset, SET NAMES failed")

    return 0
}

CreateTable()
{
    new query[2048]

    formatex(query, charsmax(query),
        "CREATE TABLE IF NOT EXISTS `%s` (`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `event_id` CHAR(32) NOT NULL, `steamid` VARCHAR(35) NOT NULL, `name` VARCHAR(64) NOT NULL, `ip` VARCHAR(45) NOT NULL, `userid` INT NOT NULL, `message` TEXT NOT NULL, `is_team` TINYINT(1) NOT NULL DEFAULT 0, `flags` VARCHAR(32) NOT NULL DEFAULT '', `team` VARCHAR(16) NOT NULL DEFAULT '', `map` VARCHAR(64) NOT NULL DEFAULT '', `server` VARCHAR(128) NOT NULL DEFAULT '', `timestamp` DATETIME NOT NULL, `unix_time` INT UNSIGNED NOT NULL, PRIMARY KEY (`id`), UNIQUE KEY `uq_event_id` (`event_id`), KEY `idx_steamid` (`steamid`), KEY `idx_unix_time` (`unix_time`), KEY `idx_timestamp` (`timestamp`), KEY `idx_server` (`server`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        g_TableName
    )

    if (RunCreateQuery(query))
        return 1

    // MySQL < 5.5.3 does not know utf8mb4 - retry with plain utf8
    WriteError("CREATE TABLE with utf8mb4 failed, retrying with utf8")

    replace(query, charsmax(query), "DEFAULT CHARSET=utf8mb4", "DEFAULT CHARSET=utf8")

    return RunCreateQuery(query)
}

RunCreateQuery(const query[])
{
    new error[256]
    new errorCode

    new Handle:queryHandle = SQL_PrepareQuery(g_SqlConnection, query, errorCode, error, charsmax(error))

    if (queryHandle == Empty_Handle)
    {
        WriteError("CREATE TABLE prepare failed [%d]: %s", errorCode, error)
        return 0
    }

    // SQL_Execute is untagged on 1.8.x: do not assign it to a bool: variable
    new success = SQL_Execute(queryHandle)

    if (!success)
    {
        SQL_QueryError(queryHandle, error, charsmax(error))
        WriteError("CREATE TABLE execute failed: %s", error)
    }

    SQL_FreeHandle(queryHandle)

    return success
}

public CmdSay(id)
{
    return HandleChat(id, 0)
}

public CmdSayTeam(id)
{
    return HandleChat(id, 1)
}

HandleChat(id, isTeam)
{
    if (id < 1 || id > MAX_PLAYERS || !is_user_connected(id))
        return PLUGIN_CONTINUE

    new message[MAX_MESSAGE_LEN + 1]

    read_args(message, charsmax(message))
    remove_quotes(message)
    trim(message)

    if (!message[0])
        return PLUGIN_CONTINUE

    QueueMessage(id, message, isTeam)

    return PLUGIN_CONTINUE
}

// ---------------------------------------------------------------------------
// Encoding helpers.
//
// CS 1.6 has no single chat encoding: current Steam clients send UTF-8,
// old (non-Steam) builds send the system codepage - CP1251 for Russian.
// Everything is normalized to UTF-8 here, so the database always gets
// one consistent encoding.
// ---------------------------------------------------------------------------

NormalizeToUtf8(const input[], output[], maxLen)
{
    if (IsValidUtf8(input))
    {
        copy(output, maxLen, input)
        return
    }

    Cp1251ToUtf8(input, output, maxLen)
}

IsValidUtf8(const string[])
{
    new len = strlen(string)
    new i

    while (i < len)
    {
        new c = string[i] & 0xFF

        if (c < 0x80)
        {
            i++
            continue
        }

        new need
        new value

        if ((c & 0xE0) == 0xC0)
        {
            need = 1
            value = c & 0x1F
        }
        else if ((c & 0xF0) == 0xE0)
        {
            need = 2
            value = c & 0x0F
        }
        else if ((c & 0xF8) == 0xF0)
        {
            need = 3
            value = c & 0x07
        }
        else
        {
            // 0x80-0xBF (stray continuation byte) or 0xF8-0xFF: not UTF-8
            return 0
        }

        // the sequence must fit into the string
        if (i + need >= len)
            return 0

        for (new k = 1; k <= need; k++)
        {
            new cc = string[i + k] & 0xFF

            if ((cc & 0xC0) != 0x80)
                return 0

            value = (value << 6) | (cc & 0x3F)
        }

        // overlong encodings, surrogates and out-of-range
        if (need == 1 && value < 0x80)
            return 0

        if (need == 2 && value < 0x800)
            return 0

        if (need == 3 && (value < 0x10000 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF)))
            return 0

        i += need + 1
    }

    return 1
}

Cp1251ToUtf8(const input[], output[], maxLen)
{
    new pos

    for (new i = 0; input[i] != 0; i++)
    {
        new c = input[i] & 0xFF

        if (c < 0x80)
        {
            if (pos > maxLen - 2)
                break

            output[pos++] = c
            continue
        }

        new u = Cp1251ToUnicode(c)

        if (!u)
        {
            // byte undefined in CP1251
            if (pos > maxLen - 2)
                break

            output[pos++] = '?'
            continue
        }

        if (u < 0x800)
        {
            if (pos > maxLen - 3)
                break

            output[pos++] = 0xC0 | (u >> 6)
            output[pos++] = 0x80 | (u & 0x3F)
        }
        else
        {
            if (pos > maxLen - 4)
                break

            output[pos++] = 0xE0 | (u >> 12)
            output[pos++] = 0x80 | ((u >> 6) & 0x3F)
            output[pos++] = 0x80 | (u & 0x3F)
        }
    }

    output[pos] = 0
}

Cp1251ToUnicode(c)
{
    // CP1251 bytes 0x80-0xBF; 0xC0-0xFF (Cyrillic) is linear, see below.
    // 0x0000 marks a byte that has no CP1251 mapping.
    static const table[64] =
    {
        0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021,
        0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
        0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x0000, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
        0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
        0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
        0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x0451,
        0x2116, 0x2118, 0x0455, 0x00BB, 0x0458, 0x0405, 0x0454, 0x0457
    }

    if (c < 0x80)
        return c

    if (c < 0xC0)
        return table[c - 0x80]

    if (c < 0xE0)
        return 0x0410 + (c - 0xC0) // uppercase Cyrillic

    return 0x0430 + (c - 0xE0)     // lowercase Cyrillic
}

QueueMessage(id, const message[], isTeam)
{
    new steamid[MAX_STEAMID_LEN]
    new name[MAX_NAME_LEN + 1]
    new ip[MAX_IP_LEN + 1]
    new flags[32]
    new team[16]

    get_user_authid(id, steamid, charsmax(steamid))
    get_user_name(id, name, charsmax(name))
    get_user_ip(id, ip, charsmax(ip), 1)
    get_flags(get_user_flags(id), flags, charsmax(flags))
    get_user_team(id, team, charsmax(team))

    if (!steamid[0])
        copy(steamid, charsmax(steamid), "UNKNOWN")

    if (!name[0])
        copy(name, charsmax(name), "UNKNOWN")

    if (!ip[0])
        copy(ip, charsmax(ip), "0.0.0.0")

    if (!team[0])
        copy(team, charsmax(team), "UNASSIGNED")

    // FIX: normalize name and message to UTF-8 before storing
    new nameUtf8[(MAX_NAME_LEN + 1) * 2]
    new messageUtf8[(MAX_MESSAGE_LEN + 1) * 2]

    NormalizeToUtf8(name, nameUtf8, charsmax(nameUtf8))
    NormalizeToUtf8(message, messageUtf8, charsmax(messageUtf8))

    new eventId[33]
    GenerateEventId(id, eventId, charsmax(eventId))

    new aEvent[80]
    new aSteam[80]
    new aName[300]
    new aIp[100]
    new aMessage[800]
    new aFlags[100]
    new aTeam[100]
    new aMap[140]
    new aServer[260]

    QueueEscape(eventId, aEvent, charsmax(aEvent))
    QueueEscape(steamid, aSteam, charsmax(aSteam))
    QueueEscape(nameUtf8, aName, charsmax(aName))
    QueueEscape(ip, aIp, charsmax(aIp))
    QueueEscape(messageUtf8, aMessage, charsmax(aMessage))
    QueueEscape(flags, aFlags, charsmax(aFlags))
    QueueEscape(team, aTeam, charsmax(aTeam))
    QueueEscape(g_MapName, aMap, charsmax(aMap))
    QueueEscape(g_ServerId, aServer, charsmax(aServer))

    new line[MAX_QUEUE_LINE]

    formatex(line, charsmax(line),
        "%s|%s|%s|%s|%d|%s|%d|%s|%s|%s|%s|%d",
        aEvent,
        aSteam,
        aName,
        aIp,
        get_user_userid(id),
        aMessage,
        isTeam,
        aFlags,
        aTeam,
        aMap,
        aServer,
        get_systime()
    )

    new fp = fopen(g_QueueFile, "at")

    if (!fp)
    {
        WriteError("CRITICAL: cannot open queue file for append: %s", g_QueueFile)
        return
    }

    fputs(fp, line)
    fputs(fp, "^n")
    fclose(fp)
}

// NOTE: in Pawn '^' is the escape character, the caret itself is '^^'
QueueEscape(const input[], output[], maxLen)
{
    new pos

    for (new i = 0; input[i] != 0 && pos < maxLen - 1; i++)
    {
        new c = input[i]
        new e = 0

        switch (c)
        {
            case '|':  e = 'p'
            case '^^': e = '^^'
            case '^n': e = 'n'
            case '^r': e = 'r'
        }

        if (e)
        {
            if (pos + 2 >= maxLen)
                break

            output[pos++] = '^^'
            output[pos++] = e
        }
        else
        {
            output[pos++] = c
        }
    }

    output[pos] = 0
}

QueueUnescape(string[], maxLen)
{
    new out[MAX_FIELD_LEN]
    new pos

    if (maxLen > MAX_FIELD_LEN - 1)
        maxLen = MAX_FIELD_LEN - 1

    for (new i = 0; string[i] != 0 && pos < maxLen - 1; i++)
    {
        if (string[i] == '^^' && string[i + 1] != 0)
        {
            i++

            switch (string[i])
            {
                case 'p':  out[pos++] = '|'
                case 'n':  out[pos++] = '^n'
                case 'r':  out[pos++] = '^r'
                case '^^': out[pos++] = '^^'
                default:
                {
                    out[pos++] = '^^'
                    out[pos++] = string[i]
                }
            }
        }
        else
        {
            out[pos++] = string[i]
        }
    }

    out[pos] = 0
    copy(string, maxLen, out)
}

GenerateEventId(id, output[], maxLen)
{
    static serial

    serial++

    formatex(output, maxLen, "%08x%08x%08x%08x",
        get_systime(),
        id,
        serial,
        get_systime() ^ (id << 8) ^ serial
    )
}

public TaskReconnectSQL()
{
    if (!g_SqlReady)
        ConnectSQL()
}

public TaskFlushQueue()
{
    if (g_FlushRunning || !g_SqlReady || !file_exists(g_QueueFile))
        return

    g_FlushRunning = 1
    FlushQueue()
    g_FlushRunning = 0
}

FlushQueue()
{
    new fp = fopen(g_QueueFile, "rt")

    if (!fp)
        return

    new tempFile[220]
    formatex(tempFile, charsmax(tempFile), "%s.tmp", g_QueueFile)

    new out = fopen(tempFile, "wt")

    if (!out)
    {
        fclose(fp)
        WriteError("Cannot create temporary queue file")
        return
    }

    new line[MAX_QUEUE_LINE]
    new processed
    new failed

    while (!feof(fp) && processed < MAX_BATCH_SIZE)
    {
        if (!fgets(fp, line, charsmax(line)))
            break

        trim(line)

        if (!line[0])
            continue

        if (SendQueueLine(line))
        {
            processed++
        }
        else
        {
            failed = 1
            fputs(out, line)
            fputs(out, "^n")
            break
        }
    }

    // If an insert failed, preserve everything after the failed line too.
    while (!feof(fp))
    {
        if (!fgets(fp, line, charsmax(line)))
            break

        trim(line)

        if (!line[0])
            continue

        fputs(out, line)
        fputs(out, "^n")
    }

    fclose(fp)
    fclose(out)

    delete_file(g_QueueFile)
    rename_file(tempFile, g_QueueFile, 1)

    if (failed)
        WriteError("Flush stopped at a failed insert; remaining messages kept in queue")
}

SendQueueLine(const line[])
{
    new field[MAX_QUEUE_FIELDS][MAX_FIELD_LEN]
    new count = SplitQueueLine(line, field, MAX_QUEUE_FIELDS)

    if (count != MAX_QUEUE_FIELDS)
    {
        WriteError("Invalid queue line (%d fields): %s", count, line)
        return 1
    }

    new eventId[80]
    new steamid[80]
    new name[140]
    new ip[100]
    new message[800]
    new flags[100]
    new team[100]
    new map[140]
    new server[260]

    copy(eventId, charsmax(eventId), field[0])
    copy(steamid, charsmax(steamid), field[1])
    copy(name, charsmax(name), field[2])
    copy(ip, charsmax(ip), field[3])
    copy(message, charsmax(message), field[5])
    copy(flags, charsmax(flags), field[7])
    copy(team, charsmax(team), field[8])
    copy(map, charsmax(map), field[9])
    copy(server, charsmax(server), field[10])

    QueueUnescape(eventId, charsmax(eventId))
    QueueUnescape(steamid, charsmax(steamid))
    QueueUnescape(name, charsmax(name))
    QueueUnescape(ip, charsmax(ip))
    QueueUnescape(message, charsmax(message))
    QueueUnescape(flags, charsmax(flags))
    QueueUnescape(team, charsmax(team))
    QueueUnescape(map, charsmax(map))
    QueueUnescape(server, charsmax(server))

    new userid = str_to_num(field[4])
    new isTeam = str_to_num(field[6])
    new unixTime = str_to_num(field[11])

    new qEvent[180]
    new qSteam[180]
    new qName[300]
    new qIp[180]
    new qMessage[1200]
    new qFlags[220]
    new qTeam[220]
    new qMap[300]
    new qServer[520]

    QuoteSQL(eventId, qEvent, charsmax(qEvent))
    QuoteSQL(steamid, qSteam, charsmax(qSteam))
    QuoteSQL(name, qName, charsmax(qName))
    QuoteSQL(ip, qIp, charsmax(qIp))
    QuoteSQL(message, qMessage, charsmax(qMessage))
    QuoteSQL(flags, qFlags, charsmax(qFlags))
    QuoteSQL(team, qTeam, charsmax(qTeam))
    QuoteSQL(map, qMap, charsmax(qMap))
    QuoteSQL(server, qServer, charsmax(qServer))

    new query[4096]

    formatex(query, charsmax(query),
        "INSERT INTO `%s` (`event_id`,`steamid`,`name`,`ip`,`userid`,`message`,`is_team`,`flags`,`team`,`map`,`server`,`timestamp`,`unix_time`) VALUES (%s,%s,%s,%s,%d,%s,%d,%s,%s,%s,%s,FROM_UNIXTIME(%d),%d) ON DUPLICATE KEY UPDATE `event_id`=`event_id`",
        g_TableName,
        qEvent,
        qSteam,
        qName,
        qIp,
        userid,
        qMessage,
        isTeam,
        qFlags,
        qTeam,
        qMap,
        qServer,
        unixTime,
        unixTime
    )

    new error[256]
    new errorCode

    new Handle:queryHandle = SQL_PrepareQuery(g_SqlConnection, query, errorCode, error, charsmax(error))

    if (queryHandle == Empty_Handle)
    {
        WriteError("INSERT prepare failed [%d]: %s", errorCode, error)
        g_SqlReady = 0
        return 0
    }

    // SQL_Execute is untagged on 1.8.x: do not assign it to a bool: variable
    new success = SQL_Execute(queryHandle)

    if (!success)
    {
        SQL_QueryError(queryHandle, error, charsmax(error))
        WriteError("INSERT execute failed: %s", error)

        SQL_FreeHandle(queryHandle)

        g_SqlReady = 0

        if (g_SqlConnection != Empty_Handle)
        {
            SQL_FreeHandle(g_SqlConnection)
            g_SqlConnection = Empty_Handle
        }

        return 0
    }

    SQL_FreeHandle(queryHandle)

    return 1
}

QuoteSQL(const input[], output[], maxLen)
{
    new escaped[1024]

    SQL_QuoteString(g_SqlConnection, escaped, charsmax(escaped), input)
    formatex(output, maxLen, "'%s'", escaped)
}

SplitQueueLine(const line[], fields[][MAX_FIELD_LEN], maxFields)
{
    new count
    new start
    new len = strlen(line)

    for (new i = 0; i <= len && count < maxFields; i++)
    {
        if (line[i] == '|' || line[i] == 0)
        {
            new fieldLen = i - start
            new maxCopy = fieldLen

            if (maxCopy > MAX_FIELD_LEN - 1)
                maxCopy = MAX_FIELD_LEN - 1

            // copy() takes only 3 arguments, so copy manually
            for (new j = 0; j < maxCopy; j++)
                fields[count][j] = line[start + j]

            fields[count][maxCopy] = 0

            count++
            start = i + 1
        }
    }

    return count
}

WriteError(const fmt[], any:...)
{
    new message[512]

    vformat(message, charsmax(message), fmt, 2)

    log_to_file(g_ErrorLogFile, "%s", message)
}