#include <amxmodx>
#include <amxmisc>
#include <hamsandwich>
#include <reapi>
#include <fakemeta>
#include <sqlx>

#define PLUGIN "Weapon Skins Shop (shared points)"
#define VERSION "4.1"
#define AUTHOR "nb_team"

native points_get(id);
native points_set(id, amount);
native points_is_loaded(id);
native points_load(id);
native points_set_loaded(id);

#define KEY_1 (1<<0)
#define KEY_2 (1<<1)
#define KEY_3 (1<<2)
#define KEY_4 (1<<3)
#define KEY_5 (1<<4)
#define KEY_6 (1<<5)
#define KEY_7 (1<<6)
#define KEY_8 (1<<7)
#define KEY_9 (1<<8)
#define KEY_0 (1<<9)
#define KEYS_ALL 1023

#define ITEMS_PER_PAGE 7

new const MENU_WEAPON[]  = "WSkinsWeaponMenu";
new const MENU_SKIN[]    = "WSkinsSkinMenu";
new const MENU_CONFIRM[] = "WSkinsConfirmMenu";

new Array:g_aWeaponClasses
new Array:g_aWeaponMenuNames
new Array:g_aVModels
new Array:g_aSkinNames
new Array:g_aSkinPrices

new Array:g_aPlayerSkin[33]
new g_iCurrentMenuSlot[33]
new g_iPendingWeapon[33]

new g_szOwned[33][512]
new g_szAuth[33][35]

new Handle:g_hDB
new bool:g_bDBConnected
new g_iRetryCount
new bool:g_bPlayerQueued[33]
new bool:g_bPlayerDataLoaded[33]

new g_iMenuState[33]
new g_iPendingSlot[33]
new g_iPendingSkin[33]

new g_iWeaponPage[33]   // текущая страница списка оружий
new g_iSkinPage[33]     // текущая страница списка скинов

new g_szMainMenuCmd[64] // команда возврата в главное меню (из menuSystem.ini)

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    register_clcmd("say /wskins", "Cmd_MainMenu")
    register_clcmd("say_team /wskins", "Cmd_MainMenu")
    register_clcmd("say /wpoints", "Cmd_Points")
    RegisterHam(Ham_AddPlayerItem, "player", "OnPlayerAddItem", 1)

    register_menucmd(register_menuid(MENU_WEAPON), KEYS_ALL, "Handle_WeaponMenu")
    register_menucmd(register_menuid(MENU_SKIN), KEYS_ALL, "Handle_SkinMenu")
    register_menucmd(register_menuid(MENU_CONFIRM), KEYS_ALL, "Handle_ConfirmMenu")

    LoadMenuSystemConfig()
}

public plugin_precache() {
    g_aWeaponClasses   = ArrayCreate(32)
    g_aWeaponMenuNames = ArrayCreate(64)
    g_aVModels         = ArrayCreate()
    g_aSkinNames       = ArrayCreate()
    g_aSkinPrices      = ArrayCreate()

    new szFile[256], szPath[256]
    get_configsdir(szPath, charsmax(szPath))
    formatex(szFile, charsmax(szFile), "%s/weapon_skins.ini", szPath)

    new f = fopen(szFile, "rt")
    if(!f) {
        log_amx("[WSkins] ОШИБКА: Конфиг не найден!")
        return
    }

    new szBuffer[512], szClass[32], szMenuName[64], szSkinName[64], szV[128], szPrice[8]
    while(!feof(f)) {
        fgets(f, szBuffer, charsmax(szBuffer))
        trim(szBuffer)
        if(!szBuffer[0] || szBuffer[0] == ';') continue

        new parsed = parse(szBuffer, szClass, charsmax(szClass),
                           szMenuName, charsmax(szMenuName),
                           szSkinName, charsmax(szSkinName),
                           szV, charsmax(szV),
                           szPrice, charsmax(szPrice))
        if(parsed < 4) continue

        new price = 0
        if(parsed >= 5) {
            price = str_to_num(szPrice)
            if(price < 0) price = 0
        }

        new iSlot = FindWeaponSlot(szClass)
        if(iSlot == -1) {
            ArrayPushString(g_aWeaponClasses, szClass)
            ArrayPushString(g_aWeaponMenuNames, szMenuName)

            new Array:aV = ArrayCreate(128)
            new Array:aN = ArrayCreate(64)
            new Array:aP = ArrayCreate(1)
            ArrayPushCell(g_aVModels, _:aV)
            ArrayPushCell(g_aSkinNames, _:aN)
            ArrayPushCell(g_aSkinPrices, _:aP)
            iSlot = ArraySize(g_aWeaponClasses) - 1
        }

        if(!file_exists(szV)) {
            log_amx("[WSkins] ВНИМАНИЕ: Файл не найден: %s", szV)
            continue
        }
        precache_model(szV)

        new Array:aV = Array:ArrayGetCell(g_aVModels, iSlot)
        new Array:aN = Array:ArrayGetCell(g_aSkinNames, iSlot)
        new Array:aP = Array:ArrayGetCell(g_aSkinPrices, iSlot)
        ArrayPushString(aV, szV)
        ArrayPushString(aN, szSkinName)
        ArrayPushCell(aP, price)
    }
    fclose(f)

    new iCount = ArraySize(g_aWeaponClasses)
    new szTemp[32]
    for(new i = 0; i < iCount; i++) {
        ArrayGetString(g_aWeaponClasses, i, szTemp, charsmax(szTemp))
        RegisterHam(Ham_Item_Deploy, szTemp, "Fwd_WeaponDeploy", 1)
    }
}

