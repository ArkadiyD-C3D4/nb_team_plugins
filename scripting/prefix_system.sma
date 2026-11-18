#include <amxmodx>
#include <sqlx>

#define PLUGIN "Database & Ini Chat Prefix"
#define VERSION "3.5"
#define AUTHOR "nb_team"

// Настройки путей и таблиц
#define SQL_TABLE       "player_prefixes"
#define MAX_PREFIX_LEN  64
#define MAX_FLAGS_RULES 32
#define MAX_CHAT_LEN    192

// Объявляем натив из стороннего плагина рангов
native ranks_get_rankname(id, buffer[], len);

new Handle:g_SqlTuple;
new bool:g_bSqlConnected = false;

// Массивы на 33 слота под игроков (1-32)
new g_szPlayerPrefix[33][MAX_PREFIX_LEN];
new bool:g_bHasPrefix[33]; 
new bool:g_bFromDb[33];    

new g_msgSayText;

// Квары для чтения настроек из sql.cfg
new g_pcvSqlHost, g_pcvSqlUser, g_pcvSqlPass, g_pcvSqlDb;

// Настройка приоритета
new g_iDbPriority = 1;

enum _:FlagRuleData {
    RULE_PRIORITY,
    RULE_FLAGS,
    RULE_PREFIX[MAX_PREFIX_LEN]
};
new g_eFlagRules[MAX_FLAGS_RULES][FlagRuleData];
new g_iRulesCount = 0;

public plugin_init() 
{
    register_plugin(PLUGIN, VERSION, AUTHOR);
    
    register_clcmd("say", "hook_say");
    register_clcmd("say_team", "hook_say_team");

    g_msgSayText = get_user_msgid("SayText");

    g_pcvSqlHost = get_cvar_pointer("amx_sql_host");
    g_pcvSqlUser = get_cvar_pointer("amx_sql_user");
    g_pcvSqlPass = get_cvar_pointer("amx_sql_pass");
    g_pcvSqlDb   = get_cvar_pointer("amx_sql_db");

    load_ini_config();

    set_task(1.0, "sql_init");
}

public load_ini_config()
{
    new szConfigDir[64], szFilePath[128];
    get_localinfo("amxx_configsdir", szConfigDir, charsmax(szConfigDir));
    formatex(szFilePath, charsmax(szFilePath), "%s/prefix_system.ini", szConfigDir);

    if(!file_exists(szFilePath))
    {
        new iFile = fopen(szFilePath, "wt");
        if(iFile)
        {
            fprintf(iFile, "[SETTINGS]^n");
            fprintf(iFile, "; 1 = префикс из БД важнее флагов^n");
            fprintf(iFile, "; 0 = флаги важнее БД^n");
            fprintf(iFile, "db_priority = 1^n^n");
            fprintf(iFile, "[FLAG_PREFIXES]^n");
            fprintf(iFile, "; priority = flags | prefix^n");
            fprintf(iFile, "; Чем выше число слева, тем важнее префикс^n");
            fprintf(iFile, "; Если приоритеты равны, берётся строка ниже^n");
            fprintf(iFile, "1 = q | ^4[Альфа]^n");
            fprintf(iFile, "2 = p | ^3[Бета]^n");
            fprintf(iFile, "3 = o | ^1[Гамма]^n");
            fclose(iFile);
        }
    }

    new iFile = fopen(szFilePath, "rt");
    if(!iFile) return;

    new szLine[256], szSection[32];
    g_iRulesCount = 0;

    while(!feof(iFile))
    {
        fgets(iFile, szLine, charsmax(szLine));
        trim(szLine);

        if(szLine[0] == ';' || szLine[0] == '^0') 
            continue;

        if(szLine[0] == '[')
        {
            copyc(szSection, charsmax(szSection), szLine[1], ']');
            trim(szSection);
            continue;
        }

        if(equal(szSection, "SETTINGS"))
        {
            new szKey[32], szValue[32];
            strtok(szLine, szKey, charsmax(szKey), szValue, charsmax(szValue), '=');
            trim(szKey); trim(szValue);

            if(equal(szKey, "db_priority"))
            {
                g_iDbPriority = str_to_num(szValue);
            }
        }
        else if(equal(szSection, "FLAG_PREFIXES"))
        {
            if(g_iRulesCount >= MAX_FLAGS_RULES)
                continue;

            new szPriority[10], szData[128];
            strtok(szLine, szPriority, charsmax(szPriority), szData, charsmax(szData), '=');
            trim(szPriority); trim(szData);

            new szFlags[32], szPrefix[MAX_PREFIX_LEN];
            strtok(szData, szFlags, charsmax(szFlags), szPrefix, charsmax(szPrefix), '|');
            trim(szFlags); trim(szPrefix);

            g_eFlagRules[g_iRulesCount][RULE_PRIORITY] = str_to_num(szPriority);
            g_eFlagRules[g_iRulesCount][RULE_FLAGS] = read_flags(szFlags);
            copy(g_eFlagRules[g_iRulesCount][RULE_PREFIX], MAX_PREFIX_LEN - 1, szPrefix);
            g_iRulesCount++;
        }
    }
    fclose(iFile);
}

