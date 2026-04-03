import MapKit
import UIKit

// MARK: - Snapshot Cache (for non-interactive map previews)

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
