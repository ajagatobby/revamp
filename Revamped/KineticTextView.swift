import SwiftUI

// MARK: - Kinetic Typography (After Effects-style sequential text animation)

private let textSequence: [[String]] = [
    ["Discover"],
    ["the", "world"],
    ["around", "you"],
    ["explore", "every"],
    ["corner", "of"],
    ["the", "city"],
    ["with", "the", "app"],
    ["open"],
    ["Revamped"],
]

struct KineticTextView: View {

    @State private var currentIndex = 0
    @State private var wordStates: [WordState] = []
    @State private var isAnimating = false

    struct WordState: Identifiable {
        let id = UUID()
        let text: String
        let fontSize: CGFloat
        let delay: Double
        var visible: Bool = false
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(wordStates) { word in
                KineticWord(state: word)
            }
        }
        .onAppear {
            startSequence()
        }
    }

    private func startSequence() {
        guard !isAnimating else { return }
        isAnimating = true
        currentIndex = 0
        showNextPhrase()
    }

    private func showNextPhrase() {
        guard currentIndex < textSequence.count else {
            // Loop
            currentIndex = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showNextPhrase()
            }
            return
        }

        let words = textSequence[currentIndex]
        let isHero = words.count == 1 // Single word = hero treatment

        // Build word states with staggered delays and varied sizes
        var states: [WordState] = []
        for (i, word) in words.enumerated() {
            let size: CGFloat
            if isHero {
                size = CGFloat.random(in: 72...90)
            } else if word.count <= 3 {
                size = CGFloat.random(in: 42...54)
            } else {
                size = CGFloat.random(in: 54...72)
            }
            states.append(WordState(
                text: word,
                fontSize: size,
                delay: Double(i) * 0.12
            ))
        }

        // Set new words (invisible initially)
        wordStates = states

        // Animate in each word with stagger
        for (i, _) in states.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + states[i].delay) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    if i < wordStates.count {
                        wordStates[i].visible = true
                    }
                }
            }
        }

        // Hold, then animate out
        let holdDuration = 1.6 + Double(words.count) * 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
            // Animate out all at once
            for i in wordStates.indices {
                let exitDelay = Double(i) * 0.06
                DispatchQueue.main.asyncAfter(deadline: .now() + exitDelay) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        if i < wordStates.count {
                            wordStates[i].visible = false
                        }
                    }
                }
            }

            // Next phrase
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                currentIndex += 1
                showNextPhrase()
            }
        }
    }
}

// MARK: - Single Animated Word

private struct KineticWord: View {
    let state: KineticTextView.WordState

    // Random offsets for organic feel
    @State private var randomX: CGFloat = 0
    @State private var randomY: CGFloat = 0
    @State private var randomRotation: Double = 0

    var body: some View {
        Text(state.text)
            .font(.custom("BricolageGrotesque72pt-ExtraBold", size: state.fontSize))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            .shadow(color: .white.opacity(0.15), radius: 2, y: -1)
            .scaleEffect(state.visible ? 1.0 : 2.5)
            .opacity(state.visible ? 1.0 : 0)
            .offset(
                x: state.visible ? randomX : randomX + CGFloat.random(in: -80...80),
                y: state.visible ? randomY : randomY + 120
            )
            .rotationEffect(.degrees(state.visible ? 0 : randomRotation))
            .onAppear {
                randomX = CGFloat.random(in: -20...20)
                randomY = CGFloat.random(in: -40...40)
                randomRotation = Double.random(in: -8...8)
            }
    }
}

#Preview {
    ZStack {
        Color.blue
        KineticTextView()
    }
}
