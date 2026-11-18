#pragma semicolon 1

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <engine>
#include <fun>

#define PLUGIN "Trigger System Test"
#define VERSION "1.4"
#define AUTHOR "nb_team"

#define MAX_TRIGGERS 50
#define MAX_ACTIONS 9
#define TRIGGER_CLASSNAME "ent_test_trigger"

new const g_szSaveFile[] = "addons/amxmodx/configs/test_triggers.ini";

// Данные триггеров
new Float:g_vOrigin[MAX_TRIGGERS][3];
new Float:g_vMins[MAX_TRIGGERS][3];
new Float:g_vMaxs[MAX_TRIGGERS][3];
new g_iEntID[MAX_TRIGGERS];

// Битовые маски для действий (позволяют выбирать несколько действий)
new g_iEnterActions[MAX_TRIGGERS];
new g_iLeaveActions[MAX_TRIGGERS];
new g_iStayActions[MAX_TRIGGERS];

new Float:g_flStayInterval[MAX_TRIGGERS]; // Интервал для нахождения
new Float:g_flLastStayTime[33][MAX_TRIGGERS]; // Время последнего срабатывания

new bool:g_bPlayerInside[33][MAX_TRIGGERS];
new g_iTotalTriggers = 0;

// Меню игрока
new g_iEditingTrigger[33];
new bool:g_bShowTrigger[33]; // Показывать ли контур

new g_iSpriteLaser;

// Список доступных действий
new const g_szActions[MAX_ACTIONS][64] = {
    "Ничего не делать",
    "Выдать +25 HP",
    "Установить 100 HP",
    "Убить игрока",
    "Выдать гравитацию 400",
    "Сбросить гравитацию (800)",
    "Написать сообщение в чат",
    "Отнять 5 HP (для нахождения)",
    "Выдать +25 Брони"
};

public plugin_precache() {
    g_iSpriteLaser = precache_model("sprites/laserbeam.spr");
}

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    
    register_clcmd("say /trig", "Cmd_TrigMenu", ADMIN_LEVEL_H, "Меню триггеров");
    register_clcmd("say_team /trig", "Cmd_TrigMenu", ADMIN_LEVEL_H, "Меню триггеров");
    
    set_task(0.2, "Task_CheckTriggers", 1234, "", 0, "b");
    
    LoadTriggers();
}

// =====================================
//             ГЛАВНОЕ МЕНЮ
// =====================================
public Cmd_TrigMenu(id, level, cid) {
    if (!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    
    new menu = menu_create("\r[TRIG] \yМеню триггеров", "MainMenu_Handler");
    menu_additem(menu, "Создать триггер \y(в прицеле)", "1");
    menu_additem(menu, "Редактировать триггер \y(в прицеле)", "2");
    menu_additem(menu, "Список всех триггеров", "3");
    menu_additem(menu, "Удалить триггер \r(в прицеле)", "4");
    menu_additem(menu, "Сохранить все триггеры", "5");
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public MainMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);
    menu_destroy(menu);
    
    switch (iChoice) {
        case 1: CreateTriggerAtAim(id);
        case 2: { 
            new iIdx = GetAimedTriggerIndex(id);
            if (iIdx != -1) { g_iEditingTrigger[id] = iIdx; g_bShowTrigger[id] = true; ShowEditMenu(id); }
            else { client_print(id, print_chat, "[TRIG] Наведитесь на триггер!"); Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0); }
        }
        case 3: ShowTriggerListMenu(id);
        case 4: { 
            new iIdx = GetAimedTriggerIndex(id);
            if (iIdx != -1) DeleteTrigger(iIdx);
            else client_print(id, print_chat, "[TRIG] Наведитесь на триггер!");
            Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0);
        }
        case 5: { SaveTriggers(); Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0); }
    }
    return PLUGIN_HANDLED;
}

