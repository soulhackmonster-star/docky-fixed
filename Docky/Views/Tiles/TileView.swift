//
//  TileView.swift
//  Docky
//
//  Generic tile wrapper. Picks a concrete content view based on the tile's
//  case and applies any chrome shared across all tile types (hover, etc).
//

import AppKit
import SwiftUI

struct TileView: View {
    let tile: Tile
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var workspace = WorkspaceService.shared
    @State private var isHovering = false
    @State private var isTooltipPresented = false
    @State private var isFolderPopoverPresented = false
    @State private var isContextMenuPresented = false
    @State private var folderSnapshot: FolderContentsSnapshot = .loaded([])

    private static let finderBundleIdentifier = "com.apple.finder"

    private func contextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {
        if let catalogActions = MenuCatalogService.shared.contextActions(for: tile, modifierFlags: modifierFlags) {
            switch tile.content {
            case .app, .folder, .trash:
                return catalogActions
            case .widget, .spacer, .divider:
                break
            }
        }

        switch tile.content {
        case .app(let app):
            return appContextActions(for: app, modifierFlags: modifierFlags)
        case .folder(let folder):
            return [
                .action("Open in Finder") {
                    Task {
                        _ = await AppleScriptService.shared.openFinderWindow(for: folder.url)
                    }
                },
                .action("Reveal in Finder") {
                    Task {
                        _ = await AppleScriptService.shared.revealInFinder(folder.url)
                    }
                }
            ]
        case .trash:
            return [
                .action("Open Trash") {
                    Task {
                        _ = await AppleScriptService.shared.openTrash()
                    }
                },
                .divider,
                .action("Empty Trash", isDestructive: true) {
                    Task {
                        _ = await AppleScriptService.shared.emptyTrash()
                    }
                }
            ]
        case .widget, .spacer, .divider:
            return []
        }
    }

    var body: some View {
        content
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .overlay(alignment: .bottom) {
                runningIndicator
                    .padding(.bottom, 2)
            }
            .contentShape(Rectangle())
            .onHover(perform: updateHoverState)
            .onTapGesture(perform: handleTap)
            .onDisappear {
                isHovering = false
                isTooltipPresented = false
                isFolderPopoverPresented = false
                isContextMenuPresented = false
            }
            .background {
                ContextActionMenuPresenter(
                    actionProvider: contextActions(modifierFlags:),
                    onPresentationChanged: updateContextMenuPresentation
                )

                if let tooltipTitle {
                    TileTooltipPopoverPresenter(
                        title: tooltipTitle,
                        isPresented: isTooltipPresented
                    )
                    .allowsHitTesting(false)
                }
            }
            .popover(
                isPresented: $isFolderPopoverPresented,
                attachmentAnchor: .point(.top),
                arrowEdge: .bottom
            ) {
                if case .folder(let folder) = tile.content {
                    FolderPopoverView(
                        tile: folder,
                        initialSnapshot: folderSnapshot,
                        isPresented: $isFolderPopoverPresented
                    )
                }
            }
    }

    @ViewBuilder
    private var runningIndicator: some View {
        if case .app(let app) = tile.content,
           workspace.isRunning(bundleIdentifier: app.bundleIdentifier) {
            Circle()
                .frame(width: 4, height: 4)
                .foregroundStyle(.primary.opacity(0.9))
        }
    }

