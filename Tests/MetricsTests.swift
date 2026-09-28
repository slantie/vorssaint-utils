// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// The runner lists every independently selectable suite. A filtered run says
// exactly which suites ran; an unknown or empty selection is an error.
@main
struct MetricsTests {
    static func main() {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--pdf-fixtures" {
            do {
                let directory = URL(fileURLWithPath: CommandLine.arguments[2])
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for (name, labels) in [("Three pages", ["ALPHA", "BETA", "GAMMA"]), ("Two pages", ["DELTA", "EPSILON"])] {
                    let output = MediaSupport.uniqueOutputURL(in: directory, baseName: name, fileExtension: "pdf")
                    try PDFToolTests.fixture(output, labels: labels)
                    print(output.path)
                }
                exit(0)
            } catch { fputs("\(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--media-convert-benchmark") {
            let arguments = CommandLine.arguments
            guard arguments.count == 4 || (arguments.count == 6 && arguments[4] == "--engines"),
                  let format = FileDragFormat(rawValue: arguments[3]) else {
                fputs("usage: metrics-tests --media-convert-benchmark INPUT FORMAT [--engines DIRECTORY]\n", stderr)
                exit(2)
            }
            let engines = arguments.count == 6 ? MediaEngineBundle(root: URL(fileURLWithPath: arguments[5])) : nil
            if arguments.count == 6 && engines == nil {
                fputs("invalid media engine bundle\n", stderr)
                exit(2)
            }
            do {
                let output = try FileDragConversionEngine.convert(URL(fileURLWithPath: arguments[2]),
                                                                  to: format, batch: FileDragBatch(),
                                                                  engines: engines)
                print(output.path)
                exit(0)
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        let suite = TestSuite()
        let groups: [(String, () -> Void)] = [
            ("harness", {
                TestHarnessTests.run(suite)
                PreferenceNamespaceTests.run(suite)
            }),
            ("metrics", {
                MetricsFeatureTests.run(suite)
                ProcessNameContract.run(suite)
                SystemMonitorCPUTests.run(suite)
            }),
            ("clipboard", { ClipboardFeatureTests.run(suite) }),
            ("pointer-input", {
                PointerOnDisplayContract.run(suite)
                PointerInputFeatureTests.run(suite)
                KeyboardDebounceTapTests.run(suite)
                PointerDisplayLookupContract.run(suite)
                SuperKeyTapContract.run(suite)
                PointerScreenContract.run(suite)
            }),
            ("scroll-modifier", { ScrollHorizontalModifierTests.run(suite) }),
            ("preferences", { PreferencesFeatureTests.run(suite) }),
            ("app-management", { AppManagementFeatureTests.run(suite) }),
            ("window-layout", { WindowLayoutFeatureTests.run(suite) }),
            ("media", { MediaFeatureTests.run(suite) }),
            ("mixer", {
                MixerNativeDragTests.run(suite)
                MixerOutputAdjustmentContract.run(suite)
                SoundOutputSwitchContract.run(suite)
                MixerInputVolumeContract.run(suite)
                MixerFeatureTests.run(suite)
            }),
            ("audio-priority", { AudioPriorityTests.run(suite) }),
            ("shelf", { ShelfFeatureTests.run(suite) }),
            ("overlays", { OverlayPanelTests.run(suite) }),
            ("updates", {
                UpdateFeatureTests.run(suite)
                PostUpdateStatusItemRecoveryTests.run(suite)
                UpdateAdminInstallContract.run(suite)
                UpdateHighlightsTests.run(suite)
                UpdateIntroFlowTests.run(suite)
            }),
            ("repository", { RepositoryFeatureTests.run(suite) }),
            ("screenshots", {
                ScreenshotPreviewHoverTests.run(suite)
                ScreenshotWatermarkTests.run(suite)
                ScreenshotFeatureTests.run(suite)
                ScreenshotScrollingCaptureTests.run(suite)
                ScreenCaptureToolPickerTests.run(suite)
            }),
            ("recorder", {
                RecorderFeatureTests.run(suite)
                RecorderZoomAimingTests.run(suite)
                RecorderExportSpeedTests.run(suite)
                RecorderExportRenderingTests.run(suite)
            }),
            ("command-bar", { CommandBarFeatureTests.run(suite) }),
            ("notch", {
                NotchTests.run(suite)
                NotchCompactTests.run(suite)
                NotchVolumeKeyTests.run(suite)
                NotchSettingsTabRowTests.run(suite)
            }),
            ("switcher-model", { SwitcherModelFeatureTests.run(suite) }),
            ("agents", { NotchAgentTests.run(suite) }),
            ("features", { FeatureCatalogTests.run(suite) }),
            ("utilities", {
                UtilitiesFeatureTests.run(suite)
                PortManagerRefreshTests.run(suite)
            }),
            ("settings", {
                SettingsFeatureTests.run(suite)
                SettingsWindowTests.run { suite.expect($0, $1) }
                NotchSettingsChoiceTests.run(suite)
            }),
            ("display-restoration", {
                DisplayRestorationTests.run(suite)
                BrightnessStepTests.run(suite)
            }),
            ("software-dimming", { SoftwareDimmingRouteTests.run { suite.expect($0, $1) } }),
            ("capture", { ScreenshotSelectionRefreshContract.run(suite) }),
            ("keyboard", {
                KeyboardFeatureTests.run(suite)
                AssistiveKeyboardTests.run(suite)
                ScreenshotToolShortcutTests.run(suite)
            }),
            ("storage", {
                RecentCaptureStoreTests.run(suite)
                RecorderPresetImageStoreTests.run(suite)
                StorageFeatureTests.run(suite)
                ScratchpadStoreContractTests.run(suite)
            }),
            ("quit-protection", { QuitProtectionHUD.progressChecks(suite) }),
            ("recording", {
                RecorderSampleTimingTests.run(suite)
                RecorderWriterTests.run(suite)
                RecorderExportChipTests.run { suite.expect($0, $1) }
            }),
            ("network", {
                NetworkFeatureTests.run(suite)
                SpeedTestTests.run(suite)
                NetworkAddressTests.run { suite.expect($0, $1) }
            }),
            ("app-updates", { AppUpdatesContract.run(suite) }),
            ("localization", {
                LocalizationTests.run(suite)
                LocalizationFeatureContractTests.run(suite)
            }),
            ("cleaner", {
                CleanerEligibilityTests.run(suite)
                CleanerLastRunContract.run(suite)
                CleanerScanFlowTests.run(suite)
            }),
            ("uninstaller", {
                UninstallerFlowTests.run(suite)
                SelfUninstallContract.run(suite)
            }),
            ("launcher", { QuickLauncherContract.run(suite) }),
            ("dock-autohide", {
                DockAutohideHoldTests.run(suite)
                DockPreviewFrameRestorationTests.run(suite)
            }),
            ("switcher", {
                SwitcherScrollContract.run(suite)
                SwitcherActivationTests.run(suite)
                WindowServerCaptureContract.run(suite)
            }),
            ("keep-awake", {
                KeepAwakeCatalogContract.run(suite)
                MenuPanelToggleLabelContract.run(suite)
                KeepAwakeLidSleepTests.run { suite.expect($0, $1) }
                KeepAwakeTimerHandoffTests.run { suite.expect($0, $1) }
            }),
            ("wallpaper", { WallpaperContract.run(suite) }),
            ("emoji", { CommandBarEmojiContract.run(suite) }),
        ]
        var selected = Set<String>()
        var listOnly = false
        for argument in CommandLine.arguments.dropFirst() {
            if argument == "--list" {
                listOnly = true
                continue
            }
            guard argument.hasPrefix("--suite="),
                  groups.contains(where: { $0.0 == String(argument.dropFirst(8)) }) else {
                fputs("Unknown test selection: \(argument)\n", stderr)
                exit(2)
            }
            selected.insert(String(argument.dropFirst(8)))
        }
        if listOnly {
            groups.forEach { print($0.0) }
            exit(0)
        }
        for (name, body) in groups where selected.isEmpty || selected.contains(name) {
            suite.run(name, body)
        }
        suite.finish()
    }
}
