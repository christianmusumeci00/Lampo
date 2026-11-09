import Testing
@testable import Lampo

struct PromptTemplateTests {
    let context = TemplateContext(selection: "ciao mondo", clipboard: "clip", app: "Mail", language: "Italian")

    @Test func replacesAllVariables() {
        let output = PromptTemplate.render(
            "Fix {{ selection }} from {{app}} in {{language}}. Also {{clipboard}}",
            context: context, input: .selection)
        #expect(output == "Fix <text>\nciao mondo\n</text> from Mail in Italian. Also <text>\nclip\n</text>")
    }

    @Test func appendsInputWhenTemplateOmitsIt() {
        let output = PromptTemplate.render("Make it funnier.", context: context, input: .selection)
        #expect(output == "Make it funnier.\n\n<text>\nciao mondo\n</text>")
    }

    @Test func clipboardInputAppended() {
        let output = PromptTemplate.render("Summarize.", context: context, input: .clipboard)
        #expect(output.hasSuffix("<text>\nclip\n</text>"))
    }

    @Test func noInputActionsAppendNothing() {
        #expect(PromptTemplate.render("Tell me a joke about {{app}}", context: context, input: .none)
                == "Tell me a joke about Mail")
    }

    @Test func replacementTextIsLiteral() {
        let tricky = TemplateContext(selection: "price $1 and \\0", clipboard: nil, app: nil, language: "English")
        let output = PromptTemplate.render("{{selection}}", context: tricky, input: .selection)
        #expect(output == "<text>\nprice $1 and \\0\n</text>")
    }

    @Test func detectsTheTextLanguage() {
        let italian = TemplateContext(selection: "ciao, ti scrivo per dirti che domani non posso venire alla riunione",
                                      clipboard: nil, app: nil, language: "English")
        #expect(PromptTemplate.render("Keep it in {{text_language}}.", context: italian, input: .none)
                == "Keep it in Italian.")
        let short = TemplateContext(selection: "ok", clipboard: nil, app: nil, language: "English")
        #expect(short.textLanguage == "the same language as the text")
    }

    @Test func typosDontMakeEnglishCatalan() {
        let sloppy = "hi Marta, i cant come tomorow to the meeting becuase i have a dentist appointment, can we move it to friday?"
        #expect(TextLanguage.name(of: sloppy, likely: ["it", "en"]) == "English")
        // Clear text in another language keeps its language.
        #expect(TextLanguage.name(of: "Bon dia Marta, demà no puc venir a la reunió perquè tinc hora amb el dentista.",
                                  likely: ["it", "en"]) == "Catalan")
        #expect(TextLanguage.name(of: "Hola Marta, no puedo ir mañana a la reunión porque tengo cita con el dentista.",
                                  likely: ["it", "en"]) == "Spanish")
        #expect(TextLanguage.name(of: "Salut Marta, je ne peux pas venir demain à la réunion car j'ai rendez-vous chez le dentiste.",
                                  likely: ["it", "en"]) == "French")
    }

    @Test func unknownVariables() {
        #expect(PromptTemplate.unknownVariables(in: "{{selecton}} {{app}} {{ foo }}") == ["selecton", "foo"])
    }

    @Test func builtInsRenderTheirSelection() {
        for action in BuiltInActions.all where action.input == .selection {
            let output = PromptTemplate.render(action.promptTemplate, context: context, input: action.input)
            #expect(output.contains("ciao mondo"), "\(action.name)")
            #expect(!output.contains("{{"), "\(action.name)")
        }
    }
}

struct RewriteCleanerTests {
    @Test(arguments: [
        ("  Hello there.  ", "Hello there."),
        ("\"Hello there.\"", "Hello there."),
        ("“Ciao a tutti.”", "Ciao a tutti."),
        ("Here is the corrected text:\nHello there.", "Hello there."),
        ("Ecco il testo corretto:\n\nCiao.", "Ciao."),
        ("<text>\nCiao.\n</text>", "Ciao."),
        ("He said \"hi\" and \"bye\"", "He said \"hi\" and \"bye\""),
        ("Note: keep this line\nSecond", "Note: keep this line\nSecond"),
    ])
    func cleans(_ input: String, _ expected: String) {
        #expect(RewriteCleaner.clean(input) == expected)
    }

    @Test func keepsQuotesWhenOriginalWasQuoted() {
        #expect(RewriteCleaner.clean("\"Hi.\"", original: "\"hi\"") == "\"Hi.\"")
    }

    @Test func keepsTrailingNewlineOfOriginal() {
        #expect(RewriteCleaner.clean("Fixed paragraph.", original: "fixd paragraph.\n") == "Fixed paragraph.\n")
    }
}
