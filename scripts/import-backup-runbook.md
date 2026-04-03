# Import Backup Runbook

Пошаговая инструкция для импорта JSON-бэкапа Clan Control в Supabase.

## Требования

- Node.js ≥ 18
- `@supabase/supabase-js` установлен (`npm i @supabase/supabase-js`)
- В Supabase применена миграция `0001_clan_control_v1.sql`
- Переменные окружения:
  - `SUPABASE_URL` — URL проекта Supabase
  - `SUPABASE_SERVICE_ROLE_KEY` — service-role ключ (не anon-key)

## Запуск

```bash
export SUPABASE_URL="https://<project>.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="eyJ..."

node scripts/import-backup-to-supabase.mjs path/to/clan-control-backup.json
```

## Что делает importer

### Поддерживаемые форматы backup

Importer поддерживает два формата файла:

- **Wrapped** — `{ version, exportedAt, data: { packs, roster, ... } }` — данные берутся из поля `data`
- **Raw** — `{ packs, roster, ... }` — данные берутся из корня объекта (fallback)

### Порядок импорта

| # | Таблица | Источник в backup | Примечания |
|---|---------|-------------------|------------|
| 1 | `packs` | `data.packs` | `СОЛО` не импортируется — означает отсутствие пака |
| 2 | `players` | `data.roster` + `data.archive` | Дедупликация по normalized name. Rank нормализуется: `КЛ`→`KL`, `ПЛ`→`PL`, `ИГРОК`→`Player`. Архивные игроки получают `status='archived'` |
| 3 | `player_aliases` | `data.nickAliases` | Записи `__diff__*` и `"different"` пропускаются. Алиас не создаётся если он совпадает с именем игрока |
| 4 | `calendar_events` | `data.manualEvents` + `data.eventStatuses` | Тип `Manual`, source `manual`. Поле `override_json` передаётся как JS-объект (JSONB) |
| 5 | `app_settings` | `data.valueWeights`, `data.exhaustedKeys` | Upsert по key. `exhaustedKeys` записывается всегда, если ключ присутствует в backup — в том числе как `{}` |
| 6 | `km_sessions` + `km_session_player_stats` | `data.appliedStatsByDate` | См. детали ниже |
| 7 | `player_profa_history` | `data.playerProfaByDate` | Upsert по `(player_id, session_date)` |
| 8 | `player_notes` | `data.playerNotes` | Insert |

### Очистка перед импортом

Importer выполняет **полную очистку** всех таблиц перед импортом (delete all rows). Это гарантирует идемпотентность при повторных запусках. Порядок очистки учитывает FK-зависимости.

### Alias resolution

После импорта `players` и `player_aliases` строится **in-memory alias map** из трёх источников:

1. **Нормализованные имена игроков** — `normalize(player.name)` → `{ playerId, canonicalName }` (высший приоритет)
2. **Импортированные алиасы** — `alias_text_normalized` → player (из таблицы `player_aliases`)
3. **Fallback из raw nickAliases** — транзитивное разрешение через уже построенную карту. Например, если `"френч75"` → `"ФРЕНЧ75"`, и `"ФРЕНЧ75"` уже есть в карте, то `"френч75"` тоже резолвится

Функция `resolvePlayer(rawName)`:
- Нормализует rawName (`toLowerCase().trim()`)
- Ищет в alias map
- Возвращает `{ playerId, resolvedName }` или `null`

Используется для резолва имён в:
- `km_session_player_stats` (поля `player_id`, `resolved_name`)
- `player_profa_history` (поле `player_id`)
- `player_notes` (поле `player_id`)

### KM Sessions: top-level players

Массив `appliedStatsByDate[date].players` импортируется как строки `km_session_player_stats`:
- `raw_name` = `_rawName` или `name`
- `resolved_name` = результат alias resolution
- `player_id` = результат alias resolution (nullable)
- `detected_profa` = `class2`
- `leader_name` = `null` (top-level)
- `raw_payload_json` = весь объект игрока (передаётся как JS-объект, не строка)