public plugin_cfg() {
    set_task(random_float(2.0, 10.0), "InitDatabase")
}

public plugin_end() {
    if(g_hDB != Empty_Handle) {
        SQL_FreeHandle(g_hDB)
        g_hDB = Empty_Handle
    }
}

// ============================================================================
// БД
// ============================================================================
public InitDatabase() {
    if(g_bDBConnected) return

    if(g_hDB != Empty_Handle) {
        SQL_FreeHandle(g_hDB)
        g_hDB = Empty_Handle
    }

    new h[64], u[64], p[64], d[64]
    get_cvar_string("amx_sql_host", h, 63)
    get_cvar_string("amx_sql_user", u, 63)
    get_cvar_string("amx_sql_pass", p, 63)
    get_cvar_string("amx_sql_db", d, 63)

    g_hDB = SQL_MakeDbTuple(h, u, p, d)

    SQL_ThreadQuery(g_hDB, "CheckDBConnection", "SELECT 1")
}

public CheckDBConnection(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt) {
    if(FailState != TQUERY_SUCCESS) {
        g_iRetryCount++
        if(g_iRetryCount < 30) {
            log_amx("[WSkins] DB not ready (%s), retry #%d in 10s...", Error, g_iRetryCount)
            set_task(10.0, "InitDatabase")
        } else {
            log_amx("[WSkins] DB connection failed permanently after 30 attempts.")
            ProcessQueue(false)
        }
        return
    }

    g_bDBConnected = true
    g_iRetryCount = 0
    log_amx("[WSkins] Database connected via thread.")

    new q[512]
    formatex(q, charsmax(q), "CREATE TABLE IF NOT EXISTS player_data (authid VARCHAR(32) PRIMARY KEY, points INT DEFAULT 0)")
    SQL_ThreadQuery(g_hDB, "VoidQueryIgnore", q)

    formatex(q, charsmax(q), "ALTER TABLE player_data ADD COLUMN weapon_owned TEXT")
    SQL_ThreadQuery(g_hDB, "VoidQueryIgnore", q)
    formatex(q, charsmax(q), "ALTER TABLE player_data ADD COLUMN selected_skins TEXT")
    SQL_ThreadQuery(g_hDB, "VoidQueryIgnore", q)

    ProcessQueue(true)
}

ProcessQueue(bool:success) {
    for(new i = 1; i <= 32; i++) {
        if(g_bPlayerQueued[i] && is_user_connected(i)) {
            g_bPlayerQueued[i] = false
            if(success && g_szAuth[i][0])
                LoadPlayerData(i)
        }
    }
}

public VoidQuery(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt) {
    if(FailState != TQUERY_SUCCESS)
        log_amx("[WSkins] DB Error (code %d): %s", Errcode, Error)
}

public VoidQueryIgnore(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt) {}

// ============================================================================
// КЛИЕНТЫ
// ============================================================================
public client_putinserver(id) {
    g_aPlayerSkin[id] = ArrayCreate(1)
    new iCount = ArraySize(g_aWeaponClasses)
    for(new i = 0; i < iCount; i++) {
        new Array:aSkins = Array:ArrayGetCell(g_aSkinNames, i)
        if(ArraySize(aSkins) > 0)
            ArrayPushCell(g_aPlayerSkin[id], 0)
        else
            ArrayPushCell(g_aPlayerSkin[id], -1)
    }
    g_iPendingWeapon[id] = 0
    g_szOwned[id][0] = 0
    g_iMenuState[id] = 0
    g_iPendingSlot[id] = -1
    g_iPendingSkin[id] = -1
    g_iWeaponPage[id] = 0
    g_iSkinPage[id] = 0
    g_bPlayerQueued[id] = false
    g_bPlayerDataLoaded[id] = false
    get_user_authid(id, g_szAuth[id], charsmax(g_szAuth[]))

    if(equali(g_szAuth[id], "STEAM_ID_PENDING") || !g_szAuth[id][0]) {
        g_bPlayerQueued[id] = true
        set_task(5.0, "RetryAuth", id)
        return
    }

    if(g_bDBConnected) {
        LoadPlayerData(id)
    } else {
        g_bPlayerQueued[id] = true
    }
}

