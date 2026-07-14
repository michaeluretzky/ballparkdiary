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
    /// On iOS 18 the classic `openURL:` selector hack is hard-blocked by UIKit
    /// ("Force returning false"), so taps appeared to do nothing — especially
    /// when sharing from Photos. The approach that works on iOS 18 is to walk
    /// the responder chain, cast to `UIApplication`, and call the modern
    /// `open(_:options:completionHandler:)` API on it.
    private func openHostApp() {
        guard let url = URL(string: "ballparkdiary://import") else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        var didOpen = false
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                didOpen = true
                break
            }
            responder = current.next
        }

        // Legacy fallback for systems where the cast never matched.
        if !didOpen {
            let selector = sel_registerName("openURL:")
            responder = self
            while let current = responder {
                if current !== self, current.responds(to: selector) {
                    current.perform(selector, with: url)
                    didOpen = true
                    break
                }
                responder = current.next
            }
        }

        // Give the system a beat to switch to the host app before we tear the
        // extension down. If we never found a responder, dismiss right away.
        let delay: TimeInterval = didOpen ? 0.8 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
