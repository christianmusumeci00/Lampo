import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Actions: the list of actions and an editor for the selected one.
struct ActionsSettingsView: View {
    var state: AppState
    @State private var selectedID: UUID?
    @State private var message: String?
    @State private var confirmsRestore = false

    private var store: ActionStore { state.actionStore }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(store.actions) { action in
                        Label(action.name, systemImage: action.symbol)
                            .lineLimit(1)
                            .tag(action.id)
                    }
                    .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.sidebar)
                Divider()
                toolbar
            }
            .frame(width: 210)

            Divider()

            if let selectedID, let binding = binding(for: selectedID) {
                ActionEditor(action: binding, state: state)
                    .id(selectedID)
            } else {
                Text("Select an action to edit it.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 560)
        .onAppear { if selectedID == nil { selectedID = store.actions.first?.id } }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        }
        .confirmationDialog("Restore the built-in actions?", isPresented: $confirmsRestore) {
            Button("Restore") { state.restoreBuiltInActions() }
        } message: {
            Text("Built-in actions go back to their original prompts and settings. Your own actions stay as they are.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            Button {
                let action = LampoAction(
                    name: String(localized: "New action"), symbol: "sparkles",
                    promptTemplate: "Rewrite the text below to make it clearer. Keep its language.\n\n{{selection}}")
                store.add(action)
                selectedID = action.id
            } label: {
                Image(systemName: "plus").frame(width: 22, height: 18)
            }
            .help(Text("New action"))
            .accessibilityLabel(Text("New action"))

            Button {
                guard let selectedID else { return }
                state.deleteAction(selectedID)
                self.selectedID = store.actions.first?.id
            } label: {
                Image(systemName: "minus").frame(width: 22, height: 18)
            }
            .disabled(selectedID == nil)
            .help(Text("Delete action"))
            .accessibilityLabel(Text("Delete action"))

            Button {
                guard let selectedID, let copy = store.duplicate(selectedID) else { return }
                self.selectedID = copy.id
            } label: {
                Image(systemName: "plus.square.on.square").frame(width: 22, height: 18)
            }
            .disabled(selectedID == nil)
            .help(Text("Duplicate action"))
            .accessibilityLabel(Text("Duplicate action"))

            Spacer()

            Menu {
                Button("Import Actions…") { importActions() }
                Button("Export Actions…") { exportActions() }
                Divider()
                Button("Restore Built-in Actions…") { confirmsRestore = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("More"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func binding(for id: UUID) -> Binding<LampoAction>? {
        guard let action = store.action(id: id) else { return nil }
        return Binding(
            get: { store.action(id: id) ?? action },
            set: { store.update($0) })
    }

    private func exportActions() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "Lampo Actions") + ".json"
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
        } catch {
            message = String(localized: "Couldn't export the actions.")
        }
    }

    private func importActions() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try store.importData(Data(contentsOf: url))
            message = String(localized: "Imported \(count) actions.")
            selectedID = store.actions.last?.id
        } catch {
            message = String(localized: "This file doesn't contain Lampo actions.")
        }
    }
}

/// Edits one action: name, symbol, prompt template with a live preview, input, output,
/// model, shortcut, and a "Try" run on sample text.
struct ActionEditor: View {
    @Binding var action: LampoAction
    var state: AppState

    @State private var sample = String(localized: "hi Marta, i cant come tomorow to the meeting becuase i have a dentist appointment, can we move it to friday?")
    @State private var tryOutput = ""
    @State private var tryState: TryState = .idle
    @State private var tryTask: Task<Void, Never>?

    enum TryState: Equatable {
        case idle
        case running
        case done(ModelRoute, Bool)
        case failed(String)
    }

