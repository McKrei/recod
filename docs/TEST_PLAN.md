# Test Plan: Приоритет 1 — Чистые функции (Unit Tests)

**Дата:** 2 марта 2026
**Автор:** AI-ассистент (на основе анализа кодовой базы)
**Статус:** Готов к реализации
**Оценка:** ~98 тестов, 7 файлов, 0 моков, 0 рефакторинга продакшн-кода

---

## Контекст

### Текущее покрытие
- **13 тестов** в 2 файлах (`AudioEngineGraphTests.swift`, `AudioRecorderUnitTests.swift`)
- Все тесты покрывают **только** аудио-движок и запись (AVAudioEngine, CoreAudio, WAV-файлы)
- **0 тестов** на текстовую обработку, модели, хоткеи, сегментацию, словарь замен

### Чего НЕ касается этот план
- UI/SwiftUI тесты (snapshot, preview)
- Интеграционные тесты с WhisperKit/SherpaOnnx (требуют реальные модели)
- Тесты `RecordingOrchestrator` (требует моков для 8+ зависимостей)
- Тесты `ClipboardService.insertText` (требует Accessibility permissions)
- Тесты `HotKeyManager` (Carbon API, системные хоткеи)

### Технические решения
- **Framework:** Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) — как в существующих тестах
- **Swift:** 6.0 Strict Concurrency
- **Размещение:** `Tests/` (рядом с существующими файлами)
- **Зависимости в Package.swift:** Тесты НЕ импортируют таргет `Recod` (тестовый таргет не зависит от основного). Весь тестируемый код — чистые функции из Foundation. Нужно **скопировать** минимальные типы в тест или сделать `@testable import` (см. секцию "Настройка Package.swift")

---

## ВАЖНО: Настройка Package.swift

Текущий `Package.swift` имеет пустой `dependencies: []` для `RecodTests`. Чтобы тесты могли импортировать код приложения, нужно **одно из двух**:

### Вариант A (Рекомендуемый): `@testable import Recod`

Изменить `Package.swift`:

```swift
.testTarget(
    name: "RecodTests",
    dependencies: ["Recod"],  // <-- добавить зависимость
    path: "Tests",
    swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
    ]
)
```

**Проблема:** `Recod` — это `executableTarget`, а не `library`. `@testable import` для executable таргетов в SPM может не работать. В этом случае используй Вариант B.

### Вариант B: Выделить `RecodLib` library target

```swift
.target(
    name: "RecodLib",
    dependencies: [
        .product(name: "WhisperKit", package: "WhisperKit"),
        .product(name: "Sparkle", package: "Sparkle"),
        .product(name: "SherpaOnnxSwift", package: "SherpaOnnx")
    ],
    path: "Sources",
    exclude: ["App/main.swift"],  // или как организован entry point
    swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
        .unsafeFlags(["-enable-actor-data-race-checks"])
    ]
),
.executableTarget(
    name: "Recod",
    dependencies: ["RecodLib"],
    path: "Sources/App"
),
.testTarget(
    name: "RecodTests",
    dependencies: ["RecodLib"],
    path: "Tests",
    swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
    ]
)
```

### Вариант C (Текущий подход): Автономные тесты

Существующие тесты (`AudioEngineGraphTests`, `AudioRecorderUnitTests`) дублируют CoreAudio хелперы прямо в тестовых файлах. Это работает для низкоуровневого кода, но **не подходит** для тестирования бизнес-логики (`TextReplacementService`, `ParakeetSegmentBuilder` и т.д.), потому что эти типы зависят друг от друга и от SwiftData моделей.

**Рекомендация:** Начни с Варианта A. Если не получится из-за executable target — переходи к Варианту B.

---

## Файл 1: `LevenshteinDistanceTests.swift`

**Тестируемый файл:** `Sources/Core/Utilities/String+Levenshtein.swift`
**Тестируемый метод:** `String.levenshteinDistance(to other: String) -> Int`
**Зависимости:** Нет (чистое расширение String)
**Оценка:** ~12 тестов

### Что тестируем