public RetryAuth(taskid) {
    new id = taskid
    if(!is_user_connected(id)) return

    new szNewAuth[35]
    get_user_authid(id, szNewAuth, charsmax(szNewAuth))
    if(!equali(szNewAuth, "STEAM_ID_PENDING") && szNewAuth[0] && !equali(szNewAuth, g_szAuth[id])) {
        copy(g_szAuth[id], charsmax(g_szAuth[]), szNewAuth)
        g_bPlayerQueued[id] = false
        if(g_bDBConnected)
            LoadPlayerData(id)
        else
            g_bPlayerQueued[id] = true
    } else {
        set_task(5.0, "RetryAuth", id)
    }
}

public client_disconnected(id) {
    if(g_bDBConnected && g_szAuth[id][0] && g_bPlayerDataLoaded[id])
        SavePlayerData(id)

    if(g_aPlayerSkin[id] != Invalid_Array) {
        ArrayDestroy(g_aPlayerSkin[id])
        g_aPlayerSkin[id] = Invalid_Array
    }

    g_bPlayerQueued[id] = false
    g_bPlayerDataLoaded[id] = false
    g_szAuth[id][0] = 0
    g_iWeaponPage[id] = 0
    g_iSkinPage[id] = 0
}

// ============================================================================
// ДАННЫЕ ИГРОКА
// ============================================================================
LoadPlayerData(id) {
    if(!g_szAuth[id][0] || !g_bDBConnected) return

    new szSafe[48], q[512], data[1]
    data[0] = id

    copy(szSafe, charsmax(szSafe), g_szAuth[id])
    replace_all(szSafe, charsmax(szSafe), "'", "''")

    formatex(q, charsmax(q), "SELECT weapon_owned, selected_skins FROM player_data WHERE authid='%s'", szSafe)
    SQL_ThreadQuery(g_hDB, "LoadCB", q, data, sizeof(data))
}

public LoadCB(FailState, Handle:Q, Error[], Errcode, Data[], DataSize, Float:Qt) {
    new id = Data[0]
    if(!is_user_connected(id)) return
    if(FailState != TQUERY_SUCCESS) {
        log_amx("[WSkins] LoadCB error (code %d): %s", Errcode, Error)
        g_bPlayerDataLoaded[id] = true
        return
    }

    if(SQL_NumResults(Q) > 0) {
        SQL_ReadResult(Q, 0, g_szOwned[id], charsmax(g_szOwned[]))
        new szSelected[512]
        SQL_ReadResult(Q, 1, szSelected, charsmax(szSelected))
        if(szSelected[0] != 0) {
            ParseAndApplySelectedSkins(id, szSelected)
        }
    } else {
        new szSafe[48], q[512]
        copy(szSafe, charsmax(szSafe), g_szAuth[id])
        replace_all(szSafe, charsmax(szSafe), "'", "''")

        formatex(q, charsmax(q), "INSERT INTO player_data (authid, weapon_owned, selected_skins) VALUES ('%s', '', '') ON DUPLICATE KEY UPDATE authid=authid", szSafe)
        SQL_ThreadQuery(g_hDB, "VoidQuery", q)
    }

    EnsureDefaultSkin(id)
    SavePlayerData(id)
    g_bPlayerDataLoaded[id] = true
}

EnsureDefaultSkin(id) {
    new iCount = ArraySize(g_aWeaponClasses)
    for(new i = 0; i < iCount; i++) {
        new Array:aSkins = Array:ArrayGetCell(g_aSkinNames, i)
        if(ArraySize(aSkins) > 0) {
            if(!IsWeaponSkinOwned(id, i, 0)) {
                AddOwnedWeaponSkin(id, i, 0)
            }
            new curSkin = ArrayGetCell(g_aPlayerSkin[id], i)
            if(curSkin < 0 || !IsWeaponSkinOwned(id, i, curSkin)) {
                ArraySetCell(g_aPlayerSkin[id], i, 0)
            }
        }
    }
}

