import Foundation

/// Wire limits count UTF-16 units; retain complete characters when bounding evidence or labels.
enum ConnectText {
    static func bounded(_ text: String, to limit: Int) -> String {
        var result = ""
        var count = 0
        for character in text {
            let width = String(character).utf16.count
            guard count + width <= limit else { break }
            result.append(character)
            count += width
        }
        return result
    }
}
