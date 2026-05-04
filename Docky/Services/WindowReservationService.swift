//
//  WindowReservationService.swift
//  Docky
//
//  Watches for app windows that get maximized to a screen's visibleFrame
//  and shrinks them via the Accessibility API to leave room for Docky.
//  The macOS 26 system Dock no longer reserves screen space, so apps think
//  visibleFrame is theirs to fill. This service makes Docky behave as if
//  it reserved space — only when the user opts into resizeWindow mode.
//
//  Activation gates: maximizedWindowBehavior == .resizeWindow AND
//  accessibility permission granted. The service piggybacks on
//  WindowRegistry's AX observers (which already track every app's window
//  resizes) rather than spinning up a parallel observer set.
//

import AppKit
import Combine
import Foundation

final class WindowReservationService {
    static let shared = WindowReservationService()

    private let preferences = DockyPreferences.shared
    private let permissions = PermissionsService.shared
    private let registry = WindowRegistry.shared

    private var cancellables: Set<AnyCancellable> = []
    private var registrySubscription: AnyCancellable?
    private var pidCooldowns: [pid_t: Date] = [:]
    private let cooldownInterval: TimeInterval = 0.25
    private let matchTolerance: CGFloat = 1

    private init() {}

    func start() {
        Publishers.CombineLatest(preferences.$maximizedWindowBehavior, permissions.$accessibility)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode, status in
                self?.updateActivation(mode: mode, status: status)
            }
            .store(in: &cancellables)
    }

    private func updateActivation(mode: MaximizedWindowBehavior, status: PermissionStatus) {
        let shouldBeActive = (mode == .resizeWindow) && (status == .granted)
        if shouldBeActive {
            attachIfNeeded()
        } else {
            detach()
        }
    }

    private func attachIfNeeded() {
        guard registrySubscription == nil else { return }
        registrySubscription = registry.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows in
                self?.scan(windows: windows)
            }
    }

    private func detach() {
        registrySubscription?.cancel()
        registrySubscription = nil
        pidCooldowns.removeAll()
    }

    private func scan(windows: [AppWindow]) {
        guard let mainWindow = NSApp.windows.compactMap({ $0 as? MainWindow }).first,
              let dockyScreen = mainWindow.screen,
              let dockyFrame = mainWindow.currentReservationFrame
        else { return }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let now = Date()

        for window in windows where window.processIdentifier != ownPID {
            if let until = pidCooldowns[window.processIdentifier], now < until { continue }

            guard let frame = window.frame else { continue }

            // Only act on windows on the same screen as Docky.
            guard let windowScreen = screenContaining(frame), windowScreen == dockyScreen else { continue }

            // Maximize signature: matches visibleFrame within tolerance.
            // Skip fullscreen (matches frame, larger than visibleFrame) — that's
            // a user-chosen state we never override.
            guard rectsMatch(frame, dockyScreen.visibleFrame) else { continue }

            // Compute the desired smaller frame.
            let target = subtract(reservation: dockyFrame, from: dockyScreen.visibleFrame)
            // Don't issue redundant resizes.
            guard !rectsMatch(frame, target) else { continue }
            // Don't shrink a window that's already smaller in the relevant axis.
            guard target.width > 0, target.height > 0 else { continue }

            let succeeded = registry.resize(window, to: target)
            if succeeded {
                pidCooldowns[window.processIdentifier] = now.addingTimeInterval(cooldownInterval)
            }
        }
    }

    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        // Match by largest intersection so a window straddling a display
        // boundary picks the screen it mostly lives on.
        var best: (screen: NSScreen, area: CGFloat)?
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(frame)
            let area = intersection.width * intersection.height
            if area > 0, area > (best?.area ?? 0) {
                best = (screen, area)
            }
        }
        return best?.screen
    }

    /// Subtracts Docky's footprint from the screen's visible frame, picking
    /// the side based on which edge Docky's frame is flush against.
    private func subtract(reservation dock: CGRect, from visible: CGRect) -> CGRect {
        var result = visible
        let edgeTolerance: CGFloat = 2

        if abs(dock.minX - visible.minX) < edgeTolerance, dock.maxX < visible.maxX - edgeTolerance {
            // Docky on the left.
            result.origin.x = dock.maxX
            result.size.width = max(0, visible.maxX - dock.maxX)
        } else if abs(dock.maxX - visible.maxX) < edgeTolerance, dock.minX > visible.minX + edgeTolerance {
            // Docky on the right.
            result.size.width = max(0, dock.minX - visible.minX)
        } else if abs(dock.maxY - visible.maxY) < edgeTolerance, dock.minY > visible.minY + edgeTolerance {
            // Docky at the top.
            result.size.height = max(0, dock.minY - visible.minY)
        } else if abs(dock.minY - visible.minY) < edgeTolerance, dock.maxY < visible.maxY - edgeTolerance {
            // Docky at the bottom.
            result.origin.y = dock.maxY
            result.size.height = max(0, visible.maxY - dock.maxY)
        }

        return result
    }

    private func rectsMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < matchTolerance
            && abs(a.minY - b.minY) < matchTolerance
            && abs(a.width - b.width) < matchTolerance
            && abs(a.height - b.height) < matchTolerance
    }
}