SavePlayerData(id) {
    if(!g_szAuth[id][0] || equali(g_szAuth[id], "STEAM_ID_PENDING") || !g_bDBConnected) return

    new szSafe[48], safeOwned[1024], safeSelected[1024], szSelected[512]

    copy(szSafe, charsmax(szSafe), g_szAuth[id])
    replace_all(szSafe, charsmax(szSafe), "'", "''")

    copy(safeOwned, charsmax(safeOwned), g_szOwned[id])
    replace_all(safeOwned, charsmax(safeOwned), "'", "''")

    BuildSelectedString(id, szSelected, charsmax(szSelected))
    copy(safeSelected, charsmax(safeSelected), szSelected)
    replace_all(safeSelected, charsmax(safeSelected), "'", "''")

    new q[1024]
    formatex(q, charsmax(q), "UPDATE player_data SET weapon_owned='%s', selected_skins='%s' WHERE authid='%s'",
             safeOwned, safeSelected, szSafe)
    SQL_ThreadQuery(g_hDB, "VoidQuery", q)
}

ParseAndApplySelectedSkins(id, const szSelected[]) {
    if(szSelected[0] == 0) return
    new szBuf[512], slot, skin
    copy(szBuf, charsmax(szBuf), szSelected)

    new iCount = ArraySize(g_aWeaponClasses)
    new piece[16], rest[512]
    while(szBuf[0] != 0) {
        strtok(szBuf, piece, charsmax(piece), rest, charsmax(rest), ',')
        if(piece[0] != 0) {
            new left[8], right[8]
            strtok(piece, left, charsmax(left), right, charsmax(right), ':')
            slot = str_to_num(left)
            skin = str_to_num(right)
            if(slot >= 0 && slot < iCount && g_aPlayerSkin[id] != Invalid_Array) {
                if(IsWeaponSkinOwned(id, slot, skin)) {
                    ArraySetCell(g_aPlayerSkin[id], slot, skin)
                }
            }
        }
        copy(szBuf, charsmax(szBuf), rest)
    }
}

BuildSelectedString(id, szOut[], maxlen) {
    szOut[0] = 0
    if(g_aPlayerSkin[id] == Invalid_Array) return
    new iCount = ArraySize(g_aWeaponClasses)
    new slotSkin
    for(new i = 0; i < iCount; i++) {
        slotSkin = ArrayGetCell(g_aPlayerSkin[id], i)
        if(slotSkin >= 0) {
            new tmp[16]
            formatex(tmp, charsmax(tmp), "%s%d:%d", szOut[0] ? "," : "", i, slotSkin)
            add(szOut, maxlen, tmp)
        }
    }
}

// ============================================================================
// МЕНЮ ВЫБОРА ОРУЖИЯ (старый стиль, пагинация)
// ============================================================================
public Cmd_MainMenu(id) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED
    if(!g_bPlayerDataLoaded[id]) {
        client_print(id, print_chat, "[WSkins] Подождите, данные ещё загружаются...")
        return PLUGIN_HANDLED
    }
    g_iWeaponPage[id] = 0 // при открытии — всегда с первой страницы
    ShowWeaponSelectMenu(id)
    return PLUGIN_HANDLED
}

ShowWeaponSelectMenu(id) {
    if(!is_user_connected(id)) return

    new iCount = ArraySize(g_aWeaponClasses)
    if(iCount == 0) {
        client_print(id, print_chat, "Нет загруженных скинов!")
        return
    }

    new iPages = (iCount + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE
    new iPage = g_iWeaponPage[id]
    if(iPage < 0) iPage = 0
    if(iPage >= iPages) iPage = iPages - 1
    g_iWeaponPage[id] = iPage

    new bool:bMulti = (iCount > ITEMS_PER_PAGE)
    new iPoints = points_is_loaded(id) ? points_get(id) : 0

    new szMenu[1024], len = 0
    // Индикатор страницы в меню оружий: скрыт на 1-й странице
    if(iPage > 0)
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\yСкины на оружия \r[%d очков] \y(%d/%d)^n^n", iPoints, iPage + 1, iPages)
    else
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\yСкины на оружия \r[%d очков]^n^n", iPoints)

    new keys = 0
    new szName[64]
    new iStart = iPage * ITEMS_PER_PAGE
    new iEnd = iStart + ITEMS_PER_PAGE
    if(iEnd > iCount) iEnd = iCount

    for(new i = iStart; i < iEnd; i++) {
        ArrayGetString(g_aWeaponMenuNames, i, szName, charsmax(szName))
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r%d. \w%s^n", i - iStart + 1, szName)
        keys |= (1 << (i - iStart))
    }

    // одна пустая строка между списком и кнопками
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n")

    if(!bMulti) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r9. \wНазад^n")
        keys |= KEY_9
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r8. \wНазад^n")
        keys |= KEY_8
        if(iPage < iPages - 1) {
            len += formatex(szMenu[len], charsmax(szMenu) - len, "\r9. \wДалее^n")
            keys |= KEY_9
        } else {
            len += formatex(szMenu[len], charsmax(szMenu) - len, "\d9. Далее^n")
        }
    }
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r0. \wВыход")
    keys |= KEY_0

    g_iMenuState[id] = 1
    show_menu(id, keys, szMenu, -1, MENU_WEAPON)
}

