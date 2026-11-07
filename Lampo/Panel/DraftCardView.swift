import SwiftUI

/// Editable confirmation card for "Create event" / "Create reminder".
/// Nothing is written until the user presses Add.
struct DraftCardView: View {
    @Bindable var viewModel: PanelViewModel

    var body: some View {
        if let card = viewModel.draft {
            VStack(alignment: .leading, spacing: 14) {
                header(card)
                if card.phase == .reading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading the details…").foregroundStyle(.secondary)
                    }
                    .font(.system(size: DesignTokens.Panel.bodyFontSize))
                } else if card.kind == .event {
                    EventFields(draft: eventBinding, disabled: isLocked(card))
                } else {
                    ReminderFields(draft: reminderBinding, disabled: isLocked(card))
                }
                status(card)
                buttons(card)
            }
            .padding(.horizontal, DesignTokens.Panel.horizontalPadding)
            .padding(.vertical, 16)
        }
    }

    private func isLocked(_ card: DraftCard) -> Bool {
        card.phase == .saving || card.phase == .saved
    }

    private func header(_ card: DraftCard) -> some View {
        HStack(spacing: 8) {
            Label(card.kind == .event ? "New event" : "New reminder",
                  systemImage: card.kind == .event ? "calendar.badge.plus" : "checklist")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            ProvenanceBadge(route: .onDevice)
        }
    }

    @ViewBuilder
    private func status(_ card: DraftCard) -> some View {
        switch card.phase {
        case .saved:
            Label(card.kind == .event ? "Added to Calendar" : "Added to Reminders", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
        case .failed(let message):
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if card.needsSettings {
                    Spacer(minLength: 8)
                    Button("Open System Settings") { viewModel.openDraftSettings() }
                        .controlSize(.small)
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func buttons(_ card: DraftCard) -> some View {
        HStack(spacing: 8) {
            if card.phase == .saved {
                Button {
                    viewModel.openDraftApp()
                } label: {
                    Label(card.kind == .event ? "Open Calendar" : "Open Reminders", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(LampoButtonStyle())
                Spacer(minLength: 8)
                Text("esc to close").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Button("Cancel") { viewModel.discardDraft() }
                    .buttonStyle(LampoButtonStyle())
                Spacer(minLength: 8)
                Text("Nothing is added until you confirm.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.confirmDraft()
                } label: {
                    HStack(spacing: 6) {
                        if card.phase == .saving { ProgressView().controlSize(.mini) }
                        Text(card.kind == .event ? "Add to Calendar" : "Add to Reminders")
                        Text(verbatim: "⌘↩").opacity(0.7)
                    }
                }
                .buttonStyle(LampoButtonStyle(prominent: true))
                .disabled(!card.canConfirm)
            }
        }
    }

    private var eventBinding: Binding<CalendarEventDraft> {
        Binding(
            get: { viewModel.draft?.event ?? CalendarEventDraft(title: "", start: .now, end: .now, isAllDay: true, location: "", notes: "") },
            set: { viewModel.draft?.event = $0 })
    }

    private var reminderBinding: Binding<ReminderDraft> {
        Binding(
            get: { viewModel.draft?.reminder ?? ReminderDraft(title: "", hasDueDate: false, due: .now, hasDueTime: false, notes: "") },
            set: { viewModel.draft?.reminder = $0 })
    }
}

private struct EventFields: View {
    @Binding var draft: CalendarEventDraft
    var disabled: Bool

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                FieldLabel("Title")
                TextField("Title", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15, weight: .medium))
            }
            GridRow {
                FieldLabel("Starts")
                HStack(spacing: 12) {
                    DatePicker("Starts", selection: Binding(get: { draft.start }, set: { draft.moveStart(to: $0) }),
                               displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                        .labelsHidden()
                    Toggle("All day", isOn: $draft.isAllDay)
                        .toggleStyle(.checkbox)
                }
            }
            if !draft.isAllDay {
                GridRow {
                    FieldLabel("Ends")
                    DatePicker("Ends", selection: $draft.end, in: draft.start..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
            GridRow {
                FieldLabel("Location")
                TextField("Optional", text: $draft.location)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                FieldLabel("Notes")
                TextField("Optional", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
            }
        }
        .font(.system(size: 13))
        .disabled(disabled)
    }
}

private struct ReminderFields: View {
    @Binding var draft: ReminderDraft
    var disabled: Bool

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                FieldLabel("Reminder")
                TextField("Title", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15, weight: .medium))
            }
            GridRow {
                FieldLabel("When")
                HStack(spacing: 12) {
                    Toggle("Date", isOn: $draft.hasDueDate)
                        .toggleStyle(.checkbox)
                    if draft.hasDueDate {
                        Toggle("Time", isOn: $draft.hasDueTime)
                            .toggleStyle(.checkbox)
                        DatePicker("When", selection: $draft.due,
                                   displayedComponents: draft.hasDueTime ? [.date, .hourAndMinute] : [.date])
                            .labelsHidden()
                    }
                }
            }
            GridRow {
                FieldLabel("Notes")
                TextField("Optional", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
            }
        }
        .font(.system(size: 13))
        .disabled(disabled)
    }
}

private struct FieldLabel: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }
}

/// "Create event" chip in the input row while Lampo waits for the description.
struct DraftModeChip: View {
    let kind: DraftKind
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind == .event ? "calendar.badge.plus" : "checklist")
                .font(.system(size: 11, weight: .semibold))
            Text(kind == .event ? "Create event" : "Create reminder")
                .font(.system(size: 12, weight: .semibold))
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
    }
}