ShowTriggerListMenu(id) {
    new menu = menu_create("\r[TRIG] \yСписок триггеров", "TriggerList_Handler");
    new szItem[64], szId[8];
    
    if (g_iTotalTriggers == 0) {
        menu_destroy(menu);
        client_print(id, print_chat, "[TRIG] На карте нет триггеров!");
        Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0);
        return;
    }
    
    for (new i = 0; i < g_iTotalTriggers; i++) {
        formatex(szItem, charsmax(szItem), "Триггер [%d]", i);
        num_to_str(i, szId, charsmax(szId));
        menu_additem(menu, szItem, szId);
    }
    
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public TriggerList_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    g_iEditingTrigger[id] = str_to_num(data);
    g_bShowTrigger[id] = true;
    menu_destroy(menu);
    ShowEditMenu(id);
    return PLUGIN_HANDLED;
}

CreateTriggerAtAim(id) {
    if (g_iTotalTriggers >= MAX_TRIGGERS) {
        client_print(id, print_chat, "[TRIG] Достигнут лимит триггеров!");
        return;
    }
    
    new iOrigin[3], Float:vOrigin[3];
    get_user_origin(id, iOrigin, 3);
    IVecFVec(iOrigin, vOrigin);
    
    new iIdx = g_iTotalTriggers;
    g_vOrigin[iIdx][0] = vOrigin[0];
    g_vOrigin[iIdx][1] = vOrigin[1];
    g_vOrigin[iIdx][2] = vOrigin[2];
    
    for(new j=0; j<3; j++) {
        g_vMins[iIdx][j] = -50.0;
        g_vMaxs[iIdx][j] = 50.0;
    }
    
    g_iEnterActions[iIdx] = 0;
    g_iLeaveActions[iIdx] = 0;
    g_iStayActions[iIdx] = 0;
    g_flStayInterval[iIdx] = 1.0; // По умолчанию 1 секунда
    
    SpawnTriggerEntity(iIdx);
    g_iTotalTriggers++;
    
    client_print(id, print_chat, "[TRIG] Триггер %d создан.", iIdx);
}

SpawnTriggerEntity(iIdx) {
    new iEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    set_pev(iEnt, pev_classname, TRIGGER_CLASSNAME);
    set_pev(iEnt, pev_origin, g_vOrigin[iIdx]);
    set_pev(iEnt, pev_solid, SOLID_TRIGGER);
    set_pev(iEnt, pev_movetype, MOVETYPE_NONE);
    engfunc(EngFunc_SetSize, iEnt, g_vMins[iIdx], g_vMaxs[iIdx]);
    g_iEntID[iIdx] = iEnt;
}

DeleteTrigger(iIdx) {
    if (pev_valid(g_iEntID[iIdx])) engfunc(EngFunc_RemoveEntity, g_iEntID[iIdx]);
    
    for (new i = iIdx; i < g_iTotalTriggers - 1; i++) {
        g_vOrigin[i] = g_vOrigin[i+1];
        g_vMins[i] = g_vMins[i+1];
        g_vMaxs[i] = g_vMaxs[i+1];
        g_iEntID[i] = g_iEntID[i+1];
        g_iEnterActions[i] = g_iEnterActions[i+1];
        g_iLeaveActions[i] = g_iLeaveActions[i+1];
        g_iStayActions[i] = g_iStayActions[i+1];
        g_flStayInterval[i] = g_flStayInterval[i+1];
    }
    g_iTotalTriggers--;
    client_print(0, print_chat, "[TRIG] Триггер удален.");
}

