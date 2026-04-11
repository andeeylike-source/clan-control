# Model Router

## Что работает

Batch/headless вызовы через `router.sh` / `router.ps1`.
Скрипт выбирает модель по ключевым словам или явному флагу, затем вызывает `claude --model X -p "задача"`.

## Что не работает

Routing внутри интерактивной сессии (`claude` без `-p`).
Claude Code не может сменить модель в середине сессии — это ограничение CLI.
**Interactive session = всегда Sonnet.**

## Точка входа

`.claude/router.sh` (bash) или `.claude/router.ps1` (PowerShell)

## Команды запуска

### Auto-route по ключевым словам
```bash
bash .claude/router.sh "исправь опечатку в кнопке"
bash .claude/router.sh "разберись почему не работает логин"
bash .claude/router.sh "спроектируй схему базы данных для auth"
```

### Явный выбор модели
```bash
# cheap — Haiku (быстро, дёшево)
bash .claude/router.sh --cheap "переименуй переменную"

# normal — Sonnet (стандарт)
bash .claude/router.sh --normal "отладь flow логина"

# heavy — Opus (сложные задачи)
bash .claude/router.sh --heavy "перепроектируй схему auth"
```

### PowerShell (Windows)
```powershell
.\.claude\router.ps1 --cheap  "rename variable"
.\.claude\router.ps1 --normal "debug login flow"
.\.claude\router.ps1 --heavy  "redesign auth schema"
```

## Проверка одной командой

```bash
bash .claude/router.sh --cheap "тест роутера"
```
Ожидаемый вывод в stderr: `→ routing to: claude-haiku-4-5-20251001`

## Keyword mapping

| Паттерн | Модель |
|---|---|
| architect, schema, migrate, audit, rewrite, redesign... | Opus |
| typo, rename, color, padding, quick fix, one-line... | Haiku |
| всё остальное | Sonnet |
