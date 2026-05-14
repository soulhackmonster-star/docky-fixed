#!/usr/bin/env ruby
#
# add-mas-target.rb
#
# Creates the "Docky (App Store)" target by duplicating the existing
# Docky target, then applies the App Store xcconfig + entitlements
# to its build configurations and rewrites the bundle id.
#
# Idempotent: safe to re-run. If the target already exists the script
# only re-applies its settings.
#
# Run with `ruby scripts/add-mas-target.rb` from the repo root.
#
# Requires the `xcodeproj` gem (`gem install --user-install xcodeproj`).
#

require 'xcodeproj'

PROJECT_PATH = 'Docky.xcodeproj'
SOURCE_TARGET_NAME = 'Docky'
NEW_TARGET_NAME = 'Docky (App Store)'
NEW_BUNDLE_ID = 'gt.quintero.Docky.appstore'
ENTITLEMENTS = 'Docky/Docky.AppStore.entitlements'
XCCONFIG = 'Docky/Docky.AppStore.xcconfig'

project = Xcodeproj::Project.open(PROJECT_PATH)
source_target = project.targets.find { |t| t.name == SOURCE_TARGET_NAME }

unless source_target
  abort "Source target '#{SOURCE_TARGET_NAME}' not found"
end

#
# 1. Find or create the new target by duplicating the source.
#    `Xcodeproj::Project::Object::PBXNativeTarget` doesn't have a
#    public duplicate, so we create a fresh target with the same
#    product type and copy build phases / source file references
#    over.
#
new_target = project.targets.find { |t| t.name == NEW_TARGET_NAME }

if new_target.nil?
  puts "==> Creating target '#{NEW_TARGET_NAME}'"
  new_target = project.new_target(
    :application,
    NEW_TARGET_NAME,
    :osx,
    source_target.deployment_target,
    nil,
    :swift
  )

  # Mirror source build phases (files only; build settings come from
  # the xcconfig). Build phase types we care about: Sources, Resources,
  # Frameworks, Copy Bundled Themes (a shell-script phase).
  source_target.source_build_phase.files.each do |build_file|
    next unless build_file.file_ref
    new_target.add_file_references([build_file.file_ref])
  end

  source_target.resources_build_phase.files.each do |build_file|
    next unless build_file.file_ref
    new_target.resources_build_phase.add_file_reference(build_file.file_ref, true)
  end

  source_target.frameworks_build_phase.files.each do |build_file|
    next unless build_file.file_ref
    new_target.frameworks_build_phase.add_file_reference(build_file.file_ref, true)
  end

  # Copy any shell-script run phases (e.g. "Copy Bundled Themes")
  # so the MAS bundle gets the same theme tree.
  source_target.build_phases.each do |phase|
    next unless phase.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase)
    new_phase = new_target.new_shell_script_build_phase(phase.name)
    new_phase.shell_path = phase.shell_path
    new_phase.shell_script = phase.shell_script
    new_phase.input_paths = phase.input_paths.dup
    new_phase.output_paths = phase.output_paths.dup
    new_phase.run_only_for_deployment_postprocessing = phase.run_only_for_deployment_postprocessing
  end
else
  puts "==> Target '#{NEW_TARGET_NAME}' already exists, updating settings"
end

#
# 2. Attach xcconfig + apply overrides on each build configuration.
#
xcconfig_ref = project.files.find { |f| f.path == XCCONFIG } ||
               project.new_file(XCCONFIG)

new_target.build_configurations.each do |config|
  config.base_configuration_reference = xcconfig_ref
  # Settings the xcconfig sets are inherited; we set a few explicit
  # ones here too in case the xcconfig is ever removed without
  # detaching it from the target.
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = NEW_BUNDLE_ID
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = ENTITLEMENTS
  config.build_settings['ENABLE_APP_SANDBOX'] = 'YES'
  config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
  config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] =
    "$(inherited) APP_STORE_SANDBOX"
  # Source target disables user-script sandboxing because the
  # "Copy Bundled Themes" phase needs rm -rf + ditto on its own
  # destination path; mirror that for the MAS target.
  config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
  # PRODUCT_NAME differs from "Docky" so dev builds of both targets
  # don't collide in Build/Products/Debug/. The user-facing display
  # name stays "Docky" via INFOPLIST_KEY_CFBundleDisplayName.
  config.build_settings['PRODUCT_NAME'] = 'Docky-AppStore'
  config.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Docky'
  # Same Info.plist as the source target, plus auto-generation so
  # xcodebuild stops complaining about missing keys (the source
  # target uses generated Info.plist with INFOPLIST_KEY_* overrides).
  source_release = source_target.build_configurations.find { |c| c.name == 'Release' }
  if source_release
    ['INFOPLIST_FILE', 'GENERATE_INFOPLIST_FILE',
     'INFOPLIST_KEY_NSHumanReadableCopyright',
     'INFOPLIST_KEY_LSApplicationCategoryType',
     'INFOPLIST_KEY_LSUIElement',
     'INFOPLIST_KEY_NSPrincipalClass',
     'MACOSX_DEPLOYMENT_TARGET',
     'MARKETING_VERSION',
     'CURRENT_PROJECT_VERSION',
     'CODE_SIGN_STYLE',
     'DEVELOPMENT_TEAM',
     'SWIFT_VERSION',
     'ASSETCATALOG_COMPILER_APPICON_NAME',
     'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'].each do |key|
      value = source_release.build_settings[key]
      config.build_settings[key] = value unless value.nil?
    end
    # Default to auto-generated Info.plist if the source target uses
    # that pattern (and didn't set INFOPLIST_FILE).
    if config.build_settings['INFOPLIST_FILE'].nil?
      config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    end
  end
end

#
# 3. Make sure the new entitlements + xcconfig files are in the
#    project tree so Xcode shows them under the target.
#
[ENTITLEMENTS].each do |path|
  next if project.files.any? { |f| f.path == path }
  project.new_file(path)
end

project.save
puts "==> Saved #{PROJECT_PATH}"
puts
puts "Next: open Docky.xcodeproj, create a scheme for '#{NEW_TARGET_NAME}',"
puts "then run scripts/build-mas.sh to validate."
