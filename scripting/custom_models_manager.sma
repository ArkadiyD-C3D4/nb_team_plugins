#pragma semicolon 1

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <engine>
#include <hamsandwich>
#include <fun>
#include <xs>

#define PLUGIN "Custom Models & Triggers Pro"
#define VERSION "7.0"
#define AUTHOR "nb_team"

#define MAX_MODELS 100
#define MAX_SPAWNED 200
#define MAX_TRIGGERS 200
#define MAX_PATH_POINTS 10
#define MAX_ACTIONS 9
#define MAX_TEMPLATES 50
#define MODEL_CLASSNAME "ent_custom_model"
#define TRIGGER_CLASSNAME "ent_custom_trigger"
#define MODELS_FOLDER "models/custom"

new g_szMapName[32];
new g_szModelsFile[128];
new g_szTriggersFile[128];
new const g_szTemplatesFile[] = "addons/amxmodx/configs/custom_templates.ini";

new g_szModelList[MAX_MODELS][128];
new g_iTotalModels = 0;

new g_szModelPath[MAX_SPAWNED][128];
new Float:g_vOrigin[MAX_SPAWNED][3];
new Float:g_vAngles[MAX_SPAWNED][3];
new Float:g_flScale[MAX_SPAWNED];
new g_iSequence[MAX_SPAWNED];
new g_iMaxSeq[MAX_SPAWNED];
new Float:g_flFramerate[MAX_SPAWNED];
new bool:g_bIsMoving[MAX_SPAWNED];
new Float:g_vPath[MAX_SPAWNED][MAX_PATH_POINTS][3];
new g_iPathCount[MAX_SPAWNED];
new g_iCurPath[MAX_SPAWNED];
new g_iRenderMode[MAX_SPAWNED];
new Float:g_flRenderAmt[MAX_SPAWNED];
new Float:g_vRenderColor[MAX_SPAWNED][3];
new g_iEntityID[MAX_SPAWNED];
new g_iHealth[MAX_SPAWNED];
new g_iTotalSpawned = 0;
new bool:g_bIsDead[MAX_SPAWNED];
new bool:g_bSolid[MAX_SPAWNED];

new Float:g_vTrigOrigin[MAX_TRIGGERS][3];
new Float:g_vTrigMins[MAX_TRIGGERS][3];
new Float:g_vTrigMaxs[MAX_TRIGGERS][3];
new g_iTrigEntID[MAX_TRIGGERS];
new g_iTrigModelID[MAX_TRIGGERS];
new g_iTrigEnterActions[MAX_TRIGGERS];
new g_iTrigLeaveActions[MAX_TRIGGERS];
new g_iTrigStayActions[MAX_TRIGGERS];
new Float:g_flTrigStayInterval[MAX_TRIGGERS];
new bool:g_bTrigVisible[MAX_TRIGGERS];
new bool:g_bTrigSolid[MAX_TRIGGERS];
new bool:g_bPlayerInTrigger[33][MAX_TRIGGERS];
new Float:g_flLastStayTime[33][MAX_TRIGGERS];
new g_iTotalTriggers = 0;

new g_szTplName[MAX_TEMPLATES][64];
new g_szTplData[MAX_TEMPLATES][1024];
new g_iTotalTemplates = 0;

new g_iTargetIdx[33];
new g_iEditingTrig[33];
new g_iEditMode[33];
new g_iTrigEditMode[33];
new Float:g_flInterval[33];
new Float:g_flTrigInterval[33];
new bool:g_bShowTrigger[33];
new g_iChangingModelFor[33];
new g_iModelTrigPage[33];

new g_iSpriteLaser;

new g_szActionNames[MAX_ACTIONS][64];
new g_iActionCount = 0;

public plugin_precache() {
    ScanForModels();
    g_iSpriteLaser = precache_model("sprites/laserbeam.spr");
}

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    set_cvar_num("sv_allowdownload", 1);

    get_mapname(g_szMapName, charsmax(g_szMapName));
    formatex(g_szModelsFile, charsmax(g_szModelsFile), "addons/amxmodx/configs/custom_models_%s.ini", g_szMapName);
    formatex(g_szTriggersFile, charsmax(g_szTriggersFile), "addons/amxmodx/configs/custom_triggers_%s.ini", g_szMapName);

    register_clcmd("say /cm", "Cmd_ModelMenu", ADMIN_LEVEL_H, "Менеджер моделей");
    register_clcmd("say_team /cm", "Cmd_ModelMenu", ADMIN_LEVEL_H, "Менеджер моделей");
    register_clcmd("say /trig", "Cmd_TrigMenu", ADMIN_LEVEL_H, "Менеджер триггеров");
    register_clcmd("say_team /trig", "Cmd_TrigMenu", ADMIN_LEVEL_H, "Менеджер триггеров");
    register_clcmd("say /sethp", "Cmd_SetCustomHP", ADMIN_LEVEL_H, "<значение> - Установить HP");

    register_event("HLTV", "Event_RoundStart", "a", "1=0", "2=0");

    copy(g_szActionNames[0], charsmax(g_szActionNames[]), "Ничего не делать");
    copy(g_szActionNames[1], charsmax(g_szActionNames[]), "Выдать +25 HP");
    copy(g_szActionNames[2], charsmax(g_szActionNames[]), "Установить 100 HP");
    copy(g_szActionNames[3], charsmax(g_szActionNames[]), "Убить игрока");
    copy(g_szActionNames[4], charsmax(g_szActionNames[]), "Выдать гравитацию 400");
    copy(g_szActionNames[5], charsmax(g_szActionNames[]), "Сбросить гравитацию (800)");
    copy(g_szActionNames[6], charsmax(g_szActionNames[]), "Написать сообщение в чат");
    copy(g_szActionNames[7], charsmax(g_szActionNames[]), "Отнимать по 5 HP");
    copy(g_szActionNames[8], charsmax(g_szActionNames[]), "Выдать +25 Брони");
    g_iActionCount = 9;

    RegisterHam(Ham_TakeDamage, "info_target", "Fwd_TakeDamage_Pre", 0);
    set_task(0.1, "Task_UpdateSystem", 1234, "", 0, "b");

    for (new i = 0; i < 33; i++) {
        g_iTargetIdx[i] = -1;
        g_iEditingTrig[i] = -1;
        g_iChangingModelFor[i] = -1;
        g_flInterval[i] = 1.0;
        g_flTrigInterval[i] = 10.0;
    }

    LoadModels();
    LoadTriggers();
    LoadTemplates();
}

public Event_RoundStart() {
    for (new i = 0; i < g_iTotalSpawned; i++) {
        if (g_bIsDead[i] && pev_valid(g_iEntityID[i])) {
            g_bIsDead[i] = false;
            if (g_iHealth[i] <= 0) g_iHealth[i] = 100;

            set_pev(g_iEntityID[i], pev_takedamage, g_iHealth[i] > 0 ? DAMAGE_AIM : DAMAGE_NO);
            set_pev(g_iEntityID[i], pev_effects, 0);
            set_pev(g_iEntityID[i], pev_rendermode, g_iRenderMode[i]);
            set_pev(g_iEntityID[i], pev_renderamt, g_flRenderAmt[i]);
            set_pev(g_iEntityID[i], pev_rendercolor, g_vRenderColor[i]);

            if (!g_bIsMoving[i]) {
                set_pev(g_iEntityID[i], pev_solid, g_bSolid[i] ? SOLID_BBOX : SOLID_NOT);
            }

            // Принудительно обновляем bbox после воскрешения,
            // чтобы движок пересчитал видимость
            new Float:fMins[3], Float:fMaxs[3];
            pev(g_iEntityID[i], pev_mins, fMins);
            pev(g_iEntityID[i], pev_maxs, fMaxs);
            engfunc(EngFunc_SetSize, g_iEntityID[i], fMins, fMaxs);

            // Сдвигаем на микро-единицу чтобы движок гарантированно
            // пересчитал PVS (область видимости)
            new Float:vTmp[3];
            pev(g_iEntityID[i], pev_origin, vTmp);
            vTmp[2] += 0.01;
            set_pev(g_iEntityID[i], pev_origin, vTmp);
            vTmp[2] -= 0.01;
            set_pev(g_iEntityID[i], pev_origin, vTmp);
        }
    }
}
ScanForModels() {
    g_iTotalModels = 0;
    new szDir[128], szFile[128], szFullPath[256];
    copy(szDir, charsmax(szDir), MODELS_FOLDER);
    new iDir = open_dir(szDir, szFile, charsmax(szFile));

    if (!iDir) {
        precache_model("models/w_c4.mdl");
        return;
    }

    while (next_file(iDir, szFile, charsmax(szFile))) {
        if (szFile[0] == '.') continue;
        new iLen = strlen(szFile);
        if (iLen > 4 && equali(szFile[iLen - 4], ".mdl")) {
            if (g_iTotalModels < MAX_MODELS) {
                formatex(szFullPath, charsmax(szFullPath), "%s/%s", szDir, szFile);
                precache_model(szFullPath);
                copy(g_szModelList[g_iTotalModels], charsmax(g_szModelList[]), szFullPath);
                g_iTotalModels++;
            }
        }
    }
    close_dir(iDir);
    if (g_iTotalModels == 0) precache_model("models/w_c4.mdl");
}

stock UTIL_GetModelSeqCount(const szModel[]) {
    return 200;
}

public Fwd_TakeDamage_Pre(iEnt, inflictor, attacker, Float:damage, bits) {
    if (!pev_valid(iEnt)) return HAM_IGNORED;
    new szClass[32];
    pev(iEnt, pev_classname, szClass, charsmax(szClass));
    if (!equal(szClass, MODEL_CLASSNAME)) return HAM_IGNORED;

    new iIdx = GetModelIndexByEnt(iEnt);
    if (iIdx == -1 || g_iHealth[iIdx] <= 0 || g_bIsDead[iIdx]) return HAM_IGNORED;

    g_iHealth[iIdx] -= floatround(damage);

    if (g_iHealth[iIdx] <= 0) {
        client_print(attacker, print_chat, "[CM] Модель %d уничтожена! (Оживет в след. раунде)", iIdx);
        g_bIsDead[iIdx] = true;
        set_pev(iEnt, pev_takedamage, DAMAGE_NO);
        set_pev(iEnt, pev_solid, SOLID_NOT);
        set_pev(iEnt, pev_effects, pev(iEnt, pev_effects) | EF_NODRAW);
    } else {
        client_print(attacker, print_chat, "[CM] HP модели %d: %d", iIdx, g_iHealth[iIdx]);
        set_pev(iEnt, pev_rendermode, kRenderTransTexture);
        set_pev(iEnt, pev_renderamt, 200.0);
        set_pev(iEnt, pev_rendercolor, Float:{255.0, 0.0, 0.0});
        set_task(0.2, "ResetRender", iIdx);
    }
    return HAM_SUPERCEDE;
}

public ResetRender(iIdx) {
    if (iIdx >= 0 && iIdx < g_iTotalSpawned && pev_valid(g_iEntityID[iIdx]) && !g_bIsDead[iIdx]) {
        set_pev(g_iEntityID[iIdx], pev_rendermode, g_iRenderMode[iIdx]);
        set_pev(g_iEntityID[iIdx], pev_renderamt, g_flRenderAmt[iIdx]);
        set_pev(g_iEntityID[iIdx], pev_rendercolor, g_vRenderColor[iIdx]);
    }
}

public Cmd_SetCustomHP(id, level, cid) {
    if (!cmd_access(id, level, cid, 2)) return PLUGIN_HANDLED;

    new iIdx = g_iTargetIdx[id];
    if (iIdx < 0 || iIdx >= g_iTotalSpawned || !pev_valid(g_iEntityID[iIdx])) {
        client_print(id, print_chat, "[CM] Сначала выберите модель для редактирования!");
        return PLUGIN_HANDLED;
    }

    new szHP[16];
    read_argv(1, szHP, charsmax(szHP));
    new hp = str_to_num(szHP);

    if (hp > 0) {
        g_iHealth[iIdx] = hp;
        g_bIsDead[iIdx] = false;
        set_pev(g_iEntityID[iIdx], pev_takedamage, DAMAGE_AIM);
        set_pev(g_iEntityID[iIdx], pev_effects, 0);
        set_pev(g_iEntityID[iIdx], pev_health, float(hp));
        client_print(id, print_chat, "[CM] Модели [%d] установлено %d HP.", iIdx, hp);
    } else if (hp == 0) {
        g_iHealth[iIdx] = 0;
        set_pev(g_iEntityID[iIdx], pev_takedamage, DAMAGE_NO);
        client_print(id, print_chat, "[CM] Модель [%d] стала бессмертной (0 HP).", iIdx);
    } else {
        client_print(id, print_chat, "[CM] HP не может быть отрицательным.");
    }

    UpdateModel(iIdx);
    return PLUGIN_HANDLED;
}