// =====================================
//          МЕНЮ РЕДАКТИРОВАНИЯ
// =====================================
ShowEditMenu(id) {
    new iIdx = g_iEditingTrigger[id];
    if (iIdx < 0 || iIdx >= g_iTotalTriggers) { client_print(id, print_chat, "[TRIG] Ошибка!"); return; }
    
    new szTitle[256];
    formatex(szTitle, charsmax(szTitle), "\r[TRIG] \yРедактор триггера [%d]", iIdx);
    new menu = menu_create(szTitle, "EditMenu_Handler");
    
    new szEnter[128], szLeave[128], szStay[128], szInterval[64], szVis[64];
    formatex(szEnter, charsmax(szEnter), "Действия ВХОДА: \y[%d шт]", CountBits(g_iEnterActions[iIdx]));
    formatex(szLeave, charsmax(szLeave), "Действия ВЫХОДА: \y[%d шт]", CountBits(g_iLeaveActions[iIdx]));
    formatex(szStay, charsmax(szStay), "Действия НАХОЖДЕНИЯ: \y[%d шт]", CountBits(g_iStayActions[iIdx]));
    formatex(szInterval, charsmax(szInterval), "Интервал нахождения: \y%.1f сек", g_flStayInterval[iIdx]);
    
    if (g_bShowTrigger[id]) copy(szVis, charsmax(szVis), "Скрыть триггер \r(визуализация)");
    else copy(szVis, charsmax(szVis), "Показать триггер \y(визуализация)");
    
    menu_additem(menu, szEnter, "1");
    menu_additem(menu, szLeave, "2");
    menu_additem(menu, szStay, "3");
    menu_additem(menu, szInterval, "4");
    menu_additem(menu, "Изменить размер \y(X, Y, Z)", "5");
    menu_additem(menu, "Переместить в прицел", "6");
    menu_additem(menu, szVis, "7");
    menu_additem(menu, "Удалить триггер \r(с подтверждением)", "8");
    menu_additem(menu, "Вернуться назад", "9");
    
    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public EditMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new iIdx = g_iEditingTrigger[id];
    if (iIdx < 0 || iIdx >= g_iTotalTriggers) { menu_destroy(menu); return PLUGIN_HANDLED; }
    
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);
    
    switch (iChoice) {
        case 1: { menu_destroy(menu); ShowActionMenu(id, 1); return PLUGIN_HANDLED; }
        case 2: { menu_destroy(menu); ShowActionMenu(id, 2); return PLUGIN_HANDLED; }
        case 3: { menu_destroy(menu); ShowActionMenu(id, 3); return PLUGIN_HANDLED; }
        case 4: {
            if (g_flStayInterval[iIdx] == 0.5) g_flStayInterval[iIdx] = 1.0;
            else if (g_flStayInterval[iIdx] == 1.0) g_flStayInterval[iIdx] = 2.0;
            else if (g_flStayInterval[iIdx] == 2.0) g_flStayInterval[iIdx] = 5.0;
            else g_flStayInterval[iIdx] = 0.5;
        }
        case 5: { menu_destroy(menu); ShowSizeMenu(id); return PLUGIN_HANDLED; }
        case 6: {
            new iOrigin[3]; get_user_origin(id, iOrigin, 3);
            IVecFVec(iOrigin, g_vOrigin[iIdx]);
            if (pev_valid(g_iEntID[iIdx])) set_pev(g_iEntID[iIdx], pev_origin, g_vOrigin[iIdx]);
        }
        case 7: g_bShowTrigger[id] = !g_bShowTrigger[id];
        case 8: { menu_destroy(menu); ShowDeleteConfirmMenu(id); return PLUGIN_HANDLED; }
        case 9: { menu_destroy(menu); Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0); return PLUGIN_HANDLED; }
    }
    menu_destroy(menu);
    ShowEditMenu(id);
    return PLUGIN_HANDLED;
}

// =====================================
//          МЕНЮ ПОДТВЕРЖДЕНИЯ УДАЛЕНИЯ
// =====================================
ShowDeleteConfirmMenu(id) {
    new menu = menu_create("\r[TRIG] \yУдалить этот триггер?", "DeleteConfirm_Handler");
    menu_additem(menu, "Да, удалить", "1");
    menu_additem(menu, "Нет, отменить", "2");
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public DeleteConfirm_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowEditMenu(id); return PLUGIN_HANDLED; }
    new iIdx = g_iEditingTrigger[id];
    
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);
    menu_destroy(menu);
    
    if (iChoice == 1) {
        if (iIdx >= 0 && iIdx < g_iTotalTriggers) DeleteTrigger(iIdx);
        Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0);
    } else {
        ShowEditMenu(id);
    }
    return PLUGIN_HANDLED;
}

