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

            // Camera is already at Cozy Hotel (set in makeUIView) — no jump needed.
            // Phase 1: Orbit Cozy Hotel
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let mapView = self?.mapView else { return }
                UIView.animate(withDuration: 2.0, delay: 0, options: .curveEaseInOut) {
                    mapView.camera = MKMapCamera(
                        lookingAtCenter: NYCMapView.cozyHotel,
                        fromDistance: 400, pitch: 65, heading: 220
                    )
                }
            }

            // Phase 2: Pull up heading south
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let mapView = self?.mapView else { return }
                let mid = CLLocationCoordinate2D(
                    latitude: (NYCMapView.cozyHotel.latitude + NYCMapView.timesSquare.latitude) / 2,
                    longitude: (NYCMapView.cozyHotel.longitude + NYCMapView.timesSquare.longitude) / 2
                )
                UIView.animate(withDuration: 4.0, delay: 0, options: .curveEaseInOut) {
                    mapView.camera = MKMapCamera(
                        lookingAtCenter: mid,
                        fromDistance: 3000, pitch: 50, heading: 200
                    )
                }
            }

            // Phase 3: Dive into Times Square
            DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) { [weak self] in
                guard let mapView = self?.mapView else { return }
                UIView.animate(withDuration: 4.0, delay: 0, options: .curveEaseInOut) {
                    mapView.camera = MKMapCamera(
                        lookingAtCenter: NYCMapView.timesSquare,
                        fromDistance: 500, pitch: 70, heading: 45
                    )
                }
            }

            // Phase 4: Orbit Times Square
            DispatchQueue.main.asyncAfter(deadline: .now() + 11.5) { [weak self] in
                self?.startOrbit(heading: 135)
            }
        }

        private func startOrbit(heading: Double) {
            guard let mapView else { return }
            UIView.animate(withDuration: 10.0, delay: 0, options: .curveEaseInOut) {
                mapView.camera = MKMapCamera(
                    lookingAtCenter: NYCMapView.timesSquare,
                    fromDistance: 500, pitch: 70, heading: heading
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                let next = heading + 90
                self?.startOrbit(heading: next >= 360 ? next - 360 : next)
            }
        }
    }
}

#Preview {
    NYCMapView()
}