public Cmd_ModelMenu(id, level, cid) {
    if (!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    g_iChangingModelFor[id] = -1;

    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\r[CM] \yМенеджер моделей^n\dКарта: \y%s", g_szMapName);
    new menu = menu_create(szTitle, "ModelMain_Handler");
    menu_additem(menu, "Создать модель", "1");
    menu_additem(menu, "Создать из \yШаблона", "2");
    menu_additem(menu, "Редактировать модель \y(в прицеле)", "3");
    menu_additem(menu, "Список всех моделей", "4");
    menu_additem(menu, "Удалить модель \r(в прицеле)", "5");
    menu_additem(menu, "Сохранить всё \r(модели + триггеры)", "6");
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public ModelMain_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);
    menu_destroy(menu);

    switch (iChoice) {
        case 1: { g_iChangingModelFor[id] = -1; ShowModelListMenu(id); }
        case 2: ShowTemplateMenu(id);
        case 3: {
            new iEnt = GetAimedEntity(id);
            if (iEnt != -1) {
                g_iTargetIdx[id] = GetModelIndexByEnt(iEnt);
                if (g_iTargetIdx[id] != -1) ShowTransformMenu(id);
                else { client_print(id, print_chat, "[CM] Не удалось определить модель!"); Cmd_ModelMenu(id, ADMIN_LEVEL_H, 0); }
            } else { client_print(id, print_chat, "[CM] Наведитесь на модель!"); Cmd_ModelMenu(id, ADMIN_LEVEL_H, 0); }
        }
        case 4: ShowSpawnedMenu(id);
        case 5: 
        {
            new iEnt = GetAimedEntity(id);
            if (iEnt != -1) {
                new iIdx = GetModelIndexByEnt(iEnt);
                if (iIdx != -1) {
                    DeleteModel(iIdx);
                    client_print(id, print_chat, "[CM] Модель удалена.");
                }
            } else client_print(id, print_chat, "[CM] Наведитесь на модель!");
            Cmd_ModelMenu(id, ADMIN_LEVEL_H, 0);
        }
        case 6:
        {
            SaveModels();
            SaveTriggers();
            client_print(id, print_chat, "[CM] Всё сохранено для карты %s!", g_szMapName);
            Cmd_ModelMenu(id, ADMIN_LEVEL_H, 0);
        }
    }
    return PLUGIN_HANDLED;
}

ShowModelListMenu(id) {
    new menu = menu_create("\r[CM] \yВыберите модель для спавна", "ModelList_Handler");
    new szItem[128], szId[8], szFileName[64];

    for (new i = 0; i < g_iTotalModels; i++) {
        get_filename(g_szModelList[i], szFileName, charsmax(szFileName));
        formatex(szItem, charsmax(szItem), "%s", szFileName);
        num_to_str(i, szId, charsmax(szId));
        menu_additem(menu, szItem, szId);
    }

    if (g_iTotalModels == 0) {
        menu_destroy(menu);
        client_print(id, print_chat, "[CM] Нет моделей в папке %s!", MODELS_FOLDER);
        Cmd_ModelMenu(id, ADMIN_LEVEL_H, 0);
        return;
    }
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public ModelList_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); Cmd_ModelMenu(id, ADMIN_LEVEL_H, 0); return PLUGIN_HANDLED; }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iModelIdx = str_to_num(data);
    menu_destroy(menu);

    if (g_iChangingModelFor[id] != -1) {
        new iIdx = g_iChangingModelFor[id];
        if (iIdx >= 0 && iIdx < g_iTotalSpawned && pev_valid(g_iEntityID[iIdx])) {
            copy(g_szModelPath[iIdx], charsmax(g_szModelPath[]), g_szModelList[iModelIdx]);
            engfunc(EngFunc_SetModel, g_iEntityID[iIdx], g_szModelPath[iIdx]);
            g_iMaxSeq[iIdx] = UTIL_GetModelSeqCount(g_szModelPath[iIdx]);
            UpdateModel(iIdx);
            client_print(id, print_chat, "[CM] Модель изменена.");
            g_iChangingModelFor[id] = -1;
            ShowPropsMenu(id);
            return PLUGIN_HANDLED;
        }
        g_iChangingModelFor[id] = -1;
        return PLUGIN_HANDLED;
    }

    new Float:vOrigin[3], Float:vAngles[3], Float:vForward[3];
    pev(id, pev_origin, vOrigin);
    pev(id, pev_v_angle, vAngles);
    angle_vector(vAngles, ANGLEVECTOR_FORWARD, vForward);
    vOrigin[0] += vForward[0] * 50.0;
    vOrigin[1] += vForward[1] * 50.0;
    vOrigin[2] += 20.0;

    new iNewIdx = SpawnModel(g_szModelList[iModelIdx], vOrigin, Float:{0.0, 0.0, 0.0}, 1.0);
    if (iNewIdx != -1) {
        g_iTargetIdx[id] = iNewIdx;
        client_print(id, print_chat, "[CM] Модель [%d] создана.", iNewIdx);
    }
    return PLUGIN_HANDLED;
}

ShowSpawnedMenu(id) {
    new menu = menu_create("\r[CM] \yСписок моделей на карте", "SpawnedMenu_Handler");
    new szItem[128], szId[8], szFileName[64];

    if (g_iTotalSpawned == 0) {
        menu_destroy(menu);
        client_print(id, print_chat, "[CM] На карте нет моделей!");
        Cmd_ModelMenu(id, ADMIN_LEVEL_H, 0);
        return;
    }

    for (new i = 0; i < g_iTotalSpawned; i++) {
        get_filename(g_szModelPath[i], szFileName, charsmax(szFileName));
        new szHP[16];
        if (g_iHealth[i] == 0) copy(szHP, charsmax(szHP), "БЕССМ");
        else formatex(szHP, charsmax(szHP), "HP:%d", g_iHealth[i]);
        formatex(szItem, charsmax(szItem), "[%d] %s \y%s \d%s%s", i, szFileName, szHP,
            g_bSolid[i] ? "[ХБ]" : "",
            g_bIsDead[i] ? " \r[МЕРТВА]" : "");
        num_to_str(i, szId, charsmax(szId));
        menu_additem(menu, szItem, szId);
    }
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public SpawnedMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); Cmd_ModelMenu(id, ADMIN_LEVEL_H, 0); return PLUGIN_HANDLED; }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    g_iTargetIdx[id] = str_to_num(data);
    menu_destroy(menu);
    ShowTransformMenu(id);
    return PLUGIN_HANDLED;
}

ShowTransformMenu(id) {
    new iIdx = g_iTargetIdx[id];
    if (iIdx < 0 || iIdx >= g_iTotalSpawned)
    { 
        client_print(id, print_chat, "[CM] Модель не найдена!"); 
        return; 
    }

    new szTitle[256];
    new szHPInfo[32];
    if (g_iHealth[iIdx] == 0) copy(szHPInfo, charsmax(szHPInfo), "Бессмертна");
    else formatex(szHPInfo, charsmax(szHPInfo), "HP: %d", g_iHealth[iIdx]);

    formatex(szTitle, charsmax(szTitle), "\r[CM] \yМодель [%d]^n\d%s | Хитбокс: %s | %s",
        iIdx, szHPInfo, g_bSolid[iIdx] ? "ВКЛ" : "ВЫКЛ",
        g_bIsDead[iIdx] ? "\rМЕРТВА" : "\yЖива");
    new menu = menu_create(szTitle, "TransformMenu_Handler");

    menu_additem(menu, "Трансформация \y(XYZ, Поворот, Размер)", "1");
    menu_additem(menu, "Свойства \y(Аним, Рендер, HP, Смена модели)", "2");
    menu_additem(menu, "Маршрут \y(Точки движения)", "3");
    menu_additem(menu, "Триггеры модели \y(Зоны / Кастомный хитбокс)", "4");
    menu_additem(menu, "Сохранить как \yШаблон", "5");
    menu_additem(menu, "\rУдалить модель", "6");

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public TransformMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }

    new iIdx = g_iTargetIdx[id];
    if (iIdx < 0 || iIdx >= g_iTotalSpawned || !pev_valid(g_iEntityID[iIdx])) {
        client_print(id, print_chat, "[CM] Модель исчезла!");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);

    switch (iChoice) {
        case 1: { menu_destroy(menu); ShowTransformEditMenu(id); return PLUGIN_HANDLED; }
        case 2: { menu_destroy(menu); ShowPropsMenu(id); return PLUGIN_HANDLED; }
        case 3: { menu_destroy(menu); ShowPathMenu(id); return PLUGIN_HANDLED; }
        case 4: { menu_destroy(menu); ShowModelTriggerMenu(id); return PLUGIN_HANDLED; }
        case 5: { SaveAsTemplate(id, iIdx); menu_destroy(menu); ShowTransformMenu(id); return PLUGIN_HANDLED; }
        case 6: {
            DeleteModel(iIdx);
            client_print(id, print_chat, "[CM] Модель удалена.");
            menu_destroy(menu);
            Cmd_ModelMenu(id, ADMIN_LEVEL_H, 0);
            return PLUGIN_HANDLED;
        }
    }

    menu_destroy(menu);
    ShowTransformMenu(id);
    return PLUGIN_HANDLED;
}

ShowTransformEditMenu(id) {
    new iIdx = g_iTargetIdx[id];
    if (iIdx < 0 || iIdx >= g_iTotalSpawned) { client_print(id, print_chat, "[CM] Модель не найдена!");
    return; 
    }

    new szTitle[256], szMode[16], szInterval[16];
    switch (g_iEditMode[id]) {
        case 0: copy(szMode, charsmax(szMode), "Позиция");
        case 1: copy(szMode, charsmax(szMode), "Поворот");
        case 2: copy(szMode, charsmax(szMode), "Размер");
    }
    float_to_str(g_flInterval[id], szInterval, charsmax(szInterval));

    formatex(szTitle, charsmax(szTitle), "\r[CM] \yТрансформация модели [%d]^n\dРежим: \y%s \d| Шаг: \y%s", iIdx, szMode, szInterval);
    new menu = menu_create(szTitle, "TransformEditMenu_Handler");

    menu_additem(menu, "+ X", "1");
    menu_additem(menu, "+ Y", "2");
    menu_additem(menu, "+ Z", "3");
    menu_additem(menu, "- X", "4");
    menu_additem(menu, "- Y", "5");
    menu_additem(menu, "- Z", "6");
    menu_additem(menu, "Сменить режим \y(Поз/Поворот/Размер)", "7");
    menu_additem(menu, "Изменить шаг \r(0.1/1.0/10.0)", "8");
    menu_additem(menu, "Переместить куда смотрю", "9");
    menu_additem(menu, "Назад", "10");

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public TransformEditMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowTransformMenu(id); return PLUGIN_HANDLED; }

    new iIdx = g_iTargetIdx[id];
    if (iIdx < 0 || iIdx >= g_iTotalSpawned || !pev_valid(g_iEntityID[iIdx])) {
        client_print(id, print_chat, "[CM] Модель исчезла!");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);
    new Float:flVal = g_flInterval[id];

    switch (iChoice) {
        case 1: { if (g_iEditMode[id] == 0) g_vOrigin[iIdx][0] += flVal; else if (g_iEditMode[id] == 1) g_vAngles[iIdx][0] += flVal; else g_flScale[iIdx] += flVal; }
        case 2: { if (g_iEditMode[id] == 0) g_vOrigin[iIdx][1] += flVal; else if (g_iEditMode[id] == 1) g_vAngles[iIdx][1] += flVal; else g_flScale[iIdx] += flVal; }
        case 3: { if (g_iEditMode[id] == 0) g_vOrigin[iIdx][2] += flVal; else if (g_iEditMode[id] == 1) g_vAngles[iIdx][2] += flVal; else g_flScale[iIdx] += flVal; }
        case 4: { if (g_iEditMode[id] == 0) g_vOrigin[iIdx][0] -= flVal; else if (g_iEditMode[id] == 1) g_vAngles[iIdx][0] -= flVal; else g_flScale[iIdx] -= flVal; }
        case 5: { if (g_iEditMode[id] == 0) g_vOrigin[iIdx][1] -= flVal; else if (g_iEditMode[id] == 1) g_vAngles[iIdx][1] -= flVal; else g_flScale[iIdx] -= flVal; }
        case 6: { if (g_iEditMode[id] == 0) g_vOrigin[iIdx][2] -= flVal; else if (g_iEditMode[id] == 1) g_vAngles[iIdx][2] -= flVal; else g_flScale[iIdx] -= flVal; }
        case 7: { g_iEditMode[id]++; if (g_iEditMode[id] > 2) g_iEditMode[id] = 0; }
        case 8: { if (flVal < 0.2) g_flInterval[id] = 1.0; else if (flVal < 1.5) g_flInterval[id] = 10.0; else g_flInterval[id] = 0.1; }
        case 9: {
            new iOrigin[3]; get_user_origin(id, iOrigin, 3);
            IVecFVec(iOrigin, g_vOrigin[iIdx]);
        }
        case 10: { menu_destroy(menu); ShowTransformMenu(id); return PLUGIN_HANDLED; }
    }

    if (g_flScale[iIdx] < 0.1) g_flScale[iIdx] = 0.1;
    UpdateModel(iIdx);
    menu_destroy(menu);
    ShowTransformEditMenu(id);
    return PLUGIN_HANDLED;
}

