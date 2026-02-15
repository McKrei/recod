# Design System & Style Guide

## Core Philosophy
Recod follows the "Tahoe" design aesthetic: deep translucency, glass materials, and floating interfaces that blend with the user's wallpaper. The UI relies heavily on `Material` (visual effects) rather than solid colors.

## Central Source of Truth: `AppTheme`
All styling constants are centrally located in `Sources/DesignSystem/AppTheme.swift`.
**Never hardcode values.** Always refer to `AppTheme`.

```swift
// Example Usage
.padding(AppTheme.padding)
.background(AppTheme.glassMaterial)
.clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
```

### Key Constants
- **Padding**: `AppTheme.padding` (Standard 16pt)
- **Page Padding**: `AppTheme.pagePadding` (30pt) for main content areas
- **Corner Radius**: `AppTheme.cornerRadius` (Standard 16pt)
- **Glass Material**: `AppTheme.glassMaterial` (Use for all container backgrounds)
- **Shadows**: Use `AppTheme.shadowColor`, `radius`, and `y` for consistent depth.

---

## Components

### 1. Settings Header
Standardized header for all settings pages. Includes title, subtitle, icon, and optional action button.
**File**: `Sources/DesignSystem/SettingsHeaderView.swift`

Usage:
```swift
SettingsHeaderView(
    title: "Page Title",
    subtitle: "Description",
    systemImage: "gear"
) {
    // Optional Action Button
    Button("Add") {}
}
```

### 2. Glass Row Style (Lists)
Used for items in lists like History, Models, Files.
**File**: `Sources/DesignSystem/GlassRowStyle.swift`

Usage:
```swift
HStack {
    // Content
}
.glassRowStyle(isSelected: Bool, isHovering: Bool)
.onHover { isHovering = $0 }
```

### 3. Glass Group Box
Used for grouping settings or content sections.
**File**: `Sources/DesignSystem/GlassGroupBoxStyle.swift`

Usage:
```swift
GroupBox {
    // Content
}
.groupBoxStyle(GlassGroupBoxStyle())
```

### 4. Standard Action Buttons
Consistent iconography and hover states for common actions.
**File**: `Sources/DesignSystem/StandardButtons.swift`

- `DeleteIconButton(action: ...)`: Trash icon, turns red on hover.
- `DownloadIconButton(action: ...)`: Cloud download icon.
- `CancelIconButton(action: ...)`: Small xmark.

---

## Navigation

### Sidebar Navigation
The settings sidebar is a custom implementation to support the "Icon Only" $\leftrightarrow$ "Icon + Text" animation.

**Adding a New Menu Item:**
1.  Open `Sources/Features/SettingsView.swift`.
2.  Add a case to the `SettingsSelection` enum.
3.  Define its `title` and `icon` properties.
4.  Add the view case to the `body` switch statement in `SettingsView`.

---

## Window Styling
The application uses a hidden title bar and a transparent window background to allow the `Material` effects to work correctly.

**WindowAccessor**: `Sources/Core/Utilities/WindowAccessor.swift`

**Standard Configuration:**
```swift
.background(WindowAccessor { window in
    window.isOpaque = false
    window.backgroundColor = .clear
    window.titleVisibility = .hidden
    // ...
})
```
