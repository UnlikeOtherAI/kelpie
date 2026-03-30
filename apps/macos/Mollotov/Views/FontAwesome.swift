import SwiftUI
import AppKit

/// Provides Font Awesome Brand icons for use in SwiftUI views.
enum FontAwesome {
    /// Register the Font Awesome Brands font from the app bundle.
    /// Call once at app startup.
    static func registerFonts() {
        // Try root Resources first, then nested Resources/ subdirectory (folder reference)
        let url = Bundle.main.url(forResource: "FontAwesome6Brands-Regular", withExtension: "otf")
            ?? Bundle.main.url(forResource: "FontAwesome6Brands-Regular", withExtension: "otf", subdirectory: "Resources")
        guard let url else {
            NSLog("[FontAwesome] Font file not found in bundle")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            NSLog("[FontAwesome] Failed to register font: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
        }
    }

    // Unicode codepoints for FA 6 Brands
    static let chrome  = "\u{f268}"
    static let safari  = "\u{f267}"

    /// The PostScript font name used by Font Awesome 6 Brands.
    static let brandsFontName = "FontAwesome6Brands-Regular"
    /// The family name (used by SwiftUI .custom on macOS).
    static let brandsFamilyName = "Font Awesome 6 Brands"
}

/// A SwiftUI view that renders a Font Awesome Brands icon.
struct FAIcon: View {
    let icon: String
    var size: CGFloat = 14

    var body: some View {
        Text(icon)
            .font(.custom(FontAwesome.brandsFamilyName, size: size))
    }
}
