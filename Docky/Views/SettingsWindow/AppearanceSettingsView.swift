//
//  AppearanceSettingsView.swift
//  Docky
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        Form {
            Section("Indicators") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Indicator Shape")
                        .font(.headline)

                    Picker("Active Indicator Shape", selection: $preferences.activeIndicatorShape) {
                        ForEach(DockTileIndicatorShape.allCases) { shape in
                            Text(shape.title).tag(shape)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Choose whether running apps are marked with the classic dot or a pill.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Tile Layout") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tile Vertical Padding")
                        .font(.headline)

                    HStack {
                        Slider(value: $preferences.tileVerticalPadding, in: 8...32, step: 1) {
                            Text("Tile Vertical Padding")
                        }
                        Text("\(Int(preferences.tileVerticalPadding)) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    Text("Controls the top and bottom inset inside each dock tile.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tile Spacing")
                        .font(.headline)

                    HStack {
                        Slider(value: $preferences.tileSpacing, in: 0...16, step: 1) {
                            Text("Tile Spacing")
                        }
                        Text("\(Int(preferences.tileSpacing)) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    Text("Controls the horizontal gap between adjacent dock tiles.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Window Shape") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Window Corner Radius")
                        .font(.headline)

                    HStack {
                        Slider(value: windowCornerRadiusBinding, in: 0...maximumCornerRadius, step: 1) {
                            Text("Window Corner Radius")
                        }
                        Text("\(Int(min(preferences.windowCornerRadius, maximumCornerRadius))) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    Text("Controls the roundness of the main dock window and its border, up to a full capsule.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Window Background") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Window Background Image")
                        .font(.headline)

                    HStack {
                        Button("Choose Image...") {
                            chooseWindowBackgroundImage()
                        }

                        if preferences.windowBackgroundImagePath != nil {
                            Button("Clear") {
                                preferences.windowBackgroundImagePath = nil
                            }
                        }
                    }

                    if let selectedWindowBackgroundImageName {
                        Text(selectedWindowBackgroundImageName)
                            .foregroundStyle(.secondary)
                    }

                    Text("Use an image with aspect fill behind the dock tiles. When set, it replaces the material tint and opacity until cleared.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use Custom Window Tint", isOn: usesCustomWindowTintBinding)
                        .font(.headline)

                    if preferences.windowTintColor != nil {
                        ColorPicker("Window Tint", selection: windowTintBinding, supportsOpacity: false)
                    }

                    Text("Override the translucent tint behind the main dock window. Leave this off to keep following the system material color.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .disabled(usesWindowBackgroundImage)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Window Tint Opacity")
                        .font(.headline)

                    HStack {
                        Slider(value: windowTintOpacityBinding, in: 0...1, step: 0.01) {
                            Text("Window Tint Opacity")
                        }
                        Text("\(Int(preferences.effectiveWindowTintOpacity * 100))%")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    Text("Controls how strongly the tint color is laid over the window blur.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .disabled(usesWindowBackgroundImage)
            }

            Section {
                Button("Reset to Defaults") {
                    preferences.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
    }

    private var maximumCornerRadius: CGFloat {
        let iconHeight = dockSettings.magnification ? dockSettings.largeSize : dockSettings.tileSize
        return (iconHeight + preferences.tileVerticalPadding * 2) / 2
    }

    private var windowCornerRadiusBinding: Binding<CGFloat> {
        Binding(
            get: { min(preferences.windowCornerRadius, maximumCornerRadius) },
            set: { preferences.windowCornerRadius = $0 }
        )
    }

    private var usesCustomWindowTintBinding: Binding<Bool> {
        Binding(
            get: { preferences.windowTintColor != nil },
            set: { usesCustomTint in
                preferences.windowTintColor = usesCustomTint
                    ? (preferences.windowTintColor ?? DockWindowTintColor(nsColor: preferences.effectiveWindowTintColor))
                    : nil
            }
        )
    }

    private var windowTintBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: preferences.effectiveWindowTintColor) },
            set: { newValue in
                guard let tintColor = DockWindowTintColor(nsColor: NSColor(newValue)) else {
                    return
                }

                preferences.windowTintColor = tintColor
            }
        )
    }

    private var windowTintOpacityBinding: Binding<CGFloat> {
        Binding(
            get: { preferences.effectiveWindowTintOpacity },
            set: { preferences.windowTintOpacity = min(max($0, 0), 1) }
        )
    }

    private var usesWindowBackgroundImage: Bool {
        preferences.effectiveWindowBackgroundImageURL != nil
    }

    private var selectedWindowBackgroundImageName: String? {
        guard let path = preferences.windowBackgroundImagePath, !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func chooseWindowBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose Image"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        preferences.windowBackgroundImagePath = url.path
    }
}
