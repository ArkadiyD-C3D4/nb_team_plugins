# Плагины NB Team для CS 1.6 (AMX Mod X)

Исходники серверных плагинов для Counter-Strike 1.6 под AMX Mod X. В репозитории — **41 плагин**, авторство указано как `nb_team`.

Все плагины написаны для AMX Mod X 1.9/1.10 и частично используют ReAPI, MySQL/SQLite и сторонние include-файлы.

## Структура репозитория

```
scripting/          исходники плагинов (*.sma)
README.md           этот файл
```

Скомпилированные `.amxx` в репозиторий не входят — их нужно собрать из исходников (см. раздел «Сборка»).

## Состав

### Экономика, магазин и прогрессия

| Файл | Название | Версия | Модули / include |
|---|---|---|---|
| `points_core.sma` | Points Core | 1.5-SMARTSAVE | amxmodx, sqlx |
| `points_transfer.sma` | Points Transfer | 2.1 | amxmodx, amxmisc, colorchat |
| `shop_core.sma` | Universal Shop Core | 1.5 | amxmodx, amxmisc, colorchat, engine |
| `shop_healthnade.sma` | Shop: Extended | 1.5 | amxmodx, amxmisc, colorchat, engine, hamsandwich, healthnade, reapi |
| `resource_inventory.sma` | Resource Inventory System | 2.1 | amxmodx, amxmisc, sqlx |
| `seller_brain.sma` | Seller Brain | 3.0 | amxmodx, amxmisc, reapi |
| `craft_system.sma` | Craft System Framework | 2.0 | amxmodx, amxmisc, fun, hamsandwich, sqlx |
| `skin_core.sma` | Skin Core Pro | 2.4-BUYABLE | amxmodx, amxmisc, fakemeta, hamsandwich, reapi, sqlx |
| `skin_shop.sma` | Skin Shop Menu | 1.9-PREFIX | amxmodx, amxmisc, colorchat, reapi |
| `weapon_skin.sma` | Weapon Skins Shop (shared points) | 4.1 | amxmodx, amxmisc, fakemeta, hamsandwich, reapi, sqlx |
| `skills_system.sma` | Skills System | 2.6.0 | amxmodx, amxmisc, fakemeta, reapi, sqlx |
| `prefix_system.sma` | Database & Ini Chat Prefix | 3.5 | amxmodx, sqlx |
| `betting.sma` | Betting System | 3.0-RECONNECT | amxmodx, amxmisc, fun, hamsandwich, sqlx, string |

### Ранги, статистика и логи

| Файл | Название | Версия | Модули / include |
|---|---|---|---|
| `ranks_system.sma` | Ranks System | 2.4-RECONNECT | amxmodx, amxmisc, reapi, sqlx |
| `stats_advanced.sma` | Advanced Stats MySQL | 1.7 | amxmodx, amxmisc, fakemeta, hamsandwich, sqlx |
| `ChatLogger.sma` | Chat Logger | 1.3 | amxmodx, sqlx |
| `cs16_authid_audit.sma` | CS 1.6 AuthID Audit | 1.0 | amxmodx |

### Администрирование и меню

| Файл | Название | Версия | Модули / include |
|---|---|---|---|
| `advanced_admin_menu.sma` | Advanced Admin Menu | 2.7 | amxmodx, amxmisc, engine, hamsandwich, reapi, sqlx |
| `admin_screamer.sma` | Admin Screamer Instant | 2.1 | amxmodx, amxmisc, fakemeta |
| `devmenu.sma` | Developer Menu Structured | 2.6 | amxmodx, reapi |
| `dev_resource_tester.sma` | Dev Resource Menu | 1.0 | amxmodx, amxmisc |
| `d_alpha.sma` | Alpha Menu System | 2.8 | amxmodx, amxmisc |
| `d_beta.sma` | Beta Menu System | 2.8 | amxmodx, amxmisc |
| `d_delta.sma` | Delta Menu System | 2.8 | amxmodx, amxmisc |
| `d_epsilon.sma` | Epsilon Menu System | 2.8 | amxmodx, amxmisc |
| `d_gamma.sma` | Gamma Menu System | 2.8 | amxmodx, amxmisc |
| `d_zeta.sma` | Zeta Menu System | 2.8 | amxmodx, amxmisc |
| `map_brightness.sma` | Map Brightness Menu | 1.1 | amxmodx, amxmisc, engine |
| `graphics_settings.sma` | Graphics Settings | 1.7_no_cstrike | amxmodx, fakemeta, hamsandwich, reapi |
| `resetsTab.sma` | Reset Score | 1.1 | amxmodx, fakemeta, fun |
| `test_menu_bypass.sma` | Test Menu Bypass | 1.1 | amxmodx |
| `test_privilege.sma` | Test Privilege (1 day) | 1.3 | amxmodx, amxmisc, sqlx |
| `speedometr.sma` | ReAPI Speedometer | 1.3 | amxmodx, reapi |

