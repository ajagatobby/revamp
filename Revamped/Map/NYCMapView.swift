import SwiftUI
import MapKit

// MARK: - NYC Map with snapshot placeholder

struct NYCMapView: View {

    static let cozyHotel = CLLocationCoordinate2D(latitude: 40.8012, longitude: -73.9440)
    static let timesSquare = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

    // Cached snapshot shown instantly while MKMapView loads tiles
    @State private var placeholderImage: UIImage?
    @State private var tilesLoaded = false

    var body: some View {
        ZStack {
            // Live map (loads tiles in background)
            LiveMapView(onTilesLoaded: {
                withAnimation(.easeOut(duration: 0.5)) {
                    tilesLoaded = true
                }
            })

            // Snapshot placeholder — shown instantly, fades out when tiles ready
            if let placeholderImage, !tilesLoaded {
                Image(uiImage: placeholderImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Load cached snapshot (instant from memory/disk)
            placeholderImage = MapSnapshotCache.shared.snapshot(for: "nyc_initial")
            tilesLoaded = false
        }
    }
}

// MARK: - Live MKMapView (UIViewRepresentable)

private struct LiveMapView: UIViewRepresentable {

    var onTilesLoaded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTilesLoaded: onTilesLoaded)
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

        // Start at Cozy Hotel — same as journey start. No jump.
        let initialCamera = MKMapCamera(
            lookingAtCenter: NYCMapView.cozyHotel,
            fromDistance: 400,
            pitch: 65,
            heading: 180
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
        private var hasNotifiedTilesLoaded = false
        var onTilesLoaded: () -> Void

        init(onTilesLoaded: @escaping () -> Void) {
            self.onTilesLoaded = onTilesLoaded
        }

        deinit {}

        // Detect when tiles finish loading
        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            if fullyRendered && !hasNotifiedTilesLoaded {
                hasNotifiedTilesLoaded = true
                onTilesLoaded()
            }
        }

        func scheduleJourney() {
            guard !hasStartedJourney else { return }
            hasStartedJourney = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.startJourney()
            }
        }

        private func startJourney() {
            guard let mapView else { return }

            // Use MapKit's native flyTo for each waypoint — its internal
            // camera animator is the smoothest option on iOS.
            let waypoints: [(CLLocationCoordinate2D, Double, Double, Double, TimeInterval)] = [
                // (coordinate, distance, pitch, heading, duration)
                // Phase 1: Orbit at Cozy Hotel
                (NYCMapView.cozyHotel, 500, 60, 240, 3.0),
                // Phase 2: Pull up, head south
                (CLLocationCoordinate2D(latitude: 40.7796, longitude: -73.9648), 2500, 50, 210, 5.0),
                // Phase 3: Arrive Times Square
                (NYCMapView.timesSquare, 500, 70, 45, 5.0),
            ]

            flyToWaypoint(index: 0, waypoints: waypoints, mapView: mapView)
        }

        private func flyToWaypoint(index: Int,
                                    waypoints: [(CLLocationCoordinate2D, Double, Double, Double, TimeInterval)],
                                    mapView: MKMapView) {
            guard index < waypoints.count else {
                // Journey complete — start orbit
                startOrbit(mapView: mapView)
                return
            }

            let (coord, dist, pitch, heading, duration) = waypoints[index]
            let camera = MKMapCamera(
                lookingAtCenter: coord,
                fromDistance: dist,
                pitch: pitch,
                heading: heading
            )

            // MapKit's native animated camera transition — smoothest possible
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.curveLinear, .allowAnimatedContent],
                           animations: {
                mapView.setCamera(camera, animated: false)
            }) { [weak self] _ in
                self?.flyToWaypoint(index: index + 1, waypoints: waypoints, mapView: mapView)
            }
        }

        // MARK: - Orbit using a single long animation (no per-frame updates)

        private func startOrbit(mapView: MKMapView) {
            // Get current heading and animate a full 360° in one go
            let currentHeading = mapView.camera.heading
            orbitOnce(from: currentHeading, mapView: mapView)
        }

        private func orbitOnce(from heading: Double, mapView: MKMapView) {
            // Animate 180° at a time (MapKit interpolates shortest path,
            // so 360° would be a no-op). Two 180° segments = full rotation.
            let halfwayHeading = heading + 180
            let camera1 = MKMapCamera(
                lookingAtCenter: NYCMapView.timesSquare,
                fromDistance: 500, pitch: 70,
                heading: halfwayHeading.truncatingRemainder(dividingBy: 360)
            )

            UIView.animate(withDuration: 30, delay: 0,
                           options: [.curveLinear, .allowAnimatedContent],
                           animations: {
                mapView.setCamera(camera1, animated: false)
            }) { [weak self] _ in
                let nextHeading = halfwayHeading + 180
                let camera2 = MKMapCamera(
                    lookingAtCenter: NYCMapView.timesSquare,
                    fromDistance: 500, pitch: 70,
                    heading: nextHeading.truncatingRemainder(dividingBy: 360)
                )
                UIView.animate(withDuration: 30, delay: 0,
                               options: [.curveLinear, .allowAnimatedContent],
                               animations: {
                    mapView.setCamera(camera2, animated: false)
                }) { [weak self] _ in
                    self?.orbitOnce(from: nextHeading, mapView: mapView)
                }
            }
        }
    }
}

#Preview {
    NYCMapView()
}
