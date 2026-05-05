//
//  MainWindowView.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    private let borderWidth: CGFloat = 1
    private let chromeResizeAnimation: Animation = .easeInOut(duration: 0.18)

    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var layoutService = DockLayoutService.shared

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        let cornerRadius = effectiveCornerRadius
        let chromeFrameSize = resolvedChromeFrameSize
        let dockEdge = dockEdgeAlignment

        ZStack(alignment: dockEdge) {
            chromeBackground(cornerRadius: cornerRadius)
                .frame(width: chromeFrameSize?.width, height: chromeFrameSize?.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dockEdge)
                .allowsHitTesting(true)
                .animation(chromeResizeAnimation, value: chromeFrameSize)

            TileContainerView()
        }
        .compositingGroup()
    }

    private var dockEdgeAlignment: Alignment {
        switch preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation) {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    @ViewBuilder
    private func chromeBackground(cornerRadius: CGFloat) -> some View {
        backgroundFill(cornerRadius: cornerRadius)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if !preferences.disablesGlassLook {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .inset(by: borderWidth / 2)
                        .strokeBorder(borderGradient, lineWidth: borderWidth)
                }
            }
    }

    @ViewBuilder
    private func backgroundFill(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .overlay {
                if let backgroundImage = resolvedBackgroundImage {
                    Image(nsImage: backgroundImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(nsColor: preferences.effectiveWindowTintColor)
                        .opacity(preferences.effectiveWindowTintOpacity)
                }
            }
            .clipped()
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.35),
                Color.white.opacity(0.12),
                Color.white.opacity(0.05),
                Color.white.opacity(0.12),
                Color.white.opacity(0.28),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var effectiveCornerRadius: CGFloat {
        preferences.windowClipShape.resolvedCornerRadius(
            base: preferences.windowCornerRadius,
            maximum: maximumCornerRadius
        )
    }

    private var maximumCornerRadius: CGFloat {
        let iconHeight = layoutService.scaled(dockSettings.displayTileSize)
        return (iconHeight + layoutService.scaled(preferences.tileVerticalPadding) * 2) / 2
    }

    private var resolvedChromeFrameSize: CGSize? {
        let chromeSize = layoutService.chromeSize
        guard chromeSize.width > 0, chromeSize.height > 0 else {
            return nil
        }

        return chromeSize
    }

    private var resolvedBackgroundImage: NSImage? {
        guard let backgroundImageURL = preferences.effectiveWindowBackgroundImageURL else {
            return nil
        }

        return NSImage(contentsOf: backgroundImageURL)
    }
}

