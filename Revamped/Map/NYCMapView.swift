import SwiftUI
import MapKit

struct NYCMapView: View {

    let cameraDistance: Double
    let cameraPitch: Double

    @State private var position: MapCameraPosition = .camera(MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 40.7590, longitude: -73.9845), // Broadway
        distance: 800,
        heading: 30,
        pitch: 65
    ))

    @State private var waypointIndex = 0
    @State private var isAnimating = false

    // Flyover route: Broadway → Times Square with intermediate points
    private static let waypoints: [(CLLocationCoordinate2D, Double, Double)] = [
        // (coordinate, heading, distance)
        // Start: Lower Broadway / Financial District
        (CLLocationCoordinate2D(latitude: 40.7074, longitude: -74.0113), 15, 600),
        // City Hall / Brooklyn Bridge area
        (CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), 20, 700),
        // SoHo
        (CLLocationCoordinate2D(latitude: 40.7233, longitude: -73.9985), 25, 750),
        // Union Square
        (CLLocationCoordinate2D(latitude: 40.7359, longitude: -73.9911), 30, 800),
        // Flatiron / Madison Square
        (CLLocationCoordinate2D(latitude: 40.7411, longitude: -73.9897), 32, 850),
        // Herald Square
        (CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9878), 35, 900),
        // Times Square
        (CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), 40, 700),
        // Times Square close-up, orbit
        (CLLocationCoordinate2D(latitude: 40.7590, longitude: -73.9845), 90, 500),
        // Times Square orbit continued
        (CLLocationCoordinate2D(latitude: 40.7585, longitude: -73.9850), 150, 550),
        // Full orbit
        (CLLocationCoordinate2D(latitude: 40.7588, longitude: -73.9848), 220, 500),
        // Reset heading, pull back slightly
        (CLLocationCoordinate2D(latitude: 40.7590, longitude: -73.9845), 300, 600),
        // Loop back to Broadway start
        (CLLocationCoordinate2D(latitude: 40.7074, longitude: -74.0113), 15, 600),
    ]

    var body: some View {
        Map(position: $position, interactionModes: []) {
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControlVisibility(.hidden)
        .onAppear {
            startFlyover()
        }
    }

    private func startFlyover() {
        guard !isAnimating else { return }
        isAnimating = true
        waypointIndex = 0
        flyToNextWaypoint()
    }

    private func flyToNextWaypoint() {
        let waypoints = Self.waypoints
        guard waypointIndex < waypoints.count else {
            // Loop: restart from beginning
            waypointIndex = 0
            flyToNextWaypoint()
            return
        }

        let (coord, heading, distance) = waypoints[waypointIndex]
        let camera = MapCamera(
            centerCoordinate: coord,
            distance: distance,
            heading: heading,
            pitch: 65
        )

        // Duration varies: longer for big moves, shorter for orbits
        let duration: Double = waypointIndex < 7 ? 6.0 : 4.0

        withAnimation(.easeInOut(duration: duration)) {
            position = .camera(camera)
        }

        waypointIndex += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            flyToNextWaypoint()
        }
    }
}

#Preview {
    NYCMapView(cameraDistance: 800, cameraPitch: 65)
}
