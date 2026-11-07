import Foundation

/// Evaluates purely mathematical input locally, so the panel answers instantly
/// and exactly without calling the model.
///
/// Supports `+ - * / ^`, `×`, `÷`, `−`, parentheses, postfix `%` (x/100),
/// functions `sqrt √ sin cos tan ln log abs round`, constants `pi π e`, and both
/// `.` and `,` as decimal separators. Input must contain at least one operator or
/// function, so a bare number is not treated as a calculation.
enum Calculator {
    enum Failure: Error, Equatable {
        case notMath
        case undefined
    }

    /// Returns nil when the input is not a pure math expression.
    static func evaluate(_ input: String) -> Result<Double, Failure>? {
        do {
            return .success(try strictEvaluate(input))
        } catch .undefined {
            return .failure(.undefined)
        } catch {
            return nil
        }
    }

    static func strictEvaluate(_ input: String) throws(Failure) -> Double {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("=") { trimmed.removeLast() }
        guard !trimmed.isEmpty, trimmed.count <= 500 else { throw .notMath }
        let tokens = try tokenize(trimmed)
        guard tokens.contains(where: \.isOperatorOrFunction) else { throw .notMath }
        var parser = Parser(tokens: tokens)
        let value = try parser.parseExpression()
        guard parser.isAtEnd else { throw .notMath }
        guard value.isFinite else { throw .undefined }
        return value
    }

