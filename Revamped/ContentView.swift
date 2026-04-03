import SwiftUI
import UIKit

// MARK: - Preloaded thumbnail cache

// Thumbnails loaded at 128x64 (not full 4K!) for minimal memory + fast load
private let thumbnailCache: [String: UIImage] = {
    var cache = [String: UIImage]()
    let thumbSize = CGSize(width: 128, height: 64)
    for (name, ext) in [
        ("earth_daymap", "jpg"), ("earth_nightmap", "jpg"),
        ("earth_normal_map", "tif"), ("earth_specular_map", "tif"),
        ("earth_clouds", "jpg"),
    ] {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Textures")
            ?? Bundle.main.url(forResource: name, withExtension: ext),
           let data = try? Data(contentsOf: url),
           let fullImg = UIImage(data: data) {
            // Downscale to thumbnail size
            let renderer = UIGraphicsImageRenderer(size: thumbSize)
            let thumb = renderer.image { _ in
                fullImg.draw(in: CGRect(origin: .zero, size: thumbSize))
            }
            cache[name] = thumb
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

// MARK: - Liquid spring

private let liquidSpring = Animation.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.1)

// MARK: - Content View

struct ContentView: View {

    @State private var activeTextureIndex = 0
    @State private var zoom: Float = 5.0 // Start far away (small globe)
    @Namespace private var selectionNamespace

    private let minZoom: Float = 0.5
    private let maxZoom: Float = 5.0

    // Transition threshold — auto-trigger when zoom hits this
    private let transitionThreshold: Float = 0.7

    // Globe vs map mode
    @State private var transitionPhase: TransitionPhase = .globe
    @State private var hasAutoTriggered = false

    enum TransitionPhase {
        case globe
        case zoomingIn   // Globe scaling + blur → flash
        case map         // 3D NYC map
        case zoomingOut  // Map fading → globe returns
    }

    private var isInMap: Bool { transitionPhase == .map }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // --- Map layer (always mounted for preloading) ---
            NYCMapView()
                .ignoresSafeArea()
                .opacity(isInMap ? 1 : 0)
                .scaleEffect(transitionPhase == .zoomingOut ? 0.8 : 1.0)
                .allowsHitTesting(isInMap)

            // --- Globe layer ---
            if transitionPhase != .map {
                MetalGlobeView(activeTextureIndex: $activeTextureIndex, zoom: $zoom)
                    .ignoresSafeArea()
                    .scaleEffect(transitionPhase == .zoomingIn ? 3.0 : 1.0)
                    .blur(radius: transitionPhase == .zoomingIn ? 30 : 0)
                    .opacity(transitionPhase == .zoomingIn ? 0 : 1)
                    .allowsHitTesting(transitionPhase == .globe)
            }

            // --- White flash ---
            Color.white
                .ignoresSafeArea()
                .opacity(transitionPhase == .zoomingIn ? 0.6 : 0)
                .allowsHitTesting(false)

            // --- Controls ---
            zoomControls
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 16)

            textureSelector
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 14)
                .opacity(isInMap ? 0 : 1)
                .allowsHitTesting(!isInMap)

            activeTag
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 44)
                .opacity(isInMap ? 0 : 1)

            // --- Back to globe button (map mode only) ---
            if isInMap {
                Button {
                    triggerTransitionToGlobe()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 13))
                        Text("Back to Globe")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.15), in: Capsule())
                }
                .transition(.scale.combined(with: .opacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 60)
                .padding(.leading, 16)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isInMap)
        .onChange(of: zoom) { _, newZoom in
            // Auto-transition to map when zoom hits threshold
            if newZoom <= transitionThreshold && transitionPhase == .globe && !hasAutoTriggered {
                hasAutoTriggered = true
                triggerTransitionToMap()
            }
        }
    }

    private func triggerTransitionToMap() {
        withAnimation(.easeIn(duration: 0.5)) {
            transitionPhase = .zoomingIn
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.6)) {
                transitionPhase = .map
            }
        }
    }

    private func triggerTransitionToGlobe() {
        withAnimation(.easeIn(duration: 0.4)) {
            transitionPhase = .zoomingOut
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.5)) {
                transitionPhase = .globe
                zoom = 2.0
            }
        }
    }

    // MARK: - Zoom

    private var zoomControls: some View {
        VStack(spacing: 10) {
            Button { zoom = max(zoom - 0.5, minZoom) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.08), in: Circle())
            }

            ZoomSlider(value: $zoom, range: minZoom...maxZoom)
                .frame(width: 34, height: 170)

            Button { zoom = min(zoom + 0.5, maxZoom) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
        }
    }

    // MARK: - Texture Selector with Liquid Selection Indicator

    private var textureSelector: some View {
        VStack(spacing: 8) {
            // "All" button
            thumbnailButton(id: 0, label: "All", image: nil, icon: "globe")

            ForEach(allTextures) { item in
                thumbnailButton(
                    id: item.id,
                    label: item.name,
                    image: thumbnailCache[item.imageName],
                    icon: item.icon
                )
            }
        }
    }

    private func thumbnailButton(id: Int, label: String, image: UIImage?, icon: String) -> some View {
        let selected = activeTextureIndex == id
        return Button {
            withAnimation(liquidSpring) {
                activeTextureIndex = id
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    // Liquid selection background — morphs between items
                    if selected {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(.blue.opacity(0.2))
                            .matchedGeometryEffect(id: "selection_bg", in: selectionNamespace)

                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(Color.blue.opacity(0.7), lineWidth: 2)
                            .matchedGeometryEffect(id: "selection_border", in: selectionNamespace)
                    }

                    // Thumbnail content
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(selected ? 1.0 : 0.6))
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(
                            Color.white.opacity(selected ? 0 : 0.12),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: selected ? .blue.opacity(0.3) : .clear, radius: 8, y: 2)
                .scaleEffect(selected ? 1.06 : 1.0)

                Text(label)
                    .font(.system(size: 9, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.45))
            }
        }
        .buttonStyle(LiquidButtonStyle())
    }

    // MARK: - Active Tag (Fluid morph)

    @ViewBuilder
    private var activeTag: some View {
        let activeName = activeTextureIndex == 0
            ? "All Layers"
            : (allTextures.first { $0.id == activeTextureIndex }?.name ?? "")

        HStack(spacing: 6) {
            Circle()
                .fill(.blue)
                .frame(width: 6, height: 6)

            Text(activeName.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .tracking(1.5)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .animation(liquidSpring, value: activeTextureIndex)
    }
}

// MARK: - Liquid Button Style

struct LiquidButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Zoom Slider

struct ZoomSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geo in
            let trackH = geo.size.height - 10
            let frac = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbY = frac * trackH

            ZStack(alignment: .top) {
                Capsule()
                    .fill(.white.opacity(0.1))
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
                        let clamped = min(max(drag.location.y - 5, 0), trackH)
                        value = range.lowerBound + Float(clamped / trackH) * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}

#Preview {
    ContentView()
}
