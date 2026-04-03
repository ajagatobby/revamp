import SwiftUI
import MapKit

struct NYCMapView: View {

    let cameraDistance: Double
    let cameraPitch: Double

    private let nycCenter = CLLocationCoordinate2D(
        latitude: 40.7837,
        longitude: -73.9663
    )

    var body: some View {
        Map(position: .constant(mapPosition), interactionModes: []) {
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControlVisibility(.hidden)
    }

    private var mapPosition: MapCameraPosition {
        .camera(MapCamera(
            centerCoordinate: nycCenter,
            distance: cameraDistance,
            heading: 45,
            pitch: cameraPitch
        ))
    }
}

#Preview {
    NYCMapView(cameraDistance: 1200, cameraPitch: 60)
}