    /// Formats a result for display: up to 12 significant digits, no exponent for
    /// ordinary magnitudes, using the given locale's separators.
    static func format(_ value: Double, locale: Locale = .current) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return Int64(value).formatted(.number.locale(locale))
        }
        return value.formatted(.number.precision(.significantDigits(1...12)).locale(locale))
    }

    // MARK: - Tokens

    enum Token: Equatable {
        case number(Double)
        case op(Character)
        case lparen, rparen
        case function(String)

        var isOperatorOrFunction: Bool {
            switch self {
            case .op, .function: return true
            default: return false
            }
        }
    }

    private static let functions: Set<String> = ["sqrt", "sin", "cos", "tan", "ln", "log", "abs", "round"]

    static func tokenize(_ s: String) throws(Failure) -> [Token] {
        var tokens: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c.isWhitespace {
                i = s.index(after: i)
            } else if c.isNumber && c.isASCII || ((c == "." || c == ",") && s.index(after: i) < s.endIndex && s[s.index(after: i)].isNumber) {
                var j = i
                while j < s.endIndex, s[j].isASCII, s[j].isNumber || s[j] == "." || s[j] == "," { j = s.index(after: j) }
                tokens.append(.number(try parseNumber(String(s[i..<j]))))
                i = j
            } else if c.isLetter || c == "√" || c == "π" {
                if c == "√" { tokens.append(.function("sqrt")); i = s.index(after: i); continue }
                if c == "π" { tokens.append(.number(.pi)); i = s.index(after: i); continue }
                var j = i
                while j < s.endIndex, s[j].isLetter { j = s.index(after: j) }
                let word = s[i..<j].lowercased()
                if word == "x" {
                    tokens.append(.op("*"))   // "3 x 4"
                } else if word == "pi" {
                    tokens.append(.number(.pi))
                } else if word == "e" {
                    tokens.append(.number(M_E))
                } else if functions.contains(word) {
                    tokens.append(.function(word))
                } else {
                    throw .notMath
                }
                i = j
            } else {
                switch c {
                case "+", "-", "*", "/", "^", "%": tokens.append(.op(c))
                case "×", "·": tokens.append(.op("*"))
                case "÷": tokens.append(.op("/"))
                case "−", "–": tokens.append(.op("-"))
                case "(": tokens.append(.lparen)
                case ")": tokens.append(.rparen)
                default: throw .notMath
                }
                i = s.index(after: i)
            }
        }
        return tokens
    }

    /// "3,5" and "3.5" are 3.5; "1.000,5" and "1,000.5" are 1000.5; "1.000.000" is 1e6.
    static func parseNumber(_ raw: String) throws(Failure) -> Double {
        let dots = raw.filter { $0 == "." }.count
        let commas = raw.filter { $0 == "," }.count
        var normalized = raw
        if dots > 0 && commas > 0 {
            let lastDot = raw.lastIndex(of: ".")!
            let lastComma = raw.lastIndex(of: ",")!
            let decimal: Character = lastDot > lastComma ? "." : ","
            let grouping: Character = decimal == "." ? "," : "."
            guard raw.filter({ $0 == decimal }).count == 1 else { throw .notMath }
            normalized = raw.replacingOccurrences(of: String(grouping), with: "")
                .replacingOccurrences(of: ",", with: ".")
        } else if dots > 1 || commas > 1 {
            normalized = raw.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
        } else {
            normalized = raw.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(normalized) else { throw .notMath }
        return value
    }

    // MARK: - Parser (recursive descent)

    private struct Parser {
        let tokens: [Token]
        var index = 0

        var isAtEnd: Bool { index >= tokens.count }

        private var current: Token? { isAtEnd ? nil : tokens[index] }

        mutating func parseExpression() throws(Failure) -> Double {
            var value = try parseTerm()
            while case .op(let op)? = current, op == "+" || op == "-" {
                index += 1
                let rhs = try parseTerm()
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() throws(Failure) -> Double {
            var value = try parseUnary()
            while true {
                if case .op(let op)? = current, op == "*" || op == "/" {
                    index += 1
                    let rhs = try parseUnary()
                    if op == "/" && rhs == 0 { throw .undefined }
                    value = op == "*" ? value * rhs : value / rhs
                } else if case .lparen? = current {
                    // Implicit multiplication: 2(3+4)
                    value *= try parseUnary()
                } else if case .function? = current {
                    value *= try parseUnary()
                } else {
                    return value
                }
            }
        }

        mutating func parseUnary() throws(Failure) -> Double {
            if case .op(let op)? = current, op == "-" || op == "+" {
                index += 1
                let value = try parseUnary()
                return op == "-" ? -value : value
            }
            return try parsePower()
        }

        mutating func parsePower() throws(Failure) -> Double {
            let base = try parsePostfix()
            if case .op("^")? = current {
                index += 1
                let exponent = try parseUnary()   // right-associative
                return pow(base, exponent)
            }
            return base
        }

        mutating func parsePostfix() throws(Failure) -> Double {
            var value = try parsePrimary()
            while case .op("%")? = current {
                index += 1
                value /= 100
            }
            return value
        }

        mutating func parsePrimary() throws(Failure) -> Double {
            guard let token = current else { throw .notMath }
            index += 1
            switch token {
            case .number(let value):
                return value
            case .lparen:
                let value = try parseExpression()
                guard case .rparen? = current else { throw .notMath }
                index += 1
                return value
            case .function(let name):
                let argument = try parsePostfixOrUnaryArgument()
                return try apply(name, argument)
            default:
                throw .notMath
            }
        }

        /// Function argument: parenthesised expression, or a bare number (√9, sqrt 9).
        mutating func parsePostfixOrUnaryArgument() throws(Failure) -> Double {
            if case .lparen? = current { return try parsePostfix() }
            return try parseUnary()
        }

        func apply(_ name: String, _ x: Double) throws(Failure) -> Double {
            switch name {
            case "sqrt":
                guard x >= 0 else { throw .undefined }
                return x.squareRoot()
            case "sin": return sin(x)
            case "cos": return cos(x)
            case "tan": return tan(x)
            case "ln":
                guard x > 0 else { throw .undefined }
                return log(x)
            case "log":
                guard x > 0 else { throw .undefined }
                return log10(x)
            case "abs": return abs(x)
            case "round": return x.rounded()
            default: throw .notMath
            }
        }
    }
}