Это единственный метод — вычисление расстояния Левенштейна (минимальное количество вставок/удалений/замен для преобразования одной строки в другую). Используется в `TextReplacementService` для fuzzy matching.

### Тесты

```
@Suite("Levenshtein Distance")
struct LevenshteinDistanceTests {
```

| # | Имя теста | Входные данные | Ожидаемый результат | Что проверяет |
|---|---|---|---|---|
| 1 | `identicalStringsReturnZero` | `"hello".levenshteinDistance(to: "hello")` | `0` | Базовый случай — одинаковые строки |
| 2 | `emptyToEmptyReturnsZero` | `"".levenshteinDistance(to: "")` | `0` | Оба пустые |
| 3 | `emptyToNonEmptyReturnsLength` | `"".levenshteinDistance(to: "abc")` | `3` | Пустая к непустой = длина второй |
| 4 | `nonEmptyToEmptyReturnsLength` | `"abc".levenshteinDistance(to: "")` | `3` | Непустая к пустой = длина первой |
| 5 | `singleSubstitution` | `"cat".levenshteinDistance(to: "car")` | `1` | Одна замена символа |
| 6 | `singleInsertion` | `"cat".levenshteinDistance(to: "cats")` | `1` | Одна вставка |
| 7 | `singleDeletion` | `"cats".levenshteinDistance(to: "cat")` | `1` | Одно удаление |
| 8 | `completelyDifferentSameLength` | `"abc".levenshteinDistance(to: "xyz")` | `3` | Полностью разные строки |
| 9 | `caseSensitivity` | `"ABC".levenshteinDistance(to: "abc")` | `3` | Регистрозависимость (A≠a, B≠b, C≠c) |
| 10 | `unicodeCyrillic` | `"привет".levenshteinDistance(to: "привет")` | `0` | Unicode кириллица — идентичные |
| 11 | `unicodeMixed` | `"hello".levenshteinDistance(to: "хелло")` | `5` | Латиница vs кириллица — полностью разные символы |
| 12 | `stringsWithSpaces` | `"hello world".levenshteinDistance(to: "helloworld")` | `1` | Удаление пробела |
| 13 | `symmetry` | оба направления | одинаковый результат | `a→b == b→a` (свойство метрики) |

### Примечания для разработчика
- Метод определён как `extension String` в `Sources/Core/Utilities/String+Levenshtein.swift:7`
- Реализация использует классический DP-алгоритм (O(n*m) по времени, O(m) по памяти)
- Тест `symmetry` важен — он проверяет математическое свойство метрики Левенштейна

---

## Файл 2: `TranscriptionFormatterTests.swift`

**Тестируемый файл:** `Sources/Core/Services/TranscriptionFormatter.swift`
**Тестируемый метод:** `TranscriptionFormatter.cleanSpecialTokens(_ text: String) -> String`
**Зависимости:** Нет (статический метод, Foundation regex)
**Оценка:** ~10 тестов

### Что тестируем

WhisperKit возвращает текст со специальными токенами вида `<|startoftranscript|>`, `<|en|>`, `<|transcribe|>`, `<|endoftext|>`. Метод удаляет их через regex `<\|.*?\|>` и тримит whitespace.

### Тесты

```
@Suite("TranscriptionFormatter")
struct TranscriptionFormatterTests {
```

