import SwiftUI

@main
struct EclipseMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime = RuntimeModel.shared
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(runtime: runtime)
        } label: {
            MenuBarLabel(runtime: runtime)
        }
        .menuBarExtraStyle(.window)

        Window("Eclipse", id: "eclipse-chat") {
            ContentView(settings: appSettings)
        }
        .defaultSize(width: 720, height: 680)

        Settings {
            SettingsView(runtime: runtime, appSettings: appSettings)
                .frame(minWidth: 680, minHeight: 520)
        }
    }
}
