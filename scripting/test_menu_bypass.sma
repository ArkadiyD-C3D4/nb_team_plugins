#include <amxmodx>

#define PLUGIN "Test Menu Bypass"
#define VERSION "1.1"
#define AUTHOR "nb_team"

// Уникальное имя меню, чтобы избежать конфликтов с другими плагинами
new const MENU_NAME[] = "test_menu_unique_id_v1"

// Клавиши: 1, 2, 3 и 0.
// Бит 0 (кнопка 1) = 1
// Бит 1 (кнопка 2) = 2
// Бит 2 (кнопка 3) = 4
// Бит 9 (кнопка 0) = 512
// Сумма: 1 + 2 + 4 + 512 = 519
#define MENU_KEYS 519

public plugin_init() 
{
    register_plugin(PLUGIN, VERSION, AUTHOR)

    // Регистрация команд открытия
    register_clcmd("testmenu", "cmd_ShowMenu")
    register_clcmd("say /testmenu", "cmd_ShowMenu")
    register_clcmd("say_team /testmenu", "cmd_ShowMenu")

    // ГЛАВНОЕ ИСПРАВЛЕНИЕ: Правильная регистрация меню через register_menucmd
    // Это гарантирует, что движок HLDS корректно привяжет нажатия клавиш к функции Menu_Handler
    register_menucmd(register_menuid(MENU_NAME), MENU_KEYS, "Menu_Handler")
}

public cmd_ShowMenu(id) 
{
    new szMenu[256]
    formatex(szMenu, charsmax(szMenu), "\y[\r Тестовое Меню \y]^n^n\w1. Пункт 1 (Работает!)^n\w2. Пункт 2 (Работает!)^n\w3. Пункт 3 (Работает!)^n^n\y0. Выход")

    // Показываем меню. Время 999 сек. Используем уникальное имя MENU_NAME.
    show_menu(id, MENU_KEYS, szMenu, 999, MENU_NAME)

    client_print(id, print_chat, "Меню открыто! Нажмите цифру 1, 2, 3 или 0.")
    
    return PLUGIN_HANDLED
}

public Menu_Handler(id, key) 
{
    // ВАЖНО: Выводим сообщение в консоль игрока, чтобы проверить, вызывается ли функция вообще
    client_print(id, print_console, "[DEBUG] Menu_Handler вызван. Нажата клавиша: %d", key)

    switch(key) 
    {
        case 0: client_print(id, print_chat, "Вы выбрали Пункт 1!")
        case 1: client_print(id, print_chat, "Вы выбрали Пункт 2!")
        case 2: client_print(id, print_chat, "Вы выбрали Пункт 3!")
        case 9: client_print(id, print_chat, "Вы нажали Выход.")
    }
    
    return PLUGIN_HANDLED
}