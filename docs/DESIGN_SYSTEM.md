# Дизайн-система и Руководство по Стилю

## Основная Философия
Recod следует эстетике "Tahoe": глубокая полупрозрачность, стеклянные материалы и плавающие интерфейсы, которые сливаются с обоями пользователя. UI сильно полагается на `Material` (визуальные эффекты), а не на сплошные цвета.

## Центральный Источник Истины: `AppTheme`
Все константы стилей централизованно расположены в `Sources/DesignSystem/AppTheme.swift`.
**Никогда не хардкодьте значения.** Всегда ссылайтесь на `AppTheme`.

```swift
// Пример использования
.padding(AppTheme.padding)
.background(AppTheme.glassMaterial)
.clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
```

### Ключевые Константы
- **Padding**: `AppTheme.padding` (Стандартный 16pt)
- **Page Padding**: `AppTheme.pagePadding` (30pt) для основных областей контента
- **Corner Radius**: `AppTheme.cornerRadius` (Стандартный 16pt)
- **Glass Material**: `AppTheme.glassMaterial` (Использовать для всех фонов контейнеров)
- **Shadows**: Используйте `AppTheme.shadowColor`, `radius` и `y` для постоянной глубины.

---

## Компоненты

### 1. Заголовок Настроек (Settings Header)
Стандартизированный заголовок для всех страниц настроек. Включает заголовок, подзаголовок, иконку и опциональную кнопку действия.
**Файл**: `Sources/DesignSystem/SettingsHeaderView.swift`

Использование:
```swift
SettingsHeaderView(
    title: "Название Страницы",
    subtitle: "Описание",
    systemImage: "gear"
) {
    // Опциональная Кнопка Действия
    Button("Добавить") {}
}
```

### 2. Стиль Стеклянной Строки (Glass Row Style)
Используется для элементов в списках, таких как История, Модели, Файлы.
**Файл**: `Sources/DesignSystem/GlassRowStyle.swift`

Использование:
```swift
HStack {
    // Контент
}
.glassRowStyle(isSelected: Bool, isHovering: Bool)
.onHover { isHovering = $0 }
```

### 3. Стеклянный Контейнер (Glass Group Box)
Используется для группировки настроек или секций контента.
**Файл**: `Sources/DesignSystem/GlassGroupBoxStyle.swift`

Использование:
```swift
GroupBox {
    // Контент
}
.groupBoxStyle(GlassGroupBoxStyle())
```

### 4. Стандартные Кнопки Действий
Согласованная иконографика и состояния наведения для общих действий.
**Файл**: `Sources/DesignSystem/StandardButtons.swift`

- `DeleteIconButton(action: ...)`: Иконка корзины, становится красной при наведении.
- `DownloadIconButton(action: ...)`: Иконка облачной загрузки.
- `CancelIconButton(action: ...)`: Маленький крестик (xmark).

---

## Навигация

### Навигация Боковой Панели
Боковая панель настроек — это кастомная реализация для поддержки анимации "Только Иконка" $\leftrightarrow$ "Иконка + Текст".

**Добавление Нового Пункта Меню:**
1.  Откройте `Sources/Features/SettingsView.swift` (или `Sources/Features/Settings/Models/SettingsSelection.swift`, если вынесено).
2.  Добавьте кейс в перечисление `SettingsSelection`.
3.  Определите его свойства `title` и `icon`.
4.  Добавьте кейс view в `switch` statement в `SettingsView`.

---

## Стилизация Окон
Приложение использует скрытый заголовок окна и прозрачный фон окна для корректной работы эффектов `Material`.

**WindowAccessor**: `Sources/Core/Utilities/WindowAccessor.swift`

**Стандартная Конфигурация:**
```swift
.background(WindowAccessor { window in
    window.isOpaque = false
    window.backgroundColor = .clear
    window.titleVisibility = .hidden
    // ...
})
```
