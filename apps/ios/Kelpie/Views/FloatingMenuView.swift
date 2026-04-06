import SwiftUI
import UIKit

/// App icon background color — warm peach/orange.
private let kelpieOrange = Color(red: 244 / 255, green: 176 / 255, blue: 120 / 255)
/// Richer menu item color — more red/saturated for contrast against the FAB.
private let menuItemOrange = Color(red: 240 / 255, green: 148 / 255, blue: 90 / 255)

/// UIKit blur that works over WKWebView content (SwiftUI materials cannot blur UIKit views).
private struct NativeBlur: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemThinMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

/// Floating action button that expands into a fan menu.
/// Each menu item is positioned independently via .position() so that
/// tap targets work correctly (offset-based layout breaks hit testing in SwiftUI).
struct FloatingMenuView: View {
    let onReload: () -> Void
    let onSafariAuth: () -> Void
    let onSettings: () -> Void
    let onBookmarks: () -> Void
    let onHistory: () -> Void
    let onNetworkInspector: () -> Void
    let onAI: () -> Void
    let onSnapshot3D: () -> Void
    let show3DInspector: Bool
    let showMobileViewportToggle: Bool
    let mobileViewportPresets: [MobileViewportPresetOption]
    let selectedMobileViewportPresetID: String?
    let onSelectMobileViewportPreset: (String) -> Void

    @State private var isOpen = false
    @State private var isMobileViewportPickerOpen = false
    @Binding var side: CGFloat
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private let fabSize: CGFloat = 44
    private let menuItemSize: CGFloat = 44
    private let baseSpreadRadius: CGFloat = 150
    private let minimumMenuItemGap: CGFloat = 12
    private let edgePadding: CGFloat = 16
    private let viewportPillWidth: CGFloat = 168
    private let viewportPillHeight: CGFloat = 36
    private let viewportPillLaneSpacing: CGFloat = 34
    private let viewportPillStackSpacing: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            let rightX = geo.size.width - edgePadding - fabSize / 2
            let leftX = edgePadding + fabSize / 2
            let baseX = side > 0 ? rightX : leftX
            let clampedX = min(max(baseX + dragOffset, leftX), rightX)
            let fanDirection: CGFloat = side > 0 ? -1 : 1

