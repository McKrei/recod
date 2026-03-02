# Bug Report & Fix: Bluetooth HFP Empty WAV Files

**Дата закрытия:** 02.03.2026  
**Ветка:** `fix/bluetooth-sample-rate`  
**HEAD:** `abd88c1`  
**Статус:** ✅ ИСПРАВЛЕНО — тесты проходят

---

## 1. Симптомы

- Приложение создаёт WAV-файлы размером ~4096 байт (только заголовок, 0 аудио-данных)
- Транскрипция не работает — пустой файл возвращает пустую строку
- **Нестабильность**: иногда работает (первая запись), иногда нет (вторая запись после смены модели)
- Воспроизводится при подключённых Bluetooth-наушниках (Sony WH-1000XM5, AirPods и любые гарнитуры с HFP-профилем)

---

## 2. Корневая причина

### 2.1 CoreAudio Aggregate Device + BT HFP/A2DP sample rate mismatch

Bluetooth-наушники в macOS одновременно работают в двух профилях:

| Роль | Sample Rate | Каналы | Профиль BT |
|---|---|---|---|
| Input (Микрофон) | **16 000 Hz** | 1 (моно) | HFP (Hands-Free Profile) |
| Output (Динамики) | **44 100 Hz** | 2 (стерео) | A2DP (Advanced Audio Distribution) |

`AVAudioEngine` при инициализации читает sample rates default input и default output устройств и строит внутренний **CoreAudio Aggregate Device**. Когда у input и output разные sample rates (16 000 ≠ 44 100 Hz):

- `engine.start()` завершается без ошибок
- Render graph внутри AVAudioEngine ломается **молча**
- `installTap(onBus:bufferSize:format:)` не получает ни одного буфера
- WAV-файл остаётся пустым (только 44-байтный заголовок)

**Это системное поведение macOS/CoreAudio, документально не описанное.**

### 2.2 probeEngine захватывал микрофон (причина нестабильности)

Предыдущий код создавал временный `AVAudioEngine` ("probeEngine") для чтения sample rates перед построением основного графа:

```swift
// ❌ АНТИПАТТЕРН — НЕ ДЕЛАТЬ ТАК
let probeEngine = AVAudioEngine()
let inputRate = probeEngine.inputNode.inputFormat(forBus: 0).sampleRate
// ^^^ ЗАХВАТЫВАЕТ МИКРОФОН HARDWARE
// probeEngine теряется при выходе из скоупа
```

**Проблема:** `probeEngine.inputNode` при первом обращении **захватывает аппаратный микрофон** (macOS резервирует устройство). Когда probeEngine освобождался через ARC, macOS не всегда мгновенно отпускала микрофон. Когда сразу после этого создавался основной engine и вызывался `installTap` — микрофон ещё "занят", tap получал 0 буферов.

Это объясняло паттерн **"работает — не работает"**: зависело от скорости освобождения устройства операционной системой (~0–500ms).

---

## 3. Хронология появления

| Коммит | Изменение | Эффект |
|---|---|---|
| `e565668` | Интеграция Parakeet — последний стабильный граф | ✅ Работал |
| `738ca4b` | WIP: mic device selection — переписал `connect()` на `format: nil` | ❌ Сломал граф |
| `867c3c9` | fix: AirPods stall (попытка починить pan на моно-ноде) | ❌ Не помогло |
| `39ea977` | Revert `867c3c9` | HEAD до фикса |
| `a15c388` | Race condition guard + диагностическое логирование | ✅ Добавлен "Tap FIRST buffer" лог |
| `abd88c1` | **Полный фикс** — CoreAudio probe + watchdog + тесты | ✅ **Закрыто** |

---

## 4. Что было исправлено

### 4.1 Замена probeEngine → CoreAudio API

**Файл:** `Sources/Core/AudioRecorder.swift:485–531`

