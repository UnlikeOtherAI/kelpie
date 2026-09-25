import AppKit
import SwiftUI

struct ChromeRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = Self(red: 1, green: 1, blue: 1)
    static let ink = Self(red: 0.15, green: 0.20, blue: 0.30)
    static let tabGray = Self(red: 229 / 255, green: 234 / 255, blue: 243 / 255)
    var color: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    func mixed(with other: Self, progress: Double) -> Self {
        let amount = min(1, max(0, progress))
        return Self(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }
    func distance(to other: Self) -> Double {
        max(abs(red - other.red), abs(green - other.green), abs(blue - other.blue))
    }
}

struct BrowserChromePalette: Equatable {
    var background: ChromeRGB
    var foreground: ChromeRGB
    var selectedTab: ChromeRGB
    var inactiveTab: ChromeRGB
    var selectedTabOpacity: Double
    var field: ChromeRGB

    static let neutral = Self(sample: .white)

    init(sample: ChromeRGB, collapsed: Bool = false) {
        background = sample
        let dark = sample.luminance < 0.35
        foreground = dark ? .white : .ink
        selectedTab = sample
        selectedTabOpacity = 1
        inactiveTab = .tabGray
        field = sample.mixed(with: dark ? .white : .ink, progress: dark ? 0.10 : 0.05)
    }

    func mixed(with other: Self, progress: Double) -> Self {
        var value = self
        value.background = background.mixed(with: other.background, progress: progress)
        value.foreground = foreground.mixed(with: other.foreground, progress: progress)
        value.selectedTab = selectedTab.mixed(with: other.selectedTab, progress: progress)
        value.selectedTabOpacity = selectedTabOpacity + (other.selectedTabOpacity - selectedTabOpacity) * min(1, max(0, progress))
        value.inactiveTab = inactiveTab.mixed(with: other.inactiveTab, progress: progress)
        value.field = field.mixed(with: other.field, progress: progress)
        return value
    }
}

/// One transition clock for every foreground and background in a window's chrome.
@MainActor
final class BrowserChromeAppearance: ObservableObject {
    @Published private(set) var palette = BrowserChromePalette.neutral
    private var target = BrowserChromePalette.neutral
    private var transition: Task<Void, Never>?
    private var sample: ChromeRGB?
    private var collapsed = false

    init() {
        let initial = BrowserChromePalette(sample: Self.defaultBackground)
        palette = initial
        target = initial
    }

    private static var defaultBackground: ChromeRGB {
        NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? ChromeRGB(red: 0.11, green: 0.12, blue: 0.14) : .white
    }

    func setSample(_ sample: ChromeRGB?) {
        self.sample = sample
        updateTarget()
    }

    func setCollapsed(_ collapsed: Bool) {
        self.collapsed = collapsed
        updateTarget()
    }

    private func updateTarget() {
        let next = BrowserChromePalette(sample: sample ?? Self.defaultBackground, collapsed: collapsed)
        guard next.background.distance(to: target.background) > 0.035 || next.selectedTabOpacity != target.selectedTabOpacity else { return }
        target = next
        transition?.cancel()
        let start = palette
        transition = Task { [weak self] in
            for step in 1...12 {
                do { try await Task.sleep(nanoseconds: 16_666_667) } catch { return }
                guard let self, !Task.isCancelled else { return }
                let fraction = Double(step) / 12
                let eased = fraction * fraction * (3 - 2 * fraction)
                self.palette = start.mixed(with: next, progress: eased)
            }
        }
    }

    deinit { transition?.cancel() }
}
