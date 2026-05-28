import SwiftUI

/// The overlay's contents: paperclip character outside a tailed speech bubble
/// (classic Clippy layout — character pointing at his own dialog). Stays
/// minimal — Clippy works when he's invisible 99% of the time and offers
/// exactly one clear action when he does appear.
struct ClippyView: View {
    @ObservedObject var controller: OverlayController
    @TerminalPreference private var preferredTerminal: Terminal

    /// Continuous idle bob. Subtle enough to feel alive but not distracting.
    @State private var bobAngle: Double = 0

    var body: some View {
        // `.frame(maxWidth/Height: .infinity)` on a container is the only
        // reliable way to give the SwiftUI tree real bounds inside an
        // NSHostingView/NSPanel — intrinsic sizing collapses to zero.
        // The bubble anchors at bottomTrailing of the available space.
        VStack {
            if let prompt = controller.pending {
                content(for: prompt)
                    .onAppear { startBob() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(12)
    }

    private func content(for prompt: WaitingPrompt) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: "paperclip")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tint)
                .rotationEffect(.degrees(bobAngle))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)

            bubble(for: prompt)
        }
    }

    private func bubble(for prompt: WaitingPrompt) -> some View {
        // Note: do NOT use .fixedSize(horizontal: false, vertical: true) on
        // any of these Text views — in the NSHostingView/NSPanel context
        // that modifier collapses the whole bubble to zero size. Found out
        // the hard way after a long bisection.
        VStack(alignment: .leading, spacing: 6) {
            Text("\(prompt.sessionTitle) needs your attention")
                .font(.subheadline.weight(.semibold))
            if !prompt.waitingFor.isEmpty {
                Text(prompt.waitingFor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Button("Open") {
                    TUILauncher.openTUI(in: preferredTerminal)
                    controller.dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Dismiss") {
                    controller.dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Menu {
                    Button("Snooze 1 hour") { controller.snooze(prompt.id, for: 3600) }
                    Button("Snooze 4 hours") { controller.snooze(prompt.id, for: 4 * 3600) }
                    Button("Snooze this session") { controller.snooze(prompt.id, for: .infinity) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24)
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .background(
            SpeechBubbleShape(cornerRadius: 12, tailWidth: 8, tailHeight: 14)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
        )
        .foregroundStyle(.white)
    }

    private func startBob() {
        // Subtle continuous bob: 4° each side, slow autoreverse.
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            bobAngle = 4
        }
    }
}

/// Rounded-rect bubble with a triangular tail on the left edge, pointing at
/// the speaker (the paperclip). Drawn as a single continuous path so the
/// fill doesn't seam between rect and tail.
struct SpeechBubbleShape: Shape {
    let cornerRadius: CGFloat
    let tailWidth: CGFloat
    let tailHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = cornerRadius
        let left = rect.minX + tailWidth
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY
        let tailY = top + (bottom - top) * 0.5

        p.move(to: CGPoint(x: left + r, y: top))
        p.addLine(to: CGPoint(x: right - r, y: top))
        p.addArc(center: CGPoint(x: right - r, y: top + r),
                 radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: right, y: bottom - r))
        p.addArc(center: CGPoint(x: right - r, y: bottom - r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: left + r, y: bottom))
        p.addArc(center: CGPoint(x: left + r, y: bottom - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: left, y: tailY + tailHeight / 2))
        p.addLine(to: CGPoint(x: rect.minX, y: tailY))
        p.addLine(to: CGPoint(x: left, y: tailY - tailHeight / 2))
        p.addLine(to: CGPoint(x: left, y: top + r))
        p.addArc(center: CGPoint(x: left + r, y: top + r),
                 radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}
