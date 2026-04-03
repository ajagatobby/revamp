import SwiftUI
import MapKit

struct NYCMapView: View {

    // The International Cozy Inn — 248 Lenox Ave, Harlem
    private let cozyHotel = CLLocationCoordinate2D(latitude: 40.8012, longitude: -73.9440)
    // Times Square
    private let timesSquare = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

    @State private var position: MapCameraPosition = .camera(MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 40.8012, longitude: -73.9440),
        distance: 300,
        heading: 180,
        pitch: 70
    ))

    @State private var journeyPhase = 0

    var body: some View {
        Map(position: $position, interactionModes: []) {
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControlVisibility(.hidden)
        .onAppear {
            startJourney()
        }
    }

    private func startJourney() {
        journeyPhase = 0

        // Phase 1: Show Cozy Hotel up close, slight orbit (2s)
        withAnimation(.easeInOut(duration: 2.0)) {
            position = .camera(MapCamera(
                centerCoordinate: cozyHotel,
                distance: 400,
                heading: 220,
                pitch: 65
            ))
        }

        // Phase 2: Pull up and start heading south toward Times Square (4s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let midpoint = CLLocationCoordinate2D(
                latitude: (cozyHotel.latitude + timesSquare.latitude) / 2,
                longitude: (cozyHotel.longitude + timesSquare.longitude) / 2
            )
            withAnimation(.easeInOut(duration: 4.0)) {
                position = .camera(MapCamera(
                    centerCoordinate: midpoint,
                    distance: 3000,
                    heading: 200,
                    pitch: 50
                ))
            }
        }

        // Phase 3: Dive into Times Square (4s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            withAnimation(.easeInOut(duration: 4.0)) {
                position = .camera(MapCamera(
                    centerCoordinate: timesSquare,
                    distance: 500,
                    heading: 45,
                    pitch: 70
                ))
            }
        }

        // Phase 4: Slow orbit around Times Square (continuous)
        DispatchQueue.main.asyncAfter(deadline: .now() + 11.5) {
            startOrbit(heading: 135)
        }
    }

    private func startOrbit(heading: Double) {
        withAnimation(.easeInOut(duration: 10.0)) {
            position = .camera(MapCamera(
                centerCoordinate: timesSquare,
                distance: 500,
                heading: heading,
                pitch: 70
            ))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            let next = heading + 90
            startOrbit(heading: next >= 360 ? next - 360 : next)
        }
    }
}

#Preview {
    NYCMapView()
}
