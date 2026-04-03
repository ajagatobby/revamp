import SwiftUI

@main
struct RevampedApp: App {
    init() {
        // Expand URLCache so MapKit tiles persist across sessions
        URLCache.shared = URLCache(
            memoryCapacity: 4 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            directory: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
