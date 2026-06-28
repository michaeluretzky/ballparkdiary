import UIKit
import SwiftUI

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let hostingController = UIHostingController(
            rootView: ShareView(
                extensionContext: extensionContext,
                openHostApp: { [weak self] in self?.openHostApp() }
            )
        )
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    /// Launches the containing app via its custom URL scheme.
    ///
    /// `NSExtensionContext.open(_:)` is documented to work only for Today
    /// extensions and silently fails for Share Extensions — which is why the
    /// "Open Diary" button appeared to do nothing. The reliable approach is to
    /// walk the responder chain until we reach the shared `UIApplication` and
    /// invoke `openURL:` on it via selector (the symbol is unavailable to
    /// extensions at compile time, so we call it dynamically).
    private func openHostApp() {
        guard let url = URL(string: "ballparkdiary://import") else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        var didOpen = false
        while let current = responder {
            if current !== self, current.responds(to: selector) {
                current.perform(selector, with: url)
                didOpen = true
                break
            }
            responder = current.next
        }

        // Give the system a beat to switch to the host app before we tear the
        // extension down. If we never found a responder, dismiss right away.
        let delay: TimeInterval = didOpen ? 0.5 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