    private var verticalPadding: CGFloat {
        switch tile.content {
        case .divider:
            0
        default:
            preferences.tileVerticalPadding
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tile.content {
        case .app(let app):
            AppTileView(tile: app)
        case .widget(let widget):
            WidgetTileView(tile: widget)
        case .folder(let folder):
            FolderTileView(tile: folder, isOpen: isFolderPopoverPresented)
        case .spacer:
            SpacerTileView()
        case .divider:
            DividerTileView()
        case .trash:
            TrashTileView()
        }
    }

    private var tooltipTitle: String? {
        switch tile.content {
        case .app(let app):
            app.displayName
        case .widget(let widget):
            widget.title
        case .folder(let folder):
            folder.displayName
        case .trash:
            "Trash"
        case .spacer, .divider:
            nil
        }
    }

    private func updateHoverState(isHovering: Bool) {
        self.isHovering = isHovering
        updateTooltipPresentation()
    }

    private func updateContextMenuPresentation(isPresented: Bool) {
        isContextMenuPresented = isPresented
        updateTooltipPresentation()
    }

    private func updateTooltipPresentation() {
        isTooltipPresented = isHovering
            && tooltipTitle != nil
            && !isFolderPopoverPresented
            && !isContextMenuPresented
    }

    private func handleTap() {
        switch tile.content {
        case .app(let app):
            isTooltipPresented = false
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        case .folder(let folder):
            isTooltipPresented = false

            if isFolderPopoverPresented {
                isFolderPopoverPresented = false
                return
            }

            folderSnapshot = FolderAccessService.shared.snapshot(of: folder.url)
            isFolderPopoverPresented = true
        case .trash:
            isTooltipPresented = false
            Task {
                _ = await AppleScriptService.shared.openTrash()
            }
        case .widget, .spacer, .divider:
            return
        }
    }

    private func appContextActions(
        for app: AppTile,
        modifierFlags: NSEvent.ModifierFlags
    ) -> [ContextAction] {
        guard !app.bundleIdentifier.isEmpty else {
            return []
        }

        let workspace = WorkspaceService.shared
        let isRunning = workspace.isRunning(bundleIdentifier: app.bundleIdentifier)
        let isPinned = tile.id.hasPrefix("pinned:")
        let canTogglePinned = app.bundleIdentifier != Self.finderBundleIdentifier
        let useForceQuit = modifierFlags.contains(.option)
        var actions: [ContextAction] = [
            .action("Open") {
                workspace.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
            }
        ]

        if isRunning {
            actions.append(.action("Show All Windows") {
                workspace.showAllWindows(bundleIdentifier: app.bundleIdentifier)
            })
        }

        actions.append(.divider)
        actions.append(.submenu("Options", children: appOptionsActions(for: app, isPinned: isPinned, canTogglePinned: canTogglePinned)))

        if isRunning && app.bundleIdentifier != Self.finderBundleIdentifier {
            actions.append(.divider)
            actions.append(.action("Hide") {
                workspace.hide(bundleIdentifier: app.bundleIdentifier)
            })
            actions.append(.action(
                useForceQuit ? "Force Quit" : "Quit",
                isDestructive: useForceQuit
            ) {
                workspace.quit(bundleIdentifier: app.bundleIdentifier, force: useForceQuit)
            })
        }

        return actions
    }

    private func appOptionsActions(
        for app: AppTile,
        isPinned: Bool,
        canTogglePinned: Bool
    ) -> [ContextAction] {
        var actions: [ContextAction] = []

        if canTogglePinned {
            actions.append(.action("Keep in Dock", isOn: isPinned) {
                _ = DockEditorService.shared.setPinnedApp(
                    bundleIdentifier: app.bundleIdentifier,
                    pinned: !isPinned
                )
            })
        }

        actions.append(.action("Show in Finder") {
            WorkspaceService.shared.revealApplicationInFinder(bundleIdentifier: app.bundleIdentifier)
        })

        return actions
    }

}

private struct TileTooltipView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .fixedSize()
    }
}

private struct TileTooltipPopoverPresenter: NSViewRepresentable {
    let title: String
    let isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title)
    }

    func makeNSView(context: Context) -> TooltipAnchorView {
        TooltipAnchorView()
    }

    func updateNSView(_ nsView: TooltipAnchorView, context: Context) {
        context.coordinator.update(title: title)

        if isPresented {
            context.coordinator.show(relativeTo: nsView)
        } else {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ nsView: TooltipAnchorView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator {
        private let hostingController = NSHostingController(rootView: TileTooltipView(title: ""))
        private let popover = NSPopover()

        init(title: String) {
            hostingController.rootView = TileTooltipView(title: title)
            popover.contentViewController = hostingController
            popover.animates = false
            popover.behavior = .applicationDefined
            updateContentSize()
        }

        func update(title: String) {
            hostingController.rootView = TileTooltipView(title: title)
            updateContentSize()
        }

        func show(relativeTo view: NSView) {
            guard view.window != nil, !popover.isShown else { return }
            let anchorRect = NSRect(
                x: view.bounds.midX - 0.5,
                y: view.bounds.maxY - 1,
                width: 1,
                height: 1
            )
            popover.show(relativeTo: anchorRect, of: view, preferredEdge: .maxY)
        }

        func close() {
            popover.performClose(nil)
        }

        private func updateContentSize() {
            let view = hostingController.view
            view.layoutSubtreeIfNeeded()
            let size = view.fittingSize
            hostingController.preferredContentSize = size
            popover.contentSize = size
        }
    }
}

private final class TooltipAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
