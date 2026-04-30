import Foundation
import StandardCyborgFusion

enum MeshExporter {

  /// Point cloud → PLY → SCMeshingOperation → color-stripped binary PLY.
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

    // 3. Strip vertex colors and write clean PLY
    guard stripColorsFromPLY(src: outputPLY, dst: plyURL) else {
      print("[MeshExporter] Failed to strip colors")
      return false
    }

    let size = (try? FileManager.default.attributesOfItem(atPath: plyURL.path)[.size] as? Int) ?? 0
    print("[MeshExporter] Wrote binary PLY → \(plyURL.lastPathComponent) (\(size / 1024) KB)")
    return true
  }

  // MARK: - Strip vertex colors from binary PLY

  private static let colorNames: Set<String> = ["red", "green", "blue", "alpha", "r", "g", "b", "a"]

  private static func stripColorsFromPLY(src: URL, dst: URL) -> Bool {
    guard let data = try? Data(contentsOf: src) else { return false }
    guard let endMarker = "end_header\n".data(using: .ascii),
          let endRange = data.range(of: endMarker) else { return false }

    let headerData = data[data.startIndex..<endRange.lowerBound]
    guard let headerStr = String(data: headerData, encoding: .ascii) else { return false }
    let bodyStart = endRange.upperBound

    // Parse header
    struct Prop { let name: String; let type: String; let size: Int }

    var vertexCount = 0
    var faceCount = 0
    var vertexProps: [Prop] = []
    var faceListLine = ""
    var currentElement = ""
    var newHeaderLines: [String] = []

    for line in headerStr.components(separatedBy: "\n") {
      let parts = line.trimmingCharacters(in: .whitespaces)
                      .components(separatedBy: .whitespaces)
                      .filter { !$0.isEmpty }
      guard !parts.isEmpty else {
        newHeaderLines.append(line)
        continue
      }

      switch parts[0] {
      case "element" where parts.count >= 3:
        currentElement = parts[1]
        if parts[1] == "vertex" { vertexCount = Int(parts[2]) ?? 0 }
        if parts[1] == "face"   { faceCount   = Int(parts[2]) ?? 0 }
        newHeaderLines.append(line)

      case "property" where currentElement == "vertex" && parts.count >= 3 && parts[1] != "list":
        let propName = parts[2]
        let propType = parts[1]
        let propSize = sizeOf(propType)
        vertexProps.append(Prop(name: propName, type: propType, size: propSize))
        // Only keep non-color properties in the new header
        if !colorNames.contains(propName.lowercased()) {
          newHeaderLines.append(line)
        }

      case "property" where currentElement == "face":
        faceListLine = line
        newHeaderLines.append(line)

      default:
        newHeaderLines.append(line)
      }
    }

    let oldStride = vertexProps.reduce(0) { $0 + $1.size }
    guard oldStride > 0, vertexCount > 0 else { return false }

    // Build byte ranges to keep per vertex (skip color properties)
    struct ByteRange { let offset: Int; let length: Int }
    var keepRanges: [ByteRange] = []
    var offset = 0
    for prop in vertexProps {
      if !colorNames.contains(prop.name.lowercased()) {
        keepRanges.append(ByteRange(offset: offset, length: prop.size))
      }
      offset += prop.size
    }
    let newStride = keepRanges.reduce(0) { $0 + $1.length }

    // Merge contiguous ranges for efficiency
    var merged: [ByteRange] = []
    for r in keepRanges {
      if let last = merged.last, last.offset + last.length == r.offset {
        merged[merged.count - 1] = ByteRange(offset: last.offset, length: last.length + r.length)
      } else {
        merged.append(r)
      }
    }

    // Build new header
    var newHeader = newHeaderLines.joined(separator: "\n") + "\nend_header\n"

    // Allocate output
    let vertexDataEnd = bodyStart + vertexCount * oldStride
    let faceData = data[vertexDataEnd...]
    let outputSize = newHeader.utf8.count + vertexCount * newStride + faceData.count
    var output = Data(capacity: outputSize)

    output.append(newHeader.data(using: .ascii)!)

    // Copy vertices, skipping color bytes
    data.withUnsafeBytes { raw in
      let ptr = raw.baseAddress!
      var vertexBuf = Data(count: newStride)
      for i in 0..<vertexCount {
        let base = bodyStart + i * oldStride
        var writeOff = 0
        vertexBuf.withUnsafeMutableBytes { dst in
          let dstPtr = dst.baseAddress!
          for r in merged {
            memcpy(dstPtr + writeOff, ptr + base + r.offset, r.length)
            writeOff += r.length
          }
        }
        output.append(vertexBuf)
      }
    }

    // Copy face data unchanged
    output.append(faceData)

    do {
      if FileManager.default.fileExists(atPath: dst.path) {
        try FileManager.default.removeItem(at: dst)
      }
      try output.write(to: dst)
      return true
    } catch {
      print("[MeshExporter] Write failed: \(error)")
      return false
    }
  }

  private static func sizeOf(_ plyType: String) -> Int {
    switch plyType {
    case "char", "uchar", "int8", "uint8":     return 1
    case "short", "ushort", "int16", "uint16":  return 2
    case "int", "uint", "int32", "uint32", "float", "float32": return 4
    case "double", "float64":                    return 8
    default:                                     return 4
    }
  }
}