ShowPropsMenu(id) {
    new iIdx = g_iTargetIdx[id];
    if (iIdx < 0 || iIdx >= g_iTotalSpawned || !pev_valid(g_iEntityID[iIdx])) {
        client_print(id, print_chat, "[CM] Модель не найдена!");
        ShowTransformMenu(id);
        return;
    }

    new szTitle[256];
    formatex(szTitle, charsmax(szTitle), "\r[CM] \yСвойства модели [%d] | HP: %d", iIdx, g_iHealth[iIdx]);
    new menu = menu_create(szTitle, "PropsMenu_Handler");

    new szAnim[64], szMove[64], szSolid[64], szRender[64];
    formatex(szAnim, charsmax(szAnim), "Анимация: \ySeq %d/%d", g_iSequence[iIdx], g_iMaxSeq[iIdx]);
    formatex(szMove, charsmax(szMove), "Движение по маршруту: \y%s", g_bIsMoving[iIdx] ? "ВКЛ" : "ВЫКЛ");
    formatex(szSolid, charsmax(szSolid), "Хитбокс (коллизия): \y%s", g_bSolid[iIdx] ? "ВКЛ" : "ВЫКЛ");
    formatex(szRender, charsmax(szRender), "Рендер: \y%s \d(Прозр: %.0f)", g_iRenderMode[iIdx] == kRenderNormal ? "Обычный" : "Эффект", g_flRenderAmt[iIdx]);

    menu_additem(menu, "Изменить модель \y(Выбрать новую .mdl)", "1");
    menu_additem(menu, szAnim, "2");
    menu_additem(menu, "Вкл/Выкл анимацию \y(Скор: 1.0/0.0)", "3");
    menu_additem(menu, szMove, "4");
    menu_additem(menu, szSolid, "5");
    menu_additem(menu, szRender, "6");
    menu_additem(menu, "Прозрачность: 50 / 100", "7");
    menu_additem(menu, "Сделать живой \y(100 HP)", "8");
    menu_additem(menu, "Сделать бессмертной \y(0 HP)", "9");
    menu_additem(menu, "Указать HP \y(/sethp <число>)", "10");
    menu_additem(menu, "Назад", "11");

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public PropsMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }

    new iIdx = g_iTargetIdx[id];
    if (iIdx < 0 || iIdx >= g_iTotalSpawned || !pev_valid(g_iEntityID[iIdx])) {
        client_print(id, print_chat, "[CM] Модель исчезла!");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);
    new iEnt = g_iEntityID[iIdx];
    
    switch (iChoice) 
    {
        case 1: { g_iChangingModelFor[id] = iIdx; menu_destroy(menu); ShowModelListMenu(id); return PLUGIN_HANDLED; }
        case 2: {
            g_iSequence[iIdx]++;
            if (g_iSequence[iIdx] >= g_iMaxSeq[iIdx]) g_iSequence[iIdx] = 0;
            if (g_flFramerate[iIdx] == 0.0) g_flFramerate[iIdx] = 1.0;
        }
        case 3: {
            if (g_flFramerate[iIdx] > 0.0) g_flFramerate[iIdx] = 0.0;
            else g_flFramerate[iIdx] = 1.0;
        }
        case 4: {
            g_bIsMoving[iIdx] = !g_bIsMoving[iIdx];
            if (g_bIsMoving[iIdx]) {
                set_pev(iEnt, pev_solid, SOLID_NOT);
                set_pev(iEnt, pev_movetype, MOVETYPE_FLY);
            } else {
                set_pev(iEnt, pev_movetype, MOVETYPE_NONE);
                set_pev(iEnt, pev_solid, g_bSolid[iIdx] ? SOLID_BBOX : SOLID_NOT);
            }
        }
        case 5: {
            g_bSolid[iIdx] = !g_bSolid[iIdx];
            if (!g_bIsMoving[iIdx] && !g_bIsDead[iIdx]) {
                set_pev(iEnt, pev_solid, g_bSolid[iIdx] ? SOLID_BBOX : SOLID_NOT);
            }
            client_print(id, print_chat, "[CM] Хитбокс: %s (сохраняется!)", g_bSolid[iIdx] ? "ВКЛ" : "ВЫКЛ");
        }
        case 6: {
            if (g_iRenderMode[iIdx] == kRenderNormal) {
                g_iRenderMode[iIdx] = kRenderTransTexture;
                g_vRenderColor[iIdx][0] = 0.0;
                g_vRenderColor[iIdx][1] = 255.0;
                g_vRenderColor[iIdx][2] = 0.0;
            } else {
                g_iRenderMode[iIdx] = kRenderNormal;
                g_vRenderColor[iIdx][0] = 255.0;
                g_vRenderColor[iIdx][1] = 255.0;
                g_vRenderColor[iIdx][2] = 255.0;
            }
        }
        case 7: {
            g_iRenderMode[iIdx] = kRenderTransTexture;
            if (g_flRenderAmt[iIdx] > 200.0) g_flRenderAmt[iIdx] = 128.0;
            else g_flRenderAmt[iIdx] = 255.0;
        }
        case 8: {
            g_iHealth[iIdx] = 100;
            g_bIsDead[iIdx] = false;
            set_pev(iEnt, pev_effects, 0);
            set_pev(iEnt, pev_takedamage, DAMAGE_AIM);
            set_pev(iEnt, pev_health, 100.0);
            if (!g_bIsMoving[iIdx]) set_pev(iEnt, pev_solid, g_bSolid[iIdx] ? SOLID_BBOX : SOLID_NOT);
            client_print(id, print_chat, "[CM] Модель стала живой!");
        }
        case 9: {
            g_iHealth[iIdx] = 0;
            set_pev(iEnt, pev_takedamage, DAMAGE_NO);
            client_print(id, print_chat, "[CM] Модель стала бессмертной.");
        }
        case 10: {
            client_print(id, print_chat, "[CM] Напишите в чат: /sethp <число> (например /sethp 250)");
        }
        case 11: { menu_destroy(menu); ShowTransformMenu(id); return PLUGIN_HANDLED; }
    }

    UpdateModel(iIdx);
    menu_destroy(menu);
    ShowPropsMenu(id);
    return PLUGIN_HANDLED;
}

ShowPathMenu(id) {
    new iIdx = g_iTargetIdx[id];
    if (iIdx < 0 || iIdx >= g_iTotalSpawned) { client_print(id, print_chat, "[CM] Модель не найдена!");
     return;
    }

    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\r[CM] \yМаршрут [%d] (Точек: %d/%d)", iIdx, g_iPathCount[iIdx], MAX_PATH_POINTS);
    new menu = menu_create(szTitle, "PathMenu_Handler");

    menu_additem(menu, "Добавить точку \y(куда смотрю)", "1");
    menu_additem(menu, "Очистить все точки", "2");
    menu_additem(menu, "Вкл/Выкл движение", "3");
    menu_additem(menu, "Назад", "4");

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public PathMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }

    new iIdx = g_iTargetIdx[id];
    if (iIdx < 0 || iIdx >= g_iTotalSpawned) { menu_destroy(menu); return PLUGIN_HANDLED; }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);

    switch (iChoice) {
        case 1: {
            if (g_iPathCount[iIdx] < MAX_PATH_POINTS) {
                new iOrigin[3];
                get_user_origin(id, iOrigin, 3);
                IVecFVec(iOrigin, g_vPath[iIdx][g_iPathCount[iIdx]]);
                g_iPathCount[iIdx]++;
                client_print(id, print_chat, "[CM] Точка %d добавлена.", g_iPathCount[iIdx]);
            } else client_print(id, print_chat, "[CM] Максимум %d точек!", MAX_PATH_POINTS);
        }
        case 2: {
            g_iPathCount[iIdx] = 0;
            g_iCurPath[iIdx] = 0;
            g_bIsMoving[iIdx] = false;
            if (pev_valid(g_iEntityID[iIdx])) {
                set_pev(g_iEntityID[iIdx], pev_movetype, MOVETYPE_NONE);
                set_pev(g_iEntityID[iIdx], pev_solid, g_bSolid[iIdx] ? SOLID_BBOX : SOLID_NOT);
            }
        }
        case 3: {
            if (g_iPathCount[iIdx] < 2) client_print(id, print_chat, "[CM] Нужно минимум 2 точки!");
            else {
                g_bIsMoving[iIdx] = !g_bIsMoving[iIdx];
                if (g_bIsMoving[iIdx]) {
                    set_pev(g_iEntityID[iIdx], pev_solid, SOLID_NOT);
                    set_pev(g_iEntityID[iIdx], pev_movetype, MOVETYPE_FLY);
                } else {
                    set_pev(g_iEntityID[iIdx], pev_movetype, MOVETYPE_NONE);
                    set_pev(g_iEntityID[iIdx], pev_solid, g_bSolid[iIdx] ? SOLID_BBOX : SOLID_NOT);
                }
            }
        }
        case 4: { menu_destroy(menu); ShowTransformMenu(id); return PLUGIN_HANDLED; }
    }

    UpdateModel(iIdx);
    menu_destroy(menu);
    ShowPathMenu(id);
    return PLUGIN_HANDLED;
}

ShowModelTriggerMenu(id) {
    new iIdx = g_iTargetIdx[id];
    if (iIdx < 0 || iIdx >= g_iTotalSpawned) { client_print(id, print_chat, "[CM] Модель не найдена!");
     return; 
    }
    g_iModelTrigPage[id] = 0;
    ShowModelTriggerMenuPage(id);
}

ShowModelTriggerMenuPage(id) {
    new iIdx = g_iTargetIdx[id];
    if (iIdx < 0 || iIdx >= g_iTotalSpawned) { client_print(id, print_chat, "[CM] Модель не найдена!");
     return;
     }

    new iTrigIds[MAX_TRIGGERS];
    new iTrigCount = 0;
    for (new t = 0; t < g_iTotalTriggers; t++) {
        if (g_iTrigModelID[t] == iIdx) {
            iTrigIds[iTrigCount] = t;
            iTrigCount++;
        }
    }

    new szTitle[256];
    formatex(szTitle, charsmax(szTitle), "\r[CM] \yТриггеры модели [%d]^n\dВсего: %d", iIdx, iTrigCount);
    new menu = menu_create(szTitle, "ModelTrigMenu_Handler");

    menu_additem(menu, "\yСоздать новый триггер \w(на позиции модели)", "1000");

    new iPage = g_iModelTrigPage[id];
    new iPerPage = 4;
    new iStart = iPage * iPerPage;
    new szItem[128], szInfo[8];

    for (new i = iStart; i < iStart + iPerPage && i < iTrigCount; i++) {
        new t = iTrigIds[i];
        new szSolid[32];
        if (g_bTrigSolid[t]) copy(szSolid, charsmax(szSolid), "\r[БЛОКИРУЕТ]");
        else copy(szSolid, charsmax(szSolid), "\d[проходной]");

        formatex(szItem, charsmax(szItem), "\wТриггер [%d] %s", t, szSolid);
        num_to_str(t, szInfo, charsmax(szInfo));
        menu_additem(menu, szItem, szInfo);
    }

    if (iTrigCount > (iStart + iPerPage)) {
        menu_additem(menu, "Следующая страница \y>>", "1001");
    }
    if (iPage > 0) {
        menu_additem(menu, "Предыдущая страница \y<<", "1002");
    }

    menu_additem(menu, "Назад", "1003");

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public ModelTrigMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowTransformMenu(id); return PLUGIN_HANDLED; }

    new data[8], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iVal = str_to_num(data);
    menu_destroy(menu);

    if (iVal == 1000) {
        new iIdx = g_iTargetIdx[id];
        if (iIdx < 0 || iIdx >= g_iTotalSpawned) { ShowTransformMenu(id); return PLUGIN_HANDLED; }
        new tIdx = CreateTrigger(g_vOrigin[iIdx], iIdx);
        if (tIdx != -1) {
            g_iEditingTrig[id] = tIdx;
            g_bShowTrigger[id] = true;
            client_print(id, print_chat, "[CM] Триггер [%d] создан и привязан к модели [%d].", tIdx, iIdx);
            ShowModelTrigEditMenu(id);
        }
        return PLUGIN_HANDLED;
    }
    if (iVal == 1001) {
        g_iModelTrigPage[id]++;
        ShowModelTriggerMenuPage(id);
        return PLUGIN_HANDLED;
    }
    if (iVal == 1002) {
        g_iModelTrigPage[id]--;
        if (g_iModelTrigPage[id] < 0) g_iModelTrigPage[id] = 0;
        ShowModelTriggerMenuPage(id);
        return PLUGIN_HANDLED;
    }
    if (iVal == 1003) {
        ShowTransformMenu(id);
        return PLUGIN_HANDLED;
    }

    if (iVal >= 0 && iVal < g_iTotalTriggers) {
        g_iEditingTrig[id] = iVal;
        g_bShowTrigger[id] = true;
        ShowModelTrigEditMenu(id);
        return PLUGIN_HANDLED;
    }

    ShowModelTriggerMenuPage(id);
    return PLUGIN_HANDLED;
}

