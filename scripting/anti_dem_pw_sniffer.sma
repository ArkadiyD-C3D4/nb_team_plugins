#pragma semicolon 1

#include <amxmodx>
#include <reapi>

#define PLUGIN_NAME     "Anti Demo PW Sniffer"
#define PLUGIN_VERSION  "1.0.4"
#define PLUGIN_AUTHOR   "nb_team"

// Имя защищаемого ключа авторизации (по умолчанию в CS 1.6 это "_pw")
new const PROTECTED_KEY[] = "_pw";

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
    
    // Хукаем событие изменения данных клиента в ReGameDLL
    RegisterHookChain(RG_CSGameRules_ClientUserInfoChanged, "OnClientUserInfoChanged", .post = false);
}

// Вызывается при подключении, смене ника и любом обновлении инфо-строки игрока
public OnClientUserInfoChanged(const player, const info[])
{
    // Проверяем, что игрок валиден и подключен
    if (!is_user_connected(player))
    {
        return HC_CONTINUE;
    }

    // Проверяем, есть ли вообще у игрока заполненный пароль в системе
    new current_pw[64];
    get_user_info(player, PROTECTED_KEY, current_pw, charsmax(current_pw));

    // Если пароль не пустой, мы его принудительно стираем из памяти игрока на сервере.
    // Стандартный admin.amxx считывает пароль в момент коннекта ДО этого события.
    if (current_pw[0] != '^0')
    {
        set_user_info(player, PROTECTED_KEY, "");
    }
    
    return HC_CONTINUE;
}