            ZStack {
                // Blur overlay when menu is open
                if isOpen {
                    NativeBlur(style: .systemThinMaterial)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35)) {
                                isOpen = false
                                isMobileViewportPickerOpen = false
                            }
                        }
                }

                // Menu items — each positioned independently for correct hit testing
                ForEach(Array(menuItems.enumerated()), id: \.element.elementId) { index, item in
                    menuItemView(
                        icon: item.icon,
                        elementId: item.elementId,
                        index: index,
                        itemCount: menuItems.count,
                        fanDirection: fanDirection,
                        action: item.action,
                        tint: item.tint,
                        closesMenu: item.closesMenu,
                        background: item.background,
                        border: item.border,
                        borderWidth: item.borderWidth,
                        fabX: clampedX,
                        fabY: midY,
                        geo: geo
                    )
                }

                if showMobileViewportToggle,
                   isMobileViewportPickerOpen,
                   let mobileToggleIndex = menuItems.firstIndex(where: { $0.elementId == "browser.viewport.mobile-toggle" }) {
                    mobileViewportPresetPicker(
                        mobileToggleIndex: mobileToggleIndex,
                        itemCount: menuItems.count,
                        fanDirection: fanDirection,
                        fabX: clampedX,
                        fabY: midY,
                        geo: geo
                    )
                }

                // Main FAB — flame icon
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: fabSize, height: fabSize)
                    .background(kelpieOrange)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .opacity(isOpen ? 0.8 : 1.0)
                    .contentShape(Circle())
                    .accessibilityIdentifier("browser.menu.fab")
                    .position(x: clampedX, y: midY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let distance = abs(value.translation.width)
                                if distance > 10 {
                                    isDragging = true
                                    dragOffset = value.translation.width
                                }
                            }
                            .onEnded { _ in
                                if isDragging {
                                    let finalX = min(max(baseX + dragOffset, leftX), rightX)
                                    let mid = geo.size.width / 2
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        side = finalX < mid ? -1 : 1
                                        dragOffset = 0
                                    }
                                    isDragging = false
                                } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        if isOpen {
                                            isMobileViewportPickerOpen = false
                                        }
                                        isOpen.toggle()
                                    }
                                }
                            }
                    )
            }
        }
        .onChange(of: isOpen) { open in
            if !open {
                isMobileViewportPickerOpen = false
            }
        }
    }

    private var menuItems: [MenuItem] {
        var items: [MenuItem] = [
            .init(icon: "arrow.clockwise", elementId: "browser.menu.reload", tint: .white, closesMenu: true, action: onReload),
            .init(icon: "safari", elementId: "browser.menu.safari-auth", tint: .white, closesMenu: true, action: onSafariAuth),
            .init(icon: "bookmark.fill", elementId: "browser.menu.bookmarks", tint: .white, closesMenu: true, action: onBookmarks),
            .init(icon: "clock.arrow.circlepath", elementId: "browser.menu.history", tint: .white, closesMenu: true, action: onHistory),
            .init(icon: "antenna.radiowaves.left.and.right", elementId: "browser.menu.network-inspector", tint: .white, closesMenu: true, action: onNetworkInspector),
            .init(icon: "brain", elementId: "browser.menu.ai", tint: .white, closesMenu: true, action: onAI),
            .init(icon: "gear", elementId: "browser.menu.settings", tint: .white, closesMenu: true, action: onSettings)
        ]

        if show3DInspector {
            items.insert(
                MenuItem(
                    icon: "cube.transparent",
                    elementId: "browser.menu.snapshot-3d",
                    tint: .white,
                    closesMenu: true,
                    action: onSnapshot3D
                ),
                at: max(items.count - 1, 0)
            )
        }

        if showMobileViewportToggle {
            items.insert(
                MenuItem(
                    icon: "iphone",
                    elementId: "browser.viewport.mobile-toggle",
                    tint: .white,
                    background: (selectedMobileViewportPresetID != nil || isMobileViewportPickerOpen) ? kelpieOrange : menuItemOrange,
                    border: (selectedMobileViewportPresetID != nil || isMobileViewportPickerOpen) ? Color.white.opacity(0.9) : .clear,
                    borderWidth: (selectedMobileViewportPresetID != nil || isMobileViewportPickerOpen) ? 1.5 : 0,
                    closesMenu: false,
                    action: toggleMobileViewportPicker
                ),
                at: 2
            )
        }

        return items
    }

    /// Distribute 6 items in a semicircle centered on the axis away from the docked edge.
    /// Right-docked (direction=-1): centered at 180° (fan left), arc 90°..270°
    /// Left-docked  (direction=+1): centered at   0° (fan right), arc -90°..90°
    private func fanAngle(direction: CGFloat, index: Int, itemCount: Int) -> Angle {
        let center: Double = direction < 0 ? 180 : 0
        guard itemCount > 1 else { return .degrees(center) }
        let step = 180.0 / Double(itemCount - 1)
        return .degrees(center - 90.0 + step * Double(index))
    }

    private func spreadRadius(for itemCount: Int) -> CGFloat {
        guard itemCount > 1 else { return baseSpreadRadius }

        let stepRadians = CGFloat.pi / CGFloat(itemCount - 1)
        let minimumCenterDistance = menuItemSize + minimumMenuItemGap
        let requiredRadius = minimumCenterDistance / (2 * sin(stepRadians / 2))
        return max(baseSpreadRadius, requiredRadius)
    }

    private func menuItemOffset(
        index: Int,
        itemCount: Int,
        fanDirection: CGFloat,
        fabX: CGFloat,
        fabY: CGFloat,
        geo: GeometryProxy
    ) -> CGSize {
        let angle = fanAngle(direction: fanDirection, index: index, itemCount: itemCount)
        let spreadRadius = spreadRadius(for: itemCount)
        let rawDx: CGFloat = isOpen ? CGFloat(cos(angle.radians)) * spreadRadius : 0
        let rawDy: CGFloat = isOpen ? CGFloat(sin(angle.radians)) * spreadRadius : 0
        let margin = menuItemSize / 2 + edgePadding
        let dx = min(max(rawDx, margin - fabX), geo.size.width - margin - fabX)
        let dy = min(max(rawDy, margin - fabY), geo.size.height - margin - fabY)
        return CGSize(width: dx, height: dy)
    }

    @ViewBuilder
    // swiftlint:disable:next function_parameter_count
    private func menuItemView(
        icon: String,
        elementId: String,
        index: Int,
        itemCount: Int,
        fanDirection: CGFloat,
        action: @escaping () -> Void,
        tint: Color,
        closesMenu: Bool,
        background: Color,
        border: Color,
        borderWidth: CGFloat,
        fabX: CGFloat,
        fabY: CGFloat,
        geo: GeometryProxy
    ) -> some View {
        let offset = menuItemOffset(
            index: index,
            itemCount: itemCount,
            fanDirection: fanDirection,
            fabX: fabX,
            fabY: fabY,
            geo: geo
        )

        Button {
            action()
            if closesMenu {
                withAnimation(.spring(response: 0.35)) {
                    isOpen = false
                    isMobileViewportPickerOpen = false
                }
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(tint)
                .frame(width: menuItemSize, height: menuItemSize)
                .background(background)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(border, lineWidth: borderWidth)
                }
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .accessibilityIdentifier(elementId)
        .position(x: fabX + offset.width, y: fabY + offset.height)
        .opacity(isOpen ? 1 : 0)
        .scaleEffect(isOpen ? 1 : 0.3)
        .allowsHitTesting(isOpen)
    }

    @ViewBuilder
    private func mobileViewportPresetPicker(
        mobileToggleIndex: Int,
        itemCount: Int,
        fanDirection: CGFloat,
        fabX: CGFloat,
        fabY: CGFloat,
        geo: GeometryProxy
    ) -> some View {
        let anchorOffset = menuItemOffset(
            index: mobileToggleIndex,
            itemCount: itemCount,
            fanDirection: fanDirection,
            fabX: fabX,
            fabY: fabY,
            geo: geo
        )
        let anchorX = fabX + anchorOffset.width
        let anchorY = fabY + anchorOffset.height
        let rowSpacing = viewportPillHeight + viewportPillStackSpacing
        let baseOffset = menuItemSize / 2 + viewportPillHeight / 2 + viewportPillStackSpacing
        let baseX = anchorX + fanDirection * (menuItemSize / 2 + viewportPillWidth / 2 + viewportPillLaneSpacing)
        let upwardStartY = anchorY - baseOffset
        let downwardStartY = anchorY + baseOffset
        let minCenterY = edgePadding + viewportPillHeight / 2
        let maxCenterY = geo.size.height - edgePadding - viewportPillHeight / 2
        let upwardCapacity = max(Int(floor((upwardStartY - minCenterY) / rowSpacing)) + 1, 1)
        let downwardCapacity = max(Int(floor((maxCenterY - downwardStartY) / rowSpacing)) + 1, 1)
        let stackDirection: CGFloat = downwardCapacity >= upwardCapacity ? 1 : -1
        let startY = stackDirection > 0 ? downwardStartY : upwardStartY
        let rowsPerColumn = max(stackDirection > 0 ? downwardCapacity : upwardCapacity, 1)
        let columnSpacing = viewportPillWidth + 12

        ForEach(Array(mobileViewportPresets.enumerated()), id: \.element.id) { index, preset in
            let row = index % rowsPerColumn
            let column = index / rowsPerColumn
            let rawX = baseX + fanDirection * CGFloat(column) * columnSpacing
            let rawY = startY + stackDirection * CGFloat(row) * rowSpacing
            let clampedX = min(max(rawX, viewportPillWidth / 2 + edgePadding), geo.size.width - viewportPillWidth / 2 - edgePadding)
            let clampedY = min(max(rawY, viewportPillHeight / 2 + edgePadding), geo.size.height - viewportPillHeight / 2 - edgePadding)
            let isSelected = preset.id == selectedMobileViewportPresetID

            Button {
                onSelectMobileViewportPreset(preset.id)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isMobileViewportPickerOpen = false
                    isOpen = false
                }
            } label: {
                Text(preset.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: viewportPillWidth, height: viewportPillHeight)
                    .background(isSelected ? kelpieOrange : menuItemOrange)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(isSelected ? 0.9 : 0.35), lineWidth: isSelected ? 1.5 : 1)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
            }
            .accessibilityIdentifier("browser.viewport.preset.\(preset.id)")
            .position(x: clampedX, y: clampedY)
            .opacity(isMobileViewportPickerOpen ? 1 : 0)
            .scaleEffect(isMobileViewportPickerOpen ? 1 : 0.85)
            .allowsHitTesting(isMobileViewportPickerOpen)
        }
    }

    private func toggleMobileViewportPicker() {
        guard !mobileViewportPresets.isEmpty else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isMobileViewportPickerOpen.toggle()
        }
    }

    private struct MenuItem {
        let icon: String
        let elementId: String
        let tint: Color
        let background: Color
        let border: Color
        let borderWidth: CGFloat
        let closesMenu: Bool
        let action: () -> Void

        init(
            icon: String,
            elementId: String,
            tint: Color,
            background: Color = menuItemOrange,
            border: Color = .clear,
            borderWidth: CGFloat = 0,
            closesMenu: Bool,
            action: @escaping () -> Void
        ) {
            self.icon = icon
            self.elementId = elementId
            self.tint = tint
            self.background = background
            self.border = border
            self.borderWidth = borderWidth
            self.closesMenu = closesMenu
            self.action = action
        }
    }
}

struct MobileViewportPresetOption: Identifiable, Equatable {
    let id: String
    let label: String
}
