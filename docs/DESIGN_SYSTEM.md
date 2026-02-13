# Design System & Style Guide

## Core Philosophy
MacAudio2 follows the "Tahoe" design aesthetic: deep translucency, glass materials, and floating interfaces that blend with the user's wallpaper. The UI relies heavily on `Material` (visual effects) rather than solid colors.

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
- **Corner Radius**: `AppTheme.cornerRadius` (Standard 16pt)
- **Glass Material**: `AppTheme.glassMaterial` (Use for all container backgrounds)
- **Shadows**: Use `AppTheme.shadowColor`, `radius`, and `y` for consistent depth.

---

## Components

### 1. Glass Group Box
Used for grouping settings or content sections.
**File**: `Sources/DesignSystem/GlassGroupBoxStyle.swift`

Usage:
```swift
GroupBox {
    // Content
}
.groupBoxStyle(GlassGroupBoxStyle())
```

### 2. Sidebar Navigation
The settings sidebar is a custom implementation (not `NavigationSplitView`) to support the "Icon Only" $\leftrightarrow$ "Icon + Text" animation.

**Adding a New Menu Item:**
1.  Open `Sources/Features/SettingsView.swift`.
2.  Add a case to the `SettingsSelection` enum.
3.  Define its `title` and `icon` properties.
4.  Add the view case to the `body` switch statement in `SettingsView`.

```swift
enum SettingsSelection {
    case general, history, newFeature // 1. Add case

    var title: String {
        switch self {
            // ...
            case .newFeature: return "New Feature" // 2. Add title
        }
    }
}

// In SettingsView body:
case .newFeature:
    NewFeatureView() // 3. Connect View
```

---

## Window Styling
The application uses a hidden title bar and a transparent window background to allow the `Material` effects to work correctly.

**WindowAccessor**:
Located in `Sources/Core/Utilities/WindowAccessor.swift`. This helper allows SwiftUI views to access the underlying `NSWindow`.

**Standard Configuration:**
```swift
.background(WindowAccessor { window in
    window.isOpaque = false
    window.backgroundColor = .clear
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
})
```
