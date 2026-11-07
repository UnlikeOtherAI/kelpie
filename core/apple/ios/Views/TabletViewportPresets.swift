import SwiftUI
import WebKit

let ipadMobileStagePresetDefaultsKey = "ipadMobileStagePreset"
let ipadMobileStageAvailablePresetIDsDefaultsKey = "ipadMobileStageAvailablePresetIDs"
let ipadMobileStageAvailableWidthDefaultsKey = "ipadMobileStageAvailableWidth"
let ipadMobileStageAvailableHeightDefaultsKey = "ipadMobileStageAvailableHeight"
let tabletViewportStagePadding: CGFloat = 24
let tabletViewportStageTopChromeHeight: CGFloat = 48

enum WelcomeCardPresentationSource {
    case automatic
    case helpMenu
}

struct TabletViewportPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let label: String
    let menuLabel: String
    let displaySizeLabel: String
    let pixelResolutionLabel: String
    let portraitSize: CGSize
}

func _cstr(_ ptr: UnsafePointer<CChar>?) -> String {
    guard let ptr else { return "" }
    return String(cString: ptr)
}

func viewportPresetSortValue(_ label: String) -> Double {
    let pattern = #"[0-9]+(?:\.[0-9]+)?"#
    guard let range = label.range(of: pattern, options: .regularExpression) else {
        return .greatestFiniteMagnitude
    }
    return Double(label[range]) ?? .greatestFiniteMagnitude
}

let tabletViewportPresets: [TabletViewportPreset] = {
    var result: [TabletViewportPreset] = []
    let count = Int(kelpie_viewport_preset_count())
    for i in 0 ..< count {
        guard let preset = kelpie_viewport_preset_get(Int32(i))?.pointee else { continue }
        result.append(TabletViewportPreset(
            id: _cstr(preset.id),
            name: _cstr(preset.name),
            label: _cstr(preset.label),
            menuLabel: _cstr(preset.menu_label),
            displaySizeLabel: _cstr(preset.display_size_label),
            pixelResolutionLabel: _cstr(preset.pixel_resolution_label),
            portraitSize: CGSize(width: CGFloat(preset.portrait_width), height: CGFloat(preset.portrait_height))
        ))
    }
    return result.sorted {
        let lhs = viewportPresetSortValue($0.displaySizeLabel)
        let rhs = viewportPresetSortValue($1.displaySizeLabel)
        if lhs != rhs { return lhs < rhs }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
}()

let defaultTabletViewportPresetID = "compact-base"

func tabletViewportPreset(id: String?) -> TabletViewportPreset? {
    guard let id else { return nil }
    return tabletViewportPresets.first { $0.id == id }
}

func currentTabletViewportAvailableSize() -> CGSize {
    let defaults = UserDefaults.standard
    return CGSize(
        width: defaults.double(forKey: ipadMobileStageAvailableWidthDefaultsKey),
        height: defaults.double(forKey: ipadMobileStageAvailableHeightDefaultsKey)
    )
}

func currentTabletViewportAvailablePresetIDs() -> [String] {
    let raw = UserDefaults.standard.string(forKey: ipadMobileStageAvailablePresetIDsDefaultsKey) ?? ""
    return raw.split(separator: ",").map(String.init)
}

func orientedTabletViewportSize(for preset: TabletViewportPreset, availableSize: CGSize) -> CGSize {
    guard availableSize.width > availableSize.height else { return preset.portraitSize }
    return CGSize(width: preset.portraitSize.height, height: preset.portraitSize.width)
}

func fittingTabletViewportPresets(for availableSize: CGSize) -> [TabletViewportPreset] {
    let maxWidth = max(availableSize.width - tabletViewportStagePadding * 2, 1)
    let maxHeight = max(availableSize.height - tabletViewportStagePadding * 2 - tabletViewportStageTopChromeHeight, 1)

    return tabletViewportPresets.filter { preset in
        let targetViewport = orientedTabletViewportSize(for: preset, availableSize: availableSize)
        return targetViewport.width <= maxWidth && targetViewport.height <= maxHeight
    }
}

func tabletViewportSize(for preset: TabletViewportPreset, availableSize: CGSize) -> CGSize {
    let targetViewport = orientedTabletViewportSize(for: preset, availableSize: availableSize)
    let maxWidth = max(availableSize.width - tabletViewportStagePadding * 2, 1)
    let maxHeight = max(availableSize.height - tabletViewportStagePadding * 2 - tabletViewportStageTopChromeHeight, 1)

    return CGSize(
        width: min(targetViewport.width, maxWidth),
        height: min(targetViewport.height, maxHeight)
    )
}
