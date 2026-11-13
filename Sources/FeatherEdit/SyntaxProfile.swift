import AppKit

/// A very lightweight keyword/regex syntax profile (no tree-sitter; this is a
/// small-file editor). Applied to an NSTextStorage by SyntaxHighlighter.
struct SyntaxProfile {
    let name: String
    let keywords: Set<String>
    let types: Set<String>
    /// Line-comment prefix, e.g. "//" or "#".
    let lineComment: String?
    /// Block-comment delimiters, e.g. ("/*", "*/").
    let blockComment: (String, String)?

    static func forExtension(of url: URL) -> SyntaxProfile? {
        switch url.pathExtension.lowercased() {
        case "rs": return rust
        case "swift": return swift
        case "py", "pyw": return python
        case "js", "jsx", "ts", "tsx", "mjs": return javascript
        case "c", "h", "cpp", "cc", "hpp", "m", "mm": return cFamily
        case "go": return go
        case "sh", "bash", "zsh", "fish": return shell
        case "json": return json
        default: return nil
        }
    }

    // MARK: - Profiles

    static let rust = SyntaxProfile(
        name: "Rust",
        keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
                   "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop",
                   "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static",
                   "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"],
        types: ["bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize",
                "str", "u8", "u16", "u32", "u64", "u128", "usize", "String", "Vec", "Option",
                "Result", "Box", "HashMap", "Arc", "Rc"],
        lineComment: "//",
        blockComment: ("/*", "*/")
    )

    static let swift = SyntaxProfile(
        name: "Swift",
        keywords: ["associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
                   "func", "import", "init", "inout", "internal", "let", "open", "operator",
                   "private", "protocol", "public", "rethrows", "static", "struct", "subscript",
                   "typealias", "var", "break", "case", "catch", "continue", "default", "defer",
                   "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return",
                   "throw", "switch", "where", "while", "as", "false", "is", "nil", "self",
                   "Self", "super", "throws", "true", "try"],
        types: ["Any", "AnyObject", "Array", "Bool", "Character", "Dictionary", "Double",
                "Float", "Int", "Int32", "Int64", "Never", "Optional", "Set", "String", "URL"],
        lineComment: "//",
        blockComment: ("/*", "*/")
    )

    static let python = SyntaxProfile(
        name: "Python",
        keywords: ["and", "as", "assert", "async", "await", "break", "class", "continue", "def",
                   "del", "elif", "else", "except", "finally", "for", "from", "global", "if",
                   "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise",
                   "return", "try", "while", "with", "yield", "True", "False", "None"],
        types: ["int", "float", "str", "list", "dict", "set", "tuple", "bool", "bytes", "object"],
        lineComment: "#",
        blockComment: ("\"\"\"", "\"\"\"")
    )

    static let javascript = SyntaxProfile(
        name: "JavaScript",
        keywords: ["async", "await", "break", "case", "catch", "class", "const", "continue",
                   "debugger", "default", "delete", "do", "else", "export", "extends", "finally",
                   "for", "function", "if", "import", "in", "instanceof", "let", "new", "of",
                   "return", "static", "super", "switch", "this", "throw", "try", "typeof",
                   "var", "void", "while", "with", "yield", "true", "false", "null", "undefined"],
        types: ["Array", "Boolean", "Map", "Number", "Object", "Promise", "Set", "String", "Symbol"],
        lineComment: "//",
        blockComment: ("/*", "*/")
    )

    static let cFamily = SyntaxProfile(
        name: "C/C++",
        keywords: ["alignas", "auto", "break", "case", "catch", "class", "const", "constexpr",
                   "continue", "default", "delete", "do", "else", "enum", "explicit", "extern",
                   "for", "friend", "goto", "if", "inline", "namespace", "new", "noexcept",
                   "operator", "override", "private", "protected", "public", "return", "sizeof",
                   "static", "struct", "switch", "template", "this", "throw", "try", "typedef",
                   "typename", "union", "using", "virtual", "volatile", "while", "true", "false",
                   "nullptr", "NULL"],
        types: ["bool", "char", "double", "float", "int", "long", "short", "signed", "unsigned",
                "size_t", "void", "std", "uint32_t", "uint64_t", "int32_t", "int64_t"],
        lineComment: "//",
        blockComment: ("/*", "*/")
    )

    static let go = SyntaxProfile(
        name: "Go",
        keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else",
                   "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
                   "map", "package", "range", "return", "select", "struct", "switch", "type",
                   "var", "nil", "true", "false", "iota"],
        types: ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int",
                "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16",
                "uint32", "uint64", "uintptr"],
        lineComment: "//",
        blockComment: ("/*", "*/")
    )

    static let shell = SyntaxProfile(
        name: "Shell",
        keywords: ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
                   "case", "esac", "function", "in", "select", "time", "return", "break",
                   "continue", "local", "export", "readonly", "declare", "unset", "eval", "exit"],
        types: [],
        lineComment: "#",
        blockComment: nil
    )

    static let json = SyntaxProfile(
        name: "JSON",
        keywords: ["true", "false", "null"],
        types: [],
        lineComment: nil,
        blockComment: nil
    )
}