ShowModelTrigEditMenu(id) {
    new tIdx = g_iEditingTrig[id];
    if (tIdx < 0 || tIdx >= g_iTotalTriggers) {
        client_print(id, print_chat, "[CM] Триггер не найден!");
        ShowModelTriggerMenu(id);
        return;
    }

    new szTitle[256];
    new szSolid[32];
    if (g_bTrigSolid[tIdx]) copy(szSolid, charsmax(szSolid), "\yВКЛ (Блокирует)");
    else copy(szSolid, charsmax(szSolid), "\rВЫКЛ (Проходной)");

    formatex(szTitle, charsmax(szTitle), "\r[CM] \yТриггер [%d] модели [%d]^n\dБлокировка: %s", tIdx, g_iTrigModelID[tIdx], szSolid);
    new menu = menu_create(szTitle, "ModelTrigEdit_Handler");

    menu_additem(menu, "Трансформация \y(Позиция, Размер)", "1");
    menu_additem(menu, "Блокировка: \yБлокирует / Проходной", "2");
    menu_additem(menu, "Действия \yВХОДА", "3");
    menu_additem(menu, "Действия \yВЫХОДА", "4");
    menu_additem(menu, "Действия \yНАХОЖДЕНИЯ", "5");
    menu_additem(menu, "Интервал нахождения", "6");
    menu_additem(menu, "Показать/Скрыть контур", "7");
    menu_additem(menu, "\rУдалить этот триггер", "8");
    menu_additem(menu, "Назад к списку триггеров", "9");

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public ModelTrigEdit_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); ShowModelTriggerMenu(id); return PLUGIN_HANDLED; }

    new tIdx = g_iEditingTrig[id];
    if (tIdx < 0 || tIdx >= g_iTotalTriggers) {
        client_print(id, print_chat, "[CM] Триггер был удален!");
        menu_destroy(menu);
        ShowModelTriggerMenu(id);
        return PLUGIN_HANDLED;
    }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);

    switch (iChoice) {
        case 1: { menu_destroy(menu); ShowTrigTransformMenu(id); return PLUGIN_HANDLED; }
        case 2: {
            g_bTrigSolid[tIdx] = !g_bTrigSolid[tIdx];
            client_print(id, print_chat, "[CM] Триггер [%d]: %s (сохраняется!)", tIdx, g_bTrigSolid[tIdx] ? "БЛОКИРУЕТ игроков" : "Проходной");
        }
        case 3: { menu_destroy(menu); ShowActionMenu(id, 1); return PLUGIN_HANDLED; }
        case 4: { menu_destroy(menu); ShowActionMenu(id, 2); return PLUGIN_HANDLED; }
        case 5: { menu_destroy(menu); ShowActionMenu(id, 3); return PLUGIN_HANDLED; }
        case 6: {
            if (g_flTrigStayInterval[tIdx] < 0.6) g_flTrigStayInterval[tIdx] = 1.0;
            else if (g_flTrigStayInterval[tIdx] < 1.5) g_flTrigStayInterval[tIdx] = 2.0;
            else if (g_flTrigStayInterval[tIdx] < 3.0) g_flTrigStayInterval[tIdx] = 5.0;
            else g_flTrigStayInterval[tIdx] = 0.5;
        }
        case 7: { g_bTrigVisible[tIdx] = !g_bTrigVisible[tIdx]; }
        case 8: {
            DeleteTrigger(tIdx);
            client_print(id, print_chat, "[CM] Триггер удален.");
            menu_destroy(menu);
            ShowModelTriggerMenu(id);
            return PLUGIN_HANDLED;
        }
        case 9: { menu_destroy(menu); ShowModelTriggerMenu(id); return PLUGIN_HANDLED; }
    }

    menu_destroy(menu);
    ShowModelTrigEditMenu(id);
    return PLUGIN_HANDLED;
}

ShowTrigTransformMenu(id) {
    new tIdx = g_iEditingTrig[id];
    if (tIdx < 0 || tIdx >= g_iTotalTriggers) { client_print(id, print_chat, "[CM] Триггер не найдена!");
     return; 
    }

    new szTitle[256], szMode[16], szStep[16];
    if (g_iTrigEditMode[id] == 0) copy(szMode, charsmax(szMode), "Позиция");
    else copy(szMode, charsmax(szMode), "Размер");
    float_to_str(g_flTrigInterval[id], szStep, charsmax(szStep));

    formatex(szTitle, charsmax(szTitle), "\r[CM] \yТрансформация триггера [%d]^n\dРежим: \y%s \d| Шаг: \y%s", tIdx, szMode, szStep);
    new menu = menu_create(szTitle, "TrigTransform_Handler");

    menu_additem(menu, "+ X", "1");
    menu_additem(menu, "+ Y", "2");
    menu_additem(menu, "+ Z", "3");
    menu_additem(menu, "- X", "4");
    menu_additem(menu, "- Y", "5");
    menu_additem(menu, "- Z", "6");
    menu_additem(menu, "Режим: \yПозиция/Размер", "7");
    menu_additem(menu, "Шаг: \r0.1/1/10/50", "8");
    menu_additem(menu, "Переместить куда смотрю", "9");
    menu_additem(menu, "Назад", "10");

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public TrigTransform_Handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        if (g_iEditingTrig[id] >= 0 && g_iEditingTrig[id] < g_iTotalTriggers) {
            if (g_iTrigModelID[g_iEditingTrig[id]] != -1) ShowModelTrigEditMenu(id);
            else ShowStandaloneTrigMenu(id);
        }
        return PLUGIN_HANDLED;
    }

    new tIdx = g_iEditingTrig[id];
    if (tIdx < 0 || tIdx >= g_iTotalTriggers) {
        client_print(id, print_chat, "[CM] Триггер был удален!");
        menu_destroy(menu);
        ShowModelTriggerMenu(id);
        return PLUGIN_HANDLED;
    }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);
    new Float:flVal = g_flTrigInterval[id];

    switch (iChoice) {
        case 1: { if (g_iTrigEditMode[id] == 0) g_vTrigOrigin[tIdx][0] += flVal; else { g_vTrigMins[tIdx][0] -= flVal; g_vTrigMaxs[tIdx][0] += flVal; } }
        case 2: { if (g_iTrigEditMode[id] == 0) g_vTrigOrigin[tIdx][1] += flVal; else { g_vTrigMins[tIdx][1] -= flVal; g_vTrigMaxs[tIdx][1] += flVal; } }
        case 3: { if (g_iTrigEditMode[id] == 0) g_vTrigOrigin[tIdx][2] += flVal; else { g_vTrigMins[tIdx][2] -= flVal; g_vTrigMaxs[tIdx][2] += flVal; } }
        case 4: { if (g_iTrigEditMode[id] == 0) g_vTrigOrigin[tIdx][0] -= flVal; else { g_vTrigMins[tIdx][0] += flVal; g_vTrigMaxs[tIdx][0] -= flVal; } }
        case 5: { if (g_iTrigEditMode[id] == 0) g_vTrigOrigin[tIdx][1] -= flVal; else { g_vTrigMins[tIdx][1] += flVal; g_vTrigMaxs[tIdx][1] -= flVal; } }
        case 6: { if (g_iTrigEditMode[id] == 0) g_vTrigOrigin[tIdx][2] -= flVal; else { g_vTrigMins[tIdx][2] += flVal; g_vTrigMaxs[tIdx][2] -= flVal; } }
        case 7: { g_iTrigEditMode[id] = 1 - g_iTrigEditMode[id]; }
        case 8: {
            if (flVal < 0.2) g_flTrigInterval[id] = 1.0;
            else if (flVal < 2.0) g_flTrigInterval[id] = 10.0;
            else if (flVal < 15.0) g_flTrigInterval[id] = 50.0;
            else g_flTrigInterval[id] = 0.1;
        }
        case 9: {
            new iOrigin[3]; get_user_origin(id, iOrigin, 3);
            IVecFVec(iOrigin, g_vTrigOrigin[tIdx]);
        }
        case 10: {
            menu_destroy(menu);
            if (g_iTrigModelID[tIdx] != -1) ShowModelTrigEditMenu(id);
            else ShowStandaloneTrigMenu(id);
            return PLUGIN_HANDLED;
        }
    }

    for (new a = 0; a < 3; a++) {
        if (g_vTrigMaxs[tIdx][a] - g_vTrigMins[tIdx][a] < 5.0) {
            new Float:flCenter = (g_vTrigMins[tIdx][a] + g_vTrigMaxs[tIdx][a]) * 0.5;
            g_vTrigMins[tIdx][a] = flCenter - 2.5;
            g_vTrigMaxs[tIdx][a] = flCenter + 2.5;
        }
    }

    UpdateTriggerEntity(tIdx);
    menu_destroy(menu);
    ShowTrigTransformMenu(id);
    return PLUGIN_HANDLED;
}

public Cmd_TrigMenu(id, level, cid) {
    if (!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;

    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\r[TRIG] \yМенеджер триггеров^n\dКарта: \y%s", g_szMapName);
    new menu = menu_create(szTitle, "TrigMain_Handler");
    menu_additem(menu, "Создать триггер \y(в прицеле)", "1");
    menu_additem(menu, "Редактировать триггер \y(в прицеле)", "2");
    menu_additem(menu, "Список всех триггеров", "3");
    menu_additem(menu, "Удалить триггер \r(в прицеле)", "4");
    menu_additem(menu, "Сохранить все триггеры \r(на эту карту)", "5");
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public TrigMain_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);
    menu_destroy(menu);

    switch (iChoice) {
        case 1: {
            new iOrigin[3], Float:vOrigin[3];
            get_user_origin(id, iOrigin, 3);
            IVecFVec(iOrigin, vOrigin);
            new tIdx = CreateTrigger(vOrigin, -1);
            if (tIdx != -1) {
                g_iEditingTrig[id] = tIdx;
                g_bShowTrigger[id] = true;
                client_print(id, print_chat, "[TRIG] Триггер [%d] создан.", tIdx);
                ShowStandaloneTrigMenu(id);
            }
        }
        case 2: {
            new tIdx = GetAimedTriggerIndex(id);
            if (tIdx != -1) {
                g_iEditingTrig[id] = tIdx;
                g_bShowTrigger[id] = true;
                ShowStandaloneTrigMenu(id);
            } else { client_print(id, print_chat, "[TRIG] Наведитесь на триггер!"); Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0); }
        }
        case 3: ShowTrigListMenu(id);
        case 4: {
            new tIdx = GetAimedTriggerIndex(id);
            if (tIdx != -1) {
                DeleteTrigger(tIdx);
                client_print(id, print_chat, "[TRIG] Триггер удален из мира и из списка.");
            } else client_print(id, print_chat, "[TRIG] Наведитесь на триггер!");
            Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0);
        }
        case 5: {
            SaveTriggers();
            client_print(id, print_chat, "[TRIG] Все триггеры сохранены для карты %s!", g_szMapName);
            Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0);
        }
    }
    return PLUGIN_HANDLED;
}

ShowTrigListMenu(id) {
    new menu = menu_create("\r[TRIG] \yСписок всех триггеров", "TrigList_Handler");
    new szItem[128], szId[8];

    if (g_iTotalTriggers == 0) {
        menu_destroy(menu);
        client_print(id, print_chat, "[TRIG] Нет триггеров!");
        Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0);
        return;
    }

    for (new i = 0; i < g_iTotalTriggers && i < 9; i++) {
        new szType[32], szSolid[32];
        if (g_iTrigModelID[i] == -1) copy(szType, charsmax(szType), "\yОдиночный");
        else formatex(szType, charsmax(szType), "\rМодель %d", g_iTrigModelID[i]);
        if (g_bTrigSolid[i]) copy(szSolid, charsmax(szSolid), " \w[БЛОК]");
        else copy(szSolid, charsmax(szSolid), "");

        formatex(szItem, charsmax(szItem), "[%d] %s%s", i, szType, szSolid);
        num_to_str(i, szId, charsmax(szId));
        menu_additem(menu, szItem, szId);
    }
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public TrigList_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0); return PLUGIN_HANDLED; }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    g_iEditingTrig[id] = str_to_num(data);
    g_bShowTrigger[id] = true;
    menu_destroy(menu);
    ShowStandaloneTrigMenu(id);
    return PLUGIN_HANDLED;
}

ShowStandaloneTrigMenu(id) {
    new tIdx = g_iEditingTrig[id];
    if (tIdx < 0 || tIdx >= g_iTotalTriggers) {
        client_print(id, print_chat, "[TRIG] Триггер не найден!");
        Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0);
        return;
    }

    new szTitle[256];
    new szSolid[32], szVis[32], szInterval[64];
    if (g_bTrigSolid[tIdx]) copy(szSolid, charsmax(szSolid), "\yВКЛ (Блокирует)");
    else copy(szSolid, charsmax(szSolid), "\rВЫКЛ (Проходной)");
    if (g_bTrigVisible[tIdx]) copy(szVis, charsmax(szVis), "Скрыть контур");
    else copy(szVis, charsmax(szVis), "Показать контур");
    formatex(szInterval, charsmax(szInterval), "Интервал нахождения: \y%.1fс", g_flTrigStayInterval[tIdx]);

    formatex(szTitle, charsmax(szTitle), "\r[TRIG] \yТриггер [%d]^n\dБлокировка: %s", tIdx, szSolid);
    new menu = menu_create(szTitle, "StandaloneTrigMenu_Handler");

    menu_additem(menu, "Трансформация \y(Позиция, Размер)", "1");
    menu_additem(menu, "Блокировка: \yБлокирует / Проходной", "2");
    menu_additem(menu, "Действия \yВХОДА", "3");
    menu_additem(menu, "Действия \yВЫХОДА", "4");
    menu_additem(menu, "Действия \yНАХОЖДЕНИЯ", "5");
    menu_additem(menu, szInterval, "6");
    menu_additem(menu, szVis, "7");
    menu_additem(menu, "\rУдалить триггер", "8");
    menu_additem(menu, "Назад", "9");

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
}

public StandaloneTrigMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0); return PLUGIN_HANDLED; }

    new tIdx = g_iEditingTrig[id];
    if (tIdx < 0 || tIdx >= g_iTotalTriggers) {
        client_print(id, print_chat, "[TRIG] Триггер был удален!");
        menu_destroy(menu);
        Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0);
        return PLUGIN_HANDLED;
    }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iChoice = str_to_num(data);

    switch (iChoice) {
        case 1: { menu_destroy(menu); ShowTrigTransformMenu(id); return PLUGIN_HANDLED; }
        case 2: {
            g_bTrigSolid[tIdx] = !g_bTrigSolid[tIdx];
            client_print(id, print_chat, "[TRIG] Триггер [%d]: %s (сохраняется!)", tIdx, g_bTrigSolid[tIdx] ? "БЛОКИРУЕТ" : "Проходной");
        }
        case 3: { menu_destroy(menu); ShowActionMenu(id, 1); return PLUGIN_HANDLED; }
        case 4: { menu_destroy(menu); ShowActionMenu(id, 2); return PLUGIN_HANDLED; }
        case 5: { menu_destroy(menu); ShowActionMenu(id, 3); return PLUGIN_HANDLED; }
        case 6: {
            if (g_flTrigStayInterval[tIdx] < 0.6) g_flTrigStayInterval[tIdx] = 1.0;
            else if (g_flTrigStayInterval[tIdx] < 1.5) g_flTrigStayInterval[tIdx] = 2.0;
            else if (g_flTrigStayInterval[tIdx] < 3.0) g_flTrigStayInterval[tIdx] = 5.0;
            else g_flTrigStayInterval[tIdx] = 0.5;
        }
        case 7: { g_bTrigVisible[tIdx] = !g_bTrigVisible[tIdx]; }
        case 8: {
            DeleteTrigger(tIdx);
            client_print(id, print_chat, "[TRIG] Триггер удален из мира и из списка.");
            menu_destroy(menu);
            Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0);
            return PLUGIN_HANDLED;
        }
        case 9: { menu_destroy(menu); Cmd_TrigMenu(id, ADMIN_LEVEL_H, 0); return PLUGIN_HANDLED; }
    }

    menu_destroy(menu);
    ShowStandaloneTrigMenu(id);
    return PLUGIN_HANDLED;
}

ShowActionMenu(id, iEventType) {
    new tIdx = g_iEditingTrig[id];
    if (tIdx < 0 || tIdx >= g_iTotalTriggers) {
        client_print(id, print_chat, "[CM] Триггер не найден!");
        if (tIdx >= 0 && g_iTrigModelID[tIdx] != -1) ShowModelTrigEditMenu(id);
        else ShowStandaloneTrigMenu(id);
        return;
    }

    new szTitle[128], szEvent[16];
    if (iEventType == 1) copy(szEvent, charsmax(szEvent), "Вход");
    else if (iEventType == 2) copy(szEvent, charsmax(szEvent), "Выход");
    else copy(szEvent, charsmax(szEvent), "Нахождение");

    formatex(szTitle, charsmax(szTitle), "\r[TRIG] \yДействия (%s) Триггер [%d]", szEvent, tIdx);
    new menu = menu_create(szTitle, "ActionMenu_Handler");

    new szItem[128], szInfo[8], iMask;
    if (iEventType == 1) iMask = g_iTrigEnterActions[tIdx];
    else if (iEventType == 2) iMask = g_iTrigLeaveActions[tIdx];
    else iMask = g_iTrigStayActions[tIdx];

    for (new i = 0; i < g_iActionCount; i++) {
        if (iMask & (1 << i))
            formatex(szItem, charsmax(szItem), "\y[X] \w%s", g_szActionNames[i]);
        else
            formatex(szItem, charsmax(szItem), "\r[ ] \w%s", g_szActionNames[i]);
        num_to_str(iEventType * 100 + i, szInfo, charsmax(szInfo));
        menu_additem(menu, szItem, szInfo);
    }
    menu_additem(menu, "\yГотово", "9999");
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public ActionMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        if (g_iEditingTrig[id] >= 0 && g_iEditingTrig[id] < g_iTotalTriggers) {
            if (g_iTrigModelID[g_iEditingTrig[id]] != -1) ShowModelTrigEditMenu(id);
            else ShowStandaloneTrigMenu(id);
        }
        return PLUGIN_HANDLED;
    }

    new tIdx = g_iEditingTrig[id];
    new data[8], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new iEncoded = str_to_num(data);

    if (iEncoded == 9999) {
        menu_destroy(menu);
        if (tIdx >= 0 && tIdx < g_iTotalTriggers) {
            if (g_iTrigModelID[tIdx] != -1) ShowModelTrigEditMenu(id);
            else ShowStandaloneTrigMenu(id);
        }
        return PLUGIN_HANDLED;
    }

    if (tIdx < 0 || tIdx >= g_iTotalTriggers) { menu_destroy(menu); return PLUGIN_HANDLED; }

    new iEventType = iEncoded / 100;
    new iActionID = iEncoded % 100;
    new iBit = (1 << iActionID);

    if (iEventType == 1) g_iTrigEnterActions[tIdx] ^= iBit;
    else if (iEventType == 2) g_iTrigLeaveActions[tIdx] ^= iBit;
    else g_iTrigStayActions[tIdx] ^= iBit;

    menu_destroy(menu);
    ShowActionMenu(id, iEventType);
    return PLUGIN_HANDLED;
}

public Task_UpdateSystem() {
    new Float:vCurrent[3], Float:vTarget[3], Float:vDir[3], Float:flDist;
    new Float:vPlayerOrigin[3], Float:vMins[3], Float:vMaxs[3];
    new Float:flCurrentTime = get_gametime();

    for (new i = 0; i < g_iTotalSpawned; i++) {
        if (!pev_valid(g_iEntityID[i])) continue;

        if (g_bIsMoving[i] && g_iPathCount[i] > 1 && !g_bIsDead[i]) {
            pev(g_iEntityID[i], pev_origin, vCurrent);
            for (new j = 0; j < 3; j++) vTarget[j] = g_vPath[i][g_iCurPath[i]][j];
            xs_vec_sub(vTarget, vCurrent, vDir);
            flDist = xs_vec_len(vDir);

            if (flDist < 5.0) {
                g_iCurPath[i]++;
                if (g_iCurPath[i] >= g_iPathCount[i]) g_iCurPath[i] = 0;
            } else {
                xs_vec_normalize(vDir, vDir);
                xs_vec_mul_scalar(vDir, 5.0, vDir);
                xs_vec_add(vCurrent, vDir, vDir);
                for (new j = 0; j < 3; j++) g_vOrigin[i][j] = vDir[j];
                set_pev(g_iEntityID[i], pev_origin, g_vOrigin[i]);
            }
        }

        for (new p = 1; p <= 32; p++) {
            if (!is_user_connected(p)) continue;
            if (g_iTargetIdx[p] == i) {
                if (g_iPathCount[i] > 0) {
                    pev(g_iEntityID[i], pev_origin, vCurrent);
                    for (new k = 0; k < g_iPathCount[i]; k++) {
                        DrawLine(vCurrent, g_vPath[i][k], 255, 0, 0);
                        if (k > 0) DrawLine(g_vPath[i][k-1], g_vPath[i][k], 255, 0, 0);
                    }
                    if (g_iPathCount[i] > 1) DrawLine(g_vPath[i][g_iPathCount[i]-1], g_vPath[i][0], 255, 0, 0);
                }
                break;
            }
        }
    }

    for (new t = 0; t < g_iTotalTriggers; t++) {
        if (!pev_valid(g_iTrigEntID[t])) continue;

        if (g_iTrigModelID[t] != -1) {
            new mIdx = g_iTrigModelID[t];
            if (mIdx >= 0 && mIdx < g_iTotalSpawned && pev_valid(g_iEntityID[mIdx])) {
                for (new j = 0; j < 3; j++) g_vTrigOrigin[t][j] = g_vOrigin[mIdx][j];
                set_pev(g_iTrigEntID[t], pev_origin, g_vTrigOrigin[t]);
            }
        }

        for (new j = 0; j < 3; j++) {
            vMins[j] = g_vTrigOrigin[t][j] + g_vTrigMins[t][j];
            vMaxs[j] = g_vTrigOrigin[t][j] + g_vTrigMaxs[t][j];
        }

        for (new p = 1; p <= 32; p++) {
            if (!is_user_alive(p)) continue;
            pev(p, pev_origin, vPlayerOrigin);

            new bool:bInside = (vPlayerOrigin[0] >= vMins[0] && vPlayerOrigin[0] <= vMaxs[0] &&
                                vPlayerOrigin[1] >= vMins[1] && vPlayerOrigin[1] <= vMaxs[1] &&
                                vPlayerOrigin[2] >= vMins[2] && vPlayerOrigin[2] <= vMaxs[2]);

            if (bInside && !g_bPlayerInTrigger[p][t]) {
                g_bPlayerInTrigger[p][t] = true;
                g_flLastStayTime[p][t] = flCurrentTime;
                ExecuteActions(p, t, g_iTrigEnterActions[t]);
            } else if (!bInside && g_bPlayerInTrigger[p][t]) {
                g_bPlayerInTrigger[p][t] = false;
                ExecuteActions(p, t, g_iTrigLeaveActions[t]);
            } else if (bInside && g_bPlayerInTrigger[p][t]) {
                if (g_iTrigStayActions[t] != 0 && (flCurrentTime - g_flLastStayTime[p][t] >= g_flTrigStayInterval[t])) {
                    g_flLastStayTime[p][t] = flCurrentTime;
                    ExecuteActions(p, t, g_iTrigStayActions[t]);
                }
            }

            if (bInside && g_bTrigSolid[t]) {
                new Float:distances[6];
                distances[0] = vPlayerOrigin[0] - vMins[0];
                distances[1] = vMaxs[0] - vPlayerOrigin[0];
                distances[2] = vPlayerOrigin[1] - vMins[1];
                distances[3] = vMaxs[1] - vPlayerOrigin[1];
                distances[4] = vPlayerOrigin[2] - vMins[2];
                distances[5] = vMaxs[2] - vPlayerOrigin[2];

                new iMinFace = 0;
                for (new d = 1; d < 6; d++) {
                    if (distances[d] < distances[iMinFace]) iMinFace = d;
                }

                new Float:vNewOrigin[3];
                vNewOrigin[0] = vPlayerOrigin[0];
                vNewOrigin[1] = vPlayerOrigin[1];
                vNewOrigin[2] = vPlayerOrigin[2];

                switch (iMinFace) {
                    case 0: vNewOrigin[0] = vMins[0] - 1.0;
                    case 1: vNewOrigin[0] = vMaxs[0] + 1.0;
                    case 2: vNewOrigin[1] = vMins[1] - 1.0;
                    case 3: vNewOrigin[1] = vMaxs[1] + 1.0;
                    case 4: vNewOrigin[2] = vMins[2] - 1.0;
                    case 5: vNewOrigin[2] = vMaxs[2] + 1.0;
                }

                set_pev(p, pev_origin, vNewOrigin);
            }
        }

        for (new p = 1; p <= 32; p++) {
            if (!is_user_connected(p)) continue;
            new bool:bDraw = false;

            if (g_iEditingTrig[p] == t && g_bShowTrigger[p]) {
                bDraw = true;
            } else if (g_iTargetIdx[p] >= 0 && g_iTargetIdx[p] < g_iTotalSpawned && g_iTrigModelID[t] == g_iTargetIdx[p]) {
                if (g_bTrigVisible[t]) bDraw = true;
            }

            if (bDraw) {
                new r, g, b;
                if (g_bTrigSolid[t]) { r = 255; g = 0; b = 0; }
                else { r = 0; g = 255; b = 0; }
                DrawBox(g_vTrigOrigin[t], g_vTrigMins[t], g_vTrigMaxs[t], r, g, b);
            }
        }
    }
}

ExecuteActions(id, iTrigID, iActionsMask) {
    for (new i = 0; i < g_iActionCount; i++) {
        if (iActionsMask & (1 << i)) {
            ExecuteBuiltinAction(id, iTrigID, i);
        }
    }
}