| # | Имя теста | Входные данные | Ожидаемый результат | Что проверяет |
|---|---|---|---|---|
| 1 | `removesStartOfTranscript` | `"<\|startoftranscript\|>Hello"` | `"Hello"` | Удаление одного токена в начале |
| 2 | `removesMultipleTokens` | `"<\|en\|><\|transcribe\|>Hello world<\|endoftext\|>"` | `"Hello world"` | Удаление нескольких токенов |
| 3 | `noTokensUnchanged` | `"Hello world"` | `"Hello world"` | Текст без токенов не меняется |
| 4 | `emptyStringReturnsEmpty` | `""` | `""` | Пустая строка |
| 5 | `onlyTokensReturnsEmpty` | `"<\|startoftranscript\|><\|en\|><\|endoftext\|>"` | `""` | Строка только из токенов |
| 6 | `trimsWhitespace` | `"  <\|en\|>  Hello  "` | `"Hello"` | Тримминг пробелов вокруг результата |
| 7 | `preservesNonTokenAngles` | `"3 < 5 and 5 > 3"` | `"3 < 5 and 5 > 3"` | Обычные `<>` не затрагиваются (нет `\|`) |
| 8 | `pipeWithoutAngles` | `"Hello \| world"` | `"Hello \| world"` | Pipe без angle brackets не удаляется |
| 9 | `unicodeContentPreserved` | `"<\|ru\|>Привет мир"` | `"Привет мир"` | Unicode контент сохраняется |
| 10 | `tokensInMiddleOfText` | `"Hello<\|0.00\|> world<\|2.50\|> foo"` | `"Hello world foo"` | Timestamp-подобные токены в середине текста |
| 11 | `consecutiveTokensNoSpace` | `"<\|en\|><\|transcribe\|><\|notimestamps\|>Test"` | `"Test"` | Несколько токенов подряд без пробелов |

### Примечания для разработчика
- Regex: `<\\|.*?\\|>` — lazy quantifier (`*?`), поэтому `<|en|>text<|end|>` корректно удалит оба токена, а не весь текст между первым `<|` и последним `|>`
- Метод определён как `public static` в `Sources/Core/Services/TranscriptionFormatter.swift:9`
- После удаления токенов вызывается `.trimmingCharacters(in: .whitespacesAndNewlines)`

---

## Файл 3: `HotKeyShortcutTests.swift`

**Тестируемый файл:** `Sources/Core/Models/HotKeyShortcut.swift`
**Тестируемые члены:** `carbonModifiers(from:)`, `displayString`, `modifierSymbols`, `keyName`, `Codable`, `Equatable`
**Зависимости:** Carbon framework (compile-time constants `kVK_*`, `cmdKey`, `shiftKey`, etc.)
**Оценка:** ~20 тестов

### Что тестируем

`HotKeyShortcut` — `Codable Sendable` struct, хранит `keyCode: UInt32` и `modifiers: UInt32` (Carbon modifier flags). Все computed properties чистые.

### Тесты

```
@Suite("HotKeyShortcut")
struct HotKeyShortcutTests {
```

#### Группа: carbonModifiers (NSEvent.ModifierFlags → Carbon UInt32)

| # | Имя теста | Входные данные | Ожидаемый результат |
|---|---|---|---|
| 1 | `carbonModifiersCommand` | `.command` | `UInt32(cmdKey)` |
| 2 | `carbonModifiersShift` | `.shift` | `UInt32(shiftKey)` |
| 3 | `carbonModifiersOption` | `.option` | `UInt32(optionKey)` |
| 4 | `carbonModifiersControl` | `.control` | `UInt32(controlKey)` |
| 5 | `carbonModifiersCombined` | `[.command, .shift]` | `UInt32(cmdKey \| shiftKey)` |
| 6 | `carbonModifiersAllFour` | `[.command, .shift, .option, .control]` | `UInt32(cmdKey \| shiftKey \| optionKey \| controlKey)` |
| 7 | `carbonModifiersEmpty` | `[]` (пустые флаги) | `0` |

#### Группа: displayString

| # | Имя теста | HotKeyShortcut | Ожидаемый `displayString` |
|---|---|---|---|
| 8 | `displayStringDefault` | `.default` (Cmd+Shift+R) | `"⇧⌘R"` |
| 9 | `displayStringAllModifiers` | `keyCode=kVK_ANSI_A, modifiers=all4` | `"⌃⌥⇧⌘A"` |
| 10 | `displayStringNoModifiers` | `keyCode=kVK_F5, modifiers=0` | `"F5"` |
| 11 | `displayStringSpaceKey` | `keyCode=kVK_Space, modifiers=cmdKey` | `"⌘Space"` |

#### Группа: modifierSymbols

| # | Имя теста | HotKeyShortcut | Ожидаемый `modifierSymbols` |
|---|---|---|---|
| 12 | `modifierSymbolsDefault` | `.default` | `["⇧", "⌘"]` |
| 13 | `modifierSymbolsEmpty` | `modifiers=0` | `[]` |
| 14 | `modifierSymbolsOrder` | `all 4 modifiers` | `["⌃", "⌥", "⇧", "⌘"]` (macOS стандартный порядок) |