public Handle_WeaponMenu(id, key) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED

    new iCount = ArraySize(g_aWeaponClasses)
    new iPages = (iCount + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE
    if(iPages < 1) iPages = 1
    new iPage = g_iWeaponPage[id]
    if(iPage < 0) iPage = 0
    if(iPage >= iPages) iPage = iPages - 1
    new bool:bMulti = (iCount > ITEMS_PER_PAGE)

    // 0 — Выход
    if(key == 9) {
        CloseMenu(id)
        return PLUGIN_HANDLED
    }

    // 9 — Далее (только если страниц > 1)
    if(bMulti && key == 8) {
        if(iPage < iPages - 1) {
            g_iWeaponPage[id] = iPage + 1
            ShowWeaponSelectMenu(id)
        }
        return PLUGIN_HANDLED
    }

    // Назад: на 9 если список короткий, иначе на 8
    if(key == (bMulti ? 7 : 8)) {
        if(iPage > 0) {
            g_iWeaponPage[id] = iPage - 1
            ShowWeaponSelectMenu(id)
        } else {
            OpenServerMainMenu(id) // с 1-й страницы — в главное меню сервера
        }
        return PLUGIN_HANDLED
    }

    // выбор оружия (клавиши 1-7)
    if(key >= 0 && key < ITEMS_PER_PAGE) {
        new iIndex = iPage * ITEMS_PER_PAGE + key
        if(iIndex < iCount) {
            g_iCurrentMenuSlot[id] = iIndex
            g_iSkinPage[id] = 0 // меню скинов открывается с первой страницы
            ShowSkinMenu(id, iIndex)
        }
    }

    return PLUGIN_HANDLED
}

// ============================================================================
// МЕНЮ СКИНОВ (старый стиль, пагинация)
// ============================================================================
ShowSkinMenu(id, iSlot) {
    if(!is_user_connected(id) || g_aPlayerSkin[id] == Invalid_Array) return
    if(!g_bPlayerDataLoaded[id]) {
        client_print(id, print_chat, "[WSkins] Данные ещё не готовы.")
        return
    }
    if(iSlot < 0 || iSlot >= ArraySize(g_aWeaponClasses)) return

    new Array:aN = Array:ArrayGetCell(g_aSkinNames, iSlot)
    new Array:aP = Array:ArrayGetCell(g_aSkinPrices, iSlot)
    new iCount = ArraySize(aN)

    new iPages = (iCount + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE
    if(iPages < 1) iPages = 1
    new iPage = g_iSkinPage[id]
    if(iPage < 0) iPage = 0
    if(iPage >= iPages) iPage = iPages - 1
    g_iSkinPage[id] = iPage

    new bool:bMulti = (iCount > ITEMS_PER_PAGE)
    new iPoints = points_is_loaded(id) ? points_get(id) : 0

    new szMenu[1024], len = 0
    // Индикатор страницы как на фото: (текущая/всего)
    if(iPages > 1)
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\yМеню моделей \r[%d очков] \y(%d/%d)^n^n", iPoints, iPage + 1, iPages)
    else
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\yМеню моделей \r[%d очков]^n^n", iPoints)

    new keys = 0
    if(iCount == 0) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\dНет доступных скинов^n")
    } else {
        new szName[64], szItem[160]
        new iStart = iPage * ITEMS_PER_PAGE
        new iEnd = iStart + ITEMS_PER_PAGE
        if(iEnd > iCount) iEnd = iCount
        new iCurrentSkin = ArrayGetCell(g_aPlayerSkin[id], iSlot)

        for(new i = iStart; i < iEnd; i++) {
            ArrayGetString(aN, i, szName, charsmax(szName))
            new price = ArrayGetCell(aP, i)
            new bool:owned = IsWeaponSkinOwned(id, iSlot, i)

            if(owned && iCurrentSkin == i) {
                formatex(szItem, charsmax(szItem), "\r%d. \d%s \y[Выбрано]", i - iStart + 1, szName)
            } else if(owned || price == 0) {
                formatex(szItem, charsmax(szItem), "\r%d. \w%s", i - iStart + 1, szName)
            } else {
                formatex(szItem, charsmax(szItem), "\r%d. \r[%d очков] \w%s", i - iStart + 1, price, szName)
            }
            len += formatex(szMenu[len], charsmax(szMenu) - len, "%s^n", szItem)
            keys |= (1 << (i - iStart))
        }
    }

    // одна пустая строка между списком и кнопками
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n")

    if(!bMulti) {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r9. \wНазад^n")
        keys |= KEY_9
    } else {
        len += formatex(szMenu[len], charsmax(szMenu) - len, "\r8. \wНазад^n")
        keys |= KEY_8
        if(iPage < iPages - 1) {
            len += formatex(szMenu[len], charsmax(szMenu) - len, "\r9. \wДалее^n")
            keys |= KEY_9
        } else {
            len += formatex(szMenu[len], charsmax(szMenu) - len, "\d9. Далее^n")
        }
    }
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r0. \wВыход")
    keys |= KEY_0

    g_iCurrentMenuSlot[id] = iSlot
    g_iMenuState[id] = 2
    show_menu(id, keys, szMenu, -1, MENU_SKIN)
}

