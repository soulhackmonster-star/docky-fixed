//
//  PermissionsWindowController.swift
//  Docky
//

import AppKit
import SwiftUI

private final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class OnboardingDragRegionView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class PermissionsWindowController: NSWindowController {
    var onComplete: (() -> Void)?

    private let cornerRadius: CGFloat = 30
    private let titleBarDragHeight: CGFloat = 100
    private let titleBarDragHorizontalInset: CGFloat = 88
    private var measuredWindowSize = CGSize(width: 760, height: 740)

    convenience init(steps: [Permission]) {
        let screenFrame = NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let initialSize = CGSize(width: 760, height: 740)
        let initialFrame = CGRect(
            x: screenFrame.midX - initialSize.width / 2,
            y: screenFrame.midY - initialSize.height / 2,
            width: initialSize.width,
            height: initialSize.height
        )
        let window = OnboardingWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .normal
        window.isMovable = true
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.isReleasedWhenClosed = false
        self.init(window: window)

        let view = PermissionsView(
            steps: steps,
            topBarAdjustment: titleBarDragHeight,
            onWindowFrameChange: { [weak self] frame in
                self?.updateWindowFrame(frame)
            },
            onOpenSystemSettings: { permission in
                PermissionsService.shared.openSystemSettings(for: permission)
            },
        ) { [weak self] in
            self?.close()
            self?.onComplete?()
        }
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: initialSize)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = cornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        hostingView.autoresizingMask = [.width, .height]

        let containerView = NSView(frame: CGRect(origin: .zero, size: initialSize))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = cornerRadius
        containerView.layer?.cornerCurve = .continuous
        containerView.layer?.masksToBounds = true
        containerView.addSubview(hostingView)

        let dragRegionView = OnboardingDragRegionView(
            frame: CGRect(
                x: titleBarDragHorizontalInset,
                y: initialSize.height - titleBarDragHeight,
                width: initialSize.width - titleBarDragHorizontalInset * 2,
                height: titleBarDragHeight
            )
        )
        dragRegionView.autoresizingMask = [.width, .minYMargin]
        containerView.addSubview(dragRegionView)

        let viewController = NSViewController()
        viewController.view = containerView
        window.contentViewController = viewController
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        centerWindowOnActiveScreen()
        window?.makeKeyAndOrderFront(sender)
        window?.orderFrontRegardless()
    }

    override func close() {
        super.close()
    }

    private func centerWindowOnActiveScreen() {
        guard let window else { return }

        let screen = NSApp.keyWindow?.screen ?? window.screen ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        guard !screenFrame.equalTo(.zero) else { return }
        window.setFrame(
            CGRect(
                x: screenFrame.midX - measuredWindowSize.width / 2,
                y: screenFrame.midY - measuredWindowSize.height / 2,
                width: measuredWindowSize.width,
                height: measuredWindowSize.height
            ),
            display: true
        )
    }

    private func updateWindowFrame(_ frame: CGRect) {
        let size = frame.size
        guard size.width > 0, size.height > 0 else { return }
        guard size != measuredWindowSize else { return }
        measuredWindowSize = size

        guard let window else { return }
        let currentFrame = window.frame
        window.setFrame(
            CGRect(
                x: currentFrame.midX - size.width / 2,
                y: currentFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }
}
