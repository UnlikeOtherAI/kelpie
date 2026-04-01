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
    let menuLabel: String
    let kind: DeviceKind
    let displaySizeLabel: String
    let pixelResolutionLabel: String
    let portraitSize: CGSize
}

// MARK: - Preset data loaded from core-protocol C API

private func cstr(_ ptr: UnsafePointer<CChar>?) -> String {
    guard let ptr else { return "" }
    return String(cString: ptr)
}

private func loadPresetsFromNative() -> (phones: [DesktopViewportPreset], tablets: [DesktopViewportPreset]) {
    var phones: [DesktopViewportPreset] = []
    var tablets: [DesktopViewportPreset] = []
    let count = Int(mollotov_viewport_preset_count())
    for i in 0 ..< count {
        guard let p = mollotov_viewport_preset_get(Int32(i))?.pointee else { continue }
        let preset = DesktopViewportPreset(
            id:                   cstr(p.id),
            name:                 cstr(p.name),
            label:                cstr(p.label),
            menuLabel:            cstr(p.menu_label),
            kind:                 p.kind == MOLLOTOV_DEVICE_KIND_TABLET ? .tablet : .phone,
            displaySizeLabel:     cstr(p.display_size_label),
            pixelResolutionLabel: cstr(p.pixel_resolution_label),
            portraitSize:         CGSize(width: CGFloat(p.portrait_width), height: CGFloat(p.portrait_height))
        )
        if preset.kind == .tablet { tablets.append(preset) } else { phones.append(preset) }
    }
    return (phones, tablets)
}

private let _nativePresets = loadPresetsFromNative()
let macPhonePresets:  [DesktopViewportPreset] = _nativePresets.phones
let macTabletPresets: [DesktopViewportPreset] = _nativePresets.tablets
let allMacViewportPresets = macPhonePresets + macTabletPresets

// Legacy alias kept so any existing reference sites compile.
let macViewportPresets = macPhonePresets

// MARK: - ViewportMode / ViewportState

enum ViewportMode: Equatable {
    case full
    case preset(String)
    case custom
}

/// Tracks the visible macOS browser viewport independently from the window size.
@MainActor
final class ViewportState: ObservableObject {
    private static let selectedModeDefaultsKey     = "com.mollotov.viewport-mode"
    private static let orientationDefaultsKey      = "com.mollotov.viewport-orientation"
    private static let shellWindowWidthDefaultsKey  = "com.mollotov.macos.shell-window-width"
    private static let shellWindowHeightDefaultsKey = "com.mollotov.macos.shell-window-height"
    private static let scaleDefaultsKey            = "com.mollotov.viewport-scale"
    private static let scaleStep: Double           = 0.1
    private static let minScale: Double            = 0.1
    private static let maxScale: Double            = 3.0
    static let minimumShellSize = NSSize(width: 789, height: 512)

    @Published private(set) var mode: ViewportMode
    @Published private(set) var orientation: ViewportOrientation
    @Published private(set) var stageSize: CGSize
    @Published private(set) var viewportSize: CGSize
    @Published private(set) var scale: Double

    private var requestedCustomViewportSize: CGSize?

    init() {
        let initialStageSize = CGSize(width: Self.minimumShellSize.width, height: Self.minimumShellSize.height)
        mode        = Self.restoredMode()
        orientation = Self.restoredOrientation()
        scale       = Self.restoredScale()
        stageSize   = initialStageSize
        viewportSize = Self.integralSize(initialStageSize)
        _ = recalculateViewportSize()
    }

    var minimumWindowSize: NSSize { Self.minimumShellSize }

    // MARK: - Scale

    var canScaleDown: Bool { scale > Self.minScale + 0.001 }
    var canScaleUp:   Bool { scale < Self.maxScale - 0.001 }
    var scalePercentLabel: String { "\(Int((scale * 100).rounded()))%" }

    func scaleUp() {
        scale = min(((scale + Self.scaleStep) * 10).rounded() / 10, Self.maxScale)
        UserDefaults.standard.set(scale, forKey: Self.scaleDefaultsKey)
    }

    func scaleDown() {
        scale = max(((scale - Self.scaleStep) * 10).rounded() / 10, Self.minScale)
        UserDefaults.standard.set(scale, forKey: Self.scaleDefaultsKey)
    }

    // MARK: - Stage summary (shown in the chrome pill above the viewport)

    var stageSummaryLabel: String {
        if case let .preset(id) = mode,
           let preset = allMacViewportPresets.first(where: { $0.id == id }) {
            return "\(preset.displaySizeLabel)  •  \(preset.pixelResolutionLabel)"
        }
        return "\(Int(viewportSize.width))×\(Int(viewportSize.height))"
    }

    // MARK: - Window size persistence

    static var persistedShellWindowSize: NSSize? {
        let defaults = UserDefaults.standard
        let width  = defaults.double(forKey: shellWindowWidthDefaultsKey)
        let height = defaults.double(forKey: shellWindowHeightDefaultsKey)
        guard width > 0, height > 0 else { return nil }
        return NSSize(
            width:  max(width.rounded(.down),  minimumShellSize.width),
            height: max(height.rounded(.down), minimumShellSize.height)
        )
    }

    static func persistShellWindowSize(_ size: NSSize) {
        let normalized = NSSize(
            width:  max(size.width.rounded(.down),  minimumShellSize.width),
            height: max(size.height.rounded(.down), minimumShellSize.height)
        )
        UserDefaults.standard.set(normalized.width,  forKey: shellWindowWidthDefaultsKey)
        UserDefaults.standard.set(normalized.height, forKey: shellWindowHeightDefaultsKey)
    }

    // MARK: - Available presets

    /// Presets that fit within the stage in both orientations.
    var availablePresets: [DesktopViewportPreset] {
        allMacViewportPresets.filter { preset in
            let pw = preset.portraitSize.width.rounded(.down)
            let ph = preset.portraitSize.height.rounded(.down)
            let sw = stageSize.width, sh = stageSize.height
            return min(pw, ph) <= min(sw, sh) && max(pw, ph) <= max(sw, sh)
        }
    }

    var availablePhonePresets:  [DesktopViewportPreset] { availablePresets.filter { $0.kind == .phone  } }
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

    var resolutionLabel: String { "\(Int(viewportSize.width))×\(Int(viewportSize.height))" }

    var currentViewportDimensions: (width: Int, height: Int) {
        (Int(viewportSize.width), Int(viewportSize.height))
    }

    var fullStageDimensions: (width: Int, height: Int) {
        let s = Self.integralSize(stageSize)
        return (Int(s.width), Int(s.height))
    }

    // MARK: - Mode selection

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
        let requestedWidth  = max(width  ?? current.width,  1)
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

    // MARK: - Private

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
        case .full:            value = "full"
        case .custom:          value = "custom"
        case let .preset(id):  value = "preset:\(id)"
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

    private static func restoredScale() -> Double {
        let saved = UserDefaults.standard.double(forKey: scaleDefaultsKey)
        guard saved > 0 else { return 1.0 }
        let clamped = min(max(saved, minScale), maxScale)
        return (clamped / scaleStep).rounded() * scaleStep
    }

    private static func integralSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(size.width.rounded(.down), 0), height: max(size.height.rounded(.down), 0))
    }

    private static func sizesMatch(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }
}