public Handle_SkinMenu(id, key) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED

    new iSlot = g_iCurrentMenuSlot[id]
    if(iSlot < 0 || iSlot >= ArraySize(g_aWeaponClasses)) {
        CloseMenu(id)
        return PLUGIN_HANDLED
    }

    new Array:aN = Array:ArrayGetCell(g_aSkinNames, iSlot)
    new iCount = ArraySize(aN)
    new iPages = (iCount + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE
    if(iPages < 1) iPages = 1
    new iPage = g_iSkinPage[id]
    if(iPage < 0) iPage = 0
    if(iPage >= iPages) iPage = iPages - 1
    new bool:bMulti = (iCount > ITEMS_PER_PAGE)

    // 0 — Выход
    if(key == 9) {
        CloseMenu(id)
        return PLUGIN_HANDLED
    }

    // 9 — Далее
    if(bMulti && key == 8) {
        if(iPage < iPages - 1) {
            g_iSkinPage[id] = iPage + 1
            ShowSkinMenu(id, iSlot)
        }
        return PLUGIN_HANDLED
    }

    // Назад
    if(key == (bMulti ? 7 : 8)) {
        if(iPage > 0) {
            g_iSkinPage[id] = iPage - 1
            ShowSkinMenu(id, iSlot)
        } else {
            g_iWeaponPage[id] = 0 // с 1-й страницы — в список оружий
            ShowWeaponSelectMenu(id)
        }
        return PLUGIN_HANDLED
    }

    // выбор скина (клавиши 1-7)
    if(key >= 0 && key < ITEMS_PER_PAGE) {
        new iSkin = iPage * ITEMS_PER_PAGE + key
        if(iSkin < iCount) {
            new szName[64]
            ArrayGetString(aN, iSkin, szName, charsmax(szName))
            new price = GetSkinPrice(iSlot, iSkin)

            if(IsWeaponSkinOwned(id, iSlot, iSkin) || price == 0) {
                ApplyWeaponSkin(id, iSlot, iSkin)
                SavePlayerData(id)
                client_print(id, print_chat, "Вы выбрали: %s", szName)
                ShowSkinMenu(id, iSlot) // остаёмся на той же странице
            } else {
                g_iPendingSlot[id] = iSlot
                g_iPendingSkin[id] = iSkin
                ShowConfirmMenu(id, szName, price)
            }
        }
    }

    return PLUGIN_HANDLED
}

// ============================================================================
// ПОДТВЕРЖДЕНИЕ ПОКУПКИ
// ============================================================================
ShowConfirmMenu(id, const szName[], price) {
    if(!is_user_connected(id)) return

    new szMenu[512], len = 0
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\yПодтверждение покупки^n^n")
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\wКупить \y%s \wза \r%d \wочков?^n", szName, price)
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n")
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r1. \gДа^n")
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r2. \rНет^n")
    len += formatex(szMenu[len], charsmax(szMenu) - len, "^n")
    len += formatex(szMenu[len], charsmax(szMenu) - len, "\r0. \wВыход")

    g_iMenuState[id] = 3
    show_menu(id, KEY_1 | KEY_2 | KEY_0, szMenu, -1, MENU_CONFIRM)
}