// =====================================
//          МЕНЮ РАЗМЕРОВ (X, Y, Z)
// =====================================
ShowSizeMenu(id) {
    new iIdx = g_iEditingTrigger[id];
    new szTitle[256];
    formatex(szTitle, charsmax(szTitle), "\r[TRIG] \yРазмер триггера [%d]^n\dX: %.0f | Y: %.0f | Z: %.0f", 
        iIdx, g_vMaxs[iIdx][0]*2.0, g_vMaxs[iIdx][1]*2.0, g_vMaxs[iIdx][2]*2.0);
    
    new menu = menu_create(szTitle, "SizeMenu_Handler");
    
    menu_additem(menu, "+ Ширина (X)", "0");
    menu_additem(menu, "- Ширина (X)", "1");
    menu_additem(menu, "+ Длина (Y)", "2");
    menu_additem(menu, "- Длина (Y)", "3");
    menu_additem(menu, "+ Высота (Z)", "4");
    menu_additem(menu, "- Высота (Z)", "5");
    menu_additem(menu, "Назад", "6");
    
    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public SizeMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowEditMenu(id); return PLUGIN_HANDLED; }
    new iIdx = g_iEditingTrigger[id];
    if (iIdx < 0 || iIdx >= g_iTotalTriggers) { menu_destroy(menu); return PLUGIN_HANDLED; }
    
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);
    
    if (iChoice >= 0 && iChoice <= 5) {
        new iAxis = iChoice / 2; // 0=X, 1=Y, 2=Z
        new iDir = (iChoice % 2 == 0) ? 1 : -1; // 1=Увеличить, -1=Уменьшить
        
        g_vMins[iIdx][iAxis] -= (10.0 * iDir);
        g_vMaxs[iIdx][iAxis] += (10.0 * iDir);
        
        if (g_vMaxs[iIdx][iAxis] - g_vMins[iIdx][iAxis] < 10.0) {
            g_vMaxs[iIdx][iAxis] = 5.0;
            g_vMins[iIdx][iAxis] = -5.0;
        }
        
        if (pev_valid(g_iEntID[iIdx])) engfunc(EngFunc_SetSize, g_iEntID[iIdx], g_vMins[iIdx], g_vMaxs[iIdx]);
    } else if (iChoice == 6) {
        menu_destroy(menu);
        ShowEditMenu(id);
        return PLUGIN_HANDLED;
    }
    
    menu_destroy(menu);
    ShowSizeMenu(id);
    return PLUGIN_HANDLED;
}

// =====================================
//          МЕНЮ ВЫБОРА ДЕЙСТВИЙ (С ГАЛОЧКААМИ)
// =====================================
ShowActionMenu(id, iEventType) {
    new iIdx = g_iEditingTrigger[id];
    new szTitle[128], szEvent[16];
    
    if (iEventType == 1) copy(szEvent, charsmax(szEvent), "Вход");
    else if (iEventType == 2) copy(szEvent, charsmax(szEvent), "Выход");
    else copy(szEvent, charsmax(szEvent), "Нахождение");
    
    formatex(szTitle, charsmax(szTitle), "\r[TRIG] \yДействия (%s)^n\dОтметьте нужные:", szEvent);
    new menu = menu_create(szTitle, "ActionMenu_Handler");
    
    new szItem[64], szInfo[8];
    new iMask;
    if (iEventType == 1) iMask = g_iEnterActions[iIdx];
    else if (iEventType == 2) iMask = g_iLeaveActions[iIdx];
    else iMask = g_iStayActions[iIdx];
    
    for (new i = 0; i < MAX_ACTIONS; i++) {
        if (iMask & (1 << i)) formatex(szItem, charsmax(szItem), "\y[X] \w%s", g_szActions[i]);
        else formatex(szItem, charsmax(szItem), "\r[ ] \w%s", g_szActions[i]);
        
        num_to_str(iEventType * 100 + i, szInfo, charsmax(szInfo));
        menu_additem(menu, szItem, szInfo);
    }
    
    menu_additem(menu, "Готово", "9999");
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public ActionMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowEditMenu(id); return PLUGIN_HANDLED; }
    new iIdx = g_iEditingTrigger[id];
    if (iIdx < 0 || iIdx >= g_iTotalTriggers) { menu_destroy(menu); return PLUGIN_HANDLED; }
    
    new data[8], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iEncodedData = str_to_num(data);
    
    if (iEncodedData == 9999) {
        menu_destroy(menu);
        ShowEditMenu(id);
        return PLUGIN_HANDLED;
    }
    
    new iEventType = iEncodedData / 100;
    new iActionID = iEncodedData % 100;
    new iBit = (1 << iActionID);
    
    if (iEventType == 1) g_iEnterActions[iIdx] ^= iBit;
    else if (iEventType == 2) g_iLeaveActions[iIdx] ^= iBit;
    else g_iStayActions[iIdx] ^= iBit;
    
    menu_destroy(menu);
    ShowActionMenu(id, iEventType);
    return PLUGIN_HANDLED;
}

