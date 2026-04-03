import SwiftUI
import MapKit

// MARK: - Phase 4: Programmatic MKMapView lifecycle (UIViewRepresentable)
// MKMapView is created/destroyed with the view lifecycle to prevent memory ballooning.

struct NYCMapView: UIViewRepresentable {

    // The International Cozy Inn — 248 Lenox Ave, Harlem
    static let cozyHotel = CLLocationCoordinate2D(latitude: 40.8012, longitude: -73.9440)
    // Times Square
    static let timesSquare = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.mapType = .satelliteFlyover
        mapView.isZoomEnabled = false
        mapView.isScrollEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsUserLocation = false
        mapView.delegate = context.coordinator

        // Phase 1: Attach cached tile overlay for faster re-loads
        let tileOverlay = CachedTileOverlay()
        tileOverlay.canReplaceMapContent = false // Supplement, don't replace
        mapView.addOverlay(tileOverlay, level: .aboveLabels)

        // Initial camera: Times Square overview (loads tiles while hidden behind globe)
        let initialCamera = MKMapCamera(
            lookingAtCenter: Self.timesSquare,
            fromDistance: 2000,
            pitch: 45,
            heading: 0
        )
        mapView.setCamera(initialCamera, animated: false)

        context.coordinator.mapView = mapView
        context.coordinator.scheduleJourney()

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        private var hasStartedJourney = false

        // Phase 1: Tile overlay renderer
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? CachedTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func scheduleJourney() {
            guard !hasStartedJourney else { return }
            hasStartedJourney = true

            // Give MapKit 1.5 seconds to load initial satellite tiles
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.startJourney()
            }
        }

        private func startJourney() {
            guard let mapView else { return }

            // Jump to Cozy Hotel
            let cozyCamera = MKMapCamera(
                lookingAtCenter: NYCMapView.cozyHotel,
                fromDistance: 400,
                pitch: 65,
                heading: 180
            )
            mapView.setCamera(cozyCamera, animated: false)

            // Phase 1: Orbit at Cozy Hotel (2s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let mapView = self?.mapView else { return }
                let orbitCamera = MKMapCamera(
                    lookingAtCenter: NYCMapView.cozyHotel,
                    fromDistance: 400,
                    pitch: 65,
                    heading: 220
                )
                UIView.animate(withDuration: 2.0, delay: 0, options: .curveEaseInOut) {
                    mapView.camera = orbitCamera
                }
            }

            // Phase 2: Pull up heading south (4s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let mapView = self?.mapView else { return }
                let midpoint = CLLocationCoordinate2D(
                    latitude: (NYCMapView.cozyHotel.latitude + NYCMapView.timesSquare.latitude) / 2,
                    longitude: (NYCMapView.cozyHotel.longitude + NYCMapView.timesSquare.longitude) / 2
                )
                let pullUpCamera = MKMapCamera(
                    lookingAtCenter: midpoint,
                    fromDistance: 3000,
                    pitch: 50,
                    heading: 200
                )
                UIView.animate(withDuration: 4.0, delay: 0, options: .curveEaseInOut) {
                    mapView.camera = pullUpCamera
                }
            }

            // Phase 3: Dive into Times Square (4s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) { [weak self] in
                guard let mapView = self?.mapView else { return }
                let tsCamera = MKMapCamera(
                    lookingAtCenter: NYCMapView.timesSquare,
                    fromDistance: 500,
                    pitch: 70,
                    heading: 45
                )
                UIView.animate(withDuration: 4.0, delay: 0, options: .curveEaseInOut) {
                    mapView.camera = tsCamera
                }
            }

            // Phase 4: Continuous orbit around Times Square
            DispatchQueue.main.asyncAfter(deadline: .now() + 11.5) { [weak self] in
                self?.startOrbit(heading: 135)
            }
        }

        private func startOrbit(heading: Double) {
            guard let mapView else { return }
            let orbitCamera = MKMapCamera(
                lookingAtCenter: NYCMapView.timesSquare,
                fromDistance: 500,
                pitch: 70,
                heading: heading
            )
            UIView.animate(withDuration: 10.0, delay: 0, options: .curveEaseInOut) {
                mapView.camera = orbitCamera
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                let next = heading + 90
                self?.startOrbit(heading: next >= 360 ? next - 360 : next)
            }
        }
    }
}