#### Группа: keyName

| # | Имя теста | keyCode | Ожидаемый `keyName` |
|---|---|---|---|
| 15 | `keyNameLetters` | `kVK_ANSI_A`, `kVK_ANSI_Z` | `"A"`, `"Z"` |
| 16 | `keyNameDigits` | `kVK_ANSI_0`, `kVK_ANSI_9` | `"0"`, `"9"` |
| 17 | `keyNameFunctionKeys` | `kVK_F1`, `kVK_F12` | `"F1"`, `"F12"` |
| 18 | `keyNameSpecialKeys` | `kVK_Return`, `kVK_Space`, `kVK_Escape`, `kVK_Delete`, `kVK_Tab` | `"↩"`, `"Space"`, `"⎋"`, `"⌫"`, `"⇥"` |
| 19 | `keyNameArrows` | `kVK_LeftArrow` .. `kVK_DownArrow` | `"←"`, `"→"`, `"↑"`, `"↓"` |
| 20 | `keyNameUnknown` | `UInt32(999)` (невалидный код) | `"?"` |

#### Группа: Codable & Equatable

| # | Имя теста | Что проверяет |
|---|---|---|
| 21 | `codableRoundTrip` | `JSONEncoder().encode(shortcut)` → `JSONDecoder().decode()` → `== original` |
| 22 | `equatableSame` | Два экземпляра с одинаковыми `keyCode`/`modifiers` → `==` |
| 23 | `equatableDifferentKey` | Разные `keyCode` → `!=` |
| 24 | `equatableDifferentModifiers` | Разные `modifiers` → `!=` |

### Примечания для разработчика
- Нужен `import Carbon` для констант `kVK_ANSI_R`, `kVK_F5`, `cmdKey`, `shiftKey` и т.д.
- Нужен `import AppKit` для `NSEvent.ModifierFlags`
- `displayString` определён в `HotKeyShortcut.swift:27` — порядок модификаторов: ⌃ → ⌥ → ⇧ → ⌘
- `keyName(for:)` — приватный static метод (`HotKeyShortcut.swift:53`), тестируется через публичное свойство `keyName`

---

## Файл 4: `ParakeetSegmentBuilderTests.swift`

**Тестируемый файл:** `Sources/Core/Services/ParakeetSegmentBuilder.swift`
**Тестируемый метод:** `ParakeetSegmentBuilder.buildSegments(tokens:timestamps:durations:timeOffset:) -> [TranscriptionSegment]`
**Зависимости:** `TranscriptionSegment` (struct из `Recording.swift`)
**Оценка:** ~15 тестов

### Что тестируем

Конвертер BPE-токенов от SherpaOnnx Parakeet в `TranscriptionSegment`. Работает в два этапа:
1. **BPE→слова:** Токены с префиксом `▁` (U+2581) — начало нового слова; без префикса — продолжение предыдущего слова.
2. **Слова→сегменты:** Разбиение по предложениям (`.`, `?`, `!`). Остаток без пунктуации — финальный сегмент.

### Тесты

```
@Suite("ParakeetSegmentBuilder")
struct ParakeetSegmentBuilderTests {
```

#### Группа: BPE merging (токены → слова)

| # | Имя теста | tokens | Ожидаемый текст сегмента(ов) | Что проверяет |
|---|---|---|---|---|
| 1 | `emptyTokensReturnsEmpty` | `[]` | `[]` | Guard на пустой массив |
| 2 | `singleToken` | `["▁Hello"]` | `["Hello"]` | Один токен = один сегмент |
| 3 | `basicWordBoundaries` | `["▁Hello", ",", "▁my", "▁name"]` | `"Hello, my name"` (один сегмент, нет sentence-ender) | Стандартный BPE merge |
| 4 | `continuationTokens` | `["▁Spar", "kle", "tini"]` | `"Sparkletini"` | Токены без `▁` склеиваются к предыдущему |
| 5 | `spacePrefix` | `[" Hello", " world"]` | `"Hello world"` | Пробел как альтернатива `▁` |
| 6 | `emptyTokenAfterClean` | `["▁", "▁Hello"]` | `"Hello"` | Токен-только-`▁` пропускается (cleanToken пустой после strip) |
| 7 | `mixedContinuation` | `["▁I", "'m", "▁hap", "py"]` | `"I'm happy"` | Апостроф + continuation |

