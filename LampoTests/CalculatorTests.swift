import Foundation
import Testing
@testable import Lampo

struct CalculatorTests {
    @Test(arguments: [
        ("2+2", 4.0), ("2 + 3 * 4", 14), ("(2 + 3) * 4", 20), ("10 / 4", 2.5),
        ("2^10", 1024), ("2^3^2", 512), ("-3 + 5", 2), ("3 × 4", 12), ("3 x 4", 12),
        ("12 ÷ 3", 4), ("200 * 15%", 30), ("3,5 * 2", 7), ("1.000,5 + 1", 1001.5),
        ("1,000.5 + 1", 1001.5), ("sqrt(16) + 1", 5), ("√9 * 2", 6), ("2(3+4)", 14),
        ("5 − 2", 3), ("abs(-4) + 1", 5), ("round(2.6) * 2", 6),
    ])
    func evaluates(_ input: String, _ expected: Double) throws {
        let result = try #require(Calculator.evaluate(input))
        let value = try result.get()
        #expect(abs(value - expected) < 1e-9, "\(input) → \(value)")
    }

    @Test(arguments: [
        "", "42", "ciao", "what is 2+2", "2 + ", "(2 + 3", "capitale della Francia",
        "translate this", "14:30", "e", "pi", "100 =",
    ])
    func rejectsNonMath(_ input: String) {
        #expect(Calculator.evaluate(input) == nil, "\(input)")
    }

    @Test func divisionByZeroIsUndefined() {
        #expect(Calculator.evaluate("1/0") == .failure(.undefined))
        #expect(Calculator.evaluate("sqrt(-1)") == .failure(.undefined))
    }

    @Test func constants() throws {
        let value = try #require(Calculator.evaluate("2 * pi")).get()
        #expect(abs(value - 2 * .pi) < 1e-12)
    }

    @Test func formatsWithLocale() {
        let italian = Locale(identifier: "it_IT")
        #expect(Calculator.format(12345, locale: italian) == "12.345")
        #expect(Calculator.format(2.5, locale: italian) == "2,5")
        #expect(Calculator.format(0.1 + 0.2, locale: Locale(identifier: "en_US")) == "0.3")
    }
}