final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    private var hiddenDragImageOriginals: [(NSDraggingItem, (() -> [NSDraggingImageComponent])?)] = []

    @MainActor required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL, .string])
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        registerForDraggedTypes([.fileURL, .string])
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        let urls = readURLs(from: sender)
        let pasteboardTypes = sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        if let kind = DockDragService.resolvePreview(from: urls) {
            NSLog(
                "[Docky] drag entered: kind=%@ urls=%@ pasteboardTypes=%@",
                Self.describe(kind: kind),
                urls.map(\.path).joined(separator: ", "),
                pasteboardTypes.joined(separator: ", ")
            )
            DockDragService.shared.begin(kind: kind, at: location)
            updateSystemDragImageVisibility(in: sender)
            return .copy
        }
        if DockEditModeService.shared.paletteDrag != nil {
            NSLog(
                "[Docky] drag entered: kind=palette urls=%@ pasteboardTypes=%@",
                urls.map(\.path).joined(separator: ", "),
                pasteboardTypes.joined(separator: ", ")
            )
            DockDragService.shared.cursorLocation = location
            updateSystemDragImageVisibility(in: sender)
            return .copy
        }
        NSLog(
            "[Docky] drag entered: kind=rejected urls=%@ pasteboardTypes=%@",
            urls.map(\.path).joined(separator: ", "),
            pasteboardTypes.joined(separator: ", ")
        )
        return []
    }

    /// One-line description of a `DockDragService.Kind` for logging.
    private static func describe(kind: DockDragService.Kind) -> String {
        switch kind {
        case .app(let url, let tile):
            return "app(bundle=\(tile.bundleIdentifier), path=\(url.path))"
        case .folder(let url, _):
            return "folder(path=\(url.path))"
        case .document(let urls):
            return "document(paths=[\(urls.map(\.path).joined(separator: ", "))])"
        }
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        if DockDragService.shared.kind != nil {
            DockDragService.shared.updateCursor(location)
            updateSystemDragImageVisibility(in: sender)
            return .copy
        }
        if DockEditModeService.shared.paletteDrag != nil {
            DockDragService.shared.cursorLocation = location
            updateSystemDragImageVisibility(in: sender)
            return .copy
        }
        return []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        // Cursor left the dock window, but the drag may still be live — the
        // user might be moving into a spring-loaded popover. Drop the
        // location-derived state so previews disappear, but keep `kind`
        // alive so popover-side drop handlers can resolve the source. The
        // drag service is fully cleared in `draggingEnded(_:)` once AppKit
        // tells us the drag is truly over.
        DockDragService.shared.cursorLocation = nil
        DockDragService.shared.destinationIndex = nil
        DockDragService.shared.destinationSection = nil
        DockDragService.shared.documentTargetTileID = nil
        // Keep paletteDrag alive so re-entry works — the SwiftUI .onDrag-initiated
        // drag is still in flight outside the window, and the palette item can't be
        // recovered from the pasteboard (which only carries the variant ID).
        DockEditModeService.shared.paletteDropDestination = nil
        restoreSystemDragImage()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        DockDragService.shared.clear()
    }

    /// Hide the system drag preview when our own insertion preview is active, so the
    /// user sees one drop indication instead of two competing ones. Restore originals
    /// when the active region is exited so the preview returns outside the dock.
    /// Drag-onto-tile (open-with) intentionally keeps the system preview because
    /// there's no insertion indicator competing for attention.
    private func updateSystemDragImageVisibility(in sender: any NSDraggingInfo) {
        let shouldHide =
            DockDragService.shared.destinationIndex != nil
            || DockEditModeService.shared.paletteDropDestination != nil
        if shouldHide {
            guard hiddenDragImageOriginals.isEmpty else { return }
            sender.enumerateDraggingItems(
                options: [],
                for: self,
                classes: [NSPasteboardItem.self],
                searchOptions: [:]
            ) { item, _, _ in
                self.hiddenDragImageOriginals.append((item, item.imageComponentsProvider))
                item.imageComponentsProvider = { [] }
            }
        } else {
            restoreSystemDragImage()
        }
    }

    private func restoreSystemDragImage() {
        for (item, originalProvider) in hiddenDragImageOriginals {
            item.imageComponentsProvider = originalProvider
        }
        hiddenDragImageOriginals.removeAll()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { restoreSystemDragImage() }
        if let kind = DockDragService.shared.kind {
            let destinationIndex = DockDragService.shared.destinationIndex
            let targetTileID = DockDragService.shared.documentTargetTileID
            NSLog(
                "[Docky] drag drop: kind=%@ destinationIndex=%@ documentTargetTileID=%@",
                Self.describe(kind: kind),
                destinationIndex.map(String.init) ?? "nil",
                targetTileID ?? "nil"
            )
            defer { DockDragService.shared.clear() }
            switch kind {
            case .app(_, let tile):
                guard let index = destinationIndex else { return false }
                return TileStore.shared.pinApp(bundleIdentifier: tile.bundleIdentifier, at: index)
            case .folder(let url, let tile):
                if let targetTileID,
                   let bundleIdentifier = TileStore.shared.tiles
                    .first(where: { $0.id == targetTileID })
                    .flatMap({ tile -> String? in
                        if case .app(let app) = tile.content { return app.bundleIdentifier }
                        return nil
                    }) {
                    WorkspaceService.shared.open(fileURLs: [url], withApplicationBundleIdentifier: bundleIdentifier)
                    return true
                }
                guard let index = destinationIndex else { return false }
                TileStore.shared.insertTrailingItem(
                    .folder(url: url, displayName: tile.displayName),
                    at: index
                )
                return true
            case .document(let urls):
                guard let targetTileID,
                      let bundleIdentifier = TileStore.shared.tiles
                        .first(where: { $0.id == targetTileID })
                        .flatMap({ tile -> String? in
                            if case .app(let app) = tile.content { return app.bundleIdentifier }
                            return nil
                        }) else {
                    return false
                }
                WorkspaceService.shared.open(fileURLs: urls, withApplicationBundleIdentifier: bundleIdentifier)
                return true
            }
        }
        if let paletteDrag = DockEditModeService.shared.paletteDrag,
           let destination = DockEditModeService.shared.paletteDropDestination {
            defer {
                DockEditModeService.shared.endPaletteDrag()
                DockDragService.shared.cursorLocation = nil
            }
            switch destination.section {
            case .pinned:
                guard let item = TileContainerView.makePinnedItem(from: paletteDrag) else { return false }
                TileStore.shared.insertPinnedItem(item, at: destination.index)
                return true
            case .trailing:
                guard let item = TileContainerView.makeTrailingItem(from: paletteDrag) else { return false }
                TileStore.shared.insertTrailingItem(item, at: destination.index)
                return true
            }
        }
        return false
    }

    private func readURLs(from sender: any NSDraggingInfo) -> [URL] {
        let pasteboard = sender.draggingPasteboard
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
    }
}
