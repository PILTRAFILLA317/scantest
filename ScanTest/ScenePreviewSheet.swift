import SwiftUI
import StandardCyborgFusion
import StandardCyborgUI
import UIKit

struct ScenePreviewSheet: UIViewControllerRepresentable {
  let sceneURL: URL

  func makeUIViewController(context: Context) -> UIViewController {
    let scene = SCScene(gltfAtPath: sceneURL.path)
    let vc = ScenePreviewViewController(scScene: scene)

    vc.leftButton.setTitle("Cerrar", for: .normal)
    vc.rightButton.isHidden = true

    vc.leftButton.addTarget(
      context.coordinator,
      action: #selector(Coordinator.dismissTapped),
      for: .touchUpInside
    )

    return vc
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  final class Coordinator: NSObject {
    @objc func dismissTapped() {
      // Este truco cierra el sheet desde UIKit sin necesitar binding extra
      UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?
        .rootViewController?
        .presentedViewController?
        .dismiss(animated: true)
    }
  }
}