import SwiftUI

struct ContentView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ChatView(settings: settings)
    }
}

