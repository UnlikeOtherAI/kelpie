import AppKit
import Combine

enum DeviceKind { case phone, tablet }

enum ViewportOrientation: String {
    case portrait = "portrait"
    case landscape = "landscape"
}

struct DesktopViewportPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let label: String
    let menuLabel: String           // shown in dropdown: e.g. "6.1\" Compact"
    let kind: DeviceKind
    let displaySizeLabel: String
    let pixelResolutionLabel: String
    let portraitSize: CGSize
}

let macPhonePresets: [DesktopViewportPreset] = [
    .init(id: "compact-base",      name: "Compact / Base",       label: "Compact",  menuLabel: "6.1\" Compact",    kind: .phone, displaySizeLabel: "6.1\" - 6.3\"", pixelResolutionLabel: "1170 x 2532 - 1206 x 2622", portraitSize: CGSize(width: 393, height: 852)),
    .init(id: "standard-pro",      name: "Standard / Pro",       label: "Standard", menuLabel: "6.2\" Standard",   kind: .phone, displaySizeLabel: "6.2\" - 6.4\"", pixelResolutionLabel: "1080 x 2340 - 1280 x 2856", portraitSize: CGSize(width: 402, height: 874)),
    .init(id: "large-plus",        name: "Large / Plus",         label: "Large",    menuLabel: "6.7\" Large",      kind: .phone, displaySizeLabel: "6.5\" - 6.7\"", pixelResolutionLabel: "1260 x 2736 - 1440 x 3120", portraitSize: CGSize(width: 430, height: 932)),
    .init(id: "ultra-pro-max",     name: "Ultra / Pro Max",      label: "Ultra",    menuLabel: "6.8\" Ultra",      kind: .phone, displaySizeLabel: "6.8\" - 6.9\"", pixelResolutionLabel: "1320 x 2868 - 1440 x 3120", portraitSize: CGSize(width: 440, height: 956)),
    .init(id: "book-fold-internal",name: "Book Fold (Internal)", label: "Book In",  menuLabel: "7.6\" Book Fold",  kind: .phone, displaySizeLabel: "7.6\" - 8.0\"", pixelResolutionLabel: "2076 x 2152 - 2160 x 2440", portraitSize: CGSize(width: 904, height: 1136)),
    .init(id: "book-fold-cover",   name: "Book Fold (Cover)",    label: "Book C",   menuLabel: "6.3\" Book Cover", kind: .phone, displaySizeLabel: "6.3\" - 6.5\"", pixelResolutionLabel: "1080 x 2364 - 1116 x 2484", portraitSize: CGSize(width: 360, height: 800)),
    .init(id: "flip-fold-internal",name: "Flip Fold (Internal)", label: "Flip In",  menuLabel: "6.7\" Flip Fold",  kind: .phone, displaySizeLabel: "6.7\" - 6.9\"", pixelResolutionLabel: "1080 x 2640 - 1200 x 2844", portraitSize: CGSize(width: 412, height: 914)),
    .init(id: "flip-fold-cover",   name: "Flip Fold (Cover)",    label: "Flip C",   menuLabel: "3.4\" Flip Cover", kind: .phone, displaySizeLabel: "3.4\" - 4.1\"", pixelResolutionLabel: "720 x 748 - 1056 x 1066",   portraitSize: CGSize(width: 360, height: 380)),
    .init(id: "tri-fold-internal", name: "Tri-Fold (Internal)",  label: "Tri",      menuLabel: "10\" Tri-Fold",    kind: .phone, displaySizeLabel: "~10.0\"",        pixelResolutionLabel: "2800 x 3200",               portraitSize: CGSize(width: 980, height: 1120)),
]

