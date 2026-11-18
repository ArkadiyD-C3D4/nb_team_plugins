#include <amxmodx>
#include <amxmisc>
#include <engine>

#define SVC_LIGHTSTYLE 13
#define CONFIG_FILE "map_brightness.ini"

// Глобальные переменные
new g_szDefaultLight[32];
new g_szEnforcedLight[32];
new g_szCurrentMap[64];
new g_szConfigPath[128];

public plugin_init() {
    register_plugin("Map Brightness Menu", "1.1", "nb_team");

    // Команды для вызова меню
    register_clcmd("say /bright", "CmdShowBrightMenu", ADMIN_LEVEL_H, " - меню яркости карты");
    register_clcmd("say_team /bright", "CmdShowBrightMenu", ADMIN_LEVEL_H, " - меню яркости карты");

    // Перехват смены света движком
    register_message(SVC_LIGHTSTYLE, "Hook_LightStyle");

    // Получаем имя текущей карты и путь к INI файлу
    get_mapname(g_szCurrentMap, charsmax(g_szCurrentMap));
    get_configsdir(g_szConfigPath, charsmax(g_szConfigPath));
    add(g_szConfigPath, charsmax(g_szConfigPath), "/");
    add(g_szConfigPath, charsmax(g_szConfigPath), CONFIG_FILE);

    // Загружаем сохраненную яркость для этой карты (если есть)
    LoadMapSettings();
}

// Перехват света движка
public Hook_LightStyle(msg_id, msg_dest, msg_entity) {
    new style = get_msg_arg_int(1);

    // Style 0 - это глобальное освещение карты
    if (style == 0) {
        // Если плагин НЕ задавал свой свет принудительно, запоминаем оригинальный
        if (!g_szEnforcedLight[0]) {
            get_msg_arg_string(2, g_szDefaultLight, charsmax(g_szDefaultLight));
        } 
        // Если свет задан админом, не даем движку сбросить его при рестарте раунда
        else {
            set_msg_arg_string(2, g_szEnforcedLight);
        }
    }
}

// Создание и показ меню
public CmdShowBrightMenu(id, level, cid) {
    if (!cmd_access(id, level, cid, 1)) {
        return PLUGIN_HANDLED;
    }

    new title[128];
    formatex(title, charsmax(title), "\wМенятие яркости \y(Карта: %s)", g_szCurrentMap);
    new menu = menu_create(title, "MenuHandler_Bright");

    // Предустановки света (от 'a' - темная, до 'z' - светлая)
    menu_additem(menu, "Очень темно \y(a)", "a");
    menu_additem(menu, "Темно \y(c)", "c");
    menu_additem(menu, "Сумрачно \y(e)", "e");
    menu_additem(menu, "Средне \y(h)", "h");
    menu_additem(menu, "Светло \y(m)", "m");
    menu_additem(menu, "Очень светло \y(z)", "z");
    
    menu_addblank(menu, 0); // Пустая строка для красоты

    // Сброс к оригиналу
    menu_additem(menu, "Сбросить \r(Оригинал карты)", "reset");
    
    // Сохранение для текущей карты
    menu_additem(menu, "Сохранить для этой карты \r(в INI)", "save");

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);

    return PLUGIN_HANDLED;
}

// Обработка выбора в меню
public MenuHandler_Bright(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[32], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);

    if (equal(data, "reset")) {
        // Сброс: очищаем принудительный свет и возвращаем оригинальный
        g_szEnforcedLight[0] = '^0';
        
        // 'm' - это стандарт движка, если оригинал не удалось поймать
        set_lights(g_szDefaultLight[0] ? g_szDefaultLight : "m");
        client_print(id, print_chat, "[Bright] Установлено стандартное освещение карты.");
    } 
    else if (equal(data, "save")) {
        // Сохранение в INI
        if (!g_szEnforcedLight[0]) {
            client_print(id, print_chat, "[Bright] Ошибка: Сначала выберите уровень яркости!");
        } else {
            SaveMapSetting(id);
        }
    } 
    else {
        // Выбор буквы света
        copy(g_szEnforcedLight, charsmax(g_szEnforcedLight), data);
        set_lights(g_szEnforcedLight);
        client_print(id, print_chat, "[Bright] Яркость изменена на: %s. (Не забудьте сохранить, если нужно)", g_szEnforcedLight);
    }

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// Загрузка настроек из файла при старте карты
LoadMapSettings() {
    new file = fopen(g_szConfigPath, "r");
    if (!file) return; // Файла еще нет, ничего не загружаем

    new line[128], mapname[64], light[32];
    while (!feof(file)) {
        fgets(file, line, charsmax(line));
        trim(line);

        // Пропускаем пустые строки и комментарии
        if (!line[0] || line[0] == ';' || line[0] == '/') continue;

        parse(line, mapname, charsmax(mapname), light, charsmax(light));

        // Если нашли текущую карту в файле
        if (equali(mapname, g_szCurrentMap)) {
            if (light[0] >= 'a' && light[0] <= 'z') {
                copy(g_szEnforcedLight, charsmax(g_szEnforcedLight), light);
                set_lights(g_szEnforcedLight);
                log_amx("[Bright] Загружена яркость '%s' для карты '%s'.", light, g_szCurrentMap);
            }
            break;
        }
    }
    fclose(file);
}

// Сохранение или обновление настроек карты в INI
SaveMapSetting(id) {
    new file = fopen(g_szConfigPath, "r");
    
    // Если файла нет, создаем его и сразу пишем
    if (!file) {
        file = fopen(g_szConfigPath, "w");
        if (file) {
            fprintf(file, "; Файл сохранения яркости карт^n^n^"%s^" ^"%s^"^n", g_szCurrentMap, g_szEnforcedLight);
            fclose(file);
            client_print(id, print_chat, "[Bright] Карта %s (%s) сохранена в INI.", g_szCurrentMap, g_szEnforcedLight);
        }
        return;
    }

    // Если файл есть, читаем его полностью, чтобы перезаписать без дублей
    new tempFile[164];
    formatex(tempFile, charsmax(tempFile), "%s.tmp", g_szConfigPath);
    new temp = fopen(tempFile, "w");
    
    new line[128], mapname[64], light[32];
    new bool:bFound = false;

    while (!feof(file)) {
        fgets(file, line, charsmax(line));
        
        // Комментарии и пустые строки переносим как есть
        if (!line[0] || line[0] == ';' || line[0] == '/') {
            fputs(temp, line);
            continue;
        }

        parse(line, mapname, charsmax(mapname), light, charsmax(light));

        // Если нашли нашу карту, перезаписываем строку с новым значением
        if (equali(mapname, g_szCurrentMap)) {
            fprintf(temp, "^"%s^" ^"%s^"^n", g_szCurrentMap, g_szEnforcedLight);
            bFound = true;
        } else {
            // Остальные карты оставляем без изменений
            fputs(temp, line);
        }
    }
    
    // Если карты не было в файле, дописываем в конец
    if (!bFound) {
        fprintf(temp, "^"%s^" ^"%s^"^n", g_szCurrentMap, g_szEnforcedLight);
    }

    fclose(file);
    fclose(temp);
    
    // Заменяем старый файл новым
    delete_file(g_szConfigPath);
    rename_file(tempFile, g_szConfigPath, 1);

    client_print(id, print_chat, "[Bright] Настройки для карты %s успешно сохранены!", g_szCurrentMap);
}