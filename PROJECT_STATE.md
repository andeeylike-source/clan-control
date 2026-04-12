# PROJECT_STATE

## Проект
- name: Clan Control
- format: single-file SPA (HTML + CSS + JS, без сборки)
- main file: BASA (1).html (~13 500 строк)

## Правила
- preview flow обязателен: git add → git commit → git push preview main
- production без явного "да" не трогать
- legacy файлы не менять: clan-control.html, BASA.html, BASAv1.html
- без re-scan всего проекта
- без "готово" без факта проверки
- PROJECT_STATE обновлять только при новом проверяемом факте, не после каждого edit

## Текущее состояние
- current task: поимка "Invalid Date" в Истории КМ — диагностический console.error guard добавлен в preview (ветка), в production НЕ включён; ждём реального воспроизведения бага
- current layer: data integrity / KM history render
- active file: BASA (1).html
- last tested file: BASA (1).html
- last preview url: https://andeeylike-source.github.io/clan-control-preview/BASA%20(1).html
- last verify result: Playwright ECONNRESET (системная проблема Chrome MCP); ручная DOM/код проверка — все подтверждённые изменения корректны
- residual defect: "Invalid Date" в одной карточке Истории КМ — источник не пойман (ключи appliedStatsByDate и eventStatuses чистые на момент проверки); диагностический guard в preview ждёт живого воспроизведения
- residual defect 2: system map Archive-нода проверяет только player archive (`archiveCount`), kmArchive в условии не учтён — нода остаётся idle если только КМ-архив непустой, player-архив пустой

## Рабочий контур (подтверждено)
- agents установлены: ui-fixer, admin-flow-checker, preview-validator
- skills установлены: preview-push, verify, verify-ui
- settings.local.json: git status / git add (точечные пути) / git commit -m / git push preview main — без запроса подтверждения
- Playwright MCP подключён, но системно не запускается (ECONNRESET при старте Chrome DevTools WebSocket)
- production deploy: АВТОМАТИЧЕСКИЙ на push в origin main (workflow_dispatch как fallback)

## Supabase migrations (статус)
- 0001 — base schema: применена ✓
- 0002 — user_app_data: применена ✓
- 0003 — profiles.role: применена ✓
- 0004 — km_screenshots: применена вручную в Supabase SQL editor ✓ (файл: supabase/migrations/0004_km_screenshots.sql)
- 0005 — ownership RLS (private.is_admin, calendar_events, km_sessions, km_session_player_stats): применена вручную ✓ (файл: supabase/migrations/0005_ownership_rls.sql)
- 0006 — km_sessions unique per user (DROP old UNIQUE, CREATE partial index): применена вручную ✓ (файл: supabase/migrations/0006_km_sessions_unique_per_user.sql)

## Screenshot cloud storage (отложено, незавершено)
- Frontend JS для загрузки/чтения скриншотов из Supabase Storage (loadDayScreenshotsFromDB, _uploadScreenshotToStorage, _clearDayScreenshotsFromStorage) — разработан, но ИСКЛЮЧЁН из production до полного тестирования
- В production BASA (1).html: скриншоты работают только локально (base64 в памяти, session-only)
- В preview: диагностический guard для Invalid Date присутствует (console.error только при сбое)
- Bucket km-screenshots в Supabase: создан, Storage RLS policies — на усмотрение

