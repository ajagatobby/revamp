import SwiftUI
import MapKit

struct NYCMapView: View {

    @State private var position: MapCameraPosition = .camera(MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855),
        distance: 40000,
        heading: 0,
        pitch: 0
    ))

    @State private var hasLanded = false

    // Times Square
    private let timesSquare = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

    var body: some View {
        Map(position: $position, interactionModes: []) {
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControlVisibility(.hidden)
        .onAppear {
            if !hasLanded {
                diveToTimesSquare()
            }
        }
    }

    private func diveToTimesSquare() {
        // Straight dive from high altitude to Times Square street level
        // No stops, no pauses — one continuous swoop
        withAnimation(.easeInOut(duration: 4.0)) {
            position = .camera(MapCamera(
                centerCoordinate: timesSquare,
                distance: 600,
                heading: 45,
                pitch: 70
            ))
        }

        // After landing, slow orbit around Times Square
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            hasLanded = true
            startOrbit()
        }
    }

    private func startOrbit() {
        orbitStep(heading: 135)
    }

    private func orbitStep(heading: Double) {
        withAnimation(.easeInOut(duration: 8.0)) {
            position = .camera(MapCamera(
                centerCoordinate: timesSquare,
                distance: 600,
                heading: heading,
                pitch: 70
            ))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            let nextHeading = heading + 90.0
            self.orbitStep(heading: nextHeading >= 360 ? nextHeading - 360 : nextHeading)
        }
    }
}

#Preview {
    NYCMapView()
}
