import SwiftUI

// MARK: - Design tokens: paper, ink, two greys, one burgundy accent.
// Dark mode is a pure inversion, handled by the asset catalog's appearances.
extension Color {
    static let paper  = Color("Paper")
    static let ink    = Color("Ink")
    static let ink60  = Color("Ink60")
    static let ink35  = Color("Ink35")
    static let hair   = Color("Hair")
    static let accent = Color("Accent")
}

// MARK: - Three type voices
enum Fonts {
    /// Afacad Flux — uppercase micro-labels, controls, readouts.
    static func micro(_ size: CGFloat = 11) -> Font { .custom("AfacadFlux-Regular", size: size).weight(.semibold) }
    /// Newsreader — prose; italics for hints and pronunciations.
    static func serif(_ size: CGFloat = 17) -> Font { .custom("Newsreader-Regular", size: size) }
    static func serifItalic(_ size: CGFloat = 16) -> Font { .custom("Newsreader-Italic", size: size) }
    /// Prata — headings only.
    static func display(_ size: CGFloat = 28) -> Font { .custom("Prata-Regular", size: size) }
}

// MARK: - Small building blocks
struct MicroLabel: View {
    let text: String
    var color: Color = .ink60
    var size: CGFloat = 11
    var body: some View {
        Text(text.uppercased()).font(Fonts.micro(size)).tracking(2).foregroundStyle(color)
    }
}

/// Bordered paper/ink button that inverts when pressed or selected;
/// `filled` is the pre-inverted primary action, `accent` the warning voice.
struct InkButtonStyle: ButtonStyle {
    var filled = false
    var accent = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let on = filled || configuration.isPressed
        let stroke: Color = accent ? .accent : .ink
        let fg: Color = on ? .paper : (accent ? .accent : .ink)
        let bg: Color = on ? stroke : .paper
        configuration.label
            .font(Fonts.micro(compact ? 10 : 11))
            .tracking(2)
            .textCase(.uppercase)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 8 : 11)
            .foregroundStyle(fg)
            .background(bg)
            .overlay(Rectangle().stroke(stroke, lineWidth: 1))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The unit of the mosaic: a square-cornered box with a 1px ink border.
struct Box<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.paper)
            .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
    }
}

/// Box header in the micro voice with a solid ink rule beneath.
struct BoxTitle: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel(text: text, color: .ink).padding(.horizontal, 14).padding(.vertical, 11)
            Rectangle().fill(Color.ink).frame(height: 1)
        }
    }
}

/// 1px dashed hairline separating list rows.
struct DashedRule: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(Color.hair, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(height: 1)
    }
}

/// Four-point concave sparkle — the brand mark.
struct Sparkle: View {
    var size: CGFloat = 12
    var body: some View {
        Path { p in
            let s = size / 24
            p.move(to: CGPoint(x: 12 * s, y: 1 * s))
            p.addCurve(to: CGPoint(x: 23 * s, y: 12 * s), control1: CGPoint(x: 12.6 * s, y: 7.2 * s), control2: CGPoint(x: 16.8 * s, y: 11.4 * s))
            p.addCurve(to: CGPoint(x: 12 * s, y: 23 * s), control1: CGPoint(x: 16.8 * s, y: 12.6 * s), control2: CGPoint(x: 12.6 * s, y: 16.8 * s))
            p.addCurve(to: CGPoint(x: 1 * s, y: 12 * s), control1: CGPoint(x: 11.4 * s, y: 16.8 * s), control2: CGPoint(x: 7.2 * s, y: 12.6 * s))
            p.addCurve(to: CGPoint(x: 12 * s, y: 1 * s), control1: CGPoint(x: 7.2 * s, y: 11.4 * s), control2: CGPoint(x: 11.4 * s, y: 7.2 * s))
            p.closeSubpath()
        }
        .fill(Color.ink)
        .frame(width: size, height: size)
    }
}

/// Speaker glyph as a 2px-stroke line icon.
struct SpeakerButton: View {
    let text: String
    var size: CGFloat = 16
    var body: some View {
        Button {
            Pronouncer.shared.speak(text)
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(Color.ink60)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play pronunciation")
    }
}

/// Uppercase micro-label above an input, per the design system.
struct Field<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(text: label)
            content()
        }
    }
}

struct InkTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(Fonts.serif(17))
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.paper)
            .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
    }
}

extension View {
    /// Page background: paper with the faint dot grid used between boxes.
    func paperBackground() -> some View {
        background(DotGrid().ignoresSafeArea())
    }

    /// Every screen with a text field gets a Done button above the keyboard
    /// and drag-to-dismiss. On iPhone the keyboard covers the tab bar, so
    /// without a way to put it away a page can trap the learner.
    func keyboardDismissal() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                        .font(Fonts.micro(12)).tracking(2).textCase(.uppercase)
                }
            }
    }
}

/// Resigns whichever field has the keyboard, wherever it is.
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

struct DotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 22
            var y: CGFloat = 11
            while y < size.height {
                var x: CGFloat = 11
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.hair))
                    x += step
                }
                y += step
            }
        }
        .background(Color.paper)
    }
}
