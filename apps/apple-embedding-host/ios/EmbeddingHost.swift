import AppReveal
import KelpieBrowser
import SwiftUI
import UIKit

@main
struct EmbeddingHost: App {
    var body: some Scene {
        WindowGroup { HostView() }
    }
}

private struct HostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> HostController { HostController() }
    func updateUIViewController(_ controller: HostController, context: Context) {}
}

@MainActor
private final class HostController: UIViewController {
    private let status = UILabel()
    private let first = UIViewController()
    private let second = UIViewController()
    private var presentation: KelpieBrowserPresentation?
    private var moved = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        status.text = "Host ready"
        let controls = UIStackView(arrangedSubviews: [
            button("Open browser", action: #selector(openBrowser)),
            button("Move browser", action: #selector(moveBrowser)),
            button("Close browser", action: #selector(closeBrowser)),
            status
        ])
        controls.axis = .horizontal
        controls.spacing = 12
        let containers = UIStackView()
        containers.axis = .horizontal
        containers.distribution = .fillEqually
        for controller in [first, second] {
            addChild(controller)
            containers.addArrangedSubview(controller.view)
            controller.didMove(toParent: self)
        }
        for content in [controls, containers] {
            content.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(content)
        }
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            containers.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
            containers.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containers.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containers.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        AppReveal.start()
    }

    private func button(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func openBrowser() {
        if presentation == nil {
            let provider = KelpieUOASession(
                subject: nil,
                request: { _, _, _, _ in throw URLError(.userAuthenticationRequired) },
                settingsSocket: { _, _ in throw URLError(.userAuthenticationRequired) },
                signIn: { [weak self] in self?.status.text = "Host sign-in requested" },
                signOut: { [weak self] in self?.status.text = "Host sign-out requested" }
            )
            presentation = KelpieBrowserPresentation(
                session: KelpieBrowserSession(uoaSession: provider, localControlEnabled: false)
            )
        }
        presentation?.attach(to: first)
        moved = false
        status.text = "Browser attached"
    }

    @objc private func moveBrowser() {
        guard let presentation else { return }
        moved.toggle()
        presentation.attach(to: moved ? second : first)
        status.text = moved ? "Browser moved" : "Browser returned"
    }

    @objc private func closeBrowser() {
        presentation?.detach()
        status.text = "Browser detached; host remains open"
    }
}
