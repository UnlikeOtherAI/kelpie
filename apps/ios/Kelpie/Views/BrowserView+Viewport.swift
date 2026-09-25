import SwiftUI
import WebKit

extension BrowserView {
    @ViewBuilder
    var browserViewport: some View {
        GeometryReader { geometry in
            let availablePresets = fittingTabletViewportPresets(for: geometry.size)
            let selectedPreset = availablePresets.first { $0.id == iPadMobileStagePresetID }
            let mobileStageActive = isPad && selectedPreset != nil
            let stageSize = selectedPreset.map { tabletViewportSize(for: $0, availableSize: geometry.size) } ?? geometry.size

            ZStack {
                if mobileStageActive {
                    Color(uiColor: .systemGray5)
                        .ignoresSafeArea(.container, edges: .bottom)
                }

                if let selectedPreset {
                    stagedWebViewContainer(
                        preset: selectedPreset,
                        stageSize: stageSize
                    )
                    .allowsHitTesting(!serverState.isScriptRecording)
                } else {
                    webViewContainer
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(!serverState.isScriptRecording)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.18), value: mobileStageActive)

            .onAppear { updateAvailableTabletViewportPresetState(for: geometry.size) }
            .onChange(of: geometry.size) { size in
                updateAvailableTabletViewportPresetState(for: size)
            }
        }
    }

    func presentWelcomeFromHelp() {
        showSettings = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            welcomePresentationSource = .helpMenu
            showWelcome = true
        }
    }

    var webViewContainer: some View {
        TabWebViewContainer(
            tabStore: tabStore,
            browserState: browserState,
            handlerContext: serverState.handlerContext,
            bottomClearance: serverState.isScriptRecording ? 0 : (bottomBarCollapsed ? 34 : 62),
            onScrollDirectionChange: { direction in
                guard !addressEditing, !showTabOverview, !isIn3DInspector else { return }
                withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.2)) {
                    bottomBarCollapsed = direction == .down
                }
                if isPad { chromeSampler.sampleAfterScroll() }
            },
            onWebViewReady: { wv in
                browserState.webView = wv
                serverState.webView = wv
                serverState.handlerContext.webView = wv
                externalDisplayManager.setPhoneWebView(wv)
            }
        )
    }

    @ViewBuilder
    func stagedWebViewContainer(preset: TabletViewportPreset, stageSize: CGSize) -> some View {
        if serverState.isScriptRecording {
            webViewContainer
                .frame(width: stageSize.width, height: stageSize.height)
        } else {
            VStack(spacing: 10) {
                ZStack {
                    Text(stageSummary(for: preset))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.9))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.9), lineWidth: 1)
                        }
                        .accessibilityIdentifier("browser.viewport.summary")
                }
                .frame(width: stageSize.width, height: 38)
                .overlay(alignment: .leading) {
                    Button {
                        setTabletViewportPreset("")
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.9))
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
                            }
                    }
                    .accessibilityIdentifier("browser.viewport.close")
                }

                webViewContainer
                    .frame(width: stageSize.width, height: stageSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.7), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            }
            .frame(width: stageSize.width, height: stageSize.height + tabletViewportStageTopChromeHeight)
        }
    }

    var activeTabletViewportPreset: TabletViewportPreset? {
        guard isPad else { return nil }
        return tabletViewportPresets
            .first { availableIPadViewportPresetIDs.contains($0.id) && $0.id == iPadMobileStagePresetID }
    }

    var availableTabletViewportPresetOptions: [MobileViewportPresetOption] {
        tabletViewportPresets
            .filter { availableIPadViewportPresetIDs.contains($0.id) }
            .map { MobileViewportPresetOption(id: $0.id, label: $0.menuLabel) }
    }

    func toggleTabletViewportPreset(_ presetID: String) {
        setTabletViewportPreset((iPadMobileStagePresetID == presetID) ? "" : presetID)
    }

    func stageSummary(for preset: TabletViewportPreset) -> String {
        "\(preset.displaySizeLabel) • \(preset.pixelResolutionLabel)"
    }

    func migrateLegacyTabletViewportSelectionIfNeeded() {
        guard isPad else { return }
        guard iPadMobileStagePresetID.isEmpty, legacyIPadMobileStageEnabled else { return }
        setTabletViewportPreset(defaultTabletViewportPresetID)
        legacyIPadMobileStageEnabled = false
    }

    func updateAvailableTabletViewportPresetState(for availableSize: CGSize) {
        let nextIDs = fittingTabletViewportPresets(for: availableSize).map(\.id)
        UserDefaults.standard.set(nextIDs.joined(separator: ","), forKey: ipadMobileStageAvailablePresetIDsDefaultsKey)
        UserDefaults.standard.set(availableSize.width, forKey: ipadMobileStageAvailableWidthDefaultsKey)
        UserDefaults.standard.set(availableSize.height, forKey: ipadMobileStageAvailableHeightDefaultsKey)

        if nextIDs != availableIPadViewportPresetIDs {
            availableIPadViewportPresetIDs = nextIDs
        }

        if !iPadMobileStagePresetID.isEmpty, !nextIDs.contains(iPadMobileStagePresetID) {
            setTabletViewportPreset("")
        }
    }

    func setTabletViewportPreset(_ presetID: String) {
        iPadMobileStagePresetID = presetID
        UserDefaults.standard.set(presetID, forKey: ipadMobileStagePresetDefaultsKey)
    }

}
