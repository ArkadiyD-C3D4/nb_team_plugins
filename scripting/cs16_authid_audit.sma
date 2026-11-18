#include <amxmodx>

#define PLUGIN_NAME    "CS 1.6 AuthID Audit"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR  "nb_team"
#define AUDIT_LOG      "authid_audit.log"

new g_pLogIp;
new bool:g_bAuthorized[33];

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
    g_pLogIp = register_cvar("authid_audit_log_ip", "1");
    log_to_file(AUDIT_LOG, "PLUGIN_LOADED version=%s", PLUGIN_VERSION);
}

// Earliest standard AMXX connection callback. SteamID may not be available yet.
public client_connect(id)
{
    g_bAuthorized[id] = false;
    log_to_file(AUDIT_LOG, "CONNECT_BEGIN slot=%d authid=NOT_YET_AVAILABLE", id);
}

// Supported by newer AMX Mod X versions. This observes the initial connection
// attempt and deliberately returns PLUGIN_CONTINUE without changing the reason.
public client_connectex(id, const name[], const ip[], reason[128])
{
    if (get_pcvar_num(g_pLogIp))
    {
        log_to_file(AUDIT_LOG,
            "CONNECT_EX slot=%d name=^"%s^" endpoint=^"%s^" reason=^"%s^"",
            id, name, ip, reason);
    }
    else
    {
        log_to_file(AUDIT_LOG,
            "CONNECT_EX slot=%d name=^"%s^" ip_logging=disabled reason=^"%s^"",
            id, name, reason);
    }

    return PLUGIN_CONTINUE;
}

// AMXX documents this as the point when the valid auth ID becomes available.
public client_authorized(id, const authid[])
{
    new name[64];
    new ip[46];
    get_user_name(id, name, charsmax(name));
    get_user_ip(id, ip, charsmax(ip), 1);
    g_bAuthorized[id] = true;

    if (get_pcvar_num(g_pLogIp))
    {
        log_to_file(AUDIT_LOG,
            "AUTHORIZED slot=%d name=^"%s^" authid=^"%s^" ip=^"%s^"",
            id, name, authid, ip);
    }
    else
    {
        log_to_file(AUDIT_LOG,
            "AUTHORIZED slot=%d name=^"%s^" authid=^"%s^" ip_logging=disabled",
            id, name, authid);
    }
}

// This forward can run before or after client_authorized, so label the state.
public client_putinserver(id)
{
    new name[64];
    new ip[46];
    get_user_name(id, name, charsmax(name));
    get_user_ip(id, ip, charsmax(ip), 1);

    if (g_bAuthorized[id])
    {
        new authid[64];
        get_user_authid(id, authid, charsmax(authid));

        if (get_pcvar_num(g_pLogIp))
        {
            log_to_file(AUDIT_LOG,
                "PUT_IN_SERVER slot=%d name=^"%s^" authid=^"%s^" ip=^"%s^" state=authorized",
                id, name, authid, ip);
        }
        else
        {
            log_to_file(AUDIT_LOG,
                "PUT_IN_SERVER slot=%d name=^"%s^" authid=^"%s^" ip_logging=disabled state=authorized",
                id, name, authid);
        }
    }
    else
    {
        if (get_pcvar_num(g_pLogIp))
        {
            log_to_file(AUDIT_LOG,
                "PUT_IN_SERVER slot=%d name=^"%s^" ip=^"%s^" state=authid_not_observed_yet",
                id, name, ip);
        }
        else
        {
            log_to_file(AUDIT_LOG,
                "PUT_IN_SERVER slot=%d name=^"%s^" ip_logging=disabled state=authid_not_observed_yet",
                id, name);
        }
    }
}

public client_disconnected(id, bool:drop, message[], maxlen)
{
    log_to_file(AUDIT_LOG,
        "DISCONNECTED slot=%d drop=%d message=^"%s^" authid_was_observed=%d",
        id, drop ? 1 : 0, message, g_bAuthorized[id] ? 1 : 0);

    g_bAuthorized[id] = false;
}