// =====================================
//          ЛОГИКА ТРИГГЕРОВ
// =====================================
public Task_CheckTriggers() {
    new Float:vPlayerOrigin[3], Float:vMins[3], Float:vMaxs[3], Float:flCurrentTime;
    flCurrentTime = get_gametime();
    
    for (new i = 0; i < g_iTotalTriggers; i++) {
        if (!pev_valid(g_iEntID[i])) continue;
        
        for (new p = 1; p <= 32; p++) {
            if (!is_user_alive(p)) continue;
            
            pev(p, pev_origin, vPlayerOrigin);
            
            for(new j=0; j<3; j++) {
                vMins[j] = g_vOrigin[i][j] + g_vMins[i][j];
                vMaxs[j] = g_vOrigin[i][j] + g_vMaxs[i][j];
            }
            
            new bool:bInside = false;
            if (vPlayerOrigin[0] >= vMins[0] && vPlayerOrigin[0] <= vMaxs[0] &&
                vPlayerOrigin[1] >= vMins[1] && vPlayerOrigin[1] <= vMaxs[1] &&
                vPlayerOrigin[2] >= vMins[2] && vPlayerOrigin[2] <= vMaxs[2]) {
                bInside = true;
            }
            
            if (bInside && !g_bPlayerInside[p][i]) {
                g_bPlayerInside[p][i] = true;
                g_flLastStayTime[p][i] = flCurrentTime; // Сброс таймера при входе
                ExecuteActions(p, i, g_iEnterActions[i]);
            } else if (!bInside && g_bPlayerInside[p][i]) {
                g_bPlayerInside[p][i] = false;
                ExecuteActions(p, i, g_iLeaveActions[i]);
            } else if (bInside && g_bPlayerInside[p][i]) {
                // Игрок находится внутри
                if (g_iStayActions[i] != 0 && (flCurrentTime - g_flLastStayTime[p][i] >= g_flStayInterval[i])) {
                    g_flLastStayTime[p][i] = flCurrentTime;
                    ExecuteActions(p, i, g_iStayActions[i]);
                }
            }
        }
        
        // Отрисовка контура
        for (new p = 1; p <= 32; p++) {
            if (g_iEditingTrigger[p] == i && g_bShowTrigger[p] && is_user_connected(p)) {
                DrawBox(g_vOrigin[i], g_vMins[i], g_vMaxs[i], 0, 255, 0);
            }
        }
    }
}

ExecuteActions(id, iTriggerID, iActionsMask) {
    for (new i = 0; i < MAX_ACTIONS; i++) {
        if (iActionsMask & (1 << i)) {
            ExecuteSingleAction(id, iTriggerID, i);
        }
    }
}

ExecuteSingleAction(id, iTriggerID, iActionID) {
    switch (iActionID) {
        case 0: { /* Ничего */ }
        case 1: { 
            new hp = get_user_health(id) + 25;
            set_user_health(id, hp);
            client_print(id, print_chat, "[TRIG] +%d HP (Триггер %d)", 25, iTriggerID);
        }
        case 2: { 
            set_user_health(id, 100);
            client_print(id, print_chat, "[TRIG] HP установлено на 100 (Триггер %d)", iTriggerID);
        }
        case 3: { 
            user_kill(id);
            client_print(id, print_chat, "[TRIG] Вы убиты триггером %d", iTriggerID);
        }
        case 4: { 
            set_user_gravity(id, 0.5);
            client_print(id, print_chat, "[TRIG] Гравитация 400 (Триггер %d)", iTriggerID);
        }
        case 5: { 
            set_user_gravity(id, 1.0);
            client_print(id, print_chat, "[TRIG] Гравитация сброшена (Триггер %d)", iTriggerID);
        }
        case 6: { 
            client_print(id, print_chat, "[TRIG] Вы задели зону триггера %d", iTriggerID);
        }
        case 7: { 
            new hp = get_user_health(id) - 5;
            if (hp < 1) hp = 1;
            set_user_health(id, hp);
            client_print(id, print_chat, "[TRIG] -5 HP (Триггер %d)", iTriggerID);
        }
        case 8: { 
            new ap = get_user_armor(id) + 25;
            set_user_armor(id, ap);
            client_print(id, print_chat, "[TRIG] +25 Броня (Триггер %d)", iTriggerID);
        }
    }
}