public Handle_ConfirmMenu(id, key) {
    if(!is_user_connected(id)) return PLUGIN_HANDLED

    new iSlot = g_iPendingSlot[id]
    new iSkin = g_iPendingSkin[id]
    g_iPendingSlot[id] = -1
    g_iPendingSkin[id] = -1

    if(key == 0) {
        // Да
        if(iSlot != -1 && iSkin != -1)
            AttemptPurchase(id, iSlot, iSkin)
        else
            ShowSkinMenu(id, g_iCurrentMenuSlot[id])
    } else if(key == 1) {
        // Нет — возврат в меню скинов на ту же страницу
        ShowSkinMenu(id, g_iCurrentMenuSlot[id])
    } else {
        // Выход
        CloseMenu(id)
    }
    return PLUGIN_HANDLED
}

// ============================================================================
// ПОКУПКА И ПРИМЕНЕНИЕ
// ============================================================================
AttemptPurchase(id, iSlot, iSkin) {
    if(!g_bPlayerDataLoaded[id]) {
        client_print(id, print_chat, "[WSkins] Ошибка: данные ещё не загружены. Попробуйте позже.")
        ShowSkinMenu(id, iSlot)
        return
    }
    new price = GetSkinPrice(iSlot, iSkin)
    if(price < 0) {
        ShowSkinMenu(id, iSlot)
        return
    }

    new curPoints = points_get(id)
    if(curPoints < price) {
        client_print(id, print_chat, "Недостаточно очков! Нужно %d, у вас %d", price, curPoints)
        ShowSkinMenu(id, iSlot) // остаёмся на той же странице
        return
    }

    points_set(id, curPoints - price)
    AddOwnedWeaponSkin(id, iSlot, iSkin)
    ApplyWeaponSkin(id, iSlot, iSkin)
    SavePlayerData(id)
    client_print(id, print_chat, "Скин куплен!")
    ShowSkinMenu(id, iSlot) // остаёмся на той же странице, где купили
}

CloseMenu(id) {
    if(id < 1 || id > 32) return
    if(is_user_connected(id)) {
        show_menu(id, 0, "^n", 1, MENU_WEAPON)
    }
    g_iMenuState[id] = 0
}

// Возврат в главное меню сервера (команда из menuSystem.ini, по умолчанию chooseteam)
public OpenServerMainMenu(id) {
    if(!is_user_connected(id)) return
    g_iMenuState[id] = 0
    client_cmd(id, g_szMainMenuCmd)
}

// ============================================================================
// ОРУЖЕЙНЫЕ ХУКИ
// ============================================================================
public Fwd_WeaponDeploy(iEnt) {
    new id = get_entvar(iEnt, var_owner)
    if(!is_user_alive(id)) return
    new szClass[32]
    get_entvar(iEnt, var_classname, szClass, charsmax(szClass))
    new iSlot = FindWeaponSlot(szClass)
    if(iSlot == -1 || g_aPlayerSkin[id] == Invalid_Array) return
    new iSkinIndex = ArrayGetCell(g_aPlayerSkin[id], iSlot)
    if(iSkinIndex == -1) return
    new Array:aV = Array:ArrayGetCell(g_aVModels, iSlot)
    if(iSkinIndex < 0 || iSkinIndex >= ArraySize(aV)) return
    new szV[128]
    ArrayGetString(aV, iSkinIndex, szV, charsmax(szV))
    set_entvar(id, var_viewmodel, szV)
}

public OnPlayerAddItem(id, iWeapon) {
    if(!is_user_connected(id) || !pev_valid(iWeapon)) return HAM_IGNORED
    new szClass[32]
    get_entvar(iWeapon, var_classname, szClass, charsmax(szClass))
    if(FindWeaponSlot(szClass) == -1) return HAM_IGNORED
    g_iPendingWeapon[id] = iWeapon
    set_task(0.1, "Task_ForceSkinOnAdd", id)
    return HAM_IGNORED
}

public Task_ForceSkinOnAdd(taskid) {
    new id = taskid
    new iWeapon = g_iPendingWeapon[id]
    if(!is_user_connected(id) || !pev_valid(iWeapon)) return
    new pActive = get_member(id, m_pActiveItem)
    if(pActive != iWeapon) return
    new szClass[32]
    get_entvar(iWeapon, var_classname, szClass, charsmax(szClass))
    new iSlot = FindWeaponSlot(szClass)
    if(iSlot == -1) return
    new iSkinIndex = ArrayGetCell(g_aPlayerSkin[id], iSlot)
    if(iSkinIndex < 0) return
    new Array:aV = Array:ArrayGetCell(g_aVModels, iSlot)
    if(iSkinIndex >= ArraySize(aV)) return
    new szV[128]
    ArrayGetString(aV, iSkinIndex, szV, charsmax(szV))
    set_entvar(id, var_viewmodel, szV)
    ExecuteHamB(Ham_Item_Deploy, iWeapon)
}

