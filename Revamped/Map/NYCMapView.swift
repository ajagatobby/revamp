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

        deinit {
            displayLink?.invalidate()
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

            // Camera is already at Cozy Hotel (set in makeUIView).
            // Chain each phase off the previous completion — no overlaps, no gaps.

            // Phase 1: Orbit Cozy Hotel (ease-in start)
            UIView.animate(withDuration: 3.0, delay: 0.1, options: .curveEaseIn, animations: {
                mapView.camera = MKMapCamera(
                    lookingAtCenter: NYCMapView.cozyHotel,
                    fromDistance: 500, pitch: 60, heading: 240
                )
            }) { [weak self] _ in
                guard let mapView = self?.mapView else { return }

                // Phase 2: Pull up heading south (linear — no decel/accel stutter)
                UIView.animate(withDuration: 5.0, delay: 0, options: .curveLinear, animations: {
                    let mid = CLLocationCoordinate2D(
                        latitude: (NYCMapView.cozyHotel.latitude + NYCMapView.timesSquare.latitude) / 2,
                        longitude: (NYCMapView.cozyHotel.longitude + NYCMapView.timesSquare.longitude) / 2
                    )
                    mapView.camera = MKMapCamera(
                        lookingAtCenter: mid,
                        fromDistance: 2500, pitch: 50, heading: 210
                    )
                }) { [weak self] _ in
                    guard let mapView = self?.mapView else { return }

                    // Phase 3: Dive into Times Square (ease-out landing)
                    UIView.animate(withDuration: 5.0, delay: 0, options: .curveEaseOut, animations: {
                        mapView.camera = MKMapCamera(
                            lookingAtCenter: NYCMapView.timesSquare,
                            fromDistance: 500, pitch: 70, heading: 45
                        )
                    }) { [weak self] _ in
                        // Phase 4: Continuous orbit
                        self?.startOrbit(heading: 135)
                    }
                }
            }
        }

        // MARK: - Smooth orbit via CADisplayLink (no animation handoff glitches)

        private var displayLink: CADisplayLink?
        private var orbitHeading: Double = 45
        private let orbitSpeed: Double = 3.0 // degrees per second

        private func startOrbit(heading: Double) {
            orbitHeading = heading
            stopOrbit()

            let link = CADisplayLink(target: self, selector: #selector(orbitTick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopOrbit() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func orbitTick(_ link: CADisplayLink) {
            guard let mapView else { return }

            let dt = link.targetTimestamp - link.timestamp
            orbitHeading += orbitSpeed * dt

            // Keep in 0-360 range
            if orbitHeading >= 360 { orbitHeading -= 360 }

            // Direct camera property set — no animation, no handoff, perfectly smooth
            let camera = MKMapCamera(
                lookingAtCenter: NYCMapView.timesSquare,
                fromDistance: 500,
                pitch: 70,
                heading: orbitHeading
            )
            mapView.camera = camera
        }
    }
}

#Preview {
    NYCMapView()
}
