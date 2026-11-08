import AppKit
import AVFoundation
import Foundation
import Speech

enum MicrophoneAccess: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

/// Whether the speech model for a language is on this Mac.
enum DictationReadiness: Equatable, Sendable {
    case ready
    /// The model can be downloaded from Apple (only when the user asks).
    case needsDownload
    case unsupported
}

/// While listening: the transcript so far (final + volatile) and the input level, 0…1.
enum DictationUpdate: Equatable, Sendable {
    case text(String)
    case level(Float)
}

enum DictationError: LocalizedError, Equatable {
    case microphoneDenied
    case noMicrophone
    case unsupportedLanguage(String)
    case modelNotDownloaded(String)
    case nothingHeard
    case failed

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return String(localized: "Lampo can't use the microphone. Allow it in System Settings › Privacy & Security › Microphone.")
        case .noMicrophone:
            return String(localized: "No microphone is available.")
        case .unsupportedLanguage(let language):
            return String(localized: "Dictation isn't available in \(language) on this Mac.")
        case .modelNotDownloaded(let language):
            return String(localized: "Download the \(language) dictation model in Lampo Settings › General.")
        case .nothingHeard:
            return String(localized: "Lampo didn't hear anything.")
        case .failed:
            return String(localized: "Dictation stopped working. Try again.")
        }
    }
}

/// Speech to text on this Mac, abstracted for tests.
@MainActor
protocol DictationEngine: AnyObject {
    var microphoneAccess: MicrophoneAccess { get }
    func requestMicrophone() async -> Bool
    func readiness(for language: String) async -> DictationReadiness
    /// Downloads the speech model from Apple. Only on the user's explicit request.
    func downloadModel(for language: String) async throws
    /// Starts listening. Updates arrive on the main actor until `stop` or `cancel`.
    func start(language: String) async throws -> AsyncStream<DictationUpdate>
    /// Stops listening and returns the whole transcript.
    func stop() async throws -> String
    func cancel() async
}

/// Microphone → `SpeechAnalyzer` with a `DictationTranscriber` (punctuation included).
/// Everything runs on device; no speech-recognition permission is needed, only the microphone.
@MainActor
final class SystemDictationEngine: DictationEngine {
    private var session: Session?

    private final class Session {
        let analyzer: SpeechAnalyzer
        let audio: AVAudioEngine?
        let input: AsyncStream<AnalyzerInput>.Continuation
        let updates: AsyncStream<DictationUpdate>.Continuation
        let results: Task<String, Error>
        var feeder: Task<Void, Never>?

        init(analyzer: SpeechAnalyzer, audio: AVAudioEngine?, input: AsyncStream<AnalyzerInput>.Continuation,
             updates: AsyncStream<DictationUpdate>.Continuation, results: Task<String, Error>) {
            self.analyzer = analyzer
            self.audio = audio
            self.input = input
            self.updates = updates
            self.results = results
        }
    }