ExecuteBuiltinAction(id, iTrigID, iActionID) {
    switch (iActionID) {
        case 0: { }
        case 1: {
            new hp = get_user_health(id) + 25;
            set_user_health(id, hp);
            client_print(id, print_chat, "[TRIG] +25 HP (теперь %d)", hp);
        }
        case 2: {
            set_user_health(id, 100);
            client_print(id, print_chat, "[TRIG] HP установлено на 100");
        }
        case 3: {
            user_kill(id);
            client_print(id, print_chat, "[TRIG] Вы убиты триггером!");
        }
        case 4: {
            set_user_gravity(id, 0.5);
            client_print(id, print_chat, "[TRIG] Гравитация снижена!");
        }
        case 5: {
            set_user_gravity(id, 1.0);
            client_print(id, print_chat, "[TRIG] Гравитация сброшена");
        }
        case 6: {
            client_print(id, print_chat, "[TRIG] Вы в зоне триггера [%d]!", iTrigID);
        }
        case 7: {
            new hp = get_user_health(id) - 5;
            if (hp <= 0) { user_kill(id); }
            else { set_user_health(id, hp); }
            client_print(id, print_chat, "[TRIG] -5 HP", hp);
        }
        case 8: {
            new armor = get_user_armor(id) + 25;
            set_user_armor(id, armor);
            client_print(id, print_chat, "[TRIG] +25 Брони (теперь %d)", armor);
        }
    }
}
SpawnModel(const szModel[], Float:vOrigin[3], Float:vAngles[3], Float:flScale) {
    if (g_iTotalSpawned >= MAX_SPAWNED) {
        server_print("[CM] Достигнут лимит моделей (%d)!", MAX_SPAWNED);
        return -1;
    }

    new iEnt = create_entity("info_target");
    if (!pev_valid(iEnt)) return -1;

    new iIdx = g_iTotalSpawned;
    copy(g_szModelPath[iIdx], charsmax(g_szModelPath[]), szModel);
    for (new j = 0; j < 3; j++) {
        g_vOrigin[iIdx][j] = vOrigin[j];
        g_vAngles[iIdx][j] = vAngles[j];
        g_vRenderColor[iIdx][j] = 255.0;
    }
    g_flScale[iIdx] = flScale;
    g_iSequence[iIdx] = 0;
    g_iMaxSeq[iIdx] = UTIL_GetModelSeqCount(szModel);
    g_flFramerate[iIdx] = 0.0;
    g_bIsMoving[iIdx] = false;
    g_iPathCount[iIdx] = 0;
    g_iCurPath[iIdx] = 0;
    g_iRenderMode[iIdx] = kRenderNormal;
    g_flRenderAmt[iIdx] = 255.0;
    g_iHealth[iIdx] = 0;
    g_bIsDead[iIdx] = false;
    g_bSolid[iIdx] = false;
    g_iEntityID[iIdx] = iEnt;

    // Порядок важен: сначала модель, потом spawn (вычислит реальный bbox)
    set_pev(iEnt, pev_classname, MODEL_CLASSNAME);
    engfunc(EngFunc_SetModel, iEnt, szModel);
    set_pev(iEnt, pev_origin, vOrigin);
    set_pev(iEnt, pev_angles, vAngles);
    dllfunc(DLLFunc_Spawn, iEnt);

    // Масштабируем bbox если модель не 1:1
    if (flScale != 1.0) {
        new Float:fMins[3], Float:fMaxs[3];
        pev(iEnt, pev_mins, fMins);
        pev(iEnt, pev_maxs, fMaxs);
        for (new j = 0; j < 3; j++) {
            fMins[j] *= flScale;
            fMaxs[j] *= flScale;
        }
        engfunc(EngFunc_SetSize, iEnt, fMins, fMaxs);
        set_pev(iEnt, pev_scale, flScale);
    }

    set_pev(iEnt, pev_movetype, MOVETYPE_NONE);
    set_pev(iEnt, pev_solid, SOLID_NOT);
    set_pev(iEnt, pev_takedamage, DAMAGE_NO);
    set_pev(iEnt, pev_rendermode, kRenderNormal);
    set_pev(iEnt, pev_renderamt, 255.0);
    set_pev(iEnt, pev_rendercolor, Float:{255.0, 255.0, 255.0});

    g_iTotalSpawned++;
    return iIdx;
}

UpdateModel(iIdx) {
    if (iIdx < 0 || iIdx >= g_iTotalSpawned || !pev_valid(g_iEntityID[iIdx])) return;

    new iEnt = g_iEntityID[iIdx];
    set_pev(iEnt, pev_origin, g_vOrigin[iIdx]);
    set_pev(iEnt, pev_angles, g_vAngles[iIdx]);
    set_pev(iEnt, pev_sequence, g_iSequence[iIdx]);
    set_pev(iEnt, pev_framerate, g_flFramerate[iIdx]);

    // Обновляем bbox при изменении масштаба
    if (g_flScale[iIdx] != 1.0) {
        set_pev(iEnt, pev_scale, g_flScale[iIdx]);
        // Пересчитываем bbox: сначала получаем оригинальный из модели,
        // потом масштабируем
        new szModel[128];
        pev(iEnt, pev_model, szModel, charsmax(szModel));
        if (szModel[0] != 0) {
            new Float:fMins[3], Float:fMaxs[3];
            // Временно сбрасываем масштаб чтобы получить оригинальный bbox
            set_pev(iEnt, pev_scale, 1.0);
            engfunc(EngFunc_SetModel, iEnt, szModel);
            dllfunc(DLLFunc_Spawn, iEnt);
            pev(iEnt, pev_mins, fMins);
            pev(iEnt, pev_maxs, fMaxs);
            for (new j = 0; j < 3; j++) {
                fMins[j] *= g_flScale[iIdx];
                fMaxs[j] *= g_flScale[iIdx];
            }
            engfunc(EngFunc_SetSize, iEnt, fMins, fMaxs);
            set_pev(iEnt, pev_scale, g_flScale[iIdx]);
        }
    }

    if (!g_bIsDead[iIdx]) {
        set_pev(iEnt, pev_rendermode, g_iRenderMode[iIdx]);
        set_pev(iEnt, pev_renderamt, g_flRenderAmt[iIdx]);
        set_pev(iEnt, pev_rendercolor, g_vRenderColor[iIdx]);
    }
}



CreateTrigger(Float:vOrigin[3], iModelID) {
    if (g_iTotalTriggers >= MAX_TRIGGERS) {
        client_print(0, print_chat, "[TRIG] Достигнут лимит триггеров (%d)!", MAX_TRIGGERS);
        return -1;
    }

    new iEnt = create_entity("info_target");
    if (!pev_valid(iEnt)) return -1;

    new tIdx = g_iTotalTriggers;
    for (new j = 0; j < 3; j++) {
        g_vTrigOrigin[tIdx][j] = vOrigin[j];
    }
    g_vTrigMins[tIdx][0] = -50.0;
    g_vTrigMins[tIdx][1] = -50.0;
    g_vTrigMins[tIdx][2] = -50.0;
    g_vTrigMaxs[tIdx][0] = 50.0;
    g_vTrigMaxs[tIdx][1] = 50.0;
    g_vTrigMaxs[tIdx][2] = 50.0;
    g_iTrigEntID[tIdx] = iEnt;
    g_iTrigModelID[tIdx] = iModelID;
    g_iTrigEnterActions[tIdx] = 0;
    g_iTrigLeaveActions[tIdx] = 0;
    g_iTrigStayActions[tIdx] = 0;
    g_flTrigStayInterval[tIdx] = 1.0;
    g_bTrigVisible[tIdx] = true;
    g_bTrigSolid[tIdx] = false;

    for (new p = 1; p <= 32; p++) {
        g_bPlayerInTrigger[p][tIdx] = false;
        g_flLastStayTime[p][tIdx] = 0.0;
    }

    set_pev(iEnt, pev_classname, TRIGGER_CLASSNAME);
    set_pev(iEnt, pev_origin, vOrigin);
    set_pev(iEnt, pev_movetype, MOVETYPE_NONE);
    set_pev(iEnt, pev_solid, SOLID_NOT);
    engfunc(EngFunc_SetSize, iEnt, g_vTrigMins[tIdx], g_vTrigMaxs[tIdx]);

    g_iTotalTriggers++;
    return tIdx;
}

UpdateTriggerEntity(tIdx) {
    if (tIdx < 0 || tIdx >= g_iTotalTriggers || !pev_valid(g_iTrigEntID[tIdx])) return;
    set_pev(g_iTrigEntID[tIdx], pev_origin, g_vTrigOrigin[tIdx]);
    engfunc(EngFunc_SetSize, g_iTrigEntID[tIdx], g_vTrigMins[tIdx], g_vTrigMaxs[tIdx]);
}

DeleteModel(iIdx) {
    if (iIdx < 0 || iIdx >= g_iTotalSpawned) return;

    if (pev_valid(g_iEntityID[iIdx])) {
        engfunc(EngFunc_RemoveEntity, g_iEntityID[iIdx]);
    }
    g_iEntityID[iIdx] = 0;

    new t = g_iTotalTriggers - 1;
    while (t >= 0) {
        if (g_iTrigModelID[t] == iIdx) {
            DeleteTrigger(t);
        }
        t--;
    }

    for (new i = iIdx; i < g_iTotalSpawned - 1; i++) {
        copy(g_szModelPath[i], charsmax(g_szModelPath[]), g_szModelPath[i+1]);
        for (new j = 0; j < 3; j++) {
            g_vOrigin[i][j] = g_vOrigin[i+1][j];
            g_vAngles[i][j] = g_vAngles[i+1][j];
            g_vRenderColor[i][j] = g_vRenderColor[i+1][j];
            for (new p = 0; p < MAX_PATH_POINTS; p++) {
                g_vPath[i][p][j] = g_vPath[i+1][p][j];
            }
        }
        g_flScale[i] = g_flScale[i+1];
        g_iSequence[i] = g_iSequence[i+1];
        g_iMaxSeq[i] = g_iMaxSeq[i+1];
        g_flFramerate[i] = g_flFramerate[i+1];
        g_bIsMoving[i] = g_bIsMoving[i+1];
        g_iPathCount[i] = g_iPathCount[i+1];
        g_iCurPath[i] = g_iCurPath[i+1];
        g_iRenderMode[i] = g_iRenderMode[i+1];
        g_flRenderAmt[i] = g_flRenderAmt[i+1];
        g_iEntityID[i] = g_iEntityID[i+1];
        g_iHealth[i] = g_iHealth[i+1];
        g_bIsDead[i] = g_bIsDead[i+1];
        g_bSolid[i] = g_bSolid[i+1];
    }
    g_iTotalSpawned--;

    for (new t2 = 0; t2 < g_iTotalTriggers; t2++) {
        if (g_iTrigModelID[t2] > iIdx) g_iTrigModelID[t2]--;
        else if (g_iTrigModelID[t2] == iIdx) g_iTrigModelID[t2] = -1;
    }

    for (new p = 1; p <= 32; p++) {
        if (g_iTargetIdx[p] == iIdx) g_iTargetIdx[p] = -1;
        else if (g_iTargetIdx[p] > iIdx) g_iTargetIdx[p]--;
    }
}

DeleteTrigger(tIdx) {
    if (tIdx < 0 || tIdx >= g_iTotalTriggers) return;

    if (pev_valid(g_iTrigEntID[tIdx])) {
        engfunc(EngFunc_RemoveEntity, g_iTrigEntID[tIdx]);
    }
    g_iTrigEntID[tIdx] = 0;

    for (new i = tIdx; i < g_iTotalTriggers - 1; i++) {
        for (new j = 0; j < 3; j++) {
            g_vTrigOrigin[i][j] = g_vTrigOrigin[i+1][j];
            g_vTrigMins[i][j] = g_vTrigMins[i+1][j];
            g_vTrigMaxs[i][j] = g_vTrigMaxs[i+1][j];
        }
        g_iTrigEntID[i] = g_iTrigEntID[i+1];
        g_iTrigModelID[i] = g_iTrigModelID[i+1];
        g_iTrigEnterActions[i] = g_iTrigEnterActions[i+1];
        g_iTrigLeaveActions[i] = g_iTrigLeaveActions[i+1];
        g_iTrigStayActions[i] = g_iTrigStayActions[i+1];
        g_flTrigStayInterval[i] = g_flTrigStayInterval[i+1];
        g_bTrigVisible[i] = g_bTrigVisible[i+1];
        g_bTrigSolid[i] = g_bTrigSolid[i+1];
        for (new p = 1; p <= 32; p++) {
            g_bPlayerInTrigger[p][i] = g_bPlayerInTrigger[p][i+1];
            g_flLastStayTime[p][i] = g_flLastStayTime[p][i+1];
        }
    }
    g_iTotalTriggers--;

    for (new p = 1; p <= 32; p++) {
        g_bPlayerInTrigger[p][g_iTotalTriggers] = false;
        g_flLastStayTime[p][g_iTotalTriggers] = 0.0;
    }

    for (new p = 1; p <= 32; p++) {
        if (g_iEditingTrig[p] == tIdx) g_iEditingTrig[p] = -1;
        else if (g_iEditingTrig[p] > tIdx) g_iEditingTrig[p]--;
    }
}