#### Группа: Sentence segmentation (слова → сегменты)

| # | Имя теста | tokens | Ожидаемое кол-во сегментов | Что проверяет |
|---|---|---|---|---|
| 8 | `singleSentenceWithPeriod` | `["▁Hello", "▁world", "."]` | 1 сегмент: `"Hello world."` | Точка завершает предложение |
| 9 | `multipleSentences` | `["▁Hi", ".", "▁Bye", "."]` | 2 сегмента: `"Hi."`, `"Bye."` | Разбиение на два предложения |
| 10 | `questionMark` | `["▁How", "?"]` | 1 сегмент: `"How?"` | Вопросительный знак как sentence-ender |
| 11 | `exclamationMark` | `["▁Wow", "!"]` | 1 сегмент: `"Wow!"` | Восклицательный знак |
| 12 | `noPunctuation` | `["▁Hello", "▁world"]` | 1 сегмент: `"Hello world"` | Без пунктуации = всё в одном |
| 13 | `trailingAfterSentence` | `["▁A", ".", "▁B"]` | 2 сегмента: `"A."`, `"B"` | Остаток после последней точки |

#### Группа: Timestamps & timeOffset

| # | Имя теста | Что проверяет |
|---|---|---|
| 14 | `timestampsCorrect` | `segment.start` = timestamp первого токена; `segment.end` = timestamp + duration последнего |
| 15 | `timeOffsetApplied` | С `timeOffset=5.0`: все timestamps сдвинуты на 5 секунд |
| 16 | `emptyDurationsUseDefault` | `durations=[]`: используется default 0.08 секунд на токен |
| 17 | `missingTimestampsDefaultZero` | `timestamps` короче `tokens`: отсутствующие = 0 |

### Примечания для разработчика
- `ParakeetSegmentBuilder` — `struct` с `static func buildSegments(...)` (`ParakeetSegmentBuilder.swift:23`)
- `TranscriptionSegment` — `struct: Codable, Identifiable, Hashable` (`Recording.swift:59`)
- `▁` — это U+2581 (LOWER ONE EIGHTH BLOCK), НЕ обычный underscore. В Swift: `"\u{2581}"`
- Все private методы тестируются транзитивно через `buildSegments`
- `sentenceEnders` = `[".", "?", "!"]` (`ParakeetSegmentBuilder.swift:97`)

---

## Файл 5: `TextReplacementServiceTests.swift`

**Тестируемый файл:** `Sources/Core/Services/TextReplacementService.swift`
**Тестируемый метод:** `TextReplacementService.applyReplacements(text:rules:) -> String`
**Зависимости:** `ReplacementRule` (@Model SwiftData), `String.levenshteinDistance(to:)`
**Оценка:** ~25 тестов

### ВАЖНО: SwiftData в тестах

`ReplacementRule` — это `@Model` (SwiftData). Для создания экземпляров в тестах нужен `ModelContainer` в памяти:

```swift
import SwiftData

private func makeRule(
    textToReplace: String,
    replacementText: String,
    additionalForms: [String] = [],
    useFuzzyMatching: Bool = true,
    weight: Float = 1.5
) throws -> ReplacementRule {
    // Создаём контейнер в памяти
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: ReplacementRule.self, configurations: config)
    let context = ModelContext(container)
    
    let rule = ReplacementRule(
        textToReplace: textToReplace,
        additionalIncorrectForms: additionalForms,
        replacementText: replacementText,
        weight: weight,
        useFuzzyMatching: useFuzzyMatching
    )
    context.insert(rule)
    return rule
}
```

**Альтернатива:** Если SwiftData `@Model` создаётся без `ModelContext` (просто `ReplacementRule(...)`) и не крэшит — можно обойтись без контейнера. **Проверь это первым делом.** В Swift 5.9+ `@Model` иногда можно инстанциировать без контекста для read-only использования.

