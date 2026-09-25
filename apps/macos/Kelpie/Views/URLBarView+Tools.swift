import SwiftUI

extension URLBarView {
    @ViewBuilder
    var selectorsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if show3DControls {
                inspectorControlsRow
            }

            deviceDropdown

            if viewportState.supportsOrientationSelection {
                orientationToggle
            }

            rendererSwitch
                .disabled(rendererState.isSwitching)

            if viewportState.mode != .full {
                scaleControl
            }
        }
    }

    @ViewBuilder
    var inspectorControlsRow: some View {
        HStack(spacing: 6) {
            AppKitSegmentedStrip(
                items: [
                    AppKitSegmentedStrip.Item(
                        id: "rotate",
                        systemImageName: "hand.draw",
                        accessibilityID: "browser.snapshot3d.mode.rotate",
                        accessibilityLabel: "Rotate mode",
                        width: 40,
                        iconSize: 13
                    ),
                    AppKitSegmentedStrip.Item(
                        id: "scroll",
                        systemImageName: "arrow.up.and.down",
                        accessibilityID: "browser.snapshot3d.mode.scroll",
                        accessibilityLabel: "Scroll mode",
                        width: 40,
                        iconSize: 13
                    )
                ],
                selectedID: inspectorMode,
                accessibilityID: "browser.snapshot3d.mode",
                isEnabled: true,
                onSelect: onSetInspectorMode
            )
            .frame(width: 90, height: 34)

            AppKitToolbarButton(
                systemName: "minus.magnifyingglass",
                accessibilityID: "browser.snapshot3d.zoom-out",
                accessibilityLabel: "Zoom out 3D view",
                action: onInspectorZoomOut
            )

            AppKitToolbarButton(
                systemName: "plus.magnifyingglass",
                accessibilityID: "browser.snapshot3d.zoom-in",
                accessibilityLabel: "Zoom in 3D view",
                action: onInspectorZoomIn
            )

            AppKitToolbarButton(
                systemName: "arrow.counterclockwise",
                accessibilityID: "browser.snapshot3d.reset",
                accessibilityLabel: "Reset 3D view",
                action: onInspectorReset
            )

            AppKitToolbarButton(
                systemName: "xmark",
                accessibilityID: "browser.snapshot3d.exit",
                accessibilityLabel: "Exit 3D view",
                action: onInspectorExit
            )
        }
    }

    @ViewBuilder
    var scaleControl: some View {
        let scaleSupported = rendererState.activeEngine != .chromium
        HStack(spacing: 0) {
            Text("−")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 30, height: 34)
                .opacity(scaleSupported && viewportState.canScaleDown ? 1.0 : 0.55)
                .overlay(
                    AppKitInvisibleButton(
                        accessibilityID: "browser.viewport.scale.down",
                        accessibilityLabel: "Zoom out",
                        isEnabled: scaleSupported && viewportState.canScaleDown
                    ) { viewportState.scaleDown() }
                )

            Text(scaleSupported ? viewportState.scalePercentLabel : "100%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(minWidth: 40)
                .lineLimit(1)

            Text("+")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 30, height: 34)
                .opacity(scaleSupported && viewportState.canScaleUp ? 1.0 : 0.55)
                .overlay(
                    AppKitInvisibleButton(
                        accessibilityID: "browser.viewport.scale.up",
                        accessibilityLabel: "Zoom in",
                        isEnabled: scaleSupported && viewportState.canScaleUp
                    ) { viewportState.scaleUp() }
                )
        }
        .foregroundStyle(.primary)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .accessibilityIdentifier("browser.viewport.scale")
    }

    @ViewBuilder
    var rendererSwitch: some View {
        AppKitSegmentedStrip(
            items: [
                AppKitSegmentedStrip.Item(
                    id: RendererState.Engine.webkit.rawValue,
                    imageName: "SafariLogo",
                    accessibilityID: "browser.renderer.webkit",
                    accessibilityLabel: "WebKit",
                    width: 54,
                    iconSize: 16
                ),
                AppKitSegmentedStrip.Item(
                    id: RendererState.Engine.chromium.rawValue,
                    imageName: "ChromeLogo",
                    accessibilityID: "browser.renderer.chromium",
                    accessibilityLabel: "Chromium",
                    width: 54,
                    iconSize: 16
                )
            ],
            selectedID: rendererState.activeEngine.rawValue,
            accessibilityID: "browser.renderer.switch",
            isEnabled: !rendererState.isSwitching,
            onSelect: { selectedID in
                guard let engine = RendererState.Engine(rawValue: selectedID) else { return }
                showTools = false
                onSwitchRenderer(engine)
            }
        )
        .frame(width: 118, height: 34)
    }

    @ViewBuilder
    var orientationToggle: some View {
        AppKitSegmentedStrip(
            items: [
                AppKitSegmentedStrip.Item(
                    id: ViewportOrientation.portrait.rawValue,
                    systemImageName: "rectangle.portrait",
                    accessibilityID: "browser.orientation.portrait",
                    accessibilityLabel: "Portrait",
                    width: 40,
                    iconSize: 12
                ),
                AppKitSegmentedStrip.Item(
                    id: ViewportOrientation.landscape.rawValue,
                    systemImageName: "rectangle",
                    accessibilityID: "browser.orientation.landscape",
                    accessibilityLabel: "Landscape",
                    width: 40,
                    iconSize: 12
                )
            ],
            selectedID: viewportState.reportedOrientation.rawValue,
            accessibilityID: "browser.orientation.switch",
            isEnabled: viewportState.supportsOrientationSelection,
            onSelect: { id in
                guard let orientation = ViewportOrientation(rawValue: id) else { return }
                viewportState.selectOrientation(orientation)
            }
        )
        .frame(width: 90, height: 34)
    }

    @ViewBuilder
    var deviceDropdown: some View {
        Menu {
            Button("Full") { viewportState.selectFullViewport() }
            Divider()
            ForEach(viewportState.availablePhonePresets) { preset in
                Button(preset.menuLabel) { _ = viewportState.selectPreset(preset.id) }
            }
            if !viewportState.availableTabletPresets.isEmpty {
                Divider()
                ForEach(viewportState.availableTabletPresets) { preset in
                    Button(preset.menuLabel) { _ = viewportState.selectPreset(preset.id) }
                }
            }
            if !viewportState.availableLaptopPresets.isEmpty {
                Divider()
                ForEach(viewportState.availableLaptopPresets) { preset in
                    Button(preset.menuLabel) { _ = viewportState.selectPreset(preset.id) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(viewportState.selectedPresetMenuLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier("browser.preset.switch")
    }

}