SaveModels() {
    new f = fopen(g_szModelsFile, "w");
    if (!f) {
        server_print("[CM] Ошибка создания файла: %s", g_szModelsFile);
        return;
    }

    fprintf(f, "// Custom Models Save File for map: %s^n", g_szMapName);
    fprintf(f, "// DO NOT EDIT MANUALLY UNLESS YOU KNOW WHAT YOU ARE DOING^n^n");
    fprintf(f, "%d^n", g_iTotalSpawned);

    for (new i = 0; i < g_iTotalSpawned; i++) {
        fprintf(f, "^"%s^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%d^" ^"%d^" ^"%.4f^" ^"%d^" ^"%d^" ^"%d^"^n",
            g_szModelPath[i],
            g_vOrigin[i][0], g_vOrigin[i][1], g_vOrigin[i][2],
            g_vAngles[i][0], g_vAngles[i][1], g_vAngles[i][2],
            g_flScale[i],
            g_iSequence[i], g_iMaxSeq[i], g_flFramerate[i],
            g_bIsMoving[i] ? 1 : 0, g_iPathCount[i], g_iCurPath[i]
        );

        fprintf(f, "^"%d^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%d^" ^"%d^" ^"%d^"^n",
            g_iRenderMode[i], g_flRenderAmt[i],
            g_vRenderColor[i][0], g_vRenderColor[i][1], g_vRenderColor[i][2],
            g_iHealth[i],
            g_bIsDead[i] ? 1 : 0,
            g_bSolid[i] ? 1 : 0
        );

        for (new p = 0; p < g_iPathCount[i]; p++) {
            fprintf(f, "PATH ^"%.4f^" ^"%.4f^" ^"%.4f^"^n",
                g_vPath[i][p][0], g_vPath[i][p][1], g_vPath[i][p][2]);
        }
    }

    fclose(f);
    server_print("[CM] Сохранено %d моделей в %s", g_iTotalSpawned, g_szModelsFile);
}

LoadModels() {
    new f = fopen(g_szModelsFile, "r");
    if (!f) return;

    new szLine[1024];
    new iSkipCount = 0;
    new bool:bCountRead = false;

    new iCount = 0;

    while (iSkipCount < 3 && fgets(f, szLine, charsmax(szLine))) {
        trim(szLine);
        if (szLine[0] != '/') {
            bCountRead = true;
            iSkipCount = 3;
        } else {
            iSkipCount++;
        }
    }

    if (!bCountRead) {
        if (fgets(f, szLine, charsmax(szLine))) {
            trim(szLine);
            iCount = str_to_num(szLine);
        }
    } else {
        iCount = str_to_num(szLine);
    }

    new n = 0;
    while (n < iCount && n < MAX_SPAWNED) {
        if (!fgets(f, szLine, charsmax(szLine))) {
            n = iCount;
        } else {
            trim(szLine);
            if (strlen(szLine) == 0) {
                // пустая строка - пропускаем, не увеличиваем n
            } else {
                new szPath[128];
                new s1[32], s2[32], s3[32], s4[32], s5[32], s6[32], s7[32];
                new s8[8], s9[8], s10[32], s11[8], s12[8], s13[8];

                parse(szLine, szPath, charsmax(szPath),
                    s1, charsmax(s1), s2, charsmax(s2), s3, charsmax(s3),
                    s4, charsmax(s4), s5, charsmax(s5), s6, charsmax(s6),
                    s7, charsmax(s7), s8, charsmax(s8), s9, charsmax(s9),
                    s10, charsmax(s10), s11, charsmax(s11), s12, charsmax(s12), s13, charsmax(s13)
                );

                new i = g_iTotalSpawned;
                copy(g_szModelPath[i], charsmax(g_szModelPath[]), szPath);
                g_vOrigin[i][0] = str_to_float(s1);
                g_vOrigin[i][1] = str_to_float(s2);
                g_vOrigin[i][2] = str_to_float(s3);
                g_vAngles[i][0] = str_to_float(s4);
                g_vAngles[i][1] = str_to_float(s5);
                g_vAngles[i][2] = str_to_float(s6);
                g_flScale[i] = str_to_float(s7);
                g_iSequence[i] = str_to_num(s8);
                g_iMaxSeq[i] = str_to_num(s9);
                g_flFramerate[i] = str_to_float(s10);
                g_bIsMoving[i] = (str_to_num(s11) != 0);
                new iSavedPathCount = str_to_num(s12);
                g_iPathCount[i] = 0;
                g_iCurPath[i] = str_to_num(s13);

                if (!fgets(f, szLine, charsmax(szLine))) {
                    n = iCount;
                } else {
                    trim(szLine);

                    new r1[8], r2[32], r3[32], r4[32], r5[32], r6[8], r7[8], r8[8];
                    parse(szLine, r1, charsmax(r1), r2, charsmax(r2), r3, charsmax(r3),
                        r4, charsmax(r4), r5, charsmax(r5), r6, charsmax(r6), r7, charsmax(r7), r8, charsmax(r8)
                    );

                    g_iRenderMode[i] = str_to_num(r1);
                    g_flRenderAmt[i] = str_to_float(r2);
                    g_vRenderColor[i][0] = str_to_float(r3);
                    g_vRenderColor[i][1] = str_to_float(r4);
                    g_vRenderColor[i][2] = str_to_float(r5);
                    g_iHealth[i] = str_to_num(r6);
                    g_bIsDead[i] = (str_to_num(r7) != 0);
                    g_bSolid[i] = (str_to_num(r8) != 0);

                    new p2 = 0;
                    while (p2 < iSavedPathCount && p2 < MAX_PATH_POINTS) {
                        if (!fgets(f, szLine, charsmax(szLine))) {
                            p2 = iSavedPathCount;
                        } else {
                            trim(szLine);
                            if (szLine[0] == 'P' && szLine[1] == 'A' && szLine[2] == 'T' && szLine[3] == 'H') {
                                new pp1[32], pp2[32], pp3[32], ppDummy[8];
                                parse(szLine, ppDummy, charsmax(ppDummy), pp1, charsmax(pp1), pp2, charsmax(pp2), pp3, charsmax(pp3));
                                g_vPath[i][g_iPathCount[i]][0] = str_to_float(pp1);
                                g_vPath[i][g_iPathCount[i]][1] = str_to_float(pp2);
                                g_vPath[i][g_iPathCount[i]][2] = str_to_float(pp3);
                                g_iPathCount[i]++;
                            }
                            p2++;
                        }
                    }

                                        g_iEntityID[i] = create_entity("info_target");
                    if (pev_valid(g_iEntityID[i])) {
                        set_pev(g_iEntityID[i], pev_classname, MODEL_CLASSNAME);
                        engfunc(EngFunc_SetModel, g_iEntityID[i], g_szModelPath[i]);
                        set_pev(g_iEntityID[i], pev_origin, g_vOrigin[i]);
                        set_pev(g_iEntityID[i], pev_angles, g_vAngles[i]);
                        dllfunc(DLLFunc_Spawn, g_iEntityID[i]);

                        // Масштабируем bbox после spawn
                        if (g_flScale[i] != 1.0) {
                            new Float:ldMins[3], Float:ldMaxs[3];
                            pev(g_iEntityID[i], pev_mins, ldMins);
                            pev(g_iEntityID[i], pev_maxs, ldMaxs);
                            for (new ld = 0; ld < 3; ld++) {
                                ldMins[ld] *= g_flScale[i];
                                ldMaxs[ld] *= g_flScale[i];
                            }
                            engfunc(EngFunc_SetSize, g_iEntityID[i], ldMins, ldMaxs);
                            set_pev(g_iEntityID[i], pev_scale, g_flScale[i]);
                        }

                        set_pev(g_iEntityID[i], pev_sequence, g_iSequence[i]);
                        set_pev(g_iEntityID[i], pev_framerate, g_flFramerate[i]);
                        set_pev(g_iEntityID[i], pev_rendermode, g_iRenderMode[i]);
                        set_pev(g_iEntityID[i], pev_renderamt, g_flRenderAmt[i]);
                        set_pev(g_iEntityID[i], pev_rendercolor, g_vRenderColor[i]);

                        if (g_bIsDead[i]) {
                            set_pev(g_iEntityID[i], pev_solid, SOLID_NOT);
                            set_pev(g_iEntityID[i], pev_takedamage, DAMAGE_NO);
                            set_pev(g_iEntityID[i], pev_effects, EF_NODRAW);
                            set_pev(g_iEntityID[i], pev_movetype, MOVETYPE_NONE);
                        } else {
                            if (g_bIsMoving[i]) {
                                set_pev(g_iEntityID[i], pev_solid, SOLID_NOT);
                                set_pev(g_iEntityID[i], pev_movetype, MOVETYPE_FLY);
                            } else {
                                set_pev(g_iEntityID[i], pev_solid, g_bSolid[i] ? SOLID_BBOX : SOLID_NOT);
                                set_pev(g_iEntityID[i], pev_movetype, MOVETYPE_NONE);
                            }
                            set_pev(g_iEntityID[i], pev_takedamage, g_iHealth[i] > 0 ? DAMAGE_AIM : DAMAGE_NO);
                            if (g_iHealth[i] > 0) set_pev(g_iEntityID[i], pev_health, float(g_iHealth[i]));
                        }
                    }

                    g_iTotalSpawned++;
                    n++;
                }
            }
        }
    }

    fclose(f);
    server_print("[CM] Загружено %d моделей для карты %s", g_iTotalSpawned, g_szMapName);
}

SaveTriggers() {
    new f = fopen(g_szTriggersFile, "w");
    if (!f) {
        server_print("[CM] Ошибка создания файла: %s", g_szTriggersFile);
        return;
    }

    fprintf(f, "// Custom Triggers Save File for map: %s^n", g_szMapName);
    fprintf(f, "// DO NOT EDIT MANUALLY^n^n");
    fprintf(f, "%d^n", g_iTotalTriggers);

    for (new t = 0; t < g_iTotalTriggers; t++) {
        fprintf(f, "^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%d^" ^"%d^" ^"%d^" ^"%d^" ^"%.4f^" ^"%d^" ^"%d^"^n",
            g_vTrigOrigin[t][0], g_vTrigOrigin[t][1], g_vTrigOrigin[t][2],
            g_vTrigMins[t][0], g_vTrigMins[t][1], g_vTrigMins[t][2],
            g_vTrigMaxs[t][0], g_vTrigMaxs[t][1], g_vTrigMaxs[t][2],
            g_iTrigModelID[t],
            g_iTrigEnterActions[t], g_iTrigLeaveActions[t], g_iTrigStayActions[t],
            g_flTrigStayInterval[t],
            g_bTrigVisible[t] ? 1 : 0,
            g_bTrigSolid[t] ? 1 : 0
        );
    }

    fclose(f);
    server_print("[CM] Сохранено %d триггеров в %s", g_iTotalTriggers, g_szTriggersFile);
}

LoadTriggers() {
    new f = fopen(g_szTriggersFile, "r");
    if (!f) return;

    new szLine[1024];
    new iSkipCount = 0;
    new bool:bCountRead = false;

    new iCount = 0;

    while (iSkipCount < 3 && fgets(f, szLine, charsmax(szLine))) {
        trim(szLine);
        if (szLine[0] != '/') {
            bCountRead = true;
            iSkipCount = 3;
        } else {
            iSkipCount++;
        }
    }

    if (!bCountRead) {
        if (fgets(f, szLine, charsmax(szLine))) {
            trim(szLine);
            iCount = str_to_num(szLine);
        }
    } else {
        iCount = str_to_num(szLine);
    }

    new n = 0;
    while (n < iCount && n < MAX_TRIGGERS) {
        if (!fgets(f, szLine, charsmax(szLine))) {
            n = iCount;
        } else {
            trim(szLine);
            if (strlen(szLine) == 0) {
                // пустая строка - пропускаем
            } else {
                new s1[32], s2[32], s3[32], s4[32], s5[32], s6[32];
                new s7[32], s8[32], s9[32], s10[8], s11[8], s12[8], s13[8];
                new s14[32], s15[8], s16[8];

                parse(szLine,
                    s1, charsmax(s1), s2, charsmax(s2), s3, charsmax(s3),
                    s4, charsmax(s4), s5, charsmax(s5), s6, charsmax(s6),
                    s7, charsmax(s7), s8, charsmax(s8), s9, charsmax(s9),
                    s10, charsmax(s10), s11, charsmax(s11), s12, charsmax(s12), s13, charsmax(s13),
                    s14, charsmax(s14), s15, charsmax(s15), s16, charsmax(s16)
                );

                new t = g_iTotalTriggers;
                g_vTrigOrigin[t][0] = str_to_float(s1);
                g_vTrigOrigin[t][1] = str_to_float(s2);
                g_vTrigOrigin[t][2] = str_to_float(s3);
                g_vTrigMins[t][0] = str_to_float(s4);
                g_vTrigMins[t][1] = str_to_float(s5);
                g_vTrigMins[t][2] = str_to_float(s6);
                g_vTrigMaxs[t][0] = str_to_float(s7);
                g_vTrigMaxs[t][1] = str_to_float(s8);
                g_vTrigMaxs[t][2] = str_to_float(s9);
                g_iTrigModelID[t] = str_to_num(s10);
                g_iTrigEnterActions[t] = str_to_num(s11);
                g_iTrigLeaveActions[t] = str_to_num(s12);
                g_iTrigStayActions[t] = str_to_num(s13);
                g_flTrigStayInterval[t] = str_to_float(s14);
                g_bTrigVisible[t] = (str_to_num(s15) != 0);
                g_bTrigSolid[t] = (str_to_num(s16) != 0);

                for (new p = 1; p <= 32; p++) {
                    g_bPlayerInTrigger[p][t] = false;
                    g_flLastStayTime[p][t] = 0.0;
                }

                g_iTrigEntID[t] = create_entity("info_target");
                if (pev_valid(g_iTrigEntID[t])) {
                    set_pev(g_iTrigEntID[t], pev_classname, TRIGGER_CLASSNAME);
                    set_pev(g_iTrigEntID[t], pev_origin, g_vTrigOrigin[t]);
                    set_pev(g_iTrigEntID[t], pev_movetype, MOVETYPE_NONE);
                    set_pev(g_iTrigEntID[t], pev_solid, SOLID_NOT);
                    engfunc(EngFunc_SetSize, g_iTrigEntID[t], g_vTrigMins[t], g_vTrigMaxs[t]);
                }

                g_iTotalTriggers++;
                n++;
            }
        }
    }

    fclose(f);
    server_print("[CM] Загружено %d триггеров для карты %s", g_iTotalTriggers, g_szMapName);
}

