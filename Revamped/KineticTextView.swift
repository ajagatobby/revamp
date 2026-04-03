import SwiftUI

// MARK: - Phrases + entrance style per phrase

private struct Phrase {
    let words: [String]
    let style: EntryStyle
    let alignment: HorizontalAlignment
}

private enum EntryStyle {
    case scaleUp
    case slideLeft
    case slideRight
    case slideUp
    case dropDown
    case expand
}

private let phrases: [Phrase] = [
    Phrase(words: ["Discover"], style: .scaleUp, alignment: .center),
    Phrase(words: ["the", "world"], style: .slideLeft, alignment: .trailing),
    Phrase(words: ["around", "you"], style: .slideRight, alignment: .leading),
    Phrase(words: ["explore", "every"], style: .dropDown, alignment: .center),
    Phrase(words: ["corner", "of", "the", "city"], style: .slideUp, alignment: .trailing),
    Phrase(words: ["with", "the", "app"], style: .expand, alignment: .center),
    Phrase(words: ["open"], style: .scaleUp, alignment: .leading),
    Phrase(words: ["Revamped"], style: .dropDown, alignment: .center),
]

// MARK: - Kinetic Text View

struct KineticTextView: View {

    @State private var currentPhrase = 0
    @State private var wordVisible: [Bool] = []
    @State private var isRunning = false

    var body: some View {
        // Wrap words in lines using FlowLayout-style approach
        WrappingHStack(alignment: currentAlignment) {
            if currentPhrase < phrases.count {
                let phrase = phrases[currentPhrase]
                ForEach(Array(wordVisible.enumerated()), id: \.offset) { index, visible in
                    if index < phrase.words.count {
                        Text(phrase.words[index])
                            .font(.custom("BricolageGrotesque72pt-ExtraBold",
                                          size: wordSize(for: phrase.words[index])))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                            .modifier(EntryAnimationModifier(
                                style: phrase.style,
                                visible: visible,
                                index: index
                            ))
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !isRunning else { return }
            isRunning = true
            showPhrase(0)
        }
    }

    private var currentAlignment: HorizontalAlignment {
        guard currentPhrase < phrases.count else { return .center }
        return phrases[currentPhrase].alignment
    }

    private func wordSize(for text: String) -> CGFloat {
        if text.count <= 3 { return 90 }
        if text.count <= 5 { return 100 }
        if text.count <= 7 { return 90 }
        return 64
    }

    private func showPhrase(_ index: Int) {
        let idx = index % phrases.count
        currentPhrase = idx
        let count = phrases[idx].words.count

        wordVisible = Array(repeating: false, count: count)

        // Stagger each word entrance with pop sound
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                if i < wordVisible.count {
                    SoundEngine.shared.playPop()
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                        wordVisible[i] = true
                    }
                }
            }
        }

        // Hold, then stagger exit each word
        let holdTime = 1.6 + Double(count) * 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + holdTime) {
            for i in 0..<wordVisible.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                    if i < wordVisible.count {
                        withAnimation(.easeIn(duration: 0.25)) {
                            wordVisible[i] = false
                        }
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showPhrase(index + 1)
            }
        }
    }
}

// MARK: - Wrapping HStack (words wrap to next line like text)

private struct WrappingHStack<Content: View>: View {
    let alignment: HorizontalAlignment
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: alignment, spacing: -8) {
            content()
                .fixedSize(horizontal: true, vertical: true)
        }
    }
}

// MARK: - Entry Animation Modifier

private struct EntryAnimationModifier: ViewModifier {
    let style: EntryStyle
    let visible: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .scaleEffect(scaleValue)
            .opacity(visible ? 1 : 0)
            .offset(x: offsetX, y: offsetY)
            .rotationEffect(.degrees(rotationValue))
    }

    private var scaleValue: CGFloat {
        guard !visible else { return 1 }
        switch style {
        case .scaleUp: return 2.2
        case .expand: return 0.1
        case .dropDown: return 1.3
        default: return 1
        }
    }

    private var offsetX: CGFloat {
        guard !visible else { return 0 }
        let stagger = CGFloat(index) * 30
        switch style {
        case .slideLeft: return 250 + stagger
        case .slideRight: return -250 - stagger
        default: return 0
        }
    }

    private var offsetY: CGFloat {
        guard !visible else { return 0 }
        let stagger = CGFloat(index) * 20
        switch style {
        case .slideUp: return 180 + stagger
        case .dropDown: return -180 - stagger
        case .scaleUp: return 30 + stagger
        case .expand: return 20
        default: return 0
        }
    }

    private var rotationValue: Double {
        guard !visible else { return 0 }
        switch style {
        case .expand: return Double(-12 + index * 6)
        case .slideLeft: return Double(3 + index * 2)
        case .slideRight: return Double(-3 - index * 2)
        case .dropDown: return Double(index % 2 == 0 ? 4 : -4)
        default: return 0
        }
    }
}

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()
        KineticTextView()
    }
}