```swift
// ✅ ПРАВИЛЬНО — читаем rates без захвата микрофона
private func coreAudioDefaultInputSampleRate() -> Float64 {
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &deviceID
    ) == noErr, deviceID != kAudioObjectUnknown else { return 0 }
    // ... читаем kAudioDevicePropertyNominalSampleRate
}
```

`AudioObjectGetPropertyData` читает sample rate напрямую из CoreAudio без создания engine и без захвата hardware.

### 4.2 Alignment output sample rate перед построением графа

**Файл:** `Sources/Core/AudioRecorder.swift:167–185` (в `startRecording()`)

```swift
if !graphInitialized {
    let inputRate = coreAudioDefaultInputSampleRate()
    let outputRate = coreAudioDefaultOutputSampleRate()
    if inputRate > 0 && outputRate > 0 && inputRate != outputRate {
        alignOutputSampleRate(to: inputRate)  // CoreAudio: kAudioDevicePropertyNominalSampleRate
        try await Task.sleep(nanoseconds: 300_000_000)  // ждём применения
    }
}
```

**Важно:** CoreAudio sample rate change — асинхронная операция. Нужна пауза 300ms перед `engine.start()`, иначе engine стартует раньше чем macOS применяет изменение.

### 4.3 Восстановление sample rate после записи

**Файл:** `Sources/Core/AudioRecorder.swift:587–630` (`restoreOutputSampleRate()`)

- Сохраняем original rate в `originalOutputSampleRate` перед изменением
- После `teardownGraph()` восстанавливаем через `AudioObjectSetPropertyData`
- **Защита для BT HFP:** проверяем `kAudioDevicePropertyAvailableNominalSampleRates` — если оригинальный rate недоступен (BT в HFP режиме не принимает произвольные rates), пропускаем восстановление без ошибки

### 4.4 Tap watchdog

**Файл:** `Sources/Core/AudioRecorder.swift:259–273`

```swift
// После engine.start() — ждём первого буфера max 2 секунды
let watchdogDeadline = Date().addingTimeInterval(2.0)
while tapBufferCount == 0 && Date() < watchdogDeadline {
    try await Task.sleep(nanoseconds: 100_000_000)
}
if tapBufferCount == 0 {
    engine.stop()
    teardownGraph()
    audioFile = nil
    throw AudioRecorderError.recordingFailed  // пользователь видит ошибку
}
```

Вместо тихого создания пустого WAV — немедленная ошибка через `recordingFailed`.

### 4.5 Запрет pan на моно BT-нодах

**Файл:** `Sources/Core/AudioRecorder.swift:668–669` (в `setupGraph()`)

```swift
// Pan только для стерео — моно BT HFP нода падает без буферов при pan != 0
if inputFormat.channelCount >= 2 {
    mMixer.pan = -1.0
}
```

Установка `pan` на моно AVAudioMixerNode с BT HFP форматом вызывает тихое нарушение рендер-графа.

---

## 5. Тесты

### 5.1 AudioEngineGraphTests.swift (интеграционные, 4 теста)

| Тест | Что проверяет |
|---|---|
| `minimalDirectTapReceivesBuffers` | OS-уровень: прямой tap на inputNode получает буферы |
| `fullGraphTapReceivesBuffers` | Полный граф (inputNode→micMixer→recMixer): tap получает буферы + BT alignment fix |
| `recordedFileIsNotEmpty` | WAV-файл содержит аудио-данные (>10 KB за 2с) |
| `consecutiveGraphCyclesBothReceiveBuffers` | **Regression test**: 2 последовательных цикла setup→tap→stop→teardown (смена модели Whisper→Parakeet) |

### 5.2 AudioRecorderUnitTests.swift (unit + интеграционные, 9 тестов)