### Тесты

```
@Suite("TextReplacementService")
struct TextReplacementServiceTests {
```

#### Группа: Exact Matching (`useFuzzyMatching = false`)

| # | Имя теста | text | rules | Ожидаемый результат | Что проверяет |
|---|---|---|---|---|---|
| 1 | `emptyRulesReturnsText` | `"Hello"` | `[]` | `"Hello"` | Guard на пустые правила |
| 2 | `exactCaseInsensitive` | `"hello World"` | `["hello" → "Hi"]` | `"Hi World"` | Регистронезависимая замена |
| 3 | `exactMultipleOccurrences` | `"cat and cat"` | `["cat" → "dog"]` | `"dog and dog"` | Все вхождения заменяются |
| 4 | `exactLongestFirst` | `"catalog"` | `["catalog" → "каталог", "cat" → "кот"]` | `"каталог"` | Длинные паттерны применяются первыми |
| 5 | `exactAdditionalForms` | `"colour is good"` | `[textToReplace="color", additional=["colour"], replacement="цвет"]` | `"цвет is good"` | `additionalIncorrectForms` работают |
| 6 | `exactEmptyTextToReplace` | `"hello"` | `["" → "world"]` | `"hello"` | Пустой паттерн игнорируется |
| 7 | `exactWhitespaceOnlyPattern` | `"hello"` | `["   " → "world"]` | `"hello"` | Whitespace-only паттерн тримится и игнорируется |
| 8 | `exactSpecialRegexChars` | `"price is $100"` | `["$100" → "$200"]` | `"price is $200"` | `NSRegularExpression.escapedPattern` экранирует спецсимволы |

#### Группа: Fuzzy Matching (`useFuzzyMatching = true`)

| # | Имя теста | text | rules | Ожидаемый результат | Что проверяет |
|---|---|---|---|---|---|
| 9 | `fuzzyExactMatch` | `"hello world"` | `["hello" → "Hi"]` (fuzzy, distance=0) | `"Hi world"` | Fuzzy с нулевой дистанцией |
| 10 | `fuzzyOneCharDifference` | `"claud code"` | `["claude code" → "Claude Code"]` | `"Claude Code"` | Одна буква пропущена, threshold допускает |
| 11 | `fuzzyBeyondThreshold` | `"xxxxx"` | `["hello" → "Hi"]` (len=5, threshold=1, distance=5) | `"xxxxx"` | За пределами порога — нет замены |
| 12 | `fuzzyMultiWordPattern` | `"клот код is great"` | `["claude code" → "Claude Code"]` | `"Claude Code is great"` | Multi-word fuzzy N-gram |
| 13 | `fuzzyASRMerge` | `"claudecode is nice"` | `["claude code" → "Claude Code"]` (2 words, window pw-1=1) | `"Claude Code is nice"` | ASR слило два слова в одно (окно pw-1) |
| 14 | `fuzzyASRSplit` | `"clau de code rocks"` | `["claude code" → "Claude Code"]` (2 words, window pw+1=3) | `"Claude Code rocks"` | ASR разбило слово на два (окно pw+1) |
| 15 | `fuzzyPunctuationPreserved` | `"...sparkletini, is"` | `["Sparkletini" → "Sparkletini"]` | `"...Sparkletini, is"` | Пунктуация (`...` и `,`) сохраняется |
| 16 | `fuzzyEmptyText` | `""` | `["hello" → "Hi"]` | `""` | Пустой текст |
| 17 | `fuzzySingleWord` | `"helo"` | `["hello" → "Hello"]` (len=5, threshold=1, distance=1) | `"Hello"` | Текст из одного слова |
| 18 | `fuzzyPatternLongerThanText` | `"hi"` | `["hello world foo bar" → "X"]` | `"hi"` | Паттерн длиннее всего текста |

#### Группа: Distance Threshold Boundaries

