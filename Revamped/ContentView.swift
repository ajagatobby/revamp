import SwiftUI

struct ContentView: View {

    @State private var activeTextureIndex = 0
    @State private var zoom: Float = 4.2
    @State private var mapOpacity: Double = 0

    // Phases
    @State private var transitionPhase: TransitionPhase = .welcome
    @State private var showGradient = false
    @State private var showTitle = false
    @State private var showButton = false

    enum TransitionPhase {
        case welcome     // Globe + title + button
        case zoomingIn   // Globe scales + fades → map fades in
        case map         // 3D NYC map
    }

    private var isInMap: Bool { transitionPhase == .map }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // --- Globe layer (bottom — always visible until map fully covers it) ---
            MetalGlobeView(activeTextureIndex: $activeTextureIndex, zoom: $zoom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // --- Map layer (fades in ON TOP of globe — creates morph effect) ---
            NYCMapView(onArrivedTimesSquare: {
                SoundEngine.shared.playReveal()
                withAnimation(.easeIn(duration: 1.5)) {
                    showGradient = true
                }
            })
            .ignoresSafeArea()
            .opacity(mapOpacity)
            .allowsHitTesting(isInMap)

            // --- Gradient overlay ---
            if showGradient {
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.1, green: 0.2, blue: 1.0).opacity(0.9), location: 0),
                        .init(color: Color(red: 0.15, green: 0.3, blue: 1.0).opacity(0.75), location: 0.35),
                        .init(color: Color(red: 0.2, green: 0.4, blue: 1.0).opacity(0.5), location: 0.6),
                        .init(color: Color(red: 0.25, green: 0.45, blue: 0.95).opacity(0.25), location: 0.8),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)

                KineticTextView()
                    .allowsHitTesting(false)
            }

            // --- Welcome overlay: Title + Button ---
            if transitionPhase == .welcome {
                VStack {
                    // Title at the top
                    VStack(spacing: -16) {
                        Text("Planet")
                            .font(.custom("BricolageGrotesque72pt-ExtraBold", size: 86))
                            .foregroundStyle(.white)

                        Text("Earth")
                            .font(.custom("BricolageGrotesque72pt-ExtraBold", size: 86))
                            .foregroundStyle(Color(red: 0.35, green: 0.5, blue: 1.0))
                    }
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 20)
                    .padding(.top, 70)

                    Spacer()

                    // Get me in button at the bottom
                    VStack(spacing: 16) {
                        Button {
                            getIn()
                        } label: {
                            Text("Get me in")
                                .font(.custom("BricolageGrotesque24pt-SemiBold", size: 18))
                                .foregroundStyle(.white)
                                .frame(width: 220, height: 56)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.35, green: 0.4, blue: 1.0),
                                                    Color(red: 0.25, green: 0.3, blue: 0.95),
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .shadow(color: Color(red: 0.3, green: 0.35, blue: 1.0).opacity(0.5),
                                                radius: 20, y: 8)
                                )
                        }
                        .buttonStyle(GetInButtonStyle())

                        Text("By tapping \"Get me in\" you're accepting the terms.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .opacity(showButton ? 1 : 0)
                    .offset(y: showButton ? 0 : 30)
                    .padding(.bottom, 50)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            SoundEngine.shared.startAmbient()
            // Animate title + button in
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                showTitle = true
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.6)) {
                showButton = true
            }
        }
    }

    private func getIn() {
        SoundEngine.shared.playSwoosh()

        // 1. Fade out title + button immediately
        withAnimation(.easeIn(duration: 0.3)) {
            showTitle = false
            showButton = false
        }

        // 2. Zoom globe in hard (4.2 → 0.5 = fills screen)
        zoom = 0.5

        // 3. While globe is zooming in, start fading map in on top
        //    Globe is still underneath — they blend together = morph
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            SoundEngine.shared.playWhoosh()
            withAnimation(.easeIn(duration: 2.0)) {
                mapOpacity = 1.0
            }
        }

        // 4. Once map is fully visible, mark as map phase
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            SoundEngine.shared.playImpact()
            transitionPhase = .map
        }
    }
}

// MARK: - Button Style

private struct GetInButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