public Cmd_Points(id) {
    client_print(id, print_chat, "Ваши очки: %d", points_get(id))
    return PLUGIN_HANDLED
}

// ============================================================================
// MENU SYSTEM INI (чтение команды главного меню)
// ============================================================================
public LoadMenuSystemConfig() {
    // По умолчанию возвращаемся через chooseteam
    copy(g_szMainMenuCmd, charsmax(g_szMainMenuCmd), "chooseteam")

    new szPath[256]
    get_configsdir(szPath, charsmax(szPath))
    formatex(szPath, charsmax(szPath), "%s/menuSystem.ini", szPath)

    if(!file_exists(szPath)) return

    new f = fopen(szPath, "r")
    if(!f) return

    new szLine[256]
    new bool:bInMainSection = false

    while(!feof(f)) {
        fgets(f, szLine, charsmax(szLine))
        trim(szLine)

        if(szLine[0] == EOS) continue

        // Начало секции [ ... ]
        if(szLine[0] == '[') {
            new close = contain(szLine, "]")
            if(close > 0) {
                szLine[close] = 0
                bInMainSection = equal(szLine[1], "Главное меню") ? true : false
            } else {
                bInMainSection = false
            }
            continue
        }

        // Комментарии
        if(szLine[0] == ';') continue
        if(!bInMainSection) continue

        // key = value
        new eq = contain(szLine, "=")
        if(eq <= 0) continue

        new szKey[32], szVal[64]
        copy(szKey, charsmax(szKey), szLine)
        if(eq < charsmax(szKey)) szKey[eq] = 0
        trim(szKey)

        copy(szVal, charsmax(szVal), szLine[eq + 1])
        trim(szVal)

        if(equali(szKey, "cmd") && szVal[0]) {
            copy(g_szMainMenuCmd, charsmax(g_szMainMenuCmd), szVal)
        }
    }

    fclose(f)
}

// ============================================================================
// СТОКИ
// ============================================================================
stock FindWeaponSlot(const szClassname[]) {
    new iCount = ArraySize(g_aWeaponClasses)
    new szTemp[32]
    for(new i = 0; i < iCount; i++) {
        ArrayGetString(g_aWeaponClasses, i, szTemp, charsmax(szTemp))
        if(equal(szTemp, szClassname)) return i
    }
    return -1
}

stock bool:IsWeaponSkinOwned(id, iSlot, iSkin) {
    if(GetSkinPrice(iSlot, iSkin) == 0)
        return true;
    if(g_szOwned[id][0] == 0) return false
    new key[16]
    formatex(key, charsmax(key), ",%d:%d,", iSlot, iSkin)
    new szOwned[512]
    formatex(szOwned, charsmax(szOwned), ",%s,", g_szOwned[id])
    return (contain(szOwned, key) != -1)
}

stock AddOwnedWeaponSkin(id, iSlot, iSkin) {
    if(IsWeaponSkinOwned(id, iSlot, iSkin)) return
    if(g_szOwned[id][0] != 0)
        add(g_szOwned[id], charsmax(g_szOwned[]), ",")
    new tmp[16]
    formatex(tmp, charsmax(tmp), "%d:%d", iSlot, iSkin)
    add(g_szOwned[id], charsmax(g_szOwned[]), tmp)
}

stock GetSkinPrice(iSlot, iSkin) {
    new Array:aP = Array:ArrayGetCell(g_aSkinPrices, iSlot)
    if(iSkin < 0 || iSkin >= ArraySize(aP)) return 0
    return ArrayGetCell(aP, iSkin)
}

stock ApplyWeaponSkin(id, iSlot, iSkinIndex) {
    if(g_aPlayerSkin[id] == Invalid_Array) return
    ArraySetCell(g_aPlayerSkin[id], iSlot, iSkinIndex)

    new pActiveItem = get_member(id, m_pActiveItem)
    if(pActiveItem > 0) {
        new szClass[32]
        get_entvar(pActiveItem, var_classname, szClass, charsmax(szClass))
        if(FindWeaponSlot(szClass) == iSlot) {
            new Array:aV = Array:ArrayGetCell(g_aVModels, iSlot)
            new szV[128]
            ArrayGetString(aV, iSkinIndex, szV, charsmax(szV))
            set_entvar(id, var_viewmodel, szV)
            ExecuteHamB(Ham_Item_Deploy, pActiveItem)
        }
    }
}