### KM Sessions: grouped player arrays

После импорта top-level `players`, importer проходит по **всем оставшимся ключам** session-объекта.

**Служебные ключи** (пропускаются):
- `players` — уже обработан как top-level
- `appliedAt` — timestamp применения
- `raidTotal` — число игроков в рейде
- `commandChannel` — сводная статистика по КК (не player-level)
- `packLeaders` — маппинг лидеров паков

**`screenPlayersMap` не является служебным ключом** — он обрабатывается как Case B (dict of arrays) наравне с остальными группированными ключами.

**Для всех остальных ключей (включая `screenPlayersMap`):**

- **Case A**: Если значение — массив объектов с player-like shape (есть `name` + хотя бы один из `kills/deaths/pvp_dmg/pve_dmg`), каждый объект импортируется как `km_session_player_stats` с `leader_name = key`
- **Case B**: Если значение — объект, где значения — массивы player-like объектов (паттерн `screenPlayersMap` и аналогичные), каждый sub-array импортируется с `leader_name = subKey`

Итого импортируется:

- a) top-level `players` → `km_session_player_stats` с `leader_name = null`
- b) `screenPlayersMap` → `km_session_player_stats` с `leader_name = subKey` (имя лидера/экрана)
- c) любые другие grouped arrays / grouped dicts → `km_session_player_stats` по тем же правилам

### Session metadata

На `km_sessions` сохраняется (все поля JSONB передаются как JS-объекты):
- `command_channel_json` — массив объектов КК (leader, members, kills, deaths, pvp_dmg, pve_dmg)
- `pack_leaders_json` — dict лидеров паков
- `screen_players_map_json` — полная карта screenPlayersMap
- `raw_snapshot_json` — весь session object целиком

### JSONB-поля

Все JSONB-поля (`override_json`, `command_channel_json`, `pack_leaders_json`, `screen_players_map_json`, `raw_snapshot_json`, `raw_payload_json`, `value_json`) передаются в Supabase как JS-объекты. `JSON.stringify` для JSONB-полей не используется — сериализацию выполняет клиент Supabase.

`exhaustedKeys` импортируется в `app_settings` всегда, если ключ присутствует в backup — даже если его значение равно `{}`. Проверка `Object.keys(...).length > 0` не применяется.

## Troubleshooting

| Симптом | Причина | Решение |
|---------|---------|---------|
| `Missing env: SUPABASE_URL...` | Не заданы env vars | Задать `SUPABASE_URL` и `SUPABASE_SERVICE_ROLE_KEY` |
| `upsert players: ...` | Миграция не применена | Применить `0001_clan_control_v1.sql` |
| `cannot resolve player "xxx"` | Игрок есть в `playerNotes` / `playerProfaByDate`, но не в roster/archive | Нормально для внешних имён. Запись пропускается с warning |
| Повторный запуск дублирует данные | Не должно — importer делает полную очистку | Если проблема есть — проверить FK constraints |
| Данные из `screenPlayersMap` не импортируются | `screenPlayersMap` попал в META_KEYS | Убедиться, что `screenPlayersMap` отсутствует в `META_KEYS` в скрипте |

## Проверка после импорта

```sql
SELECT 'packs' AS tbl, count(*) FROM packs
UNION ALL SELECT 'players', count(*) FROM players
UNION ALL SELECT 'player_aliases', count(*) FROM player_aliases
UNION ALL SELECT 'calendar_events', count(*) FROM calendar_events
UNION ALL SELECT 'km_sessions', count(*) FROM km_sessions
UNION ALL SELECT 'km_session_player_stats', count(*) FROM km_session_player_stats
UNION ALL SELECT 'player_profa_history', count(*) FROM player_profa_history
UNION ALL SELECT 'player_notes', count(*) FROM player_notes
UNION ALL SELECT 'app_settings', count(*) FROM app_settings;
```
