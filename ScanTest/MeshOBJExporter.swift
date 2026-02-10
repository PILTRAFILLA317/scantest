import Foundation
import StandardCyborgFusion

enum MeshOBJExporter {
  static func export(mesh: SCMesh, to url: URL) throws {
    throw NSError(
      domain: "MeshOBJExporter",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Export OBJ no implementado todavía"]
    )
  }
}