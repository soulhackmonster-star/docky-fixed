//
//  WindowManagementSettingsView.swift
//  Docky
//

import SwiftUI

struct WindowManagementSettingsView: View {
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared
    @State private var isRecordingShortcut = false

    private var shortcutHelpText: String {
        if product.isUnlocked(.windowSwitcher),
           preferences.showsWindowSwitcherFocusPreview,
           preferences.windowSwitcherPreviewMode == .instantFocus {
            return "While the switcher is open, keep the shortcut modifiers held and tap the shortcut again to cycle. In Instant Focus mode, each step immediately focuses the next window and releasing the modifiers ends cycling."
        }

        return "While the switcher is open, keep the shortcut modifiers held and tap the shortcut again to cycle. Release the modifiers to focus the selected window."
    }

    var body: some View {
        Form {
            Section("Window Switcher") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Window Switcher", isOn: $preferences.enablesWindowSwitcher)
                        .font(.headline)

                    Text("Turn Docky's Cmd-Tab-style switcher on or off without clearing its shortcut or preview preference.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shortcut")
                                .font(.headline)

                            Text("Choose the global shortcut that opens Docky's Cmd-Tab-style window switcher.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        ShortcutRecorderControl(
                            shortcut: preferences.windowSwitcherShortcut,
                            isRecording: $isRecordingShortcut,
                            resetShortcut: KeyboardShortcut(keyCode: 48, modifierFlags: [.option])
                        ) { shortcut in
                            preferences.windowSwitcherShortcut = shortcut
                        }
                        .disabled(!preferences.enablesWindowSwitcher)
                    }

                    Text(shortcutHelpText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                if !product.isUnlocked(.windowSwitcher) {
                    Text("Docky Pro unlocks switcher preview modes and window context menus inside the switcher.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Switcher Preview", isOn: $preferences.showsWindowSwitcherFocusPreview)
                        .font(.headline)
                        .disabled(!product.isUnlocked(.windowSwitcher) || !preferences.enablesWindowSwitcher)

                    Text("Choose whether the switcher should stay purely overlaid, preview the selected window behind it, or focus each step immediately while cycling.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview Mode")
                        .font(.headline)

                    Picker("Preview Mode", selection: $preferences.windowSwitcherPreviewMode) {
                        ForEach(WindowSwitcherPreviewMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(!product.isUnlocked(.windowSwitcher) || !preferences.enablesWindowSwitcher || !preferences.showsWindowSwitcherFocusPreview)

                    Text(preferences.windowSwitcherPreviewMode.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}
