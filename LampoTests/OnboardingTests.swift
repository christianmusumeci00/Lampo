import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Lampo

@MainActor
struct OnboardingProgressTests {
    @Test func startsAtTheFirstStepAndRemembersTheStep() {
        let defaults = makeTestDefaults()
        let progress = OnboardingProgress(defaults: defaults)
        #expect(!progress.isFinished)
        #expect(progress.step == .welcome)
        progress.step = .screenRecording
        #expect(OnboardingProgress(defaults: defaults).step == .screenRecording)
    }

    @Test func finishingForgetsTheStep() {
        let defaults = makeTestDefaults()
        let progress = OnboardingProgress(defaults: defaults)
        progress.step = .dictation
        progress.finish()
        #expect(progress.isFinished)
        #expect(progress.step == .welcome)
    }

    @Test func anUnknownStepStartsOver() {
        let defaults = makeTestDefaults()
        defaults.set(99, forKey: OnboardingProgress.stepKey)
        #expect(OnboardingProgress(defaults: defaults).step == .welcome)
    }

    @Test func theModelResumesSavesAndFinishes() {
        let defaults = makeTestDefaults()
        let progress = OnboardingProgress(defaults: defaults)
        progress.step = .preferences
        let model = OnboardingModel(progress: progress, permissions: PermissionMonitor(probe: .denied))
        #expect(model.step == .preferences)

        var finished: [Bool] = []
        model.onFinish = { finished.append($0) }
        model.goForward()
        #expect(model.step == .ready)
        #expect(progress.step == .ready)
        model.goForward()
        #expect(finished == [false])

        model.step = .welcome
        model.goBack()
        #expect(model.step == .welcome)
    }

    @Test func aFinishedGuideOpensFromTheStart() {
        let defaults = makeTestDefaults()
        let progress = OnboardingProgress(defaults: defaults)
        progress.step = .ready
        progress.finish()
        #expect(OnboardingModel(progress: progress, permissions: PermissionMonitor(probe: .denied)).step == .welcome)
    }

    @Test func stepsAreInOrder() {
        #expect(OnboardingStep.allCases.first == .welcome)
        #expect(OnboardingStep.allCases.last == .ready)
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.ready.next == nil)
        #expect(OnboardingStep.features.next == .accessibility)
    }
}

@MainActor
struct PermissionMonitorTests {
    final class Switches {
        var accessibility = false
        var screenRecording = false
    }

    @Test func callsBackOnlyWhenAPermissionIsTurnedOn() {
        let switches = Switches()
        let monitor = PermissionMonitor(probe: .init(
            accessibility: { switches.accessibility }, screenRecording: { switches.screenRecording },
            microphone: { .notDetermined }, calendars: { false }, reminders: { false }))
        var calls = 0
        monitor.onGranted = { calls += 1 }

        monitor.refresh()
        #expect(calls == 0)
        switches.accessibility = true
        monitor.refresh()
        #expect(calls == 1)
        #expect(monitor.accessibility)
        monitor.refresh()
        #expect(calls == 1)
        switches.screenRecording = true
        monitor.refresh()
        #expect(calls == 2)
        switches.accessibility = false
        monitor.refresh()
        #expect(calls == 2)
    }

    @Test func alreadyGrantedAtLaunchIsNotNews() {
        let monitor = PermissionMonitor(probe: .init(
            accessibility: { true }, screenRecording: { true },
            microphone: { .authorized }, calendars: { true }, reminders: { false }))
        var calls = 0
        monitor.onGranted = { calls += 1 }
        monitor.refresh()
        #expect(calls == 0)
        #expect(monitor.microphone == .authorized)
        #expect(monitor.calendars)
        #expect(!monitor.reminders)
    }
}

extension PermissionMonitor.Probe {
    static var denied: PermissionMonitor.Probe {
        PermissionMonitor.Probe(
        accessibility: { false }, screenRecording: { false },
            microphone: { .notDetermined }, calendars: { false }, reminders: { false })
    }
}

@MainActor
struct WelcomeWindowTests {
    @Test func centersInTheVisibleFrame() {
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 949)
        #expect(FrontWindow.centeredOrigin(for: NSSize(width: 640, height: 592), in: visible) == NSPoint(x: 436, y: 179))
        // A second screen to the left, below the first.
        let other = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
        #expect(FrontWindow.centeredOrigin(for: NSSize(width: 640, height: 592), in: other) == NSPoint(x: -1280, y: 44))
    }

    @Test func hasADockIconWhileAGuideWindowIsOpen() {
        var policies: [NSApplication.ActivationPolicy] = []
        let dock = DockPresence { policies.append($0) }
        let first = FrontWindow.make(title: "One", size: NSSize(width: 200, height: 100), content: EmptyViewForTests())
        let second = FrontWindow.make(title: "Two", size: NSSize(width: 200, height: 100), content: EmptyViewForTests())

        #expect(!dock.bringBack())
        dock.attach(first)
        dock.attach(first)
        dock.attach(second)
        #expect(policies == [.regular])
        #expect(dock.hasWindows)

        first.close()
        #expect(policies == [.regular])
        second.close()
        #expect(policies == [.regular, .accessory])
        #expect(!dock.hasWindows)
    }
}

