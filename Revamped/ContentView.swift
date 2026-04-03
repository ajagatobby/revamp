import SwiftUI

struct TextureItem: Identifiable {
    let id: Int
    let name: String
    let imageName: String
    let imageExt: String
    let icon: String
}

struct ContentView: View {

    @State private var activeTextureIndex = 0
    @State private var zoom: Float = 3.0
    @State private var showTextures = false

    private let minZoom: Float = 1.5
    private let maxZoom: Float = 8.0

    private let textures: [TextureItem] = [
        TextureItem(id: 1, name: "Day", imageName: "earth_daymap", imageExt: "jpg", icon: "sun.max.fill"),
        TextureItem(id: 2, name: "Night", imageName: "earth_nightmap", imageExt: "jpg", icon: "moon.stars.fill"),
        TextureItem(id: 3, name: "Normal", imageName: "earth_normal_map", imageExt: "tif", icon: "mountain.2.fill"),
        TextureItem(id: 4, name: "Specular", imageName: "earth_specular_map", imageExt: "tif", icon: "drop.fill"),
        TextureItem(id: 5, name: "Clouds", imageName: "earth_clouds", imageExt: "jpg", icon: "cloud.fill"),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MetalGlobeView(activeTextureIndex: $activeTextureIndex, zoom: $zoom)
                .ignoresSafeArea()

            // --- Left side: Zoom control ---
            VStack(spacing: 10) {
                Button {
                    zoom = max(zoom - 0.5, minZoom)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }

                ZoomSlider(value: $zoom, range: minZoom...maxZoom)
                    .frame(width: 36, height: 180)

                Button {
                    zoom = min(zoom + 0.5, maxZoom)
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
            VStack(spacing: 10) {
                // "All" button
                TextureThumbnail(
                    icon: "globe",
                    isSelected: activeTextureIndex == 0,
                    label: "All"
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        activeTextureIndex = 0
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))

                ForEach(Array(textures.enumerated()), id: \.element.id) { index, item in
                    TextureThumbnail(
                        imageName: item.imageName,
                        imageExt: item.imageExt,
                        icon: item.icon,
                        isSelected: activeTextureIndex == item.id,
                        label: item.name
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            activeTextureIndex = item.id
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
            }
            .padding(.trailing, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            // --- Bottom: Active texture label ---
            if activeTextureIndex > 0, let active = textures.first(where: { $0.id == activeTextureIndex }) {
                VStack(spacing: 6) {
                    Text(active.name.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .tracking(2)

                    Text("Texture Map")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: activeTextureIndex)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 40)
            }
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
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbY = fraction * trackHeight

            ZStack(alignment: .top) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)

                Capsule()
                    .fill(.white.opacity(0.5))
                    .frame(width: 4, height: max(4, thumbY + 6))

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
    var icon: String = "globe"
    let isSelected: Bool
    let label: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)

                    if let imageName, let imageExt,
                       let url = Bundle.main.url(forResource: imageName, withExtension: imageExt, subdirectory: "Textures")
                            ?? Bundle.main.url(forResource: imageName, withExtension: imageExt),
                       let data = try? Data(contentsOf: url),
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    // Selected overlay
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.blue.opacity(0.15))
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ? Color.blue : Color.white.opacity(0.2),
                            lineWidth: isSelected ? 2.5 : 0.5
                        )
                )
                .shadow(color: isSelected ? .blue.opacity(0.4) : .clear, radius: 8, y: 2)
                .scaleEffect(isSelected ? 1.12 : (isPressed ? 0.92 : 1.0))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)

                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
        }
        .buttonStyle(ThumbnailButtonStyle(isPressed: $isPressed))
    }
}

// MARK: - Custom Button Style for Press Animation

struct ThumbnailButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

#Preview {
    ContentView()
}
