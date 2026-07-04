# External Widget Bundles

Docky loads community-supplied widgets from native macOS bundles dropped into a known directory. This document describes the contract a bundle must satisfy and the constraints on building one.

## Install location

```
~/Library/Application Support/Docky/Widgets/
```

The directory is created on first launch. Drop a `*.dockywidget` bundle into it and restart Docky. Discovery happens once at `applicationDidFinishLaunching`, before persisted dock contents are rehydrated, so external widgets can be referenced by existing layouts without losing their slot.

## Bundle layout

`*.dockywidget` is a regular macOS bundle. Minimum layout:

```
MyWidget.dockywidget/
  Contents/
    Info.plist        # NSPrincipalClass = "<module>.<class>"
    MacOS/MyWidget    # compiled binary
```

In `Info.plist`, set `NSPrincipalClass` to the fully-qualified Swift name of the class that implements `DockyWidgetPlugin`, e.g. `MyWidget.MyWidget`.

## The DockyWidgetPlugin contract

The principal class must inherit from `NSObject` and conform to `DockyWidgetPlugin`. The protocol is `@objc` so plugins do not need to link against Docky's Swift module — they only need a copy of the protocol declaration in their own sources.

The `@objc(DockyWidgetPlugin)` attribute is required, not optional. Without the explicit name, Swift module-qualifies the Obj-C protocol name (`<Module>.DockyWidgetPlugin`) and Docky's runtime check fails to reconcile it with its own copy.

```swift
import AppKit
import SwiftUI

@objc(DockyWidgetPlugin) public protocol DockyWidgetPlugin: AnyObject {
    @objc init()

    var identifier: String { get }              // e.g. "com.example.MyWidget"
    var displayName: String { get }
    var systemImageName: String { get }         // SF Symbol shown in the dock editor

    var defaultSpanValue: Int { get }           // 1...4 tiles
    var supportedSpanValues: [Int] { get }
    var expansionWidthTiles: Int { get }
    var expansionHeightTiles: Int { get }
    var isExpandable: Bool { get }
    var includesInPalette: Bool { get }
    var includesInSmartStack: Bool { get }

    @objc optional var author: String { get }   // shown in Widget Store, defaults to "Unknown"
    @objc optional var version: String { get }  // shown in Widget Store, defaults to "1.0"
    @objc optional func makeSettingsView() -> NSView

    func makeView(
        cornerRadius: CGFloat,
        renderedSpanValue: Int,
        isWithinStack: Bool,
        isExpanded: Bool,
        isExpandedPreviewOpen: Bool
    ) -> NSView
}
```

`makeView` typically returns `NSHostingView(rootView: ...)` wrapping a SwiftUI view, but any `NSView` works.

### Optional per-widget settings UI

If your widget needs its own controls, implement `makeSettingsView()`. Docky surfaces a gear button for installed widgets that provide it and opens the returned `NSView` in a dedicated settings window.

- Return a fresh view each time `makeSettingsView()` is called. Docky may reopen the window after a previous one was closed, and reusing the same `NSView` instance can run into AppKit reparenting issues.
- Persist plugin-specific settings inside the widget bundle itself (for example with `UserDefaults`). Docky does not serialize or validate custom widget settings.
- Keep the view compact and self-contained; Docky sizes the window from the view's fitting size and allows the user to resize it afterward.

A minimal plugin:

```swift
import AppKit
import SwiftUI

@objc(MyWidget)
public final class MyWidget: NSObject, DockyWidgetPlugin {
    public override init() { super.init() }

    public var identifier: String { "com.example.MyWidget" }
    public var displayName: String { "My Widget" }
    public var systemImageName: String { "sparkles" }

    public var defaultSpanValue: Int { 3 }
    public var supportedSpanValues: [Int] { [1, 2, 3] }
    public var expansionWidthTiles: Int { 3 }
    public var expansionHeightTiles: Int { 3 }
    public var isExpandable: Bool { true }
    public var includesInPalette: Bool { true }
    public var includesInSmartStack: Bool { false }

    public func makeSettingsView() -> NSView {
        NSHostingView(rootView: Text("Settings go here").padding())
    }

    public func makeView(
        cornerRadius: CGFloat,
        renderedSpanValue: Int,
        isWithinStack: Bool,
        isExpanded: Bool,
        isExpandedPreviewOpen: Bool
    ) -> NSView {
        NSHostingView(rootView: Text("Hello from my widget"))
    }
}
```

This repo includes a worked example under `ExternalWidgets/IndividualSettingsWidget/`, plus `scripts/build_individual_settings_widget.sh` to compile it into a real `.dockywidget` bundle for local testing.

## Build settings

- **Bundle type:** `loadable bundle` (Xcode template "Bundle"), not framework.
- **Wrapper extension:** `dockywidget`.
- **Deployment target:** macOS 14.0 or later (Docky's minimum).
- **Swift version:** must match the compiler Docky was built with. Mixing toolchains breaks Swift class metadata; the loader will fail on principal-class lookup or protocol conformance.
- **Code signing:** sign with a Developer ID certificate. Docky ships the `com.apple.security.cs.disable-library-validation` entitlement, so bundles signed by other teams load successfully under hardened runtime. Unsigned bundles still fail because macOS itself rejects them.

## Identifiers and persistence

Each widget is persisted in Docky's preferences as `external:<identifier>`. Keep `identifier` stable across releases of your widget; changing it forfeits the user's pin in the dock layout. Use reverse-DNS for namespacing (`com.your-org.WidgetName`).

If a bundle is removed, any persisted dock placement referring to it shows a small "Missing widget" placeholder until the user removes it manually.

## Failure modes the loader logs (not crashes)

- Bundle can't be opened (`Bundle(url:)` returns nil).
- `bundle.load()` returns false (code signing / library validation rejected).
- `NSPrincipalClass` missing in `Info.plist`.
- Principal class does not conform to `DockyWidgetPlugin`.

Filter Console.app on subsystem `gt.quintero.Docky` and category `ExternalWidgetLoader` to see what happened.
