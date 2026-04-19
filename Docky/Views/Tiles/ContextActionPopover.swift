//
//  ContextActionPopover.swift
//  Docky
//

import AppKit
import SwiftUI

struct ContextAction: Identifiable {
    enum Kind: Equatable {
        case action
        case submenu
        case divider
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let isDestructive: Bool
    let isOn: Bool
    let children: [ContextAction]
    let handler: () -> Void

    static func action(
        _ title: String,
        isDestructive: Bool = false,
        isOn: Bool = false,
        handler: @escaping () -> Void
    ) -> Self {
        Self(
            kind: .action,
            title: title,
            isDestructive: isDestructive,
            isOn: isOn,
            children: [],
            handler: handler
        )
    }

    static func submenu(_ title: String, children: [ContextAction]) -> Self {
        Self(
            kind: .submenu,
            title: title,
            isDestructive: false,
            isOn: false,
            children: children,
            handler: {}
        )
    }

    static var divider: Self {
        Self(kind: .divider, title: "", isDestructive: false, isOn: false, children: [], handler: {})
    }
}

struct ContextActionMenuPresenter: NSViewRepresentable {
    let actionProvider: (NSEvent.ModifierFlags) -> [ContextAction]
    let onPresentationChanged: (Bool) -> Void

    init(
        actionProvider: @escaping (NSEvent.ModifierFlags) -> [ContextAction],
        onPresentationChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.actionProvider = actionProvider
        self.onPresentationChanged = onPresentationChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            actionProvider: actionProvider,
            onPresentationChanged: onPresentationChanged
        )
    }

    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        context.coordinator.update(
            actionProvider: actionProvider,
            onPresentationChanged: onPresentationChanged
        )
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(for: nsView)
        }
    }

    static func dismantleNSView(_ nsView: AnchorView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject {
        private weak var anchorView: NSView?
        private var eventMonitor: Any?
        private var actionProvider: (NSEvent.ModifierFlags) -> [ContextAction]
        private var onPresentationChanged: (Bool) -> Void

        init(
            actionProvider: @escaping (NSEvent.ModifierFlags) -> [ContextAction],
            onPresentationChanged: @escaping (Bool) -> Void
        ) {
            self.actionProvider = actionProvider
            self.onPresentationChanged = onPresentationChanged
            super.init()
        }

        func update(
            actionProvider: @escaping (NSEvent.ModifierFlags) -> [ContextAction],
            onPresentationChanged: @escaping (Bool) -> Void
        ) {
            self.actionProvider = actionProvider
            self.onPresentationChanged = onPresentationChanged
        }

        func installIfNeeded(for anchorView: NSView) {
            self.anchorView = anchorView

            guard !actionProvider([]).isEmpty else {
                uninstall()
                return
            }

            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                self?.handleContextClick(event) ?? event
            }
        }

        func uninstall() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }

            eventMonitor = nil
            anchorView = nil
        }

        private func handleContextClick(_ event: NSEvent) -> NSEvent? {
            guard let view = anchorView, let window = view.window, event.window === window else {
                return event
            }

            let isRightClick = event.type == .rightMouseDown
            let isControlClick = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
            guard isRightClick || isControlClick else {
                return event
            }

            let location = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(location) else {
                return event
            }

            let actions = actionProvider(event.modifierFlags)
            guard !actions.isEmpty else {
                return event
            }

            let menu = buildMenu(actions: actions)
            popUpCartouche(menu: menu, in: view)
            return nil
        }

        private func popUpCartouche(menu: NSMenu, in view: NSView) {
            onPresentationChanged(true)
            defer { onPresentationChanged(false) }

            let selector = NSSelectorFromString("_popUpMenuRelativeToRect:inView:preferredEdge:")
            if menu.responds(to: selector) {
                typealias Fn = @convention(c) (NSMenu, Selector, NSRect, NSView?, NSRectEdge) -> Void
                let imp = menu.method(for: selector)
                let fn = unsafeBitCast(imp, to: Fn.self)
                fn(menu, selector, view.bounds, view, .maxY)
                return
            }

            menu.update()
            let anchor = NSPoint(
                x: view.bounds.midX - menu.size.width / 2,
                y: view.bounds.maxY
            )
            menu.popUp(positioning: menu.items.last, at: anchor, in: view)
        }

        private func buildMenu(actions: [ContextAction]) -> NSMenu {
            let menu = NSMenu()
            for action in actions {
                switch action.kind {
                case .action:
                    let item = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = action
                    item.state = action.isOn ? .on : .off
                    if action.isDestructive {
                        item.attributedTitle = NSAttributedString(
                            string: action.title,
                            attributes: [.foregroundColor: NSColor.systemRed]
                        )
                    }
                    menu.addItem(item)
                case .submenu:
                    let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
                    item.submenu = buildMenu(actions: action.children)
                    menu.addItem(item)
                case .divider:
                    menu.addItem(.separator())
                }
            }
            return menu
        }

        @objc private func runAction(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ContextAction else { return }
            action.handler()
        }
    }
}

final class AnchorView: NSView {}