SaveAsTemplate(id, iIdx) {
    if (g_iTotalTemplates >= MAX_TEMPLATES) {
        client_print(id, print_chat, "[CM] Достигнут лимит шаблонов!");
        return;
    }

    new tIdx = g_iTotalTemplates;
    formatex(g_szTplName[tIdx], charsmax(g_szTplName[]), "Template_%d", tIdx + 1);

    formatex(g_szTplData[tIdx], charsmax(g_szTplData[]),
        "^"%s^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%d^" ^"%d^" ^"%.4f^" ^"%d^" ^"%d^" ^"%d^" ^"%d^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%.4f^" ^"%d^" ^"%d^" ^"%d^"",
        g_szModelPath[iIdx],
        g_vAngles[iIdx][0], g_vAngles[iIdx][1], g_vAngles[iIdx][2],
        g_flScale[iIdx],
        g_iSequence[iIdx], g_iMaxSeq[iIdx], g_flFramerate[iIdx],
        0, 0, 0,
        g_iRenderMode[iIdx], g_flRenderAmt[iIdx],
        g_vRenderColor[iIdx][0], g_vRenderColor[iIdx][1], g_vRenderColor[iIdx][2],
        g_iHealth[iIdx],
        0, 0,
        g_bSolid[iIdx] ? 1 : 0
    );

    g_iTotalTemplates++;
    SaveTemplatesToFile();
    client_print(id, print_chat, "[CM] Шаблон сохранен!");
}

SaveTemplatesToFile() {
    new f = fopen(g_szTemplatesFile, "w");
    if (!f) return;
    for (new i = 0; i < g_iTotalTemplates; i++) {
        fprintf(f, "^"%s^" %s^n", g_szTplName[i], g_szTplData[i]);
    }
    fclose(f);
}

LoadTemplates() {
    new f = fopen(g_szTemplatesFile, "r");
    if (!f) return;
    new szLine[1024], szName[64];
    g_iTotalTemplates = 0;
    while (g_iTotalTemplates < MAX_TEMPLATES && fgets(f, szLine, charsmax(szLine))) {
        trim(szLine);
        if (strlen(szLine) == 0 || szLine[0] == '/') continue;
        parse(szLine, szName, charsmax(szName), g_szTplData[g_iTotalTemplates], charsmax(g_szTplData[]));
        copy(g_szTplName[g_iTotalTemplates], charsmax(g_szTplName[]), szName);
        g_iTotalTemplates++;
    }
    fclose(f);
}

ShowTemplateMenu(id) {
    new menu = menu_create("\r[CM] \yШаблоны", "TemplateMenu_Handler");
    if (g_iTotalTemplates == 0) {
        menu_additem(menu, "\dНет сохраненных шаблонов", "0");
    } else {
        new szInfo[8];
        for (new i = 0; i < g_iTotalTemplates && i < 9; i++) {
            num_to_str(i, szInfo, charsmax(szInfo));
            menu_additem(menu, g_szTplName[i], szInfo);
        }
    }
    menu_setprop(menu, MPROP_EXITNAME, "Назад");
    menu_display(id, menu, 0);
}

public TemplateMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT || g_iTotalTemplates == 0) { menu_destroy(menu); Cmd_ModelMenu(id, ADMIN_LEVEL_H, 0); return PLUGIN_HANDLED; }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new tIdx = str_to_num(data);
    menu_destroy(menu);

    if (tIdx < 0 || tIdx >= g_iTotalTemplates) { Cmd_ModelMenu(id, ADMIN_LEVEL_H, 0); return PLUGIN_HANDLED; }

    new szPath[128], s1[32], s2[32], s3[32], s4[32], s5[32], s6[32], s7[32];
    new s8[8], s9[8], s10[32], s11[8], s12[8], s13[8], s14[8], s15[32], s16[32], s17[32], s18[32];
    new s19[8], s20[8], s21[8];

    parse(g_szTplData[tIdx], szPath, charsmax(szPath),
        s1, charsmax(s1), s2, charsmax(s2), s3, charsmax(s3), s4, charsmax(s4),
        s5, charsmax(s5), s6, charsmax(s6), s7, charsmax(s7), s8, charsmax(s8),
        s9, charsmax(s9), s10, charsmax(s10), s11, charsmax(s11), s12, charsmax(s12),
        s13, charsmax(s13), s14, charsmax(s14), s15, charsmax(s15), s16, charsmax(s16),
        s17, charsmax(s17), s18, charsmax(s18), s19, charsmax(s19), s20, charsmax(s20),
        s21, charsmax(s21)
    );

    new Float:vOrigin[3], Float:vAngles[3], Float:vForward[3];
    pev(id, pev_origin, vOrigin);
    pev(id, pev_v_angle, vAngles);
    angle_vector(vAngles, ANGLEVECTOR_FORWARD, vForward);
    vOrigin[0] += vForward[0] * 50.0;
    vOrigin[1] += vForward[1] * 50.0;
    vOrigin[2] += 20.0;

    vAngles[0] = str_to_float(s1);
    vAngles[1] = str_to_float(s2);
    vAngles[2] = str_to_float(s3);
    new Float:flScale = str_to_float(s4);

    new iNewIdx = SpawnModel(szPath, vOrigin, vAngles, flScale);
    if (iNewIdx != -1) {
        g_iSequence[iNewIdx] = str_to_num(s5);
        g_iMaxSeq[iNewIdx] = str_to_num(s6);
        g_flFramerate[iNewIdx] = str_to_float(s7);
        g_iRenderMode[iNewIdx] = str_to_num(s13);
        g_flRenderAmt[iNewIdx] = str_to_float(s14);
        g_vRenderColor[iNewIdx][0] = str_to_float(s15);
        g_vRenderColor[iNewIdx][1] = str_to_float(s16);
        g_vRenderColor[iNewIdx][2] = str_to_float(s17);
        g_iHealth[iNewIdx] = str_to_num(s18);
        g_bSolid[iNewIdx] = (str_to_num(s21) != 0);

        if (g_bSolid[iNewIdx]) {
            set_pev(g_iEntityID[iNewIdx], pev_solid, SOLID_BBOX);
        }
        if (g_iHealth[iNewIdx] > 0) {
            set_pev(g_iEntityID[iNewIdx], pev_takedamage, DAMAGE_AIM);
            set_pev(g_iEntityID[iNewIdx], pev_health, float(g_iHealth[iNewIdx]));
        }

        UpdateModel(iNewIdx);
        g_iTargetIdx[id] = iNewIdx;
        client_print(id, print_chat, "[CM] Модель [%d] создана из шаблона '%s'.", iNewIdx, g_szTplName[tIdx]);
    }

    Cmd_ModelMenu(id, ADMIN_LEVEL_H, 0);
    return PLUGIN_HANDLED;
}

GetAimedEntity(id) {
    new iOrigin[3];
    get_user_origin(id, iOrigin, 3);

    new Float:vOrigin[3];
    IVecFVec(iOrigin, vOrigin);

    new iBestEnt = -1;
    new Float:flMinDist = 100.0;
    new Float:vEntOrigin[3], Float:flDist;

    for (new i = 0; i < g_iTotalSpawned; i++) {
        if (!pev_valid(g_iEntityID[i]) || g_bIsDead[i]) continue;
        pev(g_iEntityID[i], pev_origin, vEntOrigin);
        flDist = get_distance_f(vOrigin, vEntOrigin);
        if (flDist < flMinDist) {
            flMinDist = flDist;
            iBestEnt = g_iEntityID[i];
        }
    }

    return iBestEnt;
}

GetAimedTriggerIndex(id) {
    new iOrigin[3];
    get_user_origin(id, iOrigin, 3);

    new Float:vOrigin[3];
    IVecFVec(iOrigin, vOrigin);

    new iBestIdx = -1;
    new Float:flMinDist = 150.0;
    new Float:vMins[3], Float:vMaxs[3], Float:flDist;

    for (new t = 0; t < g_iTotalTriggers; t++) {
        for (new j = 0; j < 3; j++) {
            vMins[j] = g_vTrigOrigin[t][j] + g_vTrigMins[t][j];
            vMaxs[j] = g_vTrigOrigin[t][j] + g_vTrigMaxs[t][j];
        }

        if (vOrigin[0] >= vMins[0] && vOrigin[0] <= vMaxs[0] &&
            vOrigin[1] >= vMins[1] && vOrigin[1] <= vMaxs[1] &&
            vOrigin[2] >= vMins[2] && vOrigin[2] <= vMaxs[2]) {
            flDist = 0.0;
        } else {
            new Float:vClosest[3];
            for (new j = 0; j < 3; j++) {
                if (vOrigin[j] < vMins[j]) vClosest[j] = vMins[j];
                else if (vOrigin[j] > vMaxs[j]) vClosest[j] = vMaxs[j];
                else vClosest[j] = vOrigin[j];
            }
            flDist = get_distance_f(vOrigin, vClosest);
        }

        if (flDist < flMinDist) {
            flMinDist = flDist;
            iBestIdx = t;
        }
    }

    return iBestIdx;
}

GetModelIndexByEnt(iEnt) {
    for (new i = 0; i < g_iTotalSpawned; i++) {
        if (g_iEntityID[i] == iEnt) return i;
    }
    return -1;
}

DrawLine(Float:vStart[3], Float:vEnd[3], r, g, b) {
    new iStart[3], iEnd[3];
    FVecIVec(vStart, iStart);
    FVecIVec(vEnd, iEnd);

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMPOINTS);
    write_coord(iStart[0]); write_coord(iStart[1]); write_coord(iStart[2]);
    write_coord(iEnd[0]); write_coord(iEnd[1]); write_coord(iEnd[2]);
    write_short(g_iSpriteLaser);
    write_byte(1);
    write_byte(10);
    write_byte(5);
    write_byte(5);
    write_byte(0);
    write_byte(r); write_byte(g); write_byte(b);
    write_byte(200);
    write_byte(0);
    message_end();
}

DrawBox(Float:vOrigin[3], Float:vMins[3], Float:vMaxs[3], r, g, b) {
    new Float:vA[3], Float:vB[3], Float:vC[3], Float:vD[3];
    new Float:vE[3], Float:vF[3], Float:vG[3], Float:vH[3];

    vA[0] = vOrigin[0] + vMins[0]; vA[1] = vOrigin[1] + vMins[1]; vA[2] = vOrigin[2] + vMins[2];
    vB[0] = vOrigin[0] + vMaxs[0]; vB[1] = vOrigin[1] + vMins[1]; vB[2] = vOrigin[2] + vMins[2];
    vC[0] = vOrigin[0] + vMaxs[0]; vC[1] = vOrigin[1] + vMaxs[1]; vC[2] = vOrigin[2] + vMins[2];
    vD[0] = vOrigin[0] + vMins[0]; vD[1] = vOrigin[1] + vMaxs[1]; vD[2] = vOrigin[2] + vMins[2];
    vE[0] = vOrigin[0] + vMins[0]; vE[1] = vOrigin[1] + vMins[1]; vE[2] = vOrigin[2] + vMaxs[2];
    vF[0] = vOrigin[0] + vMaxs[0]; vF[1] = vOrigin[1] + vMins[1]; vF[2] = vOrigin[2] + vMaxs[2];
    vG[0] = vOrigin[0] + vMaxs[0]; vG[1] = vOrigin[1] + vMaxs[1]; vG[2] = vOrigin[2] + vMaxs[2];
    vH[0] = vOrigin[0] + vMins[0]; vH[1] = vOrigin[1] + vMaxs[1]; vH[2] = vOrigin[2] + vMaxs[2];

    DrawLine(vA, vB, r, g, b); DrawLine(vB, vC, r, g, b);
    DrawLine(vC, vD, r, g, b); DrawLine(vD, vA, r, g, b);
    DrawLine(vE, vF, r, g, b); DrawLine(vF, vG, r, g, b);
    DrawLine(vG, vH, r, g, b); DrawLine(vH, vE, r, g, b);
    DrawLine(vA, vE, r, g, b); DrawLine(vB, vF, r, g, b);
    DrawLine(vC, vG, r, g, b); DrawLine(vD, vH, r, g, b);
}

stock get_filename(const szPath[], szOut[], iLen) {
    new iPos = strlen(szPath) - 1;
    while (iPos > 0 && szPath[iPos] != '/' && szPath[iPos] != 92) iPos--;
    if (szPath[iPos] == '/' || szPath[iPos] == 92) iPos++;
    copy(szOut, iLen, szPath[iPos]);
}