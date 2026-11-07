import SwiftUI

public struct KelpieBrowserCommands: Commands {
    @AppStorage(ipadMobileStagePresetDefaultsKey) private var iPadMobileStagePresetID = ""

    public init() {}

    public var body: some Commands {
            CommandGroup(after: .appSettings) {
                Button("Show Welcome Screen") {
                    NotificationCenter.default.post(name: .showWelcomeCard, object: nil)
                }

                Divider()

                Button("Open Kelpie Website") {
                    openHelpURL("https://unlikeotherai.github.io/kelpie")
                }

                Button("Open GitHub Repository") {
                    openHelpURL("https://github.com/UnlikeOtherAI/kelpie")
                }

                Button("Open UnlikeOtherAI") {
                    openHelpURL("https://unlikeotherai.com")
                }
            }

            if UIDevice.current.userInterfaceIdiom == .pad {
                CommandGroup(after: .toolbar) {
                    Button {
                        selectViewportPreset("")
                    } label: {
                        if iPadMobileStagePresetID.isEmpty {
                            Label("Full Width", systemImage: "checkmark")
                        } else {
                            Text("Full Width")
                        }
                    }

                    Divider()

                    ForEach(availableViewMenuPresets) { preset in
                        Button {
                            selectViewportPreset(preset.id)
                        } label: {
                            if iPadMobileStagePresetID == preset.id {
                                Label(preset.menuLabel, systemImage: "checkmark")
                            } else {
                                Text(preset.menuLabel)
                            }
                        }
                    }

                    if availableViewMenuPresets.isEmpty {
                        Button("No Viewports Available") {}
                            .disabled(true)
                    }
                }
            }
    }

    private func openHelpURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        UIApplication.shared.open(url)
    }

    private var availableViewMenuPresets: [TabletViewportPreset] {
        let availableIDs = Set(currentTabletViewportAvailablePresetIDs())
        return tabletViewportPresets.filter { availableIDs.contains($0.id) }
    }

    private func selectViewportPreset(_ presetID: String) {
        NotificationCenter.default.post(
            name: .selectViewportPreset,
            object: nil,
            userInfo: ["presetId": presetID]
        )
    }
}