## Последние изменения (хронологически, новые сверху)
- 2026-04-13 — production sync: revert debug guard (d915042) + revert screenshot storage foundation JS (50ce39a); migration 0004 восстановлена в repo; PROJECT_STATE обновлён; push origin main
- 1dd1732 fix ownership inserts and km session unique — migration 0006: DROP CONSTRAINT km_sessions_session_date_key; CREATE UNIQUE INDEX idx_km_sessions_user_date_unique ON km_sessions(user_id, session_date) WHERE user_id IS NOT NULL. Push preview 2026-04-12.
- ca19933 feat add ownership rls migration — migration 0005: private schema + is_admin() SECURITY DEFINER; RLS policies для calendar_events, km_sessions, km_session_player_stats (owner CRUD + admin SELECT). Push preview 2026-04-12.
- 013e6b0/6101245/da51a57 docs ownership model — docs/ownership-model.md: entity matrix, RLS patterns, design decisions. Push preview 2026-04-12.
- 51c4fae feat polish aliases and manual km flow — блок "Алиасы ников" сворачивается по клику, по умолчанию свёрнут; _mkeSave после сохранения КМ вызывает renderCalendar/renderStats/renderDashboard/renderPlayerProfile + toast "КМ сохранён ✓"; addAliasRow авторазворачивает aliases-блок. Push preview 2026-04-12.
- e83a9d1 feat add mini roster picker for manual km — _mkeOpenRosterPicker: position:fixed modal (z-index 10000) с таблицей Ник/Класс/Пак; фильтры: text-input по нику + select по паку + select по профе; _mkeNickPick заполняет ник+профу и закрывает модал. Push preview 2026-04-12.
- b5e0908 fix: render km archive even when player archive is empty — убран ранний return в renderArchive когда player-archive пустой; теперь KM-archive секция рендерится всегда. Push preview 2026-04-12.
- 3ade0d5 feat: move deleted km event to archive with restore — deleteKmEvent переносит запись в kmArchive (snap + statuses + overrides); restoreKmEvent / deleteKmFromArchive на странице архива; kmArchive включён в saveToStorage/loadFromStorage/_applyAppData/exportData/_resetAppState. Push preview 2026-04-12.
- b1d26ea feat delete km event with confirm — showConfirm получил confirmLabel/cancelLabel параметры; deleteKmEvent(dateStr) вызывает confirm с "Да"/"Нет"; кнопка 🗑 в карточке Истории КМ. Push preview 2026-04-12.
- e958e9c fix pro cta in free mode — _activateTestPro обрабатывает admin+adminTestMode==='free' как отдельный кейс (переключает adminTestMode на 'pro'); ранее guard !== 'free' всегда блокировал admin. Push origin/main 2026-04-12.
- 2ff9042 feat: add calendar entrypoint and player hints for manual km — в day-modal добавлена кнопка «✍️ Ввести КМ вручную»; колонка «Класс» в редакторе КМ с пикером профы; автоподсказки ника. Push preview 2026-04-12.
- 5e20e8b fix: show clan pipeline on system map — узлы clan_api / clan_apply в system map. Push origin/main 2026-04-12.

## Production deploy (подтверждено)
- repo: andeeylike-source/clan-control
- workflow: .github/workflows/deploy-production-pages.yml
- триггер: push в main (авто) + workflow_dispatch (ручной fallback)
- path: '.' (весь репозиторий)
- последний production push запланирован: 2026-04-13 (текущая сессия)

## Preview deploy (подтверждено)
- repo: andeeylike-source/clan-control-preview
- remote: preview
- последний commit на preview: d915042 (debug guard — только для диагностики Invalid Date)

## Что нельзя ломать
- позиции CVE-блоков в режиме просмотра календаря (hero-meta layout)
- интеграция Supabase app_settings (хранение фона администратора)
- порядок CSS-каскада: base → GLASS PREMIUM CALENDAR REDESIGN → #v1-shell-override → #readability-layer
- preview push flow (remote "preview", не "origin")
- авторизация/логаут (loginLogout, topbarEmail, ccAdminBtn)
- порядок DOMContentLoaded handlers: Supabase createClient регистрируется первым (в head), auth IIFE — вторым

## Ближайший следующий шаг
- поймать "Invalid Date" через console.error в preview (guard уже активен); после поимки — минимальный фикс в BASA (1).html + push production
- при наличии реального kmArchive — добавить kmArchiveCount в system map data object и обновить switch case 'archive_page'
- screenshot cloud storage: полноценное тестирование перед включением в production
