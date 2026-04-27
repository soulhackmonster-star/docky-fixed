//
//  MainWindowView.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import AppKit
import Combine
import SwiftUI

final class MainWindowView: NSView {
    override var wantsUpdateLayer: Bool { true }

    private let borderWidth: CGFloat = 1
    private let dockSettings = DockSettingsService.shared
    private let preferences = DockyPreferences.shared
    private let layoutService = DockLayoutService.shared
    private let backgroundImageLayer = CALayer()
    private let borderLayer = CAGradientLayer()
    private var cancellables: Set<AnyCancellable> = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layout() {
        super.layout()

        let cornerRadius = effectiveCornerRadius
        updateBackgroundImageLayer(cornerRadius: cornerRadius)
        updateBorderLayer(cornerRadius: cornerRadius)
    }

    override func updateLayer() {
        guard let layer else { return }

        let cornerRadius = effectiveCornerRadius
        let backgroundImage = resolvedBackgroundImage

        if let backgroundImage {
            backgroundImageLayer.contents = backgroundImage
            backgroundImageLayer.isHidden = false
            layer.backgroundColor = NSColor.clear.cgColor
        } else {
            let materialTint = preferences.effectiveWindowTintColor

            backgroundImageLayer.contents = nil
            backgroundImageLayer.isHidden = true
            layer.backgroundColor = materialTint.withAlphaComponent(preferences.effectiveWindowTintOpacity).cgColor
        }

        layer.cornerCurve = .continuous
        layer.cornerRadius = cornerRadius
        borderLayer.isHidden = preferences.disablesGlassLook
        updateBackgroundImageLayer(cornerRadius: cornerRadius)
        updateBorderLayer(cornerRadius: cornerRadius)
    }

    private func setup() {
        wantsLayer = true
        backgroundImageLayer.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
        backgroundImageLayer.contentsGravity = .resizeAspectFill
        backgroundImageLayer.masksToBounds = true
        borderLayer.actions = ["bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(backgroundImageLayer)
        layer?.addSublayer(borderLayer)

        let hosting = ClickThroughHostingView(rootView: TileContainerView())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        let signals: [AnyPublisher<Void, Never>] = [
            preferences.$tileVerticalPadding.map { _ in () }.eraseToAnyPublisher(),
            preferences.$windowCornerRadius.map { _ in () }.eraseToAnyPublisher(),
            preferences.$windowClipShape.map { _ in () }.eraseToAnyPublisher(),
            preferences.$windowTintColor.map { _ in () }.eraseToAnyPublisher(),
            preferences.$windowTintOpacity.map { _ in () }.eraseToAnyPublisher(),
            preferences.$disablesGlassLook.map { _ in () }.eraseToAnyPublisher(),
            preferences.$windowBackgroundImagePath.map { _ in () }.eraseToAnyPublisher(),
            layoutService.$contentScale.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$tileSize.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$largeSize.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$magnification.map { _ in () }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(signals)
            .sink { [weak self] _ in self?.needsDisplay = true }
            .store(in: &cancellables)
    }

    private var effectiveCornerRadius: CGFloat {
        preferences.windowClipShape.resolvedCornerRadius(
            base: preferences.windowCornerRadius,
            maximum: maximumCornerRadius
        )
    }

    private var maximumCornerRadius: CGFloat {
        let iconHeight = layoutService.scaled(dockSettings.magnification ? dockSettings.largeSize : dockSettings.tileSize)
        return (iconHeight + layoutService.scaled(preferences.tileVerticalPadding) * 2) / 2
    }

    private var resolvedBackgroundImage: CGImage? {
        guard let backgroundImageURL = preferences.effectiveWindowBackgroundImageURL,
              let image = NSImage(contentsOf: backgroundImageURL) else {
            return nil
        }

        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func updateBackgroundImageLayer(cornerRadius: CGFloat) {
        backgroundImageLayer.frame = bounds
        backgroundImageLayer.cornerCurve = .continuous
        backgroundImageLayer.cornerRadius = cornerRadius
        backgroundImageLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func borderMask(in rect: CGRect, cornerRadius: CGFloat) -> CALayer {
        let localRect = CGRect(origin: .zero, size: rect.size)

        let mask = CALayer()
        mask.frame = localRect
        mask.cornerCurve = .continuous
        mask.cornerRadius = max(cornerRadius - borderWidth / 2, 0)
        mask.borderWidth = borderWidth
        mask.borderColor = NSColor.black.cgColor
        mask.backgroundColor = NSColor.clear.cgColor
        mask.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return mask
    }

    private func updateBorderLayer(cornerRadius: CGFloat) {
        guard !preferences.disablesGlassLook else {
            borderLayer.mask = nil
            return
        }

        let borderFrame = bounds
        let borderCornerRadius = cornerRadius

        borderLayer.frame = borderFrame
        borderLayer.cornerCurve = .continuous
        borderLayer.cornerRadius = borderCornerRadius
        borderLayer.startPoint = CGPoint(x: 0, y: 1)
        borderLayer.endPoint = CGPoint(x: 1, y: 0)
        borderLayer.colors = [
            NSColor.white.withAlphaComponent(0.35).cgColor,
            NSColor.white.withAlphaComponent(0.12).cgColor,
            NSColor.white.withAlphaComponent(0.05).cgColor,
            NSColor.white.withAlphaComponent(0.12).cgColor,
            NSColor.white.withAlphaComponent(0.28).cgColor,
        ]
        borderLayer.locations = [0, 0.35, 0.65, 1]

        let mask = borderMask(in: borderLayer.bounds, cornerRadius: borderCornerRadius)
        borderLayer.mask = mask
    }
}

private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
