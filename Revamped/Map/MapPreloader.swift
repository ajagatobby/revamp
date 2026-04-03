import MapKit

/// Pre-warms MapKit's tile cache by taking snapshots of every waypoint
/// along the NYC flyover route. Snapshots force tile downloads even
/// off-screen. Tiles persist in URLCache across app sessions.
final class MapPreloader {

    static let shared = MapPreloader()
    private var isPreloading = false

    // Same waypoints as NYCMapView flyover route
    private let waypoints: [(CLLocationCoordinate2D, Double, Double)] = [
        (CLLocationCoordinate2D(latitude: 40.7074, longitude: -74.0113), 15, 600),
        (CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), 20, 700),
        (CLLocationCoordinate2D(latitude: 40.7233, longitude: -73.9985), 25, 750),
        (CLLocationCoordinate2D(latitude: 40.7359, longitude: -73.9911), 30, 800),
        (CLLocationCoordinate2D(latitude: 40.7411, longitude: -73.9897), 32, 850),
        (CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9878), 35, 900),
        (CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), 40, 700),
        (CLLocationCoordinate2D(latitude: 40.7590, longitude: -73.9845), 90, 500),
        (CLLocationCoordinate2D(latitude: 40.7585, longitude: -73.9850), 150, 550),
        (CLLocationCoordinate2D(latitude: 40.7588, longitude: -73.9848), 220, 500),
        (CLLocationCoordinate2D(latitude: 40.7590, longitude: -73.9845), 300, 600),
    ]

    private init() {}

    /// Call once at app launch. Configures URLCache and snapshots all waypoints.
    func preload() {
        guard !isPreloading else { return }
        isPreloading = true

        // Expand URLCache so tiles persist across sessions (100MB disk)
        let cache = URLCache(
            memoryCapacity: 4 * 1024 * 1024,    // 4 MB memory
            diskCapacity: 100 * 1024 * 1024,     // 100 MB disk
            directory: nil
        )
        URLCache.shared = cache

        // Snapshot each waypoint at multiple zoom levels in the background
        DispatchQueue.global(qos: .utility).async { [waypoints] in
            for (coord, heading, distance) in waypoints {
                self.takeSnapshot(center: coord, distance: distance, heading: heading, pitch: 65)
                // Also snapshot a wider view (higher altitude) for the transition
                self.takeSnapshot(center: coord, distance: distance * 3, heading: heading, pitch: 30)
            }
        }
    }

    private func takeSnapshot(center: CLLocationCoordinate2D, distance: Double,
                               heading: Double, pitch: Double) {
        let options = MKMapSnapshotter.Options()
        options.camera = MKMapCamera(
            lookingAtCenter: center,
            fromDistance: distance,
            pitch: CGFloat(pitch),
            heading: heading
        )
        options.mapType = .satelliteFlyover
        options.size = CGSize(width: 256, height: 256) // Small = fast, just need tile fetch

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { _, _ in
            // We don't need the image — just forcing tile download into cache
        }
    }
}