// =====================================
//          ОТРИСОВКА И ВСПОМОГАТЕЛЬНОЕ
// =====================================
DrawBox(Float:vCenter[3], Float:vMins[3], Float:vMaxs[3], red, green, blue) {
    new Float:vCorners[8][3];
    for(new i=0; i<8; i++) {
        if (i & 1) vCorners[i][0] = vCenter[0] + vMaxs[0];
        else vCorners[i][0] = vCenter[0] + vMins[0];
        
        if (i & 2) vCorners[i][1] = vCenter[1] + vMaxs[1];
        else vCorners[i][1] = vCenter[1] + vMins[1];
        
        if (i & 4) vCorners[i][2] = vCenter[2] + vMaxs[2];
        else vCorners[i][2] = vCenter[2] + vMins[2];
    }
    
    DrawLine(vCorners[0], vCorners[1], red, green, blue);
    DrawLine(vCorners[0], vCorners[2], red, green, blue);
    DrawLine(vCorners[0], vCorners[4], red, green, blue);
    DrawLine(vCorners[1], vCorners[3], red, green, blue);
    DrawLine(vCorners[1], vCorners[5], red, green, blue);
    DrawLine(vCorners[2], vCorners[3], red, green, blue);
    DrawLine(vCorners[2], vCorners[6], red, green, blue);
    DrawLine(vCorners[3], vCorners[7], red, green, blue);
    DrawLine(vCorners[4], vCorners[5], red, green, blue);
    DrawLine(vCorners[4], vCorners[6], red, green, blue);
    DrawLine(vCorners[5], vCorners[7], red, green, blue);
    DrawLine(vCorners[6], vCorners[7], red, green, blue);
}

DrawLine(Float:vStart[3], Float:vEnd[3], red, green, blue) {
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMPOINTS);
    engfunc(EngFunc_WriteCoord, vStart[0]);
    engfunc(EngFunc_WriteCoord, vStart[1]);
    engfunc(EngFunc_WriteCoord, vStart[2]);
    engfunc(EngFunc_WriteCoord, vEnd[0]);
    engfunc(EngFunc_WriteCoord, vEnd[1]);
    engfunc(EngFunc_WriteCoord, vEnd[2]);
    write_short(g_iSpriteLaser);
    write_byte(0); 
    write_byte(0); 
    write_byte(2); 
    write_byte(5); 
    write_byte(0); 
    write_byte(red);
    write_byte(green);
    write_byte(blue);
    write_byte(200); 
    write_byte(0); 
    message_end();
}

// Идеальное определение триггера в прицеле
GetAimedTriggerIndex(id) {
    new iOrigin[3], Float:vAimEnd[3];
    get_user_origin(id, iOrigin, 3); // 3 = точка конца прицела
    IVecFVec(iOrigin, vAimEnd);
    
    new iBest = -1;
    new Float:flBestDist = 9999.0;
    
    for (new i = 0; i < g_iTotalTriggers; i++) {
        // 1. Проверяем, смотрит ли игрок прямо внутрь триггера
        new Float:vMins[3], Float:vMaxs[3];
        for(new j=0; j<3; j++) {
            vMins[j] = g_vOrigin[i][j] + g_vMins[i][j];
            vMaxs[j] = g_vOrigin[i][j] + g_vMaxs[i][j];
        }
        if (vAimEnd[0] >= vMins[0] && vAimEnd[0] <= vMaxs[0] &&
            vAimEnd[1] >= vMins[1] && vAimEnd[1] <= vMaxs[1] &&
            vAimEnd[2] >= vMins[2] && vAimEnd[2] <= vMaxs[2]) {
            return i; // Точно попали в габариты
        }
        
        // 2. Запасной вариант: ищем ближайший центр триггера к лучу (в радиусе 150)
        new Float:flDist = get_distance_f(vAimEnd, g_vOrigin[i]);
        if (flDist < 150.0 && flDist < flBestDist) {
            flBestDist = flDist;
            iBest = i;
        }
    }
    return iBest;
}