| # | Имя теста | Pattern length | Ожидаемый threshold | Что проверяет |
|---|---|---|---|---|
| 19 | `thresholdLength3` | 3 chars | 0 | Строгий: exact match only |
| 20 | `thresholdLength4` | 4 chars | 1 | Допускает 1 ошибку |
| 21 | `thresholdLength6` | 6 chars | 2 | Допускает 2 ошибки |
| 22 | `thresholdLength9` | 9 chars | 3 | Допускает 3 ошибки |
| 23 | `thresholdLength13` | 13 chars | 4 | Максимум: 4 ошибки |

> **Как тестировать threshold:** Создай правило с паттерном нужной длины и текст с distance = threshold (должен пройти) и distance = threshold+1 (не должен).

#### Группа: Комбинированные тесты

| # | Имя теста | Что проверяет |
|---|---|---|
| 24 | `exactThenFuzzy` | Сначала exact, потом fuzzy на результат — оба типа правил работают вместе |
| 25 | `multipleRulesLongestFirst` | Несколько fuzzy правил: самый длинный паттерн побеждает |
| 26 | `noDoubleProcessing` | После замены слово не обрабатывается повторно (итератор `i += 1`) |

### Примечания для разработчика
- `applyReplacements` — `static func` в `TextReplacementService.swift:17`
- Exact matching использует `NSRegularExpression` с `escapedPattern` (`TextReplacementService.swift:50`)
- Fuzzy matching: sliding window с размерами `[pw, pw-1, pw+1]` (`TextReplacementService.swift:142-144`)
- `calculateDistanceThreshold` — логика порогов (`TextReplacementService.swift:172-179`):
  - 0-3 символов → threshold 0
  - 4-5 символов → threshold 1
  - 6-8 символов → threshold 2
  - 9-12 символов → threshold 3
  - 13+ символов → threshold 4
- `preservePunctuation` сохраняет leading/trailing пунктуацию оригинальных слов (`TextReplacementService.swift:183`)

---

## Файл 6: `TranscriptionEngineTests.swift`

**Тестируемый файл:** `Sources/Core/Models/TranscriptionEngine.swift`
**Тестируемые члены:** Все computed properties enum `TranscriptionEngine`
**Зависимости:** Нет
**Оценка:** ~8 тестов

### Что тестируем

Простой enum с двумя кейсами (`.whisperKit`, `.parakeet`), но важен для стабильности — его `rawValue` используется для persistence (UserDefaults/SwiftData).

### Тесты

```
@Suite("TranscriptionEngine")
struct TranscriptionEngineTests {
```

| # | Имя теста | Что проверяет |
|---|---|---|
| 1 | `allCasesCount` | `TranscriptionEngine.allCases.count == 2` |
| 2 | `rawValues` | `.whisperKit.rawValue == "whisperKit"`, `.parakeet.rawValue == "parakeet"` |
| 3 | `initFromRawValue` | `TranscriptionEngine(rawValue: "whisperKit") == .whisperKit` |
| 4 | `invalidRawValueReturnsNil` | `TranscriptionEngine(rawValue: "invalid") == nil` |
| 5 | `codableRoundTrip` | Encode → Decode → Equal (для обоих кейсов) |
| 6 | `displayNameWhisperKit` | `.whisperKit.displayName == "WhisperKit"` |
| 7 | `displayNameParakeet` | `.parakeet.displayName == "Parakeet V3"` |
| 8 | `identifiableId` | `.whisperKit.id == "whisperKit"` (id == rawValue) |
| 9 | `iconNames` | `.whisperKit.iconName == "waveform.circle"`, `.parakeet.iconName == "cpu"` |

### Примечания для разработчика
- Enum определён в `TranscriptionEngine.swift:5`
- Если в будущем добавятся новые движки, тест `allCasesCount` упадёт — это намеренная "ловушка", напоминающая обновить тесты

---

## Файл 7: `TranscriptionSegmentTests.swift`

**Тестируемый файл:** `Sources/Core/Models/Recording.swift` (struct `TranscriptionSegment` и enum `Recording.TranscriptionStatus`)
**Зависимости:** Foundation, SwiftData (для `TranscriptionStatus`)
**Оценка:** ~8 тестов

### Что тестируем

