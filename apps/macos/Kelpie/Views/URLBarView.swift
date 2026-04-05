import SwiftUI

/// URL bar with navigation buttons, URL field, renderer toggle, and device size selector.
/// Stacks selectors on a second row when window is narrow (phone portrait).
struct URLBarView: View {
    private static let toolbarButtonSize = CGSize(width: 40, height: 34)

    @ObservedObject var browserState: BrowserState
    @ObservedObject var rendererState: RendererState
    @ObservedObject var viewportState: ViewportState
    @ObservedObject var aiState: AIState
    let isAIPanelOpen: Bool
    let onNavigate: (String) -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void
    let onAIToggle: () -> Void
    let onSnapshot3D: () -> Void
    let is3DActive: Bool
    let show3DControls: Bool
    let inspectorMode: String
    let onSetInspectorMode: (String) -> Void
    let onInspectorExit: () -> Void
    let onInspectorZoomIn: () -> Void
    let onInspectorZoomOut: () -> Void
    let onInspectorReset: () -> Void
    let onSwitchRenderer: (RendererState.Engine) -> Void

    @State private var urlText: String = ""
    @State private var isNarrow = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                AppKitToolbarButton(
                    systemName: "chevron.left",
                    accessibilityID: "browser.nav.back",
                    accessibilityLabel: "Back",
                    isEnabled: browserState.canGoBack,
                    action: onBack
                )

                AppKitToolbarButton(
                    systemName: "chevron.right",
                    accessibilityID: "browser.nav.forward",
                    accessibilityLabel: "Forward",
                    isEnabled: browserState.canGoForward,
                    action: onForward
                )

                AppKitToolbarButton(
                    systemName: "arrow.clockwise",
                    accessibilityID: "browser.nav.reload",
                    accessibilityLabel: "Reload",
                    action: onReload
                )

                addressField

                if aiState.isAvailable {
                    AIStatusPill(
                        aiState: aiState,
                        isOpen: isAIPanelOpen,
                        action: onAIToggle
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }

                if rendererState.activeEngine != .chromium {
                    AppKitToolbarButton(
                        systemName: "cube.transparent",
                        accessibilityID: "browser.nav.snapshot3d",
                        accessibilityLabel: "3D Inspector",
                        isSelected: is3DActive,
                        action: onSnapshot3D
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }

                if !isNarrow {
                    selectorsRow
                }
            }
            .animation(.easeOut(duration: 0.3), value: rendererState.activeEngine)

            if isNarrow {
                selectorsRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GeometryReader { geo in
            Color.clear.onAppear {
                isNarrow = geo.size.width < 600
            }
            .onChange(of: geo.size.width) { _, w in
                isNarrow = w < 600
            }
        })
        .onAppear {
            urlText = browserState.currentURL
        }
        .onChange(of: browserState.currentURL) { _, newURL in
            urlText = newURL
        }
    }

    @ViewBuilder
    private var selectorsRow: some View {
        HStack(spacing: 6) {
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
    private var inspectorControlsRow: some View {
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
                    ),
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
    private var scaleControl: some View {
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
    private var addressField: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search or enter website name", text: $urlText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1)
                .onSubmit { navigate() }
        }
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
        .accessibilityIdentifier("browser.address")
    }

    @ViewBuilder
    private var rendererSwitch: some View {
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
                ),
            ],
            selectedID: rendererState.activeEngine.rawValue,
            accessibilityID: "browser.renderer.switch",
            isEnabled: !rendererState.isSwitching,
            onSelect: { selectedID in
                guard let engine = RendererState.Engine(rawValue: selectedID) else { return }
                onSwitchRenderer(engine)
            }
        )
        .frame(width: 118, height: 34)
    }

    @ViewBuilder
    private var orientationToggle: some View {
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
                ),
            ],
            selectedID: viewportState.reportedOrientation.rawValue,
            accessibilityID: "browser.orientation.switch",
            isEnabled: viewportState.supportsOrientationSelection,
            onSelect: { id in
                guard let o = ViewportOrientation(rawValue: id) else { return }
                viewportState.selectOrientation(o)
            }
        )
        .frame(width: 90, height: 34)
    }

    @ViewBuilder
    private var deviceDropdown: some View {
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

    private func navigate() {
        var url = urlText.trimmingCharacters(in: .whitespaces)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://\(url)"
        }
        onNavigate(url)
    }
}

