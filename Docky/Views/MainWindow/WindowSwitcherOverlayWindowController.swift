//
//  WindowSwitcherOverlayWindowController.swift
//  Docky
//

import AppKit
import Combine
import SwiftUI

final class WindowSwitcherOverlayWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow

        let overlayWindow = WindowSwitcherOverlayWindow()
        let hostingController = NSHostingController(rootView: WindowSwitcherOverlayView())
        overlayWindow.contentViewController = hostingController

        super.init(window: overlayWindow)

        observeOverlayPresentation()
        observeMainWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func observeOverlayPresentation() {
        WindowSwitcherService.shared.$isPresented
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPresented in
                guard let self else { return }
                if isPresented {
                    self.presentOverlay()
                } else {
                    self.dismissOverlay()
                }
            }
            .store(in: &cancellables)
    }

    private func observeMainWindow() {
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: mainWindow)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: mainWindow))
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification, object: mainWindow))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFrame()
            }
            .store(in: &cancellables)
    }

    private func presentOverlay() {
        guard let window else { return }

        updateFrame()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissOverlay() {
        window?.orderOut(nil)
    }

    private func updateFrame() {
        guard let window else { return }
        let screenFrame = mainWindow?.screen?.frame ?? NSScreen.main?.frame ?? .zero
        guard !screenFrame.isEmpty else { return }
        window.setFrame(screenFrame, display: true)
    }
}

private final class WindowSwitcherOverlayWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct WindowSwitcherOverlayView: View {
    @ObservedObject private var switcher = WindowSwitcherService.shared
    @ObservedObject private var preferences = DockyPreferences.shared

    private let innerPreviewCornerRadius: CGFloat = 16
    private let cardPadding: CGFloat = 12
    private let containerPadding: CGFloat = 18

    private var cardCornerRadius: CGFloat {
        innerPreviewCornerRadius + cardPadding
    }

    private var containerCornerRadius: CGFloat {
        cardCornerRadius + containerPadding
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0)
                    .ignoresSafeArea()

                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(switcher.windows) { window in
                                WindowSwitcherCard(
                                    window: window,
                                    isSelected: window.windowIdentifier == switcher.selectedWindowIdentifier,
                                    innerPreviewCornerRadius: innerPreviewCornerRadius,
                                    cardCornerRadius: cardCornerRadius
                                )
                                .id(window.windowIdentifier)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 28)
                    }
                    .frame(maxWidth: proxy.size.width - 80)
                    .fixedSize(horizontal: true, vertical: true)
                    .glassEffect(.regular, in: .rect(cornerRadius: containerCornerRadius, style: .continuous))
                    .onChange(of: switcher.selectedWindowIdentifier) { _, selection in
                        guard let selection else { return }
                        withAnimation(.easeInOut(duration: 0.14)) {
                            scrollProxy.scrollTo(selection, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

private struct WindowSwitcherCard: View {
    let window: AppWindow
    let isSelected: Bool
    let innerPreviewCornerRadius: CGFloat
    let cardCornerRadius: CGFloat
    @ObservedObject private var switcher = WindowSwitcherService.shared
    @ObservedObject private var workspace = WorkspaceService.shared

    private let previewWidth: CGFloat = 180
    private let previewHeight: CGFloat = 102

    var body: some View {
        VStack(spacing: 12) {
            previewSurface

            VStack(spacing: 4) {
                Text(window.windowTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(isSelected ? 1 : 0.25)

                Text(window.appDisplayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(isSelected ? 1 : 0.12)
            }
            .frame(width: 180)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(isSelected ? .white.opacity(0.14) : .white.opacity(0.0))
                .overlay {
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .strokeBorder(isSelected ? .white.opacity(0.28) : .white.opacity(0.0), lineWidth: 1)
                }
        }
        .background {
            ContextActionMenuPresenter(
                actionProvider: contextActions(modifierFlags:),
                onPresentationChanged: switcher.setContextMenuPresented
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .onHover { isHovering in
            guard isHovering else { return }
            switcher.selectWindow(withIdentifier: window.windowIdentifier)
        }
        .animation(.easeInOut(duration: 0.14), value: isSelected)
    }

    private var previewSurface: some View {
        Group {
            if let preview = workspace.appWindowPreview(for: window) {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: previewHeight)
            } else {
                Color.black.opacity(0.01)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: previewHeight)
            }
        }
        .frame(height: previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: innerPreviewCornerRadius/4, style: .continuous))
    }

    private func contextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {
        return [
            .action("Focus Window") {
                switcher.dismiss()
                _ = workspace.focus(window: window)
            },
            .action("Minimize Window") {
                switcher.dismiss()
                _ = workspace.minimize(window: window)
            },
            .action("Close Window", isDestructive: true) {
                if workspace.close(window: window) {
                    switcher.removeWindow(withIdentifier: window.windowIdentifier)
                }
            },
            .divider,
            .action("Focus App") {
                switcher.dismiss()
                workspace.focusApplication(bundleIdentifier: window.bundleIdentifier)
            },
            .action("Hide App") {
                switcher.dismiss()
                workspace.hide(bundleIdentifier: window.bundleIdentifier)
            },
            .action("Quit") {
                switcher.dismiss()
                workspace.quit(bundleIdentifier: window.bundleIdentifier)
            }
        ]
    }
}