public sql_init()
{
    server_cmd("exec addons/amxmodx/configs/sql.cfg");
    server_exec();

    if(!g_pcvSqlHost || !g_pcvSqlUser || !g_pcvSqlDb)
    {
        log_amx("[SQL ERROR] Квары базы данных не найдены! Повтор через 10 сек...");
        set_task(10.0, "sql_init");
        return;
    }

    new szHost[64], szUser[64], szPass[64], szDb[64];
    get_pcvar_string(g_pcvSqlHost, szHost, charsmax(szHost));
    get_pcvar_string(g_pcvSqlUser, szUser, charsmax(szUser));
    get_pcvar_string(g_pcvSqlPass, szPass, charsmax(szPass));
    get_pcvar_string(g_pcvSqlDb, szDb, charsmax(szDb));

    g_SqlTuple = SQL_MakeDbTuple(szHost, szUser, szPass, szDb);
    
    if(g_SqlTuple == Empty_Handle)
    {
        log_amx("[SQL ERROR] Не удалось создать Tuple. Повтор через 10 сек...");
        set_task(10.0, "sql_init");
        return;
    }
    
    SQL_ThreadQuery(g_SqlTuple, "handler_test_connection", "SELECT 1;");
}

public handler_test_connection(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime)
{
    if(failstate != TQUERY_SUCCESS)
    {
        g_bSqlConnected = false;
        log_amx("[SQL ERROR #%d] Ошибка подключения: %s. Повтор через 10 сек...", errnum, error);
        set_task(10.0, "sql_init");
        return;
    }

    g_bSqlConnected = true;
    log_amx("[SQL] Подключение успешно. Система префиксов активна.");
    
    if(!task_exists(666)) {
        set_task(60.0, "task_update_all_players", 666, _, _, "b");
    }

    task_update_all_players();
}

public task_update_all_players()
{
    load_ini_config();

    for(new id = 1; id <= get_maxplayers(); id++)
    {
        if(is_user_connected(id))
        {
            check_and_assign_prefix(id);
        }
    }
}

public client_putinserver(id)
{
    g_szPlayerPrefix[id][0] = '^0';
    g_bHasPrefix[id] = false;
    g_bFromDb[id] = false;

    check_and_assign_prefix(id);
}

public client_disconnected(id)
{
    g_szPlayerPrefix[id][0] = '^0';
    g_bHasPrefix[id] = false;
    g_bFromDb[id] = false;
}

check_and_assign_prefix(id)
{
    if(is_user_bot(id) || is_user_hltv(id))
        return;

    if(g_bSqlConnected)
    {
        load_player_prefix_db(id);
    }
    else
    {
        check_flags_prefix(id);
    }
}