    static let symbols = [
        "sparkles", "checkmark.circle", "briefcase", "arrow.down.right.and.arrow.up.left", "character.bubble",
        "text.line.first.and.arrowtriangle.forward", "lightbulb", "macwindow", "envelope", "list.bullet",
        "face.smiling", "pencil", "quote.bubble", "number", "calendar", "globe",
    ]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $action.name)
                HStack {
                    Picker("Symbol", selection: $action.symbol) {
                        ForEach(symbolChoices, id: \.self) { symbol in
                            Label(symbol, systemImage: symbol).tag(symbol)
                        }
                    }
                }
                if action.isBuiltIn {
                    Text("Built-in action. You can change it; “Restore Built-in Actions” brings back the original.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if action.output.draftKind == nil {
            Section {
                TextEditor(text: $action.promptTemplate)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 90, maxHeight: 140)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(Text("Prompt"))
                Menu("Insert Variable") {
                    ForEach(PromptTemplate.variables, id: \.self) { name in
                        Button { action.promptTemplate += "{{\(name)}}" } label: { Text(verbatim: "{{\(name)}}") }
                    }
                }
                .fixedSize()
                let unknown = PromptTemplate.unknownVariables(in: action.promptTemplate)
                if !unknown.isEmpty {
                    Label(String(localized: "Unknown variables: \(unknown.joined(separator: ", "))"),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if action.input == .screen && action.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Empty prompt: Lampo opens the panel with the window attached and waits for your question.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview with the sample text").font(.caption).foregroundStyle(.secondary)
                        ScrollView {
                            Text(renderedPreview)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 90)
                    }
                }
            } header: {
                Text("Prompt")
            } footer: {
                Text("Write instructions in English for the best results. {{selection}} is the selected text, {{text_language}} its language, {{language}} your answer language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            }

            Section {
                Picker("Input", selection: $action.input) {
                    Text("Selected text").tag(LampoAction.InputSource.selection)
                    Text("Clipboard").tag(LampoAction.InputSource.clipboard)
                    Text("Window screenshot").tag(LampoAction.InputSource.screen)
                    Text("Nothing").tag(LampoAction.InputSource.none)
                }
                Picker("Result", selection: $action.output) {
                    Text("Preview in the Lens").tag(LampoAction.OutputMode.preview)
                    Text("Replace without preview").tag(LampoAction.OutputMode.replaceSilently)
                    Text("Copy").tag(LampoAction.OutputMode.copy)
                    Text("Open in the panel").tag(LampoAction.OutputMode.openPanel)
                    Text("Create a calendar event").tag(LampoAction.OutputMode.calendarEvent)
                    Text("Create a reminder").tag(LampoAction.OutputMode.reminder)
                }
                if action.output.draftKind != nil {
                    Text("Lampo reads the title, day and time from the selected text (or the clipboard) and shows an editable card. Nothing is added until you confirm. No prompt is used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if action.input != .selection && action.output != .openPanel {
                    Text("Without selected text there's nothing to replace: the result opens in the panel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Model", selection: $action.route) {
                    Text("On this Mac").tag(ModelRoute.onDevice)
                    Text("Private Cloud Compute").tag(ModelRoute.privateCloud)
                }
                if action.route == .privateCloud && !state.preferences.routingPolicy.allowsPrivateCloud {
                    Text(BuildFeatures.isPrivateCloudCompiledIn
                         ? "“Only on this Mac” is on: this action runs on your Mac."
                         : "Private Cloud Compute is not available in this build: this action runs on your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                KeyboardShortcuts.Recorder(for: action.shortcutName) {
                    Text("Shortcut")
                }
                .shortcutValidation { shortcut in
                    let entries = state.shortcutEntries
                    let index = state.shortcutNames.firstIndex { $0.name == action.shortcutName } ?? -1
                    if let owner = ShortcutConflicts.owner(of: shortcut, in: entries, excluding: index) {
                        return .disallow(reason: String(localized: "This shortcut is already used by “\(owner)”."))
                    }
                    return .allow
                }
            }

            if action.output.draftKind == nil {
            Section("Try it") {
                TextField("Sample text", text: $sample, axis: .vertical)
                    .lineLimit(2...5)
                HStack {
                    Button(tryState == .running ? "Stop" : "Try") {
                        tryState == .running ? stopTry() : runTry()
                    }
                    .disabled(!canTry)
                    if !canTry {
                        Text("Screen actions can be tried from their shortcut.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if case .done(let route, _) = tryState {
                        ProvenanceBadge(route: route)
                    }
                }
                switch tryState {
                case .idle:
                    EmptyView()
                case .running where tryOutput.isEmpty:
                    ProgressView().controlSize(.small)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                default:
                    Text(RewriteCleaner.clean(tryOutput, original: sample))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if case .done(_, true) = tryState {
                        TruncationNotice()
                    }
                }
            }
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopTry() }
    }

    private var symbolChoices: [String] {
        Self.symbols.contains(action.symbol) ? Self.symbols : [action.symbol] + Self.symbols
    }

    private var sampleContext: TemplateContext {
        let runner = state.makeRunner()
        return runner.templateContext(
            selection: action.input == .selection ? sample : nil,
            clipboard: action.input == .clipboard ? sample : nil,
            app: "TextEdit")
    }

    private var renderedPreview: String {
        PromptTemplate.render(action.promptTemplate, context: sampleContext, input: action.input)
    }

    private var canTry: Bool { action.input != .screen }

    private func runTry() {
        stopTry()
        tryOutput = ""
        tryState = .running
        let action = self.action
        let context = sampleContext
        let runner = state.makeRunner()
        tryTask = Task {
            do {
                let run = try await runner.start(action, context: context)
                for try await text in run.stream { tryOutput = text }
                if !Task.isCancelled { tryState = .done(run.route, run.wasTruncated) }
            } catch is CancellationError {
                tryState = .idle
            } catch {
                guard !Task.isCancelled else { return }
                tryState = .failed((error as? LocalizedError)?.errorDescription ?? ModelError.other.localizedDescription)
            }
        }
    }

    private func stopTry() {
        tryTask?.cancel()
        tryTask = nil
        if tryState == .running { tryState = .idle }
    }
}
