import SwiftUI

@main
struct EclipseMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime = RuntimeModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(runtime: runtime)
        } label: {
            MenuBarLabel(runtime: runtime)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(runtime: runtime)
                .frame(minWidth: 680, minHeight: 520)
        }
    }
}
