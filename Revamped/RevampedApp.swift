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

        // Pre-warm snapshot cache — generates a static image of Cozy Hotel
        // (journey start point). If already cached on disk, this is a no-op.
        MapSnapshotCache.shared.prewarm(
            center: NYCMapView.cozyHotel,
            distance: 400,
            heading: 180,
            pitch: 65,
            key: "nyc_initial"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