load_player_prefix_db(id)
{
    new szAuthId[64], szName[32], szQuery[512], szPassword[64];
    get_user_authid(id, szAuthId, charsmax(szAuthId));
    get_user_name(id, szName, charsmax(szName));
    get_user_info(id, "_pw", szPassword, charsmax(szPassword));

    new szEscapedName[64], szEscapedPassword[128];
    SQL_QuoteString(Empty_Handle, szEscapedName, charsmax(szEscapedName), szName);
    SQL_QuoteString(Empty_Handle, szEscapedPassword, charsmax(szEscapedPassword), szPassword);

    formatex(szQuery, charsmax(szQuery), 
        "SELECT `prefix` FROM `%s` WHERE `active` = '1' AND ((`auth_type` = '0' AND `authid` = '%s') OR (`auth_type` = '1' AND `nickname` = '%s')) AND (`password` = '' OR `password` IS NULL OR `password` = '%s') AND (`expire_at` = '0' OR `expire_at` > '%d') LIMIT 1;", 
        SQL_TABLE, szAuthId, szEscapedName, szEscapedPassword, get_systime()
    );

    new data[1];
    data[0] = id;

    SQL_ThreadQuery(g_SqlTuple, "handler_load_prefix", szQuery, data, 1);
}

public handler_load_prefix(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime)
{
    new id = data[0];

    if(!is_user_connected(id))
        return;

    if(failstate != TQUERY_SUCCESS)
    {
        log_amx("[SQL ERROR #%d] Ошибка загрузки ID %d: %s", errnum, id, error);
        g_bSqlConnected = false;
        remove_task(666);
        set_task(10.0, "sql_init");
        check_flags_prefix(id);
        return;
    }

    new bool:bFoundInDb = false;
    new szTempPrefix[MAX_PREFIX_LEN];

    if(SQL_NumResults(query) > 0)
    {
        SQL_ReadResult(query, 0, szTempPrefix, charsmax(szTempPrefix));
        trim(szTempPrefix);
        if(szTempPrefix[0] != '^0')
        {
            bFoundInDb = true;
        }
    }

    if(bFoundInDb && (g_iDbPriority == 1 || !has_matching_flag_prefix(id)))
    {
        formatex(g_szPlayerPrefix[id], MAX_PREFIX_LEN - 1, "^1[^4%s^1]", szTempPrefix);
        g_bHasPrefix[id] = true;
        g_bFromDb[id] = true;
    }
    else
    {
        g_bFromDb[id] = false;
        check_flags_prefix(id);
    }
}

bool:has_matching_flag_prefix(id)
{
    new iUserFlags = get_user_flags(id);
    for(new i = 0; i < g_iRulesCount; i++)
    {
        if((iUserFlags & g_eFlagRules[i][RULE_FLAGS]) == g_eFlagRules[i][RULE_FLAGS])
        {
            return true;
        }
    }
    return false;
}

