import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 560)
    }
}

private struct GeneralSettings: View {
    @Bindable private var settings = Settings.shared
    @State private var accessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("Activation") {
                LabeledContent("Show Pesty") { HotkeyRecorderView() }
                Stepper(value: $settings.historyLimit, in: 50...5000, step: 50) {
                    LabeledContent("History limit", value: "\(settings.historyLimit) items")
                }
            }

            Section("Behavior") {
                Toggle("Paste directly into the active app", isOn: $settings.pasteDirectly)
                Toggle("Ignore passwords (concealed clips)", isOn: $settings.ignoreConcealed)
                Toggle("Play sound on paste", isOn: $settings.playSound)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                VStack(alignment: .leading) {
                    LabeledContent("Bar height", value: "\(Int(settings.barHeight)) px")
                    Slider(value: $settings.barHeight, in: 260...640, step: 20)
                }
            }

            Section("Permissions") {
                HStack {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                        Text(accessibilityGranted
                             ? "Direct paste is enabled."
                             : "Required to paste directly into other apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !accessibilityGranted {
                        Button("Grant…") {
                            PasteService.ensureAccessibility(prompt: true)
                            openAccessibilityPane()
                        }
                    }
                }
            }

            Section("Data") {
                Button("Clear Clipboard History", role: .destructive) {
                    ClipboardStore.shared.clearHistory()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { accessibilityGranted = AXIsProcessTrusted() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    private func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable().frame(width: 88, height: 88)
            Text("Pesty").font(.system(size: 26, weight: .bold))
            Text("Version \(Bundle.main.appVersion)")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("A free, open-source clipboard manager for macOS.\nInspired by Paste.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/momenbasel/pesty")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/momenbasel/pesty/issues")!)
            }
            .padding(.top, 4)
            Spacer()
            Text("MIT Licensed · Made with SwiftUI")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
