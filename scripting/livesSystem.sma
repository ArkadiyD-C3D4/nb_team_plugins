#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <colorchat> // Необходимо для работы client_print_color в AMXX 1.8.2

#define PLUGIN "Lives System"
#define VERSION "1.6.1"
#define AUTHOR "nb_team"

#define MAX_PLAYERS 32

// Points Core natives
native points_get(id)
native points_set(id, amount)
native points_is_loaded(id)

// Cvars
new g_cvarBuyPrice
new g_cvarSellPrice
new g_cvarReviveTime

// Player data
new g_iLives[MAX_PLAYERS+1]
new g_iLastReviveTime[MAX_PLAYERS+1]
new g_bMenuActive[MAX_PLAYERS+1]

// Глобальное время начала раунда
new g_iRoundStartTime

public plugin_precache()
{
    g_cvarBuyPrice = register_cvar("ls_buy_price", "10")
    g_cvarSellPrice = register_cvar("ls_sell_price", "5")
    g_cvarReviveTime = register_cvar("ls_revive_time", "40")
}

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)
    
    // Регистрация команд и хуков (без изменений)
    register_clcmd("say /lives", "Cmd_Lives")
    register_clcmd("say_team /lives", "Cmd_Lives")
    register_menucmd(register_menuid("Lives Menu"), 1023, "Menu_Handler")
    
    RegisterHookChain(RG_CSGameRules_RestartRound, "OnRoundRestart", true)
    register_logevent("Event_RoundStart", 2, "1=Round_Start")
    register_event("DeathMsg", "Event_DeathMsg", "a")
    
    g_iRoundStartTime = get_systime()
}

public OnRoundRestart()
{
    g_iRoundStartTime = get_systime()
}

public Event_RoundStart()
{
    g_iRoundStartTime = get_systime()
}

public client_putinserver(id)
{
    g_iLives[id] = 0
    g_iLastReviveTime[id] = 0
    g_bMenuActive[id] = false
}

public client_disconnect(id)
{
    g_bMenuActive[id] = false
}

public Cmd_Lives(id)
{
    if(!is_user_connected(id)) return PLUGIN_HANDLED
    
    if(get_user_team(id) == 3) {
        client_print_color(id, print_team_default, "^4[LIVES]^1 Это меню доступно только игрокам в команде!")
        return PLUGIN_HANDLED
    }
    
    if(!points_is_loaded(id)) {
        client_print_color(id, print_team_default, "^4[LIVES]^1 Данные ещё загружаются...")
        return PLUGIN_HANDLED
    }
    
    ShowLivesMenu(id)
    return PLUGIN_HANDLED
}

ShowLivesMenu(id)
{
    new szMenu[512], len
    new iPoints = points_get(id)
    
    // Получаем АКТУАЛЬНЫЕ значения из cvar прямо в момент открытия меню
    new iBuyPrice = get_pcvar_num(g_cvarBuyPrice)
    new iSellPrice = get_pcvar_num(g_cvarSellPrice)
    new iReviveTime = get_pcvar_num(g_cvarReviveTime)
    
    new iCurrentTime = get_systime()
    new iTimeLeft = iReviveTime - (iCurrentTime - g_iRoundStartTime)
    if(iTimeLeft < 0) iTimeLeft = 0
    
    new aliveT = GetAliveCount(1)
    new aliveCT = GetAliveCount(2)
    new bool:is1v1 = (aliveT == 1 && aliveCT == 1)
    new bool:canRevive = (iTimeLeft > 0) && !is1v1
    
    len = formatex(szMenu, charsmax(szMenu), "\yМеню жизней \r[\yЖизни: \r%d\y]\w^n^n", g_iLives[id])
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r1. \wВоскреситься^n")
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r2. \wКупить жизнь [\y%d \wочков\r]^n", iBuyPrice)
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r3. \wПродать жизнь [\y%d \wочков\r]^n", iSellPrice)
    
    if(is1v1) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "^n\yВоскрешение недоступно! Ситуация 1 на 1.")
    }
    else if(canRevive) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "^n\yВоскрешение доступно ещё \r%d сек.", iTimeLeft)
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "^n\yВоскрешение недоступно! Прошло более %d сек. с начала раунда.", iReviveTime)
    }
    
    // Битовая маска для клавиш 1, 2, 3 и 0 (Exit)
    show_menu(id, (1<<0)|(1<<1)|(1<<2)|(1<<9), szMenu, -1, "Lives Menu")
    g_bMenuActive[id] = true
}

