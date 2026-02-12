import Foundation
import StandardCyborgFusion

enum MeshExporter {

  /// Point cloud → PLY → SCMeshingOperation → binary PLY mesh.
  /// Runs synchronously – call from a background thread.
  static func buildAndExport(pointCloud: SCPointCloud, to plyURL: URL) -> Bool {
    let tmp = FileManager.default.temporaryDirectory
    let id  = UUID().uuidString
    let inputPLY  = tmp.appendingPathComponent("\(id)_in.ply")
    let outputPLY = tmp.appendingPathComponent("\(id)_mesh.ply")

    defer {
      try? FileManager.default.removeItem(at: inputPLY)
      try? FileManager.default.removeItem(at: outputPLY)
    }

    // 1. Save point cloud as PLY
    guard pointCloud.writeToPLY(atPath: inputPLY.path) else {
      print("[MeshExporter] Failed to write input PLY")
      return false
    }

    // 2. Poisson surface reconstruction
    let meshOp = SCMeshingOperation(inputPLYPath: inputPLY.path, outputPLYPath: outputPLY.path)
    let params = SCMeshingParameters()
    params.resolution = 10
    params.smoothness = 1
    params.surfaceTrimmingAmount = 7
    params.closed = false
    meshOp.parameters = params
    meshOp.start()

    guard FileManager.default.fileExists(atPath: outputPLY.path) else {
      print("[MeshExporter] Meshing produced no output")
      return false
    }

    // 3. Move binary PLY to destination
    do {
      if FileManager.default.fileExists(atPath: plyURL.path) {
        try FileManager.default.removeItem(at: plyURL)
      }
      try FileManager.default.moveItem(at: outputPLY, to: plyURL)
      let size = (try? FileManager.default.attributesOfItem(atPath: plyURL.path)[.size] as? Int) ?? 0
      print("[MeshExporter] Wrote binary PLY → \(plyURL.lastPathComponent) (\(size / 1024) KB)")
      return true
    } catch {
      print("[MeshExporter] Failed to move PLY: \(error)")
      return false
    }
  }
}
