import SwiftUI

// MARK: - Text phrases (each array = one screen, shown together)

private let phrases: [[String]] = [
    ["Discover"],
    ["the", "world"],
    ["around", "you"],
    ["explore", "every"],
    ["corner of", "the city"],
    ["with the app"],
    ["open"],
    ["Revamped"],
]

// MARK: - Kinetic Text View

struct KineticTextView: View {

    @State private var currentPhrase = 0
    @State private var lineVisible: [Bool] = []
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: -6) {
            if currentPhrase < phrases.count {
                ForEach(Array(lineVisible.enumerated()), id: \.offset) { index, visible in
                    if index < phrases[currentPhrase].count {
                        Text(phrases[currentPhrase][index])
                            .font(.custom("BricolageGrotesque72pt-ExtraBold",
                                          size: lineSize(for: phrases[currentPhrase][index])))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                            .multilineTextAlignment(.center)
                            .scaleEffect(visible ? 1.0 : 1.8)
                            .opacity(visible ? 1.0 : 0)
                            .offset(y: visible ? 0 : 40)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.75)
                                    .delay(Double(index) * 0.15),
                                value: visible
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !isRunning else { return }
            isRunning = true
            showPhrase(0)
        }
    }

    private func lineSize(for text: String) -> CGFloat {
        if text.count <= 4 { return 80 }
        if text.count <= 7 { return 64 }
        return 48
    }

    private func showPhrase(_ index: Int) {
        let idx = index % phrases.count
        currentPhrase = idx
        let count = phrases[idx].count

        // Reset all invisible
        lineVisible = Array(repeating: false, count: count)

        // Animate in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            lineVisible = Array(repeating: true, count: count)
        }

        // Hold, then animate out
        let holdTime = 1.5 + Double(count) * 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + holdTime) {
            lineVisible = Array(repeating: false, count: count)

            // Next phrase after exit animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showPhrase(index + 1)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.blue
        KineticTextView()
    }
}
