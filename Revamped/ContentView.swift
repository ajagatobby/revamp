import SwiftUI

struct ContentView: View {

    @State private var activeTextureIndex = 0
    @State private var zoom: Float = 3.0

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

            // --- Map layer (always mounted for preloading) ---
            NYCMapView(onArrivedTimesSquare: {
                SoundEngine.shared.playReveal()
                withAnimation(.easeIn(duration: 1.5)) {
                    showGradient = true
                }
            })
            .ignoresSafeArea()
            .opacity(transitionPhase == .map || transitionPhase == .zoomingIn ? 1 : 0)
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

            // --- Globe layer ---
            MetalGlobeView(activeTextureIndex: $activeTextureIndex, zoom: $zoom)
                .ignoresSafeArea()
                .scaleEffect(transitionPhase == .zoomingIn ? 1.5 : 1.0)
                .opacity(transitionPhase == .welcome ? 1.0 : 0.0)
                .allowsHitTesting(false)

            // --- Welcome overlay: Title + Button ---
            if transitionPhase == .welcome {
                VStack(spacing: 0) {
                    // Title
                    VStack(spacing: -12) {
                        Text("Planet")
                            .font(.custom("BricolageGrotesque72pt-ExtraBold", size: 72))
                            .foregroundStyle(.white)

                        Text("Earth")
                            .font(.custom("BricolageGrotesque72pt-ExtraBold", size: 72))
                            .foregroundStyle(Color(red: 0.35, green: 0.5, blue: 1.0))
                    }
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 20)
                    .padding(.top, 80)

                    Spacer()

                    // Get me in button
                    VStack(spacing: 16) {
                        Button {
                            getIn()
                        } label: {
                            Text("Get me in")
                                .font(.custom("BricolageGrotesque24pt-SemiBold", size: 18))
                                .foregroundStyle(.white)
                                .frame(width: 200, height: 54)
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
                    .padding(.bottom, 60)
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

        // Fade out title + button
        withAnimation(.easeIn(duration: 0.3)) {
            showTitle = false
            showButton = false
        }

        // Start zoom in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            zoom = 0.5
        }

        // Transition to map after zoom
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SoundEngine.shared.playWhoosh()
            withAnimation(.easeInOut(duration: 1.2)) {
                transitionPhase = .zoomingIn
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                SoundEngine.shared.playImpact()
                withAnimation(.easeOut(duration: 0.4)) {
                    transitionPhase = .map
                }
            }
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
