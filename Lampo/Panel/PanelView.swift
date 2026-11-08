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
            if let notice = viewModel.notice {
                Divider()
                NoticeRow(notice: notice) { viewModel.grantPermission($0) }
                    .padding(.horizontal, DesignTokens.Panel.horizontalPadding)
                    .padding(.vertical, 10)
            } else if !viewModel.isAccessibilityGranted && !viewModel.hasContent {
                Divider()
                NoticeRow(notice: .permission(.accessibility)) { viewModel.grantPermission($0) }
                    .padding(.horizontal, DesignTokens.Panel.horizontalPadding)
                    .padding(.vertical, 10)
            }
            if viewModel.draft != nil {
                Divider()
                DraftCardView(viewModel: viewModel)
            } else if viewModel.hasContent {
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

    private var placeholder: LocalizedStringKey {
        switch viewModel.draftInputKind {
        case .event: return "Describe the event, e.g. dinner with Marco Thursday at 8pm"
        case .reminder: return "What should I remind you? e.g. call Anna tomorrow at 10"
        case nil: break
        }
        if viewModel.hasWindowContext { return "Ask about this window…" }
        return viewModel.hasContent ? "Ask a follow-up…" : "Ask Lampo…"
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
            if let kind = viewModel.draftInputKind {
                DraftModeChip(kind: kind) { viewModel.cancelDraftInput() }
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            }
            ForEach(viewModel.contextItems) { item in
                ContextChip(item: item) { viewModel.removeContext(id: item.id) }
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            }
            if viewModel.isCapturingWindow {
                ProgressView()
                    .controlSize(.small)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    .accessibilityLabel(Text("Capturing the window"))
            }
            TextField(text: $viewModel.query, axis: .vertical) {
                Text(placeholder)
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
                    CurrentTurnView(turn: turn,
                                    onThinkHarder: viewModel.canThinkHarder ? { viewModel.thinkHarder() } : nil)
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
    /// Offered with the "Long text" notice when Private Cloud Compute is allowed.
    var onThinkHarder: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary = turn.contextSummary {
                Label(summary, systemImage: "text.quote")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
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
            if turn.wasTruncated && turn.isFinished {
                TruncationNotice(onThinkHarder: onThinkHarder)
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
                viewModel.insertCurrentAnswer()
            } label: {
                Label("Insert", systemImage: "arrow.uturn.left")
                    .badgeShortcut("⌘↩")
            }
            .buttonStyle(LampoButtonStyle())
            .disabled(!viewModel.canInsert)
            .help(insertHelp)

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

    private var insertHelp: LocalizedStringKey {
        viewModel.activeSelection == nil
            ? "Paste the answer at the cursor in the app you were using"
            : "Replace the selected text with the answer"
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
            // Longer Italian labels ("Approfondisci") must not wrap inside a 34 pt button.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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

/// A removable context chip in the input row ("Selection · 12 words").
struct ContextChip: View {
    let item: ContextItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            if case .window(let capture) = item {
                Image(decorative: capture.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(item.summary)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove"))
        }
        .foregroundStyle(DesignTokens.accent)
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .frame(height: 26)
        .background(Capsule().fill(DesignTokens.accent.opacity(0.14)))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .help(helpText)
    }

    private var symbol: String {
        switch item {
        case .selection: return "text.cursor"
        case .clipboard: return "doc.on.clipboard"
        case .window: return "macwindow"
        }
    }

    private var helpText: String {
        switch item {
        case .selection(let selection): return String(selection.text.prefix(300))
        case .clipboard(let text): return String(text.prefix(300))
        case .window(let capture): return capture.title ?? capture.app.name
        }
    }
}

/// A missing permission with an "Allow…" button, or a short message.
struct NoticeRow: View {
    let notice: PanelNotice
    let onGrant: (PermissionKind) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(DesignTokens.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if case .permission(let kind) = notice {
                Button("Allow…") { onGrant(kind) }
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch notice {
        case .permission(.accessibility): return "hand.raised"
        case .permission(.screenRecording): return "macwindow"
        case .message: return "exclamationmark.triangle"
        }
    }

    private var text: String {
        switch notice {
        case .permission(.accessibility):
            return String(localized: "Allow Accessibility to use the text you select in other apps.")
        case .permission(.screenRecording):
            return ScreenCaptureError.permissionDenied.localizedDescription
        case .message(let message):
            return message
        }
    }
}
