import SwiftUI

/// "Extract": a contact (to Contacts), a table (to copy) or to-dos (to Reminders), with a
/// switcher for when Lampo guessed the wrong kind.
struct ExtractionView: View {
    @Bindable var viewModel: PanelViewModel

    /// Rows shown in the table preview; Copy always takes them all.
    static let previewRows = 12

    var body: some View {
        if let card = viewModel.extraction {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    header(card)
                    content(card)
                }
                .padding(.horizontal, DesignTokens.Panel.horizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, showsReminders(card) ? 0 : 16)
                if showsReminders(card) {
                    DraftCardView(viewModel: viewModel)
                }
            }
        }
    }

    private func showsReminders(_ card: ExtractionCard) -> Bool {
        card.kind == .todos && viewModel.draft != nil
    }

    private func header(_ card: ExtractionCard) -> some View {
        HStack(spacing: 10) {
            Label("Extract", systemImage: "tablecells")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Picker("Extract", selection: Binding(get: { card.kind }, set: { viewModel.switchExtraction(to: $0) })) {
                ForEach(ExtractKind.allCases, id: \.self) { kind in
                    Text(verbatim: kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            ProvenanceBadge(route: .onDevice)
        }
    }

    @ViewBuilder
    private func content(_ card: ExtractionCard) -> some View {
        switch card.phase {
        case .reading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the text…").foregroundStyle(.secondary)
            }
            .font(.system(size: DesignTokens.Panel.bodyFontSize))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .ready:
            if card.isFallback {
                Text("Apple Intelligence isn't available: Lampo used simple rules. Check the result.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            switch card.kind {
            case .contact:
                ContactFields(contact: contactBinding)
                contactButtons
            case .table:
                TablePreview(table: card.table)
                tableButtons
            case .todos:
                EmptyView()
            }
        }
    }

    private var contactButtons: some View {
        HStack(spacing: 8) {
            Button("Copy") { viewModel.copyContact() }
                .buttonStyle(LampoButtonStyle())
            if let flash = viewModel.flash {
                Text(flash).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("Contacts asks before adding it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                viewModel.saveContact()
            } label: {
                HStack(spacing: 6) {
                    Text("Add to Contacts")
                    Text(verbatim: "⌘↩").opacity(0.7)
                }
            }
            .buttonStyle(LampoButtonStyle(prominent: true))
        }
    }

    private var tableButtons: some View {
        HStack(spacing: 8) {
            Button("Copy as Markdown") { viewModel.copyTable(asMarkdown: true) }
                .buttonStyle(LampoButtonStyle())
            if let flash = viewModel.flash {
                Text(flash).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("Pastes as cells in Numbers and Excel.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                viewModel.copyTable()
            } label: {
                HStack(spacing: 6) {
                    Text("Copy")
                    Text(verbatim: "⌘C").opacity(0.7)
                }
            }
            .buttonStyle(LampoButtonStyle(prominent: true))
        }
    }

    private var contactBinding: Binding<ContactDraft> {
        Binding(get: { viewModel.extraction?.contact ?? ContactDraft() },
                set: { viewModel.extraction?.contact = $0 })
    }
}

private struct ContactFields: View {
    @Binding var contact: ContactDraft

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                label("Name")
                HStack(spacing: 8) {
                    TextField("First name", text: $contact.givenName)
                    TextField("Last name", text: $contact.familyName)
                }
                .font(.system(size: 15, weight: .medium))
            }
            GridRow {
                label("Company")
                HStack(spacing: 8) {
                    TextField("Company", text: $contact.organization)
                    TextField("Job title", text: $contact.jobTitle)
                }
            }
            ForEach(contact.phones.indices, id: \.self) { index in
                GridRow {
                    label("Phone")
                    TextField("Phone", text: $contact.phones[index])
                }
            }
            ForEach(contact.emails.indices, id: \.self) { index in
                GridRow {
                    label("Email")
                    TextField("Email", text: $contact.emails[index])
                }
            }
            if !contact.address.isEmpty {
                GridRow {
                    label("Address")
                    TextField("Address", text: $contact.address)
                }
            }
            if !contact.website.isEmpty {
                GridRow {
                    label("Website")
                    TextField("Website", text: $contact.website)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 13))
    }

    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }
}

private struct TablePreview: View {
    let table: ExtractedTable

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                if !table.columns.isEmpty {
                    GridRow {
                        ForEach(table.columns.indices, id: \.self) { index in
                            Text(verbatim: table.columns[index]).fontWeight(.semibold)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                }
                ForEach(Array(table.rows.prefix(ExtractionView.previewRows).enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(row.indices, id: \.self) { index in
                            Text(verbatim: row[index]).lineLimit(2)
                        }
                    }
                }
            }
            .font(.system(size: 13))
            .textSelection(.enabled)
            if table.rows.count > ExtractionView.previewRows {
                Text("+ \(table.rows.count - ExtractionView.previewRows) more rows")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Table"))
    }
}