public Menu_Handler(id, iKey)
{
    if(!g_bMenuActive[id]) return PLUGIN_HANDLED
    
    switch(iKey) {
        case 0: Cmd_Revive(id)
        case 1: Cmd_BuyLife(id)
        case 2: Cmd_SellLife(id)
        case 9: {
            g_bMenuActive[id] = false
            return PLUGIN_HANDLED
        }
    }
    
    if(is_user_connected(id)) {
        ShowLivesMenu(id) // Перерисовываем меню после действия
    }
    
    return PLUGIN_HANDLED
}

public Cmd_Revive(id)
{
    if(!is_user_connected(id) || !points_is_loaded(id)) return
    
    if(get_user_team(id) == 3) {
        client_print_color(id, print_team_default, "^4[LIVES]^1 Спектаторам нельзя воскрешаться!")
        return
    }
    
    if(is_user_alive(id)) {
        client_print_color(id, print_team_default, "^4[LIVES]^1 Вы должны быть мертвы для воскрешения!")
        return
    }
    
    new iCurrentTime = get_systime()
    new iTimeSinceRoundStart = iCurrentTime - g_iRoundStartTime
    new iReviveTime = get_pcvar_num(g_cvarReviveTime)
    
    if(iTimeSinceRoundStart > iReviveTime) {
        client_print_color(id, print_team_default, "^4[LIVES]^1 Воскрешение недоступно! Прошло более %d секунд с начала раунда.", iReviveTime)
        return
    }
    
    new aliveT = GetAliveCount(1)
    new aliveCT = GetAliveCount(2)
    if(aliveT == 1 && aliveCT == 1) {
        client_print_color(id, print_team_default, "^4[LIVES]^1 Воскрешение недоступно в ситуации 1 на 1!")
        return
    }
    
    if(g_iLives[id] <= 0) {
        client_print_color(id, print_team_default, "^4[LIVES]^1 У вас нет жизней!")
        return
    }
    
    g_iLives[id]--
    g_iLastReviveTime[id] = iCurrentTime
    client_print_color(id, print_team_default, "^4[LIVES]^1 Вы воскресли! Осталось жизней: %d", g_iLives[id])
    
    rg_round_respawn(id)
}

public Cmd_BuyLife(id)
{
    if(!is_user_connected(id) || !points_is_loaded(id)) return
    
    new iPoints = points_get(id)
    new iBuyPrice = get_pcvar_num(g_cvarBuyPrice) // Читаем актуальную цену
    
    if(iPoints < iBuyPrice) {
        client_print_color(id, print_team_default, "^4[LIVES]^1 Недостаточно очков! Нужно: %d, У вас: %d", iBuyPrice, iPoints)
        return
    }
    
    points_set(id, iPoints - iBuyPrice)
    g_iLives[id]++
    
    client_print_color(id, print_team_default, "^4[LIVES]^1 Вы купили жизнь за %d очков! Всего жизней: %d", iBuyPrice, g_iLives[id])
}

public Cmd_SellLife(id)
{
    if(!is_user_connected(id) || !points_is_loaded(id)) return
    
    if(g_iLives[id] <= 0) {
        client_print_color(id, print_team_default, "^4[LIVES]^1 Нечего продавать!")
        return
    }
    
    new iSellPrice = get_pcvar_num(g_cvarSellPrice) // Читаем актуальную цену
    new iCurrentPoints = points_get(id)
    
    g_iLives[id]--
    points_set(id, iCurrentPoints + iSellPrice)
    
    client_print_color(id, print_team_default, "^4[LIVES]^1 Вы продали жизнь за %d очков! Осталось жизней: %d", iSellPrice, g_iLives[id])
}

public Event_DeathMsg()
{
    new victim = read_data(2)
    
    if(!is_user_connected(victim)) return
    
    if(g_iLives[victim] <= 0) {
        client_print_color(victim, print_team_default, "^4[LIVES]^1 \rУ вас закончились жизни!")
    }
}

stock GetAliveCount(team)
{
    new count = 0
    for(new i = 1; i <= MAX_PLAYERS; i++) {
        if(is_user_alive(i) && get_user_team(i) == team)
            count++
    }
    return count
}

public plugin_cfg()
{
    // Проверяем, применились ли настройки из конфига
    new iBuy = get_pcvar_num(g_cvarBuyPrice)
    new iSell = get_pcvar_num(g_cvarSellPrice)
    if (iBuy == 50 || iSell == 25)
    {
        // Если значения по умолчанию – предупреждаем в лог
        log_amx("[LIVES] WARNING: buy/sell prices may not be loaded from config. Check order of loading.")
    }
}