1. `TranscriptionSegment` — `Codable`, `Identifiable`, `Hashable` struct с полями `id`, `start`, `end`, `text`
2. `Recording.TranscriptionStatus` — `String` enum с кейсами `.pending`, `.streamingTranscription`, `.transcribing`, `.completed`, `.failed`

### Тесты

```
@Suite("TranscriptionSegment & TranscriptionStatus")
struct TranscriptionSegmentTests {
```

#### Группа: TranscriptionSegment

| # | Имя теста | Что проверяет |
|---|---|---|
| 1 | `segmentInit` | Init с `start: 1.0, end: 2.5, text: "Hello"` — все поля корректны |
| 2 | `segmentCodableRoundTrip` | Encode → Decode → поля совпадают (start, end, text, id) |
| 3 | `segmentIdentifiable` | `segment.id` — валидный UUID |
| 4 | `segmentHashableSameContent` | Два сегмента с разными `id` но одинаковым `start/end/text` — **не равны** (потому что `id` входит в Hashable) |
| 5 | `segmentHashableSameId` | Два сегмента с одинаковым `id` — равны |

#### Группа: Recording.TranscriptionStatus

| # | Имя теста | Что проверяет |
|---|---|---|
| 6 | `statusRawValues` | Каждый кейс имеет ожидаемый rawValue: `"pending"`, `"streamingTranscription"`, `"transcribing"`, `"completed"`, `"failed"` |
| 7 | `statusCodableRoundTrip` | Encode `.completed` → Decode → `.completed` |
| 8 | `statusInitFromRawValue` | `TranscriptionStatus(rawValue: "pending") == .pending` |
| 9 | `statusInvalidRawValue` | `TranscriptionStatus(rawValue: "unknown") == nil` |

### Примечания для разработчика
- `TranscriptionSegment` определён в `Recording.swift:59-63`
- `TranscriptionStatus` — nested enum внутри `Recording` класса (`Recording.swift:6-12`)
- `TranscriptionSegment` автоматически синтезирует `Hashable` из всех stored properties (`id`, `start`, `end`, `text`)
- Два сегмента с разными UUID но одинаковым текстом/таймингами будут `.hash` отличаться — это **ожидаемое поведение**

---

## Чеклист перед стартом

- [ ] Выбрать и реализовать Вариант A, B или C для настройки `Package.swift`
- [ ] Убедиться что `import Testing` работает в новых файлах
- [ ] Убедиться что `ReplacementRule` можно создать без `ModelContext` (если нет — использовать in-memory `ModelContainer`)
- [ ] Все файлы тестов создаются в `Tests/`
- [ ] Запуск: `swift build --build-tests && swift test`
- [ ] Не добавлять `@Suite(.serialized)` если тесты не конфликтуют по shared state (эти тесты — чистые функции, serialization не нужна)
- [ ] Использовать `#expect()` для ассертов, `#require()` для preconditions (Swift Testing API)

## Порядок реализации (рекомендуемый)

1. **`LevenshteinDistanceTests`** — самый простой, 0 зависимостей, валидирует настройку Package.swift
2. **`TranscriptionFormatterTests`** — тоже 0 зависимостей, быстро
3. **`TranscriptionEngineTests`** — простой enum, быстро
4. **`TranscriptionSegmentTests`** — простые структуры
5. **`HotKeyShortcutTests`** — нужен `import Carbon` + `import AppKit`
6. **`ParakeetSegmentBuilderTests`** — зависит от `TranscriptionSegment`
7. **`TextReplacementServiceTests`** — самый сложный, зависит от `ReplacementRule` (SwiftData) + `String.levenshteinDistance`

---

## Метрики успеха

| Метрика | До | После |
|---|---|---|
| Тестовых файлов | 2 | 9 |
| Тестов | 13 | ~111 |
| Покрытие: текстовая обработка | 0% | ~90% |
| Покрытие: модели данных | 0% | ~80% |
| Покрытие: хоткеи (модель) | 0% | ~95% |
| Покрытие: сегментация | 0% | ~90% |
| Моков написано | 0 | 0 |
| Рефакторинг прод-кода | — | Не требуется (кроме `Package.swift`) |
