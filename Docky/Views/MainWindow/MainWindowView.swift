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
        updateBorderLayer(cornerRadius: effectiveCornerRadius)
    }

    override func updateLayer() {
        guard let layer else { return }

        let cornerRadius = effectiveCornerRadius
        let materialTint = NSColor.windowBackgroundColor.blended(withFraction: 0.18, of: .black) ?? .windowBackgroundColor

        layer.backgroundColor = materialTint.withAlphaComponent(0.22).cgColor
        layer.cornerCurve = .continuous
        layer.cornerRadius = cornerRadius
        updateBorderLayer(cornerRadius: cornerRadius)
    }

    private func setup() {
        wantsLayer = true
        borderLayer.actions = ["bounds": NSNull(), "position": NSNull()]
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
            dockSettings.$tileSize.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$largeSize.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$magnification.map { _ in () }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(signals)
            .sink { [weak self] _ in self?.needsDisplay = true }
            .store(in: &cancellables)
    }

    private var effectiveCornerRadius: CGFloat {
        min(preferences.windowCornerRadius, maximumCornerRadius)
    }

    private var maximumCornerRadius: CGFloat {
        let iconHeight = dockSettings.magnification ? dockSettings.largeSize : dockSettings.tileSize
        return (iconHeight + preferences.tileVerticalPadding * 2) / 2
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
