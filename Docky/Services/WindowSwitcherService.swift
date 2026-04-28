//
//  WindowSwitcherService.swift
//  Docky
//

import AppKit
import Carbon
import Combine

final class WindowSwitcherService: ObservableObject {
    static let shared = WindowSwitcherService()

    @Published private(set) var isPresented = false
    @Published private(set) var windows: [AppWindow] = []
    @Published private(set) var selectedWindowIdentifier: String?
    @Published private(set) var isContextMenuPresented = false

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var localKeyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private let forwardHotKeyID = EventHotKeyID(signature: OSType(0x444B5957), id: 1)
    private let reverseHotKeyID = EventHotKeyID(signature: OSType(0x444B5957), id: 2)
    private var reverseHotKeyRef: EventHotKeyRef?

    private init() {
        installHotKeyHandlerIfNeeded()
        registerHotKey(shortcut: DockyPreferences.shared.windowSwitcherShortcut)
        installEventMonitors()
        subscribeToPreferences()
    }

    deinit {
        unregisterHotKey()

        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
        }

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
        }
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
        }
    }

    func handleHotKeyPress(direction: Int) {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "switch between windows")
            return
        }

        let latestWindows = WorkspaceService.shared.switchableWindows()
        guard !latestWindows.isEmpty else {
            dismiss()
            return
        }

        let previousSelectionIdentifier = selectedWindowIdentifier
        windows = latestWindows

        if isPresented {
            let currentIndex = previousSelectionIdentifier.flatMap { identifier in
                latestWindows.firstIndex { $0.windowIdentifier == identifier }
            } ?? 0
            selectWindow(at: currentIndex + direction)
            return
        }

        isPresented = true
        let initialIndex: Int
        if latestWindows.count <= 1 {
            initialIndex = 0
        } else if direction < 0 {
            initialIndex = latestWindows.count - 1
        } else {
            initialIndex = 1
        }
        selectWindow(at: initialIndex)
    }

    func confirmSelection() {
        guard let selectedWindow else {
            dismiss()
            return
        }

        dismiss()
        _ = WorkspaceService.shared.focus(window: selectedWindow)
    }

    func dismiss() {
        isPresented = false
        isContextMenuPresented = false
        windows = []
        selectedWindowIdentifier = nil
    }

    func moveSelection(delta: Int) {
        guard !windows.isEmpty else { return }

        let currentIndex = selectedWindow.flatMap { window in
            windows.firstIndex { $0.windowIdentifier == window.windowIdentifier }
        } ?? 0
        selectWindow(at: currentIndex + delta)
    }

    func selectWindow(withIdentifier identifier: String) {
        guard windows.contains(where: { $0.windowIdentifier == identifier }) else {
            return
        }

        selectedWindowIdentifier = identifier
    }

    func setContextMenuPresented(_ isPresented: Bool) {
        isContextMenuPresented = isPresented

        guard !isPresented else {
            return
        }

        dismissIfShortcutReleased(flags: NSEvent.modifierFlags)
    }

    func removeWindow(withIdentifier identifier: String) {
        guard let removedIndex = windows.firstIndex(where: { $0.windowIdentifier == identifier }) else {
            return
        }

        windows.remove(at: removedIndex)

        guard !windows.isEmpty else {
            dismiss()
            return
        }

        let nextIndex = min(removedIndex, windows.count - 1)
        selectedWindowIdentifier = windows[nextIndex].windowIdentifier
    }

    private var selectedWindow: AppWindow? {
        guard let selectedWindowIdentifier else {
            return nil
        }

        return windows.first { $0.windowIdentifier == selectedWindowIdentifier }
    }

    private func subscribeToPreferences() {
        DockyPreferences.shared.$windowSwitcherShortcut
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shortcut in
                self?.registerHotKey(shortcut: shortcut)
            }
            .store(in: &cancellables)
    }

    private func installEventMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresented else {
                return event
            }

            switch event.keyCode {
            case 53:
                self.dismiss()
                return nil
            case 36, 76:
                self.confirmSelection()
                return nil
            case 123, 126:
                self.moveSelection(delta: -1)
                return nil
            case 124, 125:
                self.moveSelection(delta: 1)
                return nil
            default:
                return event
            }
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierReleaseIfNeeded(flags: event.modifierFlags)
            return event
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierReleaseIfNeeded(flags: event.modifierFlags)
        }
    }

    private func handleModifierReleaseIfNeeded(flags: NSEvent.ModifierFlags) {
        guard isPresented else { return }
        guard !isContextMenuPresented else { return }

        let requiredFlags = DockyPreferences.shared.windowSwitcherShortcut.modifierFlags
        let activeFlags = flags.intersection(KeyboardShortcut.supportedModifierFlags)
        guard !requiredFlags.isEmpty, !activeFlags.isSuperset(of: requiredFlags) else {
            return
        }

        confirmSelection()
    }

    private func dismissIfShortcutReleased(flags: NSEvent.ModifierFlags) {
        guard isPresented else { return }

        let requiredFlags = DockyPreferences.shared.windowSwitcherShortcut.modifierFlags
        let activeFlags = flags.intersection(KeyboardShortcut.supportedModifierFlags)
        guard !requiredFlags.isEmpty, !activeFlags.isSuperset(of: requiredFlags) else {
            return
        }

        dismiss()
    }

    private func selectWindow(at index: Int) {
        guard !windows.isEmpty else {
            selectedWindowIdentifier = nil
            return
        }

        let wrappedIndex = ((index % windows.count) + windows.count) % windows.count
        selectedWindowIdentifier = windows[wrappedIndex].windowIdentifier
    }

    private func installHotKeyHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else {
                return OSStatus(eventNotHandledErr)
            }

            let service = Unmanaged<WindowSwitcherService>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr,
                  hotKeyID.signature == service.forwardHotKeyID.signature else {
                return OSStatus(eventNotHandledErr)
            }

            let direction = hotKeyID.id == service.reverseHotKeyID.id ? -1 : 1

            Task { @MainActor in
                service.handleHotKeyPress(direction: direction)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )
    }

    private func registerHotKey(shortcut: KeyboardShortcut) {
        unregisterHotKey()

        guard shortcut.isValid else {
            return
        }

        RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags,
            forwardHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags | UInt32(shiftKey),
            reverseHotKeyID,
            GetApplicationEventTarget(),
            0,
            &reverseHotKeyRef
        )
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let reverseHotKeyRef {
            UnregisterEventHotKey(reverseHotKeyRef)
            self.reverseHotKeyRef = nil
        }
    }
}
