import SwiftUI
import StandardCyborgUI
import StandardCyborgFusion
import UIKit

// MARK: - Subclass to configure depth limits

/// Subclasses ScanningViewController to set minDepth/maxDepth on the
/// private SCReconstructionManager via Mirror (Swift reflection).
/// This controls the scanning distance range in meters.
private class DepthLimitedScanningVC: ScanningViewController {

  var scanMaxDepth: Float = 0.30

  override func viewDidLoad() {
    super.viewDidLoad() // initializes the lazy _reconstructionManager

    guard let manager = findReconstructionManager() else {
      print("[ScannerSheet] Could not find SCReconstructionManager – depth limits not applied")
      return
    }
    manager.minDepth = 0.15
    manager.maxDepth = scanMaxDepth
    print("[ScannerSheet] Depth limits: 0.15 – \(scanMaxDepth) m")
  }

  /// Walks the Mirror superclass chain to find the private _reconstructionManager.
  private func findReconstructionManager() -> SCReconstructionManager? {
    var mirror: Mirror? = Mirror(reflecting: self)
    while let m = mirror {
      for child in m.children {
        guard let label = child.label,
              label.contains("reconstructionManager") else { continue }

        // Direct cast (non-lazy or already-evaluated)
        if let mgr = child.value as? SCReconstructionManager { return mgr }

        // Lazy vars are stored as Optional internally
        let inner = Mirror(reflecting: child.value)
        if inner.displayStyle == .optional,
           let (_, unwrapped) = inner.children.first,
           let mgr = unwrapped as? SCReconstructionManager { return mgr }
      }
      mirror = m.superclassMirror
    }
    return nil
  }
}

// MARK: - SwiftUI Bridge

struct ScannerSheet: UIViewControllerRepresentable {

  /// Maximum scan distance in meters (default 0.80 m = 80 cm).
  /// Typical values:
  ///  - Face/small object:  0.50
  ///  - Bust/torso:         0.80
  ///  - Medium object:      1.20
  var maxDepth: Float = 0.30

  let onFinished: (SCPointCloud, ScanningViewController) -> Void
  let onCanceled: () -> Void

  final class Coordinator: NSObject, ScanningViewControllerDelegate {
    let onFinished: (SCPointCloud, ScanningViewController) -> Void
    let onCanceled: () -> Void

    init(
      onFinished: @escaping (SCPointCloud, ScanningViewController) -> Void,
      onCanceled: @escaping () -> Void
    ) {
      self.onFinished = onFinished
      self.onCanceled = onCanceled
    }

    func scanningViewControllerDidCancel(_ controller: ScanningViewController) {
      onCanceled()
    }

    func scanningViewController(_ controller: ScanningViewController, didScan pointCloud: SCPointCloud) {
      onFinished(pointCloud, controller)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onFinished: onFinished, onCanceled: onCanceled)
  }

  func makeUIViewController(context: Context) -> UIViewController {
    let scanningVC = DepthLimitedScanningVC()
    scanningVC.scanMaxDepth = maxDepth
    scanningVC.delegate = context.coordinator
    scanningVC.generatesTexturedMeshes = false
    scanningVC.modalPresentationStyle = .fullScreen
    return scanningVC
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
