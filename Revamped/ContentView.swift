import SwiftUI

struct TextureItem: Identifiable {
    let id: Int
    let name: String
    let imageName: String
    let imageExt: String
}

struct ContentView: View {

    @State private var activeTextureIndex = 0
    @State private var zoom: Float = 3.0

    private let minZoom: Float = 1.5
    private let maxZoom: Float = 8.0

    private let textures: [TextureItem] = [
        TextureItem(id: 1, name: "Day", imageName: "earth_daymap", imageExt: "jpg"),
        TextureItem(id: 2, name: "Night", imageName: "earth_nightmap", imageExt: "jpg"),
        TextureItem(id: 3, name: "Normal", imageName: "earth_normal_map", imageExt: "tif"),
        TextureItem(id: 4, name: "Specular", imageName: "earth_specular_map", imageExt: "tif"),
        TextureItem(id: 5, name: "Clouds", imageName: "earth_clouds", imageExt: "jpg"),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MetalGlobeView(activeTextureIndex: $activeTextureIndex, zoom: $zoom)
                .ignoresSafeArea()

            // --- Left side: Zoom control ---
            VStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        zoom = max(zoom - 0.5, minZoom)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }

                // Vertical zoom slider
                ZoomSlider(value: $zoom, range: minZoom...maxZoom)
                    .frame(width: 36, height: 180)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        zoom = min(zoom + 0.5, maxZoom)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            // --- Right side: Texture selector ---
            VStack(spacing: 12) {
                TextureThumbnail(
                    isSelected: activeTextureIndex == 0,
                    label: "All"
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        activeTextureIndex = 0
                    }
                }

                ForEach(textures) { item in
                    TextureThumbnail(
                        imageName: item.imageName,
                        imageExt: item.imageExt,
                        isSelected: activeTextureIndex == item.id,
                        label: item.name
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            activeTextureIndex = item.id
                        }
                    }
                }
            }
            .padding(.trailing, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Zoom Slider (Vertical)

struct ZoomSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geo in
            let trackHeight = geo.size.height - 12
            // Invert: top = zoomed in (min value), bottom = zoomed out (max value)
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbY = fraction * trackHeight

            ZStack(alignment: .top) {
                // Track background
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)

                // Active track
                Capsule()
                    .fill(.white.opacity(0.5))
                    .frame(width: 4, height: max(4, thumbY + 6))

                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .offset(y: thumbY)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let clamped = min(max(drag.location.y - 6, 0), trackHeight)
                        let newFraction = Float(clamped / trackHeight)
                        value = range.lowerBound + newFraction * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}

// MARK: - Texture Thumbnail

struct TextureThumbnail: View {
    var imageName: String? = nil
    var imageExt: String? = nil
    let isSelected: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if let imageName, let imageExt,
                       let url = Bundle.main.url(forResource: imageName, withExtension: imageExt, subdirectory: "Textures")
                            ?? Bundle.main.url(forResource: imageName, withExtension: imageExt),
                       let data = try? Data(contentsOf: url),
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.blue : Color.white.opacity(0.3),
                                lineWidth: isSelected ? 2.5 : 1)
                )
                .shadow(color: isSelected ? .blue.opacity(0.5) : .clear, radius: 6)
                .scaleEffect(isSelected ? 1.1 : 1.0)

                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