let macTabletPresets: [DesktopViewportPreset] = [
    .init(id: "ipad-mini",   name: "iPad mini",          label: "mini",    menuLabel: "8.3\" iPad mini",   kind: .tablet, displaySizeLabel: "8.3\"",  pixelResolutionLabel: "1488 x 2266", portraitSize: CGSize(width: 744,  height: 1133)),
    .init(id: "ipad-10",     name: "iPad 10.9\"",        label: "iPad",    menuLabel: "10.9\" iPad",       kind: .tablet, displaySizeLabel: "10.9\"", pixelResolutionLabel: "1640 x 2360", portraitSize: CGSize(width: 820,  height: 1180)),
    .init(id: "ipad-pro-11", name: "iPad Pro 11\"",      label: "Pro 11",  menuLabel: "11\" iPad Pro",     kind: .tablet, displaySizeLabel: "11\"",   pixelResolutionLabel: "1668 x 2388", portraitSize: CGSize(width: 834,  height: 1194)),
    .init(id: "ipad-air-13", name: "iPad Air 13\"",      label: "Air 13",  menuLabel: "13\" iPad Air",     kind: .tablet, displaySizeLabel: "13\"",   pixelResolutionLabel: "2048 x 2732", portraitSize: CGSize(width: 1024, height: 1366)),
    .init(id: "ipad-pro-13", name: "iPad Pro 13\"",      label: "Pro 13",  menuLabel: "13\" iPad Pro",     kind: .tablet, displaySizeLabel: "13\"",   pixelResolutionLabel: "2064 x 2752", portraitSize: CGSize(width: 1032, height: 1376)),
    .init(id: "tab-s-11",    name: "Galaxy Tab S 11\"",  label: "Tab 11",  menuLabel: "11\" Galaxy Tab S", kind: .tablet, displaySizeLabel: "11\"",   pixelResolutionLabel: "1600 x 2560", portraitSize: CGSize(width: 800,  height: 1280)),
    .init(id: "tab-s-12",    name: "Galaxy Tab S 12.4\"",label: "Tab 12",  menuLabel: "12.4\" Galaxy Tab", kind: .tablet, displaySizeLabel: "12.4\"", pixelResolutionLabel: "1752 x 2800", portraitSize: CGSize(width: 840,  height: 1344)),
]

// Keep old name as alias so any existing references compile.
let macViewportPresets = macPhonePresets
let allMacViewportPresets = macPhonePresets + macTabletPresets

enum ViewportMode: Equatable {
    case full
    case preset(String)
    case custom
}

/// Tracks the visible macOS browser viewport independently from the window size.
@MainActor
final class ViewportState: ObservableObject {
    private static let selectedModeDefaultsKey = "com.mollotov.viewport-mode"
    private static let orientationDefaultsKey  = "com.mollotov.viewport-orientation"
    private static let shellWindowWidthDefaultsKey  = "com.mollotov.macos.shell-window-width"
    private static let shellWindowHeightDefaultsKey = "com.mollotov.macos.shell-window-height"
    static let minimumShellSize = NSSize(width: 789, height: 512)

    @Published private(set) var mode: ViewportMode
    @Published private(set) var orientation: ViewportOrientation
    @Published private(set) var stageSize: CGSize
    @Published private(set) var viewportSize: CGSize

    private var requestedCustomViewportSize: CGSize?

    init() {
        let initialStageSize = CGSize(width: Self.minimumShellSize.width, height: Self.minimumShellSize.height)
        mode = Self.restoredMode()
        orientation = Self.restoredOrientation()
        stageSize = initialStageSize
        viewportSize = Self.integralSize(initialStageSize)
        _ = recalculateViewportSize()
    }

    var minimumWindowSize: NSSize { Self.minimumShellSize }

