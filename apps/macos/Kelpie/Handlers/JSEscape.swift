import Foundation

/// Escapes a string for safe interpolation inside a JavaScript single-quoted string literal.
enum JSEscape {
    static func string(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count + 8)
        for char in value {
            switch char {
            case "\\": result += "\\\\"
            case "'":  result += "\\'"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{2028}": result += "\\u2028"
            case "\u{2029}": result += "\\u2029"
            default: result.append(char)
            }
        }
        return result
    }
}
