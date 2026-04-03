import SwiftUI

@main
struct RevampedApp: App {
    init() {
        MapPreloader.shared.preload()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
