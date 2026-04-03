import SwiftUI

@main
struct RevampedApp: App {
    init() {
        // Expand URLCache for MapKit tile persistence across sessions
        URLCache.shared = URLCache(
            memoryCapacity: 4 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            directory: nil
        )

        // Pre-warm snapshot cache — generates a static image of Times Square
        // on a background thread. If already cached on disk, this is a no-op.
        MapSnapshotCache.shared.prewarm(
            center: NYCMapView.timesSquare,
            distance: 2000,
            heading: 0,
            pitch: 45,
            key: "nyc_initial"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
