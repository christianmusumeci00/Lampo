import AppKit
import SwiftUI

/// Explains why the on-device model can't be used and how to fix it.
struct AvailabilityView: View {
    enum Style {
        case compact
        case full
    }

    let availability: ModelAvailability
    var style: Style = .full
    var onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: style == .full ? 28 : 20))
                .foregroundStyle(availability == .modelNotReady ? DesignTokens.accent : .orange)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: style == .full ? 15 : 14, weight: .semibold))
                Text(availability.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if availability == .appleIntelligenceNotEnabled || availability == .modelNotReady {
                        Button("Open System Settings") { Self.openAppleIntelligenceSettings() }
                    }
                    Button("Check again", action: onRetry)
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch availability {
        case .modelNotReady: return "arrow.down.circle"
        case .deviceNotEligible: return "desktopcomputer.trianglebadge.exclamationmark"
        default: return "exclamationmark.triangle"
        }
    }

    private var title: LocalizedStringKey {
        switch availability {
        case .available: return "Ready"
        case .modelNotReady: return "Model downloading"
        case .appleIntelligenceNotEnabled: return "Apple Intelligence is off"
        case .deviceNotEligible: return "Mac not supported"
        case .unknown: return "Model not available"
        }
    }

    static func openAppleIntelligenceSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