| Тест | Что проверяет |
|---|---|
| `coreAudioInputRateIsNonzero` | CoreAudio helper возвращает ненулевой rate без захвата mic |
| `coreAudioOutputRateIsNonzero` | CoreAudio helper для output возвращает ненулевой rate |
| `coreAudioRateProbeDoesNotCaptureMic` | **Regression**: после CoreAudio probe следующий engine получает буферы |
| `streamingConverterProducesSamples` | AVAudioConverter native→16kHz выдаёт ~32000 сэмплов за 2с |
| `streamBufferGetNewSamplesCorrectness` | `getNewAudioSamples(from:)` возвращает только новые сэмплы |
| `restoreIsNoOpWhenNoAlignmentWasPerformed` | restore guard: no-op при `deviceID=kAudioObjectUnknown` |
| `alignThenRestoreOutputSampleRate` | Полный цикл align→verify→restore→verify |
| `watchdogDetectsZeroBuffersAndAborts` | Disconnected tap → 0 буферов → watchdog срабатывает |
| `watchdogDoesNotFireOnHealthyGraph` | Здоровый граф получает буферы в пределах 2с watchdog window |

### 5.3 Запуск тестов

```bash
# ВАЖНО: убедиться что BT-наушники не являются default input
SwitchAudioSource -t input -s "Микрофон MacBook Pro"

make test
```

**Результаты на 02.03.2026 (built-in mic 48kHz):**
```
✔ AudioEngineGraphTests  — 4/4  (9.7s)
✔ AudioRecorderUnitTests — 9/9  (6.0s)
Total: 13 passed, 0 failed
```

---

## 6. Известные ограничения фикса

### BT HFP `AudioObjectSetPropertyData` → `kAudioHardwareUnsupportedOperationError (1852797029)`

Когда BT-наушники активны в HFP-режиме (микрофон), попытка изменить output sample rate через CoreAudio **возвращает ошибку**. Устройство в HFP-режиме не принимает изменения sample rate.

**Следствие:** если input=16kHz (HFP) и output=44100Hz (A2DP), `alignOutputSampleRate` не может выровнять их → граф всё равно сломается → watchdog выбросит `recordingFailed`.

**Обходной путь для пользователя:** переключить default input на встроенный микрофон перед записью. Приложение показывает ошибку через `recordingFailed` вместо тихого пустого файла.

**Возможное полное решение** (не реализовано): создать CoreAudio Aggregate Device с явно заданным sample rate для обоих физических устройств. Это требует значительного усложнения кода и было откачено ранее (`738ca4b`) из-за регрессий.

### macOS принудительно возвращает BT как default input

macOS иногда автоматически возвращает BT-наушники как default input даже после ручного переключения. Это поведение системы, не поддающееся контролю приложения.

---

## 7. Ключевые инварианты кода (НЕ НАРУШАТЬ)

1. **НЕ использовать `AVAudioEngine` для probe** — даже временный engine с `inputNode` захватывает микрофон
2. **НЕ использовать 16kHz в графе** — конвертация только в `processBufferForStreaming`, после tap
3. **Tap с `format: nil`** — нативный формат ноды
4. **`engine = nil` в teardownGraph** — освобождает BT A2DP
5. **Pan только для стерео** — моно BT HFP падает с pan != 0
6. **Alignment ПЕРЕД `setupGraph()`** — engine читает device rates при первом обращении к `inputNode`
7. **300ms sleep после alignment** — CoreAudio применяет rate change асинхронно

---

## 8. Файлы изменённые в фиксе

| Файл | Изменения |
|---|---|
| `Sources/Core/AudioRecorder.swift` | CoreAudio probe (x2 методы), alignment, watchdog, restore guard, pan guard |
| `Tests/AudioEngineGraphTests.swift` | Новый файл: 4 интеграционных теста + CoreAudio helpers |
| `Tests/AudioRecorderUnitTests.swift` | Новый файл: 9 unit/интеграционных тестов |
| `Package.swift` | Добавлен `testTarget("RecodTests")` |
| `Makefile` | Подписание xctest bundle с `audio-input` entitlement; запуск обоих тестовых сьютов |

---

*Отчёт составлен на основе двухсессионного дебага (01.03.2026 – 02.03.2026). Исправление зафиксировано в коммите `abd88c1` на ветке `fix/bluetooth-sample-rate`.*
