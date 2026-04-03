import MapKit
import UIKit

// MARK: - Phase 1: Cached Tile Overlay (disk-backed LRU cache)

final class CachedTileOverlay: MKTileOverlay {

    private let cache = URLCache(
        memoryCapacity: 8 * 1024 * 1024,    // 8 MB memory
        diskCapacity: 150 * 1024 * 1024,     // 150 MB disk
        directory: CachedTileOverlay.cacheDirectory
    )

    private static var cacheDirectory: URL? = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths.first?.appendingPathComponent("MapTileCache", isDirectory: true)
    }()

    override func loadTile(at path: MKTileOverlayPath,
                           result: @escaping (Data?, Error?) -> Void) {
        let tileURL = url(forTilePath: path)
        let request = URLRequest(url: tileURL)

        // Check disk cache first
        if let cachedResponse = cache.cachedResponse(for: request) {
            result(cachedResponse.data, nil)
            return
        }

        // Cache miss — download and save
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let data = data, let response = response {
                let cachedResp = CachedURLResponse(response: response, data: data)
                self?.cache.storeCachedResponse(cachedResp, for: request)
                result(data, nil)
            } else {
                result(nil, error)
            }
        }
        task.resume()
    }
}

// MARK: - Phase 2: Snapshot Cache (for non-interactive map previews)

final class MapSnapshotCache {
    static let shared = MapSnapshotCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 20
        cache.totalCostLimit = 30 * 1024 * 1024 // 30 MB
    }

    func snapshot(for key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }

    func generateSnapshot(center: CLLocationCoordinate2D,
                          distance: Double,
                          heading: Double,
                          pitch: Double,
                          size: CGSize,
                          key: String,
                          completion: @escaping (UIImage?) -> Void) {
        // Check cache first
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
            self?.cache.setObject(image, forKey: key as NSString,
                                  cost: image.pngData()?.count ?? 0)
            DispatchQueue.main.async { completion(image) }
        }
    }
}