    static var persistedShellWindowSize: NSSize? {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: shellWindowWidthDefaultsKey)
        let height = defaults.double(forKey: shellWindowHeightDefaultsKey)
        guard width > 0, height > 0 else { return nil }
        return NSSize(
            width: max(width.rounded(.down), minimumShellSize.width),
            height: max(height.rounded(.down), minimumShellSize.height)
        )
    }

    static func persistShellWindowSize(_ size: NSSize) {
        let normalized = NSSize(
            width: max(size.width.rounded(.down), minimumShellSize.width),
            height: max(size.height.rounded(.down), minimumShellSize.height)
        )
        UserDefaults.standard.set(normalized.width, forKey: shellWindowWidthDefaultsKey)
        UserDefaults.standard.set(normalized.height, forKey: shellWindowHeightDefaultsKey)
    }

    /// Presets that fit within the stage in both orientations.
    var availablePresets: [DesktopViewportPreset] {
        allMacViewportPresets.filter { preset in
            let pw = preset.portraitSize.width.rounded(.down)
            let ph = preset.portraitSize.height.rounded(.down)
            let sw = stageSize.width, sh = stageSize.height
            return min(pw, ph) <= min(sw, sh) && max(pw, ph) <= max(sw, sh)
        }
    }

    var availablePhonePresets:  [DesktopViewportPreset] { availablePresets.filter { $0.kind == .phone } }
    var availableTabletPresets: [DesktopViewportPreset] { availablePresets.filter { $0.kind == .tablet } }

    var activePresetId: String? {
        guard case let .preset(id) = mode else { return nil }
        return id
    }

    var activePreset: DesktopViewportPreset? {
        allMacViewportPresets.first { $0.id == activePresetId }
    }

    var showsViewportStageChrome: Bool { mode != .full }

    var selectedPresetMenuLabel: String {
        switch mode {
        case .full:   return "Full"
        case .custom: return "Custom"
        case .preset: return activePreset?.menuLabel ?? "Full"
        }
    }

    var resolutionLabel: String { "\(Int(viewportSize.width))x\(Int(viewportSize.height))" }

    var currentViewportDimensions: (width: Int, height: Int) {
        (Int(viewportSize.width), Int(viewportSize.height))
    }

    var fullStageDimensions: (width: Int, height: Int) {
        let s = Self.integralSize(stageSize)
        return (Int(s.width), Int(s.height))
    }

    @discardableResult
    func selectFullViewport() -> CGSize {
        mode = .full
        requestedCustomViewportSize = nil
        persistSelectedMode()
        return recalculateViewportSize()
    }

    @discardableResult
    func selectPreset(_ presetID: String) -> CGSize? {
        guard availablePresets.contains(where: { $0.id == presetID }) else { return nil }
        mode = .preset(presetID)
        requestedCustomViewportSize = nil
        persistSelectedMode()
        return recalculateViewportSize()
    }

    func selectOrientation(_ newOrientation: ViewportOrientation) {
        guard orientation != newOrientation else { return }
        orientation = newOrientation
        UserDefaults.standard.set(newOrientation.rawValue, forKey: Self.orientationDefaultsKey)
        _ = recalculateViewportSize()
    }

    @discardableResult
    func resizeViewport(width: Int?, height: Int?) -> CGSize {
        let current = currentViewportDimensions
        let requestedWidth = max(width ?? current.width, 1)
        let requestedHeight = max(height ?? current.height, 1)
        mode = .custom
        requestedCustomViewportSize = CGSize(width: requestedWidth, height: requestedHeight)
        persistSelectedMode()
        return recalculateViewportSize()
    }

    @discardableResult
    func resetViewport() -> CGSize {
        mode = .full
        requestedCustomViewportSize = nil
        persistSelectedMode()
        return recalculateViewportSize()
    }

    func updateStageSize(_ newSize: CGSize) {
        let normalized = Self.integralSize(newSize)
        guard normalized.width > 0, normalized.height > 0 else { return }
        guard !Self.sizesMatch(stageSize, normalized) else { return }
        stageSize = normalized
        _ = recalculateViewportSize()
    }

    @discardableResult
    private func recalculateViewportSize() -> CGSize {
        if case let .preset(id) = mode, !availablePresets.contains(where: { $0.id == id }) {
            mode = .full
            persistSelectedMode()
        }
        let nextSize = resolvedDesiredViewportSize()
        if !Self.sizesMatch(viewportSize, nextSize) { viewportSize = nextSize }
        return viewportSize
    }

    private func resolvedDesiredViewportSize() -> CGSize {
        switch mode {
        case .full:   return stageSize
        case .custom: return requestedCustomViewportSize ?? stageSize
        case let .preset(id):
            guard let preset = allMacViewportPresets.first(where: { $0.id == id }) else { return stageSize }
            let p = preset.portraitSize
            return orientation == .landscape ? CGSize(width: p.height, height: p.width) : p
        }
    }

    private func persistSelectedMode() {
        let value: String
        switch mode {
        case .full:              value = "full"
        case .custom:            value = "custom"
        case let .preset(id):   value = "preset:\(id)"
        }
        UserDefaults.standard.set(value, forKey: Self.selectedModeDefaultsKey)
    }

    private static func restoredMode() -> ViewportMode {
        let raw = UserDefaults.standard.string(forKey: selectedModeDefaultsKey) ?? "full"
        if raw == "full" || raw == "custom" { return .full }
        if raw.hasPrefix("preset:") {
            let id = String(raw.dropFirst("preset:".count))
            if allMacViewportPresets.contains(where: { $0.id == id }) { return .preset(id) }
        }
        return .full
    }

    private static func restoredOrientation() -> ViewportOrientation {
        let raw = UserDefaults.standard.string(forKey: orientationDefaultsKey) ?? ""
        return ViewportOrientation(rawValue: raw) ?? .portrait
    }

    private static func integralSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(size.width.rounded(.down), 0), height: max(size.height.rounded(.down), 0))
    }

    private static func sizesMatch(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }
}
