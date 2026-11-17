import Foundation

/// Re-indents JSON text without changing anything else: object key order,
/// number spelling and string escapes are preserved verbatim; only the
/// whitespace between tokens is normalized (one item per line, two-space
/// indentation, ": " after keys).
enum JSONFormatter {

    private struct Token {
        enum Kind {
            case openBrace, closeBrace, openBracket, closeBracket
            case comma, colon, value
        }
        let kind: Kind
        let text: String
    }

    /// Pretty-print `json`. Returns nil if the text could not be tokenized
    /// (callers are expected to validate with JSONSerialization first, so
    /// this only happens on input the system parser somehow accepts but the
    /// tokenizer cannot handle).
    static func prettyPrint(_ json: String) -> String? {
        guard let tokens = tokenize(json) else { return nil }
        var out = ""
        var indent = 0
        var atLineStart = false
        func indentSpaces() {
            if atLineStart {
                out += String(repeating: "  ", count: max(indent, 0))
                atLineStart = false
            }
        }

        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            switch token.kind {
            case .openBrace, .openBracket:
                let closer: Token.Kind = token.kind == .openBrace ? .closeBrace : .closeBracket
                indentSpaces()
                // Empty object/array: "{}" / "[]".
                if i + 1 < tokens.count, tokens[i + 1].kind == closer {
                    out += token.text + tokens[i + 1].text
                    i += 2
                } else {
                    out += token.text
                    indent += 1
                    out += "\n"
                    atLineStart = true
                    i += 1
                }
            case .closeBrace, .closeBracket:
                indent -= 1
                if !atLineStart {
                    out += "\n"
                    atLineStart = true
                }
                indentSpaces()
                out += token.text
                i += 1
            case .comma:
                out += ",\n"
                atLineStart = true
                i += 1
            case .colon:
                out += ": "
                i += 1
            case .value:
                indentSpaces()
                out += token.text
                i += 1
            }
        }
        return out
    }

    // MARK: - Tokenizer

    /// Split JSON into punctuation and verbatim value tokens, skipping
    /// whitespace. Returns nil on anything unexpected.
    private static func tokenize(_ json: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(json)
        var i = 0

        func skipWhitespace() {
            while i < chars.count, " \t\n\r".contains(chars[i]) {
                i += 1
            }
        }

        while true {
            skipWhitespace()
            guard i < chars.count else { break }
            let c = chars[i]

            switch c {
            case "{":
                tokens.append(Token(kind: .openBrace, text: "{")); i += 1
            case "}":
                tokens.append(Token(kind: .closeBrace, text: "}")); i += 1
            case "[":
                tokens.append(Token(kind: .openBracket, text: "[")); i += 1
            case "]":
                tokens.append(Token(kind: .closeBracket, text: "]")); i += 1
            case ",":
                tokens.append(Token(kind: .comma, text: ",")); i += 1
            case ":":
                tokens.append(Token(kind: .colon, text: ":")); i += 1
            case "\"":
                // A string, kept verbatim including its escapes.
                var j = i + 1
                while j < chars.count {
                    if chars[j] == "\\" {
                        // Skip the escaped character (or a \uXXXX escape).
                        j = chars[j + 1] == "u" && j + 5 < chars.count ? j + 6 : j + 2
                        continue
                    }
                    if chars[j] == "\"" { break }
                    j += 1
                }
                guard j < chars.count else { return nil }  // unterminated string
                tokens.append(Token(kind: .value, text: String(chars[i...j])))
                i = j + 1
            default:
                // A number, kept verbatim (1.50 stays 1.50), or a literal.
                var j = i
                while j < chars.count, "-+.eE0123456789".contains(chars[j]) {
                    j += 1
                }
                if j > i {
                    tokens.append(Token(kind: .value, text: String(chars[i..<j])))
                    i = j
                    continue
                }
                // true / false / null.
                var matched = false
                for literal in ["true", "false", "null"] {
                    let literalChars = Array(literal)
                    let end = min(i + literalChars.count, chars.count)
                    if chars[i..<end].elementsEqual(literalChars) {
                        tokens.append(Token(kind: .value, text: literal))
                        i += literalChars.count
                        matched = true
                        break
                    }
                }
                if !matched { return nil }
            }
        }
        return tokens
    }
}