private struct EmptyViewForTests: View {
    var body: some View { Color.clear }
}

struct AppLanguageTests {
    @Test func englishUntilTheUserChoosesItalian() throws {
        let name = "LampoTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(AppLanguage.current(defaults: defaults, domain: name) == .english)
        #expect(AppLanguage.applyDefault(defaults: defaults, domain: name))
        #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] as? [String] == ["en"])
        #expect(!AppLanguage.applyDefault(defaults: defaults, domain: name))

        AppLanguage.choose(.italian, defaults: defaults)
        #expect(AppLanguage.current(defaults: defaults, domain: name) == .italian)
        #expect(!AppLanguage.applyDefault(defaults: defaults, domain: name))
        #expect(AppLanguage.current(defaults: defaults, domain: name) == .italian)
    }

    @Test func regionalAndUnknownLanguages() throws {
        let name = "LampoTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["it-IT"], forKey: "AppleLanguages")
        #expect(AppLanguage.current(defaults: defaults, domain: name) == .italian)
        defaults.set(["fr-FR"], forKey: "AppleLanguages")
        #expect(AppLanguage.current(defaults: defaults, domain: name) == .english)
    }

    @Test func theMacsLanguageStillDecidesAnswers() {
        let global: [String: Any] = ["AppleLanguages": ["it-IT", "en-US"]]
        #expect(SystemLanguage.preferred(global: global) == ["it-IT", "en-US"])
        #expect(SystemLanguage.code(preferred: ["it-IT", "en-US"]) == "it")
        #expect(SystemLanguage.code(preferred: []) == "en")
        #expect(!SystemLanguage.preferred(global: [:]).isEmpty)

        #expect(TranslationPlanner.userLanguage(.automatic, systemLanguage: "it") == "it")
        #expect(TranslationPlanner.userLanguage(.english, systemLanguage: "it") == "en")
        #expect(SystemInstructions.languageName(.automatic, systemLanguage: "it") == "Italian")
        #expect(SystemInstructions.answerLanguage(for: "", preference: .automatic, systemLanguage: "it") == "Italian")
    }
}

@MainActor
struct BuiltInNameLanguageTests {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("LampoTests-\(UUID().uuidString)").appendingPathComponent("actions.json")

    @Test func shippedNamesCoverEveryLanguage() {
        let names = BuiltInActions.shippedNames(for: BuiltInActions.correctID)
        #expect(names.contains("Correct"))
        #expect(names.contains("Correggi"))
        #expect(BuiltInActions.shippedNames(for: UUID()).isEmpty)
        // Every built-in has its English name listed, and its current name is one of them.
        for action in BuiltInActions.all {
            #expect(BuiltInActions.shippedNames(for: action.id).contains(action.name))
        }
    }

    @Test func untouchedBuiltInNamesFollowTheLanguage() {
        func shipped(_ name: String, _ id: UUID) -> LampoAction {
            LampoAction(id: id, name: name, symbol: "star", promptTemplate: "{{selection}}", isBuiltIn: true)
        }
        // Saved while Lampo was in Italian; one of them renamed by the user.
        _ = ActionStore(fileURL: url, builtIns: {
            [shipped("Correggi", BuiltInActions.correctID), shipped("Riscrivi", BuiltInActions.rewriteID)]
        })
        let saved = ActionStore(fileURL: url, builtIns: {
            [shipped("Correggi", BuiltInActions.correctID), shipped("Riscrivi", BuiltInActions.rewriteID)]
        })
        var renamed = saved.action(id: BuiltInActions.rewriteID)!
        renamed.name = "Il mio stile"
        saved.update(renamed)

        // Now in English.
        let reloaded = ActionStore(fileURL: url, builtIns: {
            [shipped("Correct", BuiltInActions.correctID), shipped("Rewrite", BuiltInActions.rewriteID)]
        })
        #expect(reloaded.action(id: BuiltInActions.correctID)?.name == "Correct")
        #expect(reloaded.action(id: BuiltInActions.rewriteID)?.name == "Il mio stile")
    }
}