stock CountBits(mask) {
    new count = 0;
    for(new i=0; i<MAX_ACTIONS; i++) {
        if (mask & (1 << i)) count++;
    }
    return count;
}

// =====================================
//          СОХРАНЕНИЕ И ЗАГРУЗКА
// =====================================
SaveTriggers() {
    if (file_exists(g_szSaveFile)) delete_file(g_szSaveFile);
    new f = fopen(g_szSaveFile, "wt");
    if (!f) return;
    
    new szBuffer[256];
    for (new i = 0; i < g_iTotalTriggers; i++) {
        formatex(szBuffer, charsmax(szBuffer), "^"%f %f %f^" ^"%f %f %f^" ^"%f %f %f^" ^"%d^" ^"%d^" ^"%d^" ^"%f^"^n", 
            g_vOrigin[i][0], g_vOrigin[i][1], g_vOrigin[i][2],
            g_vMins[i][0], g_vMins[i][1], g_vMins[i][2],
            g_vMaxs[i][0], g_vMaxs[i][1], g_vMaxs[i][2],
            g_iEnterActions[i], g_iLeaveActions[i], g_iStayActions[i], g_flStayInterval[i]);
        fputs(f, szBuffer);
    }
    fclose(f);
    client_print(0, print_chat, "[TRIG] Триггеры сохранены (%d шт).", g_iTotalTriggers);
}

LoadTriggers() {
    if (!file_exists(g_szSaveFile)) return;
    new f = fopen(g_szSaveFile, "rt");
    if (!f) return;
    
    new szLine[256], szOrigin[64], szMins[64], szMaxs[64], szEnter[16], szLeave[16], szStay[16], szInterval[16];
    
    while (!feof(f) && g_iTotalTriggers < MAX_TRIGGERS) {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);
        if (!szLine[0] || szLine[0] == ';') continue;
        
        parse(szLine, szOrigin, charsmax(szOrigin), szMins, charsmax(szMins), szMaxs, charsmax(szMaxs), 
              szEnter, charsmax(szEnter), szLeave, charsmax(szLeave), szStay, charsmax(szStay), szInterval, charsmax(szInterval));
        
        parse_origin(szOrigin, g_vOrigin[g_iTotalTriggers]);
        parse_origin(szMins, g_vMins[g_iTotalTriggers]);
        parse_origin(szMaxs, g_vMaxs[g_iTotalTriggers]);
        g_iEnterActions[g_iTotalTriggers] = str_to_num(szEnter);
        g_iLeaveActions[g_iTotalTriggers] = str_to_num(szLeave);
        g_iStayActions[g_iTotalTriggers] = str_to_num(szStay);
        g_flStayInterval[g_iTotalTriggers] = str_to_float(szInterval);
        
        SpawnTriggerEntity(g_iTotalTriggers);
        g_iTotalTriggers++;
    }
    fclose(f);
}

stock parse_origin(const szStr[], Float:vOut[3]) {
    new szX[16], szY[16], szZ[16];
    parse(szStr, szX, charsmax(szX), szY, charsmax(szY), szZ, charsmax(szZ));
    vOut[0] = str_to_float(szX); 
    vOut[1] = str_to_float(szY); 
    vOut[2] = str_to_float(szZ);
}

stock xs_vec_add(const Float:vec1[], const Float:vec2[], Float:out[]) { out[0]=vec1[0]+vec2[0]; out[1]=vec1[1]+vec2[1]; out[2]=vec1[2]+vec2[2]; }