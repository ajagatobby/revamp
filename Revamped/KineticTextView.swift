import SwiftUI

// MARK: - Phrases + entrance style per phrase

private struct Phrase {
    let lines: [String]
    let style: EntryStyle
    let alignment: HorizontalAlignment
}

private enum EntryStyle {
    case scaleUp       // Scale from huge + fade in
    case slideLeft     // Slide from right
    case slideRight    // Slide from left
    case slideUp       // Slide from bottom
    case dropDown      // Drop from above with bounce
    case expand        // Scale from 0 + rotate
}

private let phrases: [Phrase] = [
    Phrase(lines: ["Discover"], style: .scaleUp, alignment: .center),
    Phrase(lines: ["the", "world"], style: .slideLeft, alignment: .trailing),
    Phrase(lines: ["around", "you"], style: .slideRight, alignment: .leading),
    Phrase(lines: ["explore", "every"], style: .dropDown, alignment: .center),
    Phrase(lines: ["corner of", "the city"], style: .slideUp, alignment: .trailing),
    Phrase(lines: ["with the app"], style: .expand, alignment: .center),
    Phrase(lines: ["open"], style: .scaleUp, alignment: .leading),
    Phrase(lines: ["Revamped"], style: .dropDown, alignment: .center),
]

// MARK: - Kinetic Text View

struct KineticTextView: View {

    @State private var currentPhrase = 0
    @State private var lineVisible: [Bool] = []
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: currentAlignment, spacing: -8) {
            if currentPhrase < phrases.count {
                let phrase = phrases[currentPhrase]
                ForEach(Array(lineVisible.enumerated()), id: \.offset) { index, visible in
                    if index < phrase.lines.count {
                        Text(phrase.lines[index])
                            .font(.custom("BricolageGrotesque72pt-ExtraBold",
                                          size: lineSize(for: phrase.lines[index])))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                            .multilineTextAlignment(textAlignment(for: phrase.alignment))
                            .modifier(EntryAnimationModifier(
                                style: phrase.style,
                                visible: visible,
                                index: index
                            ))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
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

    private func textAlignment(for alignment: HorizontalAlignment) -> TextAlignment {
        switch alignment {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }

    private func lineSize(for text: String) -> CGFloat {
        if text.count <= 4 { return 120 }
        if text.count <= 7 { return 90 }
        return 64
    }

    private func showPhrase(_ index: Int) {
        let idx = index % phrases.count
        currentPhrase = idx
        let count = phrases[idx].lines.count

        lineVisible = Array(repeating: false, count: count)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            lineVisible = Array(repeating: true, count: count)
        }

        let holdTime = 1.5 + Double(count) * 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + holdTime) {
            lineVisible = Array(repeating: false, count: count)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showPhrase(index + 1)
            }
        }
    }
}

// MARK: - Entry Animation Modifier (different style per phrase)

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
            .animation(
                .spring(response: 0.55, dampingFraction: 0.7)
                    .delay(Double(index) * 0.12),
                value: visible
            )
    }

    private var scaleValue: CGFloat {
        guard !visible else { return 1 }
        switch style {
        case .scaleUp: return 2.2
        case .expand: return 0.1
        default: return 1
        }
    }

    private var offsetX: CGFloat {
        guard !visible else { return 0 }
        switch style {
        case .slideLeft: return 300
        case .slideRight: return -300
        default: return 0
        }
    }

    private var offsetY: CGFloat {
        guard !visible else { return 0 }
        switch style {
        case .slideUp: return 200
        case .dropDown: return -200
        case .scaleUp: return 30
        default: return 0
        }
    }

    private var rotationValue: Double {
        guard !visible else { return 0 }
        switch style {
        case .expand: return -15
        case .slideLeft: return 5
        case .slideRight: return -5
        default: return 0
        }
    }
}

#Preview {
    ZStack {
        Color.blue
        KineticTextView()
    }
}
