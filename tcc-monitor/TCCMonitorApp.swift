import SwiftUI

@main
struct TCCMonitorApp: App {
    @StateObject private var monitor = SystemMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .onAppear { monitor.start() }
        }
    }
}
