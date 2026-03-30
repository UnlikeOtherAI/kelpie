import SwiftUI

/// Device viewport presets for window resizing.
enum DevicePreset: String, CaseIterable, Identifiable {
    case iphonePortrait = "iPhone P"
    case iphoneLandscape = "iPhone L"
    case tabletPortrait = "Tablet P"
    case tabletLandscape = "Tablet L"
    case laptop = "Laptop"
    case custom = "Custom"

    var id: String { rawValue }

    var size: NSSize? {
        switch self {
        case .iphonePortrait:  return NSSize(width: 393, height: 852)
        case .iphoneLandscape: return NSSize(width: 852, height: 393)
        case .tabletPortrait:  return NSSize(width: 820, height: 1180)
        case .tabletLandscape: return NSSize(width: 1180, height: 820)
        case .laptop:          return NSSize(width: 1280, height: 800)
        case .custom:          return nil
        }
    }

    var icon: String {
        switch self {
        case .iphonePortrait:  return "iphone"
        case .iphoneLandscape: return "iphone.landscape"
        case .tabletPortrait:  return "ipad"
        case .tabletLandscape: return "ipad.landscape"
        case .laptop:          return "laptopcomputer"
        case .custom:          return "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// URL bar with navigation buttons, URL field, renderer toggle, and device size selector.
/// Stacks selectors on a second row when window is narrow (phone portrait).
struct URLBarView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var rendererState: RendererState
    let onNavigate: (String) -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void
    let onSwitchRenderer: (RendererState.Engine) -> Void

    @State private var urlText: String = ""
    @State private var selectedPreset: DevicePreset = {
        let saved = UserDefaults.standard.string(forKey: "com.mollotov.device-preset") ?? ""
        return DevicePreset(rawValue: saved) ?? .laptop
    }()
    @State private var isNarrow = false
    @State private var windowResizeObserver: Any?
    @State private var isAnimatingResize = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!browserState.canGoBack)
                .buttonStyle(.borderless)

                Button(action: onForward) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!browserState.canGoForward)
                .buttonStyle(.borderless)

                Button(action: onReload) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                TextField("URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { navigate() }

                if !isNarrow {
                    selectorsRow
                }
            }

            if isNarrow {
                selectorsRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
            observeWindowResize()
            // Apply persisted device preset on launch
            if selectedPreset != .custom {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    applyPreset(selectedPreset)
                }
            }
        }
        .onChange(of: browserState.currentURL) { _, newURL in
            urlText = newURL
        }
    }

    @ViewBuilder
    private var selectorsRow: some View {
        HStack(spacing: 8) {
            // Renderer toggle
            HStack(spacing: 0) {
                rendererButton(engine: .webkit, icon: FontAwesome.safari)
                rendererButton(engine: .chromium, icon: FontAwesome.chrome)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .disabled(rendererState.isSwitching)

            // Device size selector
            HStack(spacing: 0) {
                ForEach(DevicePreset.allCases) { preset in
                    presetButton(preset)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private func presetButton(_ preset: DevicePreset) -> some View {
        let isActive = selectedPreset == preset
        Button {
            selectedPreset = preset
            UserDefaults.standard.set(preset.rawValue, forKey: "com.mollotov.device-preset")
            applyPreset(preset)
        } label: {
            Image(systemName: preset.icon)
                .font(.system(size: 11))
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
                .foregroundColor(isActive ? .white : .primary)
                .background(isActive ? Color(white: 0.25) : Color.clear)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .padding(2)
    }

    @ViewBuilder
    private func rendererButton(engine: RendererState.Engine, icon: String) -> some View {
        let isActive = rendererState.activeEngine == engine
        Button {
            onSwitchRenderer(engine)
        } label: {
            FAIcon(icon: icon, size: 14)
                .allowsHitTesting(false)
                .frame(width: 36, height: 24)
                .contentShape(Rectangle())
                .background(isActive ? Color(white: 0.25) : Color.clear)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .padding(2)
    }

    private func navigate() {
        var url = urlText.trimmingCharacters(in: .whitespaces)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://\(url)"
        }
        onNavigate(url)
    }

    private func applyPreset(_ preset: DevicePreset) {
        guard let window = NSApplication.shared.keyWindow else { return }

        if preset == .custom {
            // Enable free resizing
            window.styleMask.insert(.resizable)
            window.minSize = NSSize(width: 320, height: 480)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        } else if let size = preset.size {
            // Suppress the resize observer during programmatic animation
            isAnimatingResize = true

            window.minSize = NSSize(width: 1, height: 1)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            let origin = window.frame.origin
            let newFrame = NSRect(
                x: origin.x,
                y: origin.y + window.frame.height - size.height,
                width: size.width,
                height: size.height
            )
            window.setFrame(newFrame, display: true, animate: true)

            // Lock to exact size and re-enable observer after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let window = NSApplication.shared.keyWindow else { return }
                window.minSize = size
                window.maxSize = size
                isAnimatingResize = false
            }
        }
    }

    /// Watch for user-initiated window resizes — switch to Custom when user drags.
    private func observeWindowResize() {
        windowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { _ in
            guard !isAnimatingResize else { return }
            guard selectedPreset != .custom else { return }
            guard let window = NSApplication.shared.keyWindow else { return }
            if let expected = selectedPreset.size,
               abs(window.frame.width - expected.width) > 2 || abs(window.frame.height - expected.height) > 2 {
                selectedPreset = .custom
                UserDefaults.standard.set(DevicePreset.custom.rawValue, forKey: "com.mollotov.device-preset")
                window.minSize = NSSize(width: 320, height: 480)
                window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }
        }
    }
}