    var microphoneAccess: MicrophoneAccess {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LAMPO_QA_DICTATION_FILE"] != nil { return .granted }
        #endif
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func locale(for language: String) async -> Locale? {
        await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: language))
    }

    private func transcriber(_ locale: Locale) -> DictationTranscriber {
        DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
    }

    func readiness(for language: String) async -> DictationReadiness {
        guard let locale = await locale(for: language) else { return .unsupported }
        let installed = await DictationTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) { return .ready }
        switch await AssetInventory.status(forModules: [transcriber(locale)]) {
        case .installed: return .ready
        case .supported, .downloading: return .needsDownload
        default: return .unsupported
        }
    }

    func downloadModel(for language: String) async throws {
        guard let locale = await locale(for: language) else {
            throw DictationError.unsupportedLanguage(TranslationPlanner.displayName(language))
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber(locale)]) {
            try await request.downloadAndInstall()
        }
    }

    func start(language: String) async throws -> AsyncStream<DictationUpdate> {
        await cancel()
        let name = TranslationPlanner.displayName(language)
        guard let locale = await locale(for: language) else { throw DictationError.unsupportedLanguage(name) }
        if await readiness(for: language) != .ready { throw DictationError.modelNotDownloaded(name) }

        let transcriber = transcriber(locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw DictationError.failed
        }
        try await analyzer.prepareToAnalyze(in: format)

        let (input, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        let (updates, updatesContinuation) = AsyncStream<DictationUpdate>.makeStream()
        try await analyzer.start(inputSequence: input)

        let results = Task<String, Error> {
            var finished = ""
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                if result.isFinal {
                    finished += text
                    updatesContinuation.yield(.text(finished))
                } else {
                    updatesContinuation.yield(.text(finished + text))
                }
            }
            return finished
        }

        #if DEBUG
        // Manual QA without a microphone: `LAMPO_QA_DICTATION_FILE=<audio file>` feeds that file instead.
        if let path = ProcessInfo.processInfo.environment["LAMPO_QA_DICTATION_FILE"] {
            let session = Session(analyzer: analyzer, audio: nil, input: inputContinuation,
                                  updates: updatesContinuation, results: results)
            session.feeder = Task { await AudioTap.feed(fileAt: URL(fileURLWithPath: path), as: format, into: inputContinuation) }
            self.session = session
            return updates
        }
        #endif

        guard microphoneAccess == .granted else {
            inputContinuation.finish()
            await analyzer.cancelAndFinishNow()
            throw DictationError.microphoneDenied
        }
        let audio = AVAudioEngine()
        let node = audio.inputNode
        let inputFormat = node.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0,
              let tap = AudioTap(from: inputFormat, to: format, input: inputContinuation, updates: updatesContinuation) else {
            inputContinuation.finish()
            await analyzer.cancelAndFinishNow()
            throw DictationError.noMicrophone
        }
        // macOS 27 deprecates installTap(onBus:bufferSize:format:block:); its replacement (with an
        // error) has no Swift refinement yet, so the refined-for-Swift name is called directly.
        do {
            try node.__installTap(onBus: 0, bufferSize: 4096, format: inputFormat, error: (), block: tap.block())
            audio.prepare()
            try audio.start()
        } catch {
            node.removeTap(onBus: 0)
            inputContinuation.finish()
            await analyzer.cancelAndFinishNow()
            Log.app.error("microphone didn't start: \(error.localizedDescription, privacy: .public)")
            throw DictationError.noMicrophone
        }
        session = Session(analyzer: analyzer, audio: audio, input: inputContinuation,
                          updates: updatesContinuation, results: results)
        return updates
    }

    func stop() async throws -> String {
        guard let session else { throw DictationError.failed }
        self.session = nil
        stopAudio(session)
        await session.feeder?.value
        session.input.finish()
        defer { session.updates.finish() }
        do {
            try await session.analyzer.finalizeAndFinishThroughEndOfInput()
            return try await session.results.value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Log.app.error("dictation failed: \(error.localizedDescription, privacy: .public)")
            throw DictationError.failed
        }
    }

    func cancel() async {
        guard let session else { return }
        self.session = nil
        stopAudio(session)
        session.feeder?.cancel()
        session.input.finish()
        session.updates.finish()
        session.results.cancel()
        await session.analyzer.cancelAndFinishNow()
    }

    private func stopAudio(_ session: Session) {
        guard let audio = session.audio else { return }
        audio.inputNode.removeTap(onBus: 0)
        audio.stop()
    }
}

/// Converts microphone buffers to the analyzer's format and measures the level. Runs on the
/// audio thread, so it's nonisolated and touches nothing but its own converter.
private final class AudioTap: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let output: AVAudioFormat
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let updates: AsyncStream<DictationUpdate>.Continuation

    init?(from source: AVAudioFormat, to output: AVAudioFormat, input: AsyncStream<AnalyzerInput>.Continuation,
          updates: AsyncStream<DictationUpdate>.Continuation) {
        guard let converter = AVAudioConverter(from: source, to: output) else { return nil }
        self.converter = converter
        self.output = output
        self.input = input
        self.updates = updates
    }

    func block() -> AVAudioNodeTapBlock {
        { [self] buffer, _ in process(buffer) }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        updates.yield(.level(Self.level(of: buffer)))
        if let converted = Self.convert(buffer, with: converter, to: output) {
            input.yield(AnalyzerInput(buffer: converted))
        }
    }

    static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                        to output: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && converted.frameLength > 0 ? converted : nil
    }

    /// RMS of the first channel, mapped to 0…1 on a -50…0 dB scale.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-6))
        return min(max((decibels + 50) / 50, 0), 1)
    }

    #if DEBUG
    /// Reads an audio file in real time, as if it came from the microphone.
    static func feed(fileAt url: URL, as output: AVAudioFormat, into input: AsyncStream<AnalyzerInput>.Continuation) async {
        guard let file = try? AVAudioFile(forReading: url),
              let converter = AVAudioConverter(from: file.processingFormat, to: output) else { return }
        let chunk: AVAudioFrameCount = 4096
        while !Task.isCancelled, file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
                  (try? file.read(into: buffer, frameCount: chunk)) != nil, buffer.frameLength > 0 else { break }
            if let converted = convert(buffer, with: converter, to: output) {
                input.yield(AnalyzerInput(buffer: converted))
            }
            try? await Task.sleep(for: .seconds(Double(buffer.frameLength) / file.processingFormat.sampleRate))
        }
    }
    #endif
}