### Геймплей

| Файл | Название | Версия | Модули / include |
|---|---|---|---|
| `freeguns.sma` | Respawn Weapon Menu + Armor & Nades | 1.1 | amxmodx, reapi |
| `parachute_for_all_reapi.sma` | Parachute for ALL [ReAPI] | 3.1 | amxmodx, engine, reapi |
| `chat_teams.sma` | Chat Team Changer (ReAPI) | 2.9-SmartBalance | amxmodx, reapi |
| `livesSystem.sma` | Lives System | 1.6.1 | amxmodx, colorchat, fakemeta, reapi |
| `trigger_test.sma` | Trigger System Test | 1.4 | amxmodx, amxmisc, engine, fakemeta, fun |
| `custom_models_manager.sma` | Custom Models & Triggers Pro | 7.0 | amxmodx, amxmisc, engine, fakemeta, fun, hamsandwich, xs |
| `anti_dem_pw_sniffer.sma` | Anti Demo PW Sniffer | 1.0.4 | amxmodx, reapi |
| `semiclip.sma` | Team Semiclip | 1.1 | amxmodx, fakemeta |

> `parachute_for_all_reapi.sma` — совместная работа: `Leo_[BH] & nb_team`.

## Требования

- AMX Mod X 1.9 или 1.10.
- Модули AMXX: `fakemeta`, `engine`, `fun`, `hamsandwich`, `sqlx`, `mysql` и/или `sqlite`.
- [ReAPI](https://github.com/s1lentq/reapi) — для плагинов, использующих `reapi`.
- Сторонние include-файлы, которых нет в стандартной поставке AMXX:
  - `colorchat.inc` — `points_transfer`, `shop_core`, `shop_healthnade`, `skin_shop`, `livesSystem`;
  - `healthnade.inc` — `shop_healthnade`;
  - `xs.inc` — `custom_models_manager`.

Перед сборкой положите эти include в `cstrike/addons/amxmodx/scripting/include/`.

## Сборка

1. Установите AMX Mod X 1.9/1.10 и ReAPI.
2. Скопируйте исходники в `cstrike/addons/amxmodx/scripting/`.
3. Добавьте недостающие include-файлы в `scripting/include/`.
4. Скомпилируйте:

```bat
cd cstrike\addons\amxmodx\scripting
amxxpc.exe points_core.sma -o ..\plugins\points_core.amxx
```

Либо запустите `compile.exe` и соберите все `.sma` сразу.

## Установка

1. Положите полученные `.amxx` в `cstrike/addons/amxmodx/plugins/`.
2. Пропишите нужные плагины в `cstrike/addons/amxmodx/configs/plugins.ini`.
3. Включите требуемые модули в `configs/modules.ini`.
4. Перезапустите сервер или выполните `amx_reload` / смену карты.

## Настройки и базы данных

Плагины не содержат логинов и паролей. Доступ к MySQL читается из cvars AMX Mod X:

```
amx_sql_host "127.0.0.1"
amx_sql_user "user"
amx_sql_pass "password"
amx_sql_db   "database"
```

Указывайте свои значения в `cstrike/addons/amxmodx/configs/sql.cfg` или в `amxx.cfg`.

## Примечания

- Часть плагинов (`d_*`, `dev*`, `test_*`, `trigger_test`) — служебные/тестовые и могут быть не нужны на публичном сервере.
- Версии и списки зависимостей указаны по состоянию исходников на момент публикации.
- Лицензия не задана: по умолчанию все права сохраняются за авторами. Если планируется открытое распространение и доработка — добавьте `LICENSE` (например, MIT или GPL-3.0).
