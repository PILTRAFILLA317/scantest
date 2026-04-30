import SwiftUI
import SceneKit
import SceneKit.ModelIO
import ModelIO
import StandardCyborgFusion
import StandardCyborgUI
import UIKit

struct ScenePreviewSheet: UIViewControllerRepresentable {
  let sceneURL: URL

  func makeUIViewController(context: Context) -> UIViewController {
    let ext = sceneURL.pathExtension.lowercased()
    if ext == "obj" || ext == "ply" {
      return makeSceneKitPreview(context: context)
    } else {
      return makeGLTFPreview(context: context)
    }
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  // MARK: - OBJ / PLY mesh preview (ModelIO + SceneKit)

  private func makeSceneKitPreview(context: Context) -> UIViewController {
    let mdlAsset = MDLAsset(url: sceneURL)
    mdlAsset.loadTextures()
    let scnScene = SCNScene(mdlAsset: mdlAsset)

    // Strip vertex colors and force white material
    let whiteMat = SCNMaterial()
    whiteMat.diffuse.contents = UIColor.white
    whiteMat.lightingModel = .physicallyBased
    whiteMat.isDoubleSided = true
    scnScene.rootNode.enumerateChildNodes { node, _ in
      if let geo = node.geometry {
        let sources = geo.sources.filter { $0.semantic != .color }
        let newGeo = SCNGeometry(sources: sources, elements: geo.elements)
        newGeo.materials = [whiteMat]
        node.geometry = newGeo
      }
    }

    let vc = UIViewController()

    let scnView = SCNView()
    scnView.scene = scnScene
    scnView.allowsCameraControl = true
    scnView.autoenablesDefaultLighting = true
    scnView.backgroundColor = .black
    scnView.translatesAutoresizingMaskIntoConstraints = false
    vc.view.addSubview(scnView)

    let closeBtn = UIButton(type: .system)
    closeBtn.setTitle("Cerrar", for: .normal)
    closeBtn.titleLabel?.font = .boldSystemFont(ofSize: 17)
    closeBtn.setTitleColor(.white, for: .normal)
    closeBtn.addTarget(context.coordinator, action: #selector(Coordinator.dismissTapped), for: .touchUpInside)
    closeBtn.translatesAutoresizingMaskIntoConstraints = false
    vc.view.addSubview(closeBtn)

    NSLayoutConstraint.activate([
      scnView.topAnchor.constraint(equalTo: vc.view.topAnchor),
      scnView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
      scnView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
      scnView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),

      closeBtn.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 12),
      closeBtn.leadingAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
    ])

    return vc
  }

  // MARK: - GLTF preview (StandardCyborgUI)

  private func makeGLTFPreview(context: Context) -> UIViewController {
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

  // MARK: - Coordinator

  final class Coordinator: NSObject {
    @objc func dismissTapped() {
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