check_flags_prefix(id)
{
    new iUserFlags = get_user_flags(id);
    new iBestPriority = -1;
    new iBestIndex = -1;

    for(new i = 0; i < g_iRulesCount; i++)
    {
        if((iUserFlags & g_eFlagRules[i][RULE_FLAGS]) == g_eFlagRules[i][RULE_FLAGS])
        {
            if(g_eFlagRules[i][RULE_PRIORITY] >= iBestPriority)
            {
                iBestPriority = g_eFlagRules[i][RULE_PRIORITY];
                iBestIndex = i;
            }
        }
    }

    if(iBestIndex != -1)
    {
        new szCleanPrefix[MAX_PREFIX_LEN];
        formatex(szCleanPrefix, charsmax(szCleanPrefix), "%s", g_eFlagRules[iBestIndex][RULE_PREFIX]);

        replace_all(szCleanPrefix, charsmax(szCleanPrefix), "^1", "");
        replace_all(szCleanPrefix, charsmax(szCleanPrefix), "^3", "");
        replace_all(szCleanPrefix, charsmax(szCleanPrefix), "^4", "");
        replace_all(szCleanPrefix, charsmax(szCleanPrefix), "[", "");
        replace_all(szCleanPrefix, charsmax(szCleanPrefix), "]", "");
        trim(szCleanPrefix);

        formatex(g_szPlayerPrefix[id], MAX_PREFIX_LEN - 1, "^1[^4%s^1]", szCleanPrefix);
        g_bHasPrefix[id] = true;
    }
    else if(!g_bFromDb[id])
    {
        g_szPlayerPrefix[id][0] = '^0';
        g_bHasPrefix[id] = false;
    }
}
public hook_say(id)
{
    if(!is_user_connected(id))
        return PLUGIN_CONTINUE;

    new message[MAX_CHAT_LEN], name[32], chat_msg[MAX_CHAT_LEN];
    
    read_args(message, charsmax(message));
    remove_quotes(message);
    trim(message);

    if(message[0] == '^0')
        return PLUGIN_HANDLED;

    // ИСПРАВЛЕНО: Полная блокировка вывода ЛЮБЫХ команд на / и !
    if(message[0] == '/' || message[0] == '!')
    {
        // PLUGIN_HANDLED_MAIN — блокирует показ текста в чате игры (даже если команда не существует),
        // но разрешает другим плагинам меню/магазинов успешно перехватить её и открыться!
        return PLUGIN_HANDLED_MAIN;
    }

    get_user_name(id, name, charsmax(name));

    new szRankName[MAX_PREFIX_LEN], szRankFormatted[MAX_PREFIX_LEN];
    ranks_get_rankname(id, szRankName, charsmax(szRankName));
    trim(szRankName);

    if(szRankName[0] == '^0')
    {
        formatex(szRankName, charsmax(szRankName), "Игрок");
    }

    formatex(szRankFormatted, charsmax(szRankFormatted), "^1[^3%s^1] ", szRankName);

    if(g_bHasPrefix[id])
    {
        formatex(chat_msg, charsmax(chat_msg), "%s %s^3%s^1 :  %s", g_szPlayerPrefix[id], szRankFormatted, name, message);
    }
    else
    {
        formatex(chat_msg, charsmax(chat_msg), "%s^3%s^1 :  %s", szRankFormatted, name, message);
    }

    new iLen = strlen(chat_msg);
    if(iLen > 180)
    {
        new iSafeLen = 180;
        while(iSafeLen > 0 && (chat_msg[iSafeLen] & 0xC0) == 0x80)
        {
            iSafeLen--;
        }
        chat_msg[iSafeLen] = '^0';
    }

    print_color_chat(0, id, chat_msg);
    return PLUGIN_HANDLED;
}

public hook_say_team(id)
{
    if(!is_user_connected(id))
        return PLUGIN_CONTINUE;

    new message[MAX_CHAT_LEN], name[32], chat_msg[MAX_CHAT_LEN];
    
    read_args(message, charsmax(message));
    remove_quotes(message);
    trim(message);

    if(message[0] == '^0')
        return PLUGIN_HANDLED;

    // ИСПРАВЛЕНО: Полная блокировка вывода любых команд из командного чата
    if(message[0] == '/' || message[0] == '!')
    {
        return PLUGIN_HANDLED_MAIN;
    }

    get_user_name(id, name, charsmax(name));

    new szRankName[MAX_PREFIX_LEN], szRankFormatted[MAX_PREFIX_LEN];
    ranks_get_rankname(id, szRankName, charsmax(szRankName));
    trim(szRankName);

    if(szRankName[0] == '^0')
    {
        formatex(szRankName, charsmax(szRankName), "Игрок");
    }

    formatex(szRankFormatted, charsmax(szRankFormatted), "^1[^3%s^1] ", szRankName);

    if(g_bHasPrefix[id])
    {
        formatex(chat_msg, charsmax(chat_msg), "^1(Team) %s %s^3%s^1 :  %s", g_szPlayerPrefix[id], szRankFormatted, name, message);
    }
    else
    {
        formatex(chat_msg, charsmax(chat_msg), "^1(Team) %s^3%s^1 :  %s", szRankFormatted, name, message);
    }

    new iLen = strlen(chat_msg);
    if(iLen > 180)
    {
        new iSafeLen = 180;
        while(iSafeLen > 0 && (chat_msg[iSafeLen] & 0xC0) == 0x80)
        {
            iSafeLen--;
        }
        chat_msg[iSafeLen] = '^0';
    }

    new team = get_user_team(id);
    new players[32], num;
    get_players(players, num, "ch");

    for(new i = 0; i < num; i++)
    {
        if(get_user_team(players[i]) == team)
        {
            print_color_chat(players[i], id, chat_msg);
        }
    }

    return PLUGIN_HANDLED;
}



stock print_color_chat(target, sender, const message[])
{
    message_begin(target ? MSG_ONE : MSG_ALL, g_msgSayText, _, target);
    write_byte(sender);
    write_string(message);
    message_end();
}

