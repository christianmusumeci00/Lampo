import SwiftUI

/// The Glass panel: input row, streamed answer, action bar.
struct PanelView: View {
    @Bindable var viewModel: PanelViewModel
    var presentation: PanelPresentation
    var onHeightChange: (CGFloat) -> Void
    var onClose: () -> Void

    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            if showsAvailability {
                Divider()
                AvailabilityView(availability: viewModel.availability, style: .compact) {
                    viewModel.refreshAvailability()
                }
                .padding(.horizontal, DesignTokens.Panel.horizontalPadding)
                .padding(.vertical, 14)
            }
            if viewModel.hasContent {
                Divider()
                ConversationView(viewModel: viewModel)
                Divider()
                ActionBar(viewModel: viewModel)
            }
        }
        .frame(width: DesignTokens.Panel.width)
        .modifier(PanelSurface(cornerRadius: DesignTokens.Panel.cornerRadius))
        .scaleEffect(presentation.isPresented || reduceMotion ? 1 : 0.98, anchor: .top)
        .padding(DesignTokens.Panel.shadowMargin)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.focusRequest, initial: true) { inputFocused = true }
    }

    private var showsAvailability: Bool {
        viewModel.availability != .available && viewModel.availability != .unknown && !viewModel.hasContent
    }

    private var inputRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(DesignTokens.accent)
                .accessibilityHidden(true)
            TextField(text: $viewModel.query, axis: .vertical) {
                Text(viewModel.hasContent ? "Ask a follow-up…" : "Ask Lampo…")
            }
            .textFieldStyle(.plain)
            .font(.system(size: DesignTokens.Panel.inputFontSize))
            .lineLimit(1...5)
            .focused($inputFocused)
            .onSubmit { viewModel.submit() }
            .accessibilityLabel(Text("Ask Lampo"))
            if !viewModel.query.isEmpty {
                Text(verbatim: "↩")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, DesignTokens.Panel.horizontalPadding)
        .padding(.vertical, DesignTokens.Panel.verticalPadding)
    }
}

/// Liquid Glass, or an opaque surface when "Reduce transparency" is on.
struct PanelSurface: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if reduceTransparency {
                content.background(Color(nsColor: .windowBackgroundColor), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: DesignTokens.Panel.shadowRadius, y: 14)
    }
}

/// Previous questions (compact) and the current answer.
struct ConversationView: View {
    var viewModel: PanelViewModel
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.previousTurns) { turn in
                    PreviousTurnRow(turn: turn)
                }
                if let turn = viewModel.currentTurn {
                    CurrentTurnView(turn: turn)
                }
            }
            .padding(.horizontal, DesignTokens.Panel.horizontalPadding)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollIndicators(.automatic)
        .frame(height: min(max(contentHeight, 1), DesignTokens.Panel.maxResponseHeight))
    }
}

struct PreviousTurnRow: View {
    let turn: ConversationTurn
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(turn.question)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Previous question: \(turn.question)"))
            .accessibilityHint(Text(isExpanded ? "Hides the answer" : "Shows the answer"))

            if isExpanded {
                MarkdownView(text: turn.answer)
                    .padding(.leading, 16)
                    .opacity(0.85)
            }
        }
    }
}

struct CurrentTurnView: View {
    let turn: ConversationTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(turn.question)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                ProvenanceBadge(route: turn.route, isCalculation: turn.kind == .calculation)
            }

            switch turn.state {
            case .streaming where turn.answer.isEmpty:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…").foregroundStyle(.secondary)
                }
                .font(.system(size: DesignTokens.Panel.bodyFontSize))
            case .failed(let message):
                if !turn.answer.isEmpty { MarkdownView(text: turn.answer) }
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
            default:
                if turn.kind == .calculation {
                    Text(turn.answer)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .textSelection(.enabled)
                } else {
                    MarkdownView(text: turn.answer)
                }
                if turn.state == .cancelled {
                    Text("Stopped")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Always says where the request ran.
struct ProvenanceBadge: View {
    let route: ModelRoute
    var isCalculation = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.system(size: DesignTokens.Badge.fontSize, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: DesignTokens.Badge.height)
        .background(Capsule().fill(.quaternary.opacity(0.6)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityTitle))
    }

    private var symbol: String {
        if isCalculation { return "function" }
        return route == .onDevice ? "lock.fill" : "cloud"
    }

    private var title: LocalizedStringKey {
        if isCalculation { return "Calculated on Mac" }
        return route == .onDevice ? "On Mac" : "Private Cloud"
    }

    private var accessibilityTitle: LocalizedStringKey {
        if isCalculation { return "Calculated locally on this Mac" }
        return route == .onDevice ? "Answered on this Mac" : "Answered with Private Cloud Compute"
    }
}

struct ActionBar: View {
    var viewModel: PanelViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.copyCurrentAnswer()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .badgeShortcut("⌘C")
            }
            .buttonStyle(LampoButtonStyle(prominent: true))
            .disabled(!viewModel.canCopy)
            .accessibilityHint(Text("Copies the answer"))

            Button {
                viewModel.goDeeper()
            } label: {
                Label("Go deeper", systemImage: "text.append")
            }
            .buttonStyle(LampoButtonStyle())
            .disabled(!viewModel.canFollowUp)

            Button {
                viewModel.thinkHarder()
            } label: {
                Label("Think harder", systemImage: "cloud")
            }
            .buttonStyle(LampoButtonStyle())
            .disabled(!viewModel.canThinkHarder)
            .help(thinkHarderHelp)

            Spacer(minLength: 8)

            if let flash = viewModel.flash {
                Text(flash)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.accent)
                    .transition(.opacity)
            } else if viewModel.isGenerating {
                Text("esc to stop").hintStyle()
            } else {
                Text("esc to close").hintStyle()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(.easeOut(duration: 0.15), value: viewModel.flash)
    }

    private var thinkHarderHelp: LocalizedStringKey {
        BuildFeatures.isPrivateCloudCompiledIn
            ? "Ask again on Private Cloud Compute with deeper reasoning"
            : "Not available in this build"
    }
}

private extension Text {
    func hintStyle() -> some View {
        font(.system(size: 12)).foregroundStyle(.secondary)
    }
}

private extension View {
    func badgeShortcut(_ shortcut: String) -> some View {
        HStack(spacing: 6) {
            self
            Text(verbatim: shortcut)
                .font(.system(size: 11, weight: .medium))
                .opacity(0.7)
        }
    }
}

/// Buttons of the panel and lens: 34 pt tall, 9 pt radius.
struct LampoButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: DesignTokens.Button.height)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Button.cornerRadius, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(DesignTokens.accent) : AnyShapeStyle(.quaternary.opacity(0.7)))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}
