# Save to File Feature — Summary

**Дата:** 2026-03-05  
**Статус:** ✅ Завершено

## Задача

Добавить в Post-Processing Actions возможность автоматического сохранения LLM-результата в файл.

## Реализовано

| Компонент | Файл |
|-----------|------|
| Модель + enum | `Sources/Core/Models/PostProcessingAction.swift`, `SaveToFileMode.swift` |
| Сервис записи | `Sources/Core/Services/FileOutputService.swift` |
| Интеграция | `Sources/Core/Services/PostProcessingService.swift` |
| UI (секция) | `Sources/Features/PostProcessing/AddActionSaveToFileSection.swift` |
| UI (форма) | `Sources/Features/PostProcessing/AddActionView.swift` |
| Индикатор | `Sources/Features/PostProcessing/ActionRowView.swift` |
| Backup/Import | `Sources/Core/Services/DataBackupService.swift` |
| Документация | `docs/POST_PROCESSING.md` |

## Режимы

- **New file** — создаёт файл по шаблону с timestamp (`{YYYY}-{MM}-{DD}_{HH}{mm}{ss}`)
- **Existing file** — дописывает в один файл с разделителем

## Особенности

- Работает для auto и manual запуска
- Ошибки логируются, не прерывают pipeline
- UI: скроллируемая форма, кнопки прибиты к футеру
- Path validation: директория vs файл проверяется при записи

## Edge Cases

- SwiftData migration: `@Attribute(originalName:)` для rename `saveToFileEnabled` → `saveToFileEnabledRaw`
- Fallback для пустого шаблона
- Separate state для directory/file path в UI
