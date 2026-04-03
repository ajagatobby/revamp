import SwiftUI
import UIKit

// MARK: - Preloaded thumbnail cache (load once, not every frame)

private let thumbnailCache: [String: UIImage] = {
    var cache = [String: UIImage]()
    let items: [(String, String)] = [
        ("earth_daymap", "jpg"),
        ("earth_nightmap", "jpg"),
        ("earth_normal_map", "tif"),
        ("earth_specular_map", "tif"),
        ("earth_clouds", "jpg"),
    ]
    for (name, ext) in items {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Textures")
            ?? Bundle.main.url(forResource: name, withExtension: ext),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            cache[name] = image
        }
    }
    return cache
}()

// MARK: - Data

struct TextureItem: Identifiable {
    let id: Int
    let name: String
    let imageName: String
    let icon: String
}

private let allTextures: [TextureItem] = [
    TextureItem(id: 1, name: "Day", imageName: "earth_daymap", icon: "sun.max.fill"),
    TextureItem(id: 2, name: "Night", imageName: "earth_nightmap", icon: "moon.stars.fill"),
    TextureItem(id: 3, name: "Normal", imageName: "earth_normal_map", icon: "mountain.2.fill"),
    TextureItem(id: 4, name: "Specular", imageName: "earth_specular_map", icon: "drop.fill"),
    TextureItem(id: 5, name: "Clouds", imageName: "earth_clouds", icon: "cloud.fill"),
]

// MARK: - Content View

struct ContentView: View {

    @State private var activeTextureIndex = 0
    @State private var zoom: Float = 3.0

    private let minZoom: Float = 1.5
    private let maxZoom: Float = 8.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MetalGlobeView(activeTextureIndex: $activeTextureIndex, zoom: $zoom)
                .ignoresSafeArea()

            // Zoom controls — left
            zoomControls
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 16)

            // Texture selector — right
            textureSelector
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 16)

            // Active label — bottom
            activeLabel
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 40)
        }
        .animation(.snappy(duration: 0.3), value: activeTextureIndex)
    }

    // MARK: - Zoom Controls

    private var zoomControls: some View {
        VStack(spacing: 10) {
            Button { zoom = max(zoom - 0.5, minZoom) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1), in: Circle())
            }

            ZoomSlider(value: $zoom, range: minZoom...maxZoom)
                .frame(width: 36, height: 180)

            Button { zoom = min(zoom + 0.5, maxZoom) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
        }
    }

    // MARK: - Texture Selector

    private var textureSelector: some View {
        VStack(spacing: 10) {
            TextureThumbnail(
                isSelected: activeTextureIndex == 0,
                label: "All"
            ) {
                activeTextureIndex = 0
            }

            ForEach(allTextures) { item in
                TextureThumbnail(
                    image: thumbnailCache[item.imageName],
                    isSelected: activeTextureIndex == item.id,
                    label: item.name
                ) {
                    activeTextureIndex = item.id
                }
            }
        }
    }

    // MARK: - Active Label

    @ViewBuilder
    private var activeLabel: some View {
        if activeTextureIndex > 0,
           let active = allTextures.first(where: { $0.id == activeTextureIndex }) {
            Text(active.name.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .tracking(2)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: Capsule())
                .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }
}

// MARK: - Zoom Slider

struct ZoomSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geo in
            let trackHeight = geo.size.height - 12
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbY = fraction * trackHeight

            ZStack(alignment: .top) {
                Capsule()
                    .fill(.white.opacity(0.12))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .offset(y: thumbY)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let clamped = min(max(drag.location.y - 6, 0), trackHeight)
                        value = range.lowerBound + Float(clamped / trackHeight) * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}

// MARK: - Texture Thumbnail (GPU-friendly, no material blur)

struct TextureThumbnail: View {
    var image: UIImage? = nil
    let isSelected: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                thumbnailImage
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isSelected ? Color.blue : Color.white.opacity(0.15),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    )
                    .shadow(color: isSelected ? .blue.opacity(0.35) : .clear, radius: 6)
                    .scaleEffect(isSelected ? 1.08 : 1.0)

                Text(label)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.5))
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.white.opacity(0.06)
                Image(systemName: "globe")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

// MARK: - Performant Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
