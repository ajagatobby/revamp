import MapKit

/// Pre-warms MapKit's tile cache by taking snapshots of every waypoint
/// along the NYC flyover route. Snapshots force tile downloads even
/// off-screen. Tiles persist in URLCache across app sessions.
final class MapPreloader {

    static let shared = MapPreloader()
    private var isPreloading = false

    // Cozy Hotel → Times Square journey waypoints for preloading
    private let waypoints: [(CLLocationCoordinate2D, Double, Double)] = [
        // Cozy Hotel (248 Lenox Ave, Harlem)
        (CLLocationCoordinate2D(latitude: 40.8012, longitude: -73.9440), 180, 400),
        (CLLocationCoordinate2D(latitude: 40.8012, longitude: -73.9440), 220, 300),
        // Midpoint (pull-up view)
        (CLLocationCoordinate2D(latitude: 40.7796, longitude: -73.9648), 200, 3000),
        // Times Square approach
        (CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), 45, 500),
        // Times Square orbit angles
        (CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), 135, 500),
        (CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), 225, 500),
        (CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), 315, 500),
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
