import SwiftUI
import UIKit

/// Read UIKit's docked keyboard guide instead of treating a floating keyboard's
/// bounding rectangle as a bottom safe area. Coordinates stay local to the window.
struct BrowserKeyboardInset: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> KeyboardRegion {
        let view = KeyboardRegion()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: KeyboardRegion, context: Context) { view.onChange = onChange }

    final class KeyboardRegion: UIView {
        var onChange: ((CGFloat) -> Void)?
        private var previousInset: CGFloat = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            keyboardLayoutGuide.followsUndockedKeyboard = false
            let probe = UIView()
            probe.translatesAutoresizingMaskIntoConstraints = false
            addSubview(probe)
            NSLayoutConstraint.activate([
                probe.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
                probe.leadingAnchor.constraint(equalTo: leadingAnchor),
                probe.widthAnchor.constraint(equalToConstant: 0),
                probe.heightAnchor.constraint(equalToConstant: 0)
            ])
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            let inset = max(0, safeAreaLayoutGuide.layoutFrame.maxY - keyboardLayoutGuide.layoutFrame.minY)
            guard abs(inset - previousInset) > 0.5 else { return }
            previousInset = inset
            DispatchQueue.main.async { [weak self] in
                guard let self, self.previousInset == inset else { return }
                self.onChange?(inset)
            }
        }
    }
}
