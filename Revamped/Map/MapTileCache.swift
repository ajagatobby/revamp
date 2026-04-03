import MapKit
import UIKit

// MARK: - Snapshot Cache (memory + disk backed)
// Shows a cached static image instantly while live MKMapView loads tiles behind it.

final class MapSnapshotCache {
    static let shared = MapSnapshotCache()

    // Memory cache for instant access
    private let memoryCache = NSCache<NSString, UIImage>()
    // Disk directory for persistence across app launches
    private let diskDirectory: URL?

    private init() {
        memoryCache.countLimit = 10
        memoryCache.totalCostLimit = 20 * 1024 * 1024 // 20 MB

        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        diskDirectory = paths.first?.appendingPathComponent("MapSnapshots", isDirectory: true)
        if let dir = diskDirectory {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Read (memory → disk → nil)

    func snapshot(for key: String) -> UIImage? {
        // Check memory first
        if let img = memoryCache.object(forKey: key as NSString) {
            return img
        }
        // Check disk
        if let diskURL = diskURL(for: key),
           let data = try? Data(contentsOf: diskURL),
           let img = UIImage(data: data) {
            memoryCache.setObject(img, forKey: key as NSString)
            return img
        }
        return nil
    }

    // MARK: - Generate (check cache → generate → save to both)

    func generateSnapshot(center: CLLocationCoordinate2D,
                          distance: Double,
                          heading: Double,
                          pitch: Double,
                          size: CGSize,
                          key: String,
                          completion: @escaping (UIImage?) -> Void) {
        // Already cached? Return immediately.
        if let cached = snapshot(for: key) {
            completion(cached)
            return
        }

        let options = MKMapSnapshotter.Options()
        options.camera = MKMapCamera(
            lookingAtCenter: center,
            fromDistance: distance,
            pitch: CGFloat(pitch),
            heading: heading
        )
        options.mapType = .satelliteFlyover
        options.size = size

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start(with: .global(qos: .userInitiated)) { [weak self] snapshot, error in
            guard let image = snapshot?.image else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // Save to memory cache
            self?.memoryCache.setObject(image, forKey: key as NSString)
            // Save to disk cache (JPEG for smaller size)
            if let diskURL = self?.diskURL(for: key),
               let jpegData = image.jpegData(compressionQuality: 0.85) {
                try? jpegData.write(to: diskURL)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    // MARK: - Pre-warm (fire and forget, populates cache for later)

    func prewarm(center: CLLocationCoordinate2D, distance: Double,
                 heading: Double, pitch: Double, key: String) {
        // Skip if already cached
        if snapshot(for: key) != nil { return }

        generateSnapshot(center: center, distance: distance,
                         heading: heading, pitch: pitch,
                         size: CGSize(width: 400, height: 800),
                         key: key) { _ in }
    }

    private func diskURL(for key: String) -> URL? {
        diskDirectory?.appendingPathComponent("\(key).jpg")
    }
}
