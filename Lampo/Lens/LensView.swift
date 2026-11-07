import KeyboardShortcuts
import SwiftUI

/// Where the Lens arrow points, set by the controller after positioning.
@MainActor
@Observable
final class LensLayout {
    enum Edge {
        case top      // Lens below the selection, arrow on top
        case bottom   // Lens above the selection, arrow at the bottom
    }

    var arrowEdge: Edge = .top
    var arrowX: CGFloat = DesignTokens.Lens.width / 2
}

struct LensView: View {
    static let arrowSize = CGSize(width: 18, height: 9)

    var viewModel: LensViewModel
    var layout: LensLayout
    var onHeightChange: (CGFloat) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chips
            preview
            if viewModel.wasTruncated {
                TruncationNotice(
                    detail: "Replace is off so no text is lost.",
                    onThinkHarder: viewModel.canThinkHarder ? { viewModel.thinkHarder() } : nil)
            }
            buttons
        }
        .padding(16)
        .padding(layout.arrowEdge == .top ? .top : .bottom, Self.arrowSize.height)
        .frame(width: DesignTokens.Lens.width)
        .modifier(LensSurface(layout: layout))
        .padding(DesignTokens.Panel.shadowMargin)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: layout.arrowEdge == .top ? .top : .bottom)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(headerText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            ProvenanceBadge(route: viewModel.route)
        }
    }

    private var headerText: String {
        let words = viewModel.selection.wordCount
        let wordsText = String(localized: "\(words) words")
        if let app = viewModel.selection.app?.name, !app.isEmpty {
            return String(localized: "Selected text · \(wordsText) · \(app)")
        }
        return String(localized: "Selected text · \(wordsText)")
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(viewModel.actions.enumerated()), id: \.element.id) { index, action in
                        ActionChip(action: action, isActive: index == viewModel.activeIndex) {
                            viewModel.select(index)
                        }
                        .id(action.id)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)
            .onChange(of: viewModel.activeIndex, initial: true) {
                if let id = viewModel.activeAction?.id {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private var preview: some View {
        Group {
            switch viewModel.phase {
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .streaming where viewModel.output.isEmpty:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Writing…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                PreviewText(text: viewModel.result)
            }
        }
        .font(.system(size: 14))
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Lens.previewCornerRadius, style: .continuous)
                .fill(.quaternary.opacity(0.45))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Preview"))
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button { viewModel.retry() } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(LampoButtonStyle())
            .disabled(viewModel.isStreaming)

            Button { viewModel.copy() } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(LampoButtonStyle())
            .disabled(viewModel.result.isEmpty)

            Spacer(minLength: 8)

            if let flash = viewModel.flash {
                Text(flash)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.accent)
            } else {
                Text("tab next action · esc cancel")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Button { viewModel.replace() } label: {
                HStack(spacing: 6) {
                    Text("Replace")
                    Text(verbatim: "↩").opacity(0.75)
                }
            }
            .buttonStyle(LampoButtonStyle(prominent: true))
            .disabled(!viewModel.canReplace)
            .accessibilityHint(Text("Replaces the selected text in the original app"))
        }
    }
}

private struct PreviewText: View {
    let text: String
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            Text(text)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .frame(height: min(max(height, 20), 260))
    }
}

struct ActionChip: View {
    let action: LampoAction
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: action.symbol)
                    .font(.system(size: 12))
                Text(action.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                if let shortcut = KeyboardShortcuts.getShortcut(for: action.shortcutName) {
                    Text(verbatim: shortcut.description)
                        .font(.system(size: 11))
                        .foregroundStyle(isActive ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                }
            }
            .padding(.horizontal, 11)
            .frame(height: DesignTokens.Lens.chipHeight)
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                Capsule().fill(isActive ? AnyShapeStyle(DesignTokens.accent) : AnyShapeStyle(.quaternary.opacity(0.6)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// Rounded rectangle with a small arrow pointing at the selection.
struct LensBubble: Shape {
    var cornerRadius: CGFloat
    var arrowEdge: LensLayout.Edge
    var arrowX: CGFloat
    var arrowSize: CGSize

    func path(in rect: CGRect) -> Path {
        var body = rect
        if arrowEdge == .top {
            body.origin.y += arrowSize.height
        }
        body.size.height -= arrowSize.height
        var path = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)
        let x = min(max(arrowX, cornerRadius + arrowSize.width / 2), rect.width - cornerRadius - arrowSize.width / 2)
        var arrow = Path()
        if arrowEdge == .top {
            arrow.move(to: CGPoint(x: x - arrowSize.width / 2, y: body.minY + 0.5))
            arrow.addLine(to: CGPoint(x: x, y: rect.minY))
            arrow.addLine(to: CGPoint(x: x + arrowSize.width / 2, y: body.minY + 0.5))
        } else {
            arrow.move(to: CGPoint(x: x - arrowSize.width / 2, y: body.maxY - 0.5))
            arrow.addLine(to: CGPoint(x: x, y: rect.maxY))
            arrow.addLine(to: CGPoint(x: x + arrowSize.width / 2, y: body.maxY - 0.5))
        }
        arrow.closeSubpath()
        path.addPath(arrow)
        return path
    }
}

private struct LensSurface: ViewModifier {
    var layout: LensLayout
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = LensBubble(cornerRadius: DesignTokens.Lens.cornerRadius, arrowEdge: layout.arrowEdge,
                               arrowX: layout.arrowX, arrowSize: LensView.arrowSize)
        Group {
            if reduceTransparency {
                content.background(Color(nsColor: .windowBackgroundColor), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
    }
}

/// "Long text: used an excerpt", with "Think harder" when Private Cloud Compute can take more text.
struct TruncationNotice: View {
    var detail: LocalizedStringKey?
    var onThinkHarder: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scissors")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Long text: used an excerpt.")
                .fontWeight(.medium)
            if let detail {
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let onThinkHarder {
                Button("Think harder", action: onThinkHarder)
                    .controlSize(.small)
                    .help(Text("Ask again on Private Cloud Compute, which can read more text"))
            }
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .combine)
    }
}
