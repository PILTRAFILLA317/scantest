import Foundation
import StandardCyborgFusion

enum MeshOBJExporter {

  // MARK: - Public: full pipeline

  /// Point cloud → PLY → SCMeshingOperation → mesh PLY → parse → white OBJ.
  /// Runs synchronously – call from a background thread.
  static func buildAndExport(pointCloud: SCPointCloud, to objURL: URL) -> Bool {
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

    // 2. Poisson surface reconstruction (local, no API key)
    //    Tuned for plantar insole scanning: clean surface, few polygons.
    let meshOp = SCMeshingOperation(inputPLYPath: inputPLY.path, outputPLYPath: outputPLY.path)
    let params = SCMeshingParameters()
    params.resolution = 10            // 1-10: balance between detail and file size
    params.smoothness = 1            // 1-10: moderate smoothing, keeps arch shape
    params.surfaceTrimmingAmount = 8 // 0-10: high = elimina geometria inventada en zonas sin datos
    params.closed = false            // open mesh – only the plantar surface matters
    meshOp.parameters = params
    meshOp.start()

    guard FileManager.default.fileExists(atPath: outputPLY.path) else {
      print("[MeshExporter] Meshing produced no output")
      return false
    }

    // 3. Parse mesh PLY → write white OBJ
    return plyToWhiteOBJ(plyURL: outputPLY, objURL: objURL)
  }

  // MARK: - PLY → white OBJ converter

  private static func plyToWhiteOBJ(plyURL: URL, objURL: URL) -> Bool {
    guard let data = try? Data(contentsOf: plyURL) else { return false }
    guard let header = parsePLYHeader(data) else {
      print("[MeshExporter] Failed to parse PLY header")
      return false
    }
    guard header.vertexCount > 0, header.faceCount > 0 else {
      print("[MeshExporter] PLY has 0 vertices or 0 faces")
      return false
    }

    let mesh: (positions: [Float], normals: [Float], faces: [Int32])

    if header.format == "ascii" {
      guard let str = String(data: data, encoding: .ascii),
            let m = readAsciiPLY(str, header: header) else { return false }
      mesh = m
    } else {
      guard let m = readBinaryPLY(data, header: header) else { return false }
      mesh = m
    }

    do {
      try writeWhiteOBJ(positions: mesh.positions,
                         normals: mesh.normals,
                         faces: mesh.faces,
                         to: objURL)
      let vc = mesh.positions.count / 3
      let fc = mesh.faces.count / 3
      print("[MeshExporter] Wrote \(vc) verts, \(fc) faces → \(objURL.lastPathComponent)")
      return true
    } catch {
      print("[MeshExporter] OBJ write failed: \(error)")
      return false
    }
  }

  // MARK: - PLY header parser

  private struct PLYHeader {
    var format = "binary_little_endian"
    var vertexCount = 0
    var faceCount = 0
    var vertexProps: [(name: String, type: String)] = []
    var faceCountType = "uchar"
    var faceIndexType = "int"
    var bodyOffset = 0
  }

  private static func parsePLYHeader(_ data: Data) -> PLYHeader? {
    guard let endMarker = "end_header\n".data(using: .ascii),
          let range = data.range(of: endMarker) else { return nil }

    var h = PLYHeader()
    h.bodyOffset = range.upperBound

    guard let headerStr = String(data: data[0..<range.lowerBound], encoding: .ascii) else { return nil }

    var currentElement = ""
    for line in headerStr.components(separatedBy: "\n") {
      let parts = line.trimmingCharacters(in: .whitespaces)
                      .components(separatedBy: .whitespaces)
                      .filter { !$0.isEmpty }
      guard !parts.isEmpty else { continue }

      switch parts[0] {
      case "format" where parts.count >= 2:
        h.format = parts[1]

      case "element" where parts.count >= 3:
        currentElement = parts[1]
        if parts[1] == "vertex" { h.vertexCount = Int(parts[2]) ?? 0 }
        if parts[1] == "face"   { h.faceCount   = Int(parts[2]) ?? 0 }

      case "property" where currentElement == "vertex" && parts.count >= 3 && parts[1] != "list":
        h.vertexProps.append((name: parts[2], type: parts[1]))

      case "property" where currentElement == "face" && parts[1] == "list" && parts.count >= 5:
        h.faceCountType = parts[2]
        h.faceIndexType = parts[3]

      default: break
      }
    }
    return h
  }

  // MARK: - Binary PLY reader

  private static func readBinaryPLY(_ data: Data, header: PLYHeader)
    -> (positions: [Float], normals: [Float], faces: [Int32])?
  {
    let vertexStride = header.vertexProps.reduce(0) { $0 + sizeOf($1.type) }
    guard vertexStride > 0 else { return nil }

    // Property byte offsets within a vertex
    var offsets: [String: Int] = [:]
    var off = 0
    for p in header.vertexProps {
      offsets[p.name] = off
      off += sizeOf(p.type)
    }

    guard let xOff = offsets["x"], let yOff = offsets["y"], let zOff = offsets["z"] else { return nil }
    let nxOff = offsets["nx"]; let nyOff = offsets["ny"]; let nzOff = offsets["nz"]
    let hasN = nxOff != nil && nyOff != nil && nzOff != nil

    var positions = [Float](repeating: 0, count: header.vertexCount * 3)
    var normals   = hasN ? [Float](repeating: 0, count: header.vertexCount * 3) : [Float]()

    let vStart = header.bodyOffset

    data.withUnsafeBytes { raw in
      let ptr = raw.baseAddress!
      for i in 0..<header.vertexCount {
        let base = vStart + i * vertexStride
        positions[i*3]   = ptr.load(fromByteOffset: base + xOff, as: Float.self)
        positions[i*3+1] = ptr.load(fromByteOffset: base + yOff, as: Float.self)
        positions[i*3+2] = ptr.load(fromByteOffset: base + zOff, as: Float.self)
        if hasN {
          normals[i*3]   = ptr.load(fromByteOffset: base + nxOff!, as: Float.self)
          normals[i*3+1] = ptr.load(fromByteOffset: base + nyOff!, as: Float.self)
          normals[i*3+2] = ptr.load(fromByteOffset: base + nzOff!, as: Float.self)
        }
      }
    }

    // Faces
    let fStart = vStart + header.vertexCount * vertexStride
    let cSize  = sizeOf(header.faceCountType)
    let iSize  = sizeOf(header.faceIndexType)

    var faces = [Int32]()
    faces.reserveCapacity(header.faceCount * 3)

    data.withUnsafeBytes { raw in
      let ptr = raw.baseAddress!
      var cursor = fStart
      for _ in 0..<header.faceCount {
        let nVerts: Int
        switch cSize {
        case 1:  nVerts = Int(ptr.load(fromByteOffset: cursor, as: UInt8.self))
        case 4:  nVerts = Int(ptr.load(fromByteOffset: cursor, as: Int32.self))
        default: nVerts = Int(ptr.load(fromByteOffset: cursor, as: UInt8.self))
        }
        cursor += cSize

        if nVerts == 3 && iSize == 4 {
          faces.append(ptr.load(fromByteOffset: cursor,     as: Int32.self))
          faces.append(ptr.load(fromByteOffset: cursor + 4, as: Int32.self))
          faces.append(ptr.load(fromByteOffset: cursor + 8, as: Int32.self))
        }
        cursor += nVerts * iSize
      }
    }

    return (positions, normals, faces)
  }

  // MARK: - ASCII PLY reader

  private static func readAsciiPLY(_ text: String, header: PLYHeader)
    -> (positions: [Float], normals: [Float], faces: [Int32])?
  {
    let lines = text.components(separatedBy: "\n")
    guard let hEnd = lines.firstIndex(where: { $0.hasPrefix("end_header") }) else { return nil }
    let body = Array(lines[(hEnd + 1)...])

    let names = header.vertexProps.map { $0.name }
    let xi = names.firstIndex(of: "x") ?? 0
    let yi = names.firstIndex(of: "y") ?? 1
    let zi = names.firstIndex(of: "z") ?? 2
    let nxi = names.firstIndex(of: "nx")
    let nyi = names.firstIndex(of: "ny")
    let nzi = names.firstIndex(of: "nz")
    let hasN = nxi != nil && nyi != nil && nzi != nil

    var positions = [Float](); positions.reserveCapacity(header.vertexCount * 3)
    var normals   = [Float](); if hasN { normals.reserveCapacity(header.vertexCount * 3) }

    for i in 0..<header.vertexCount {
      guard i < body.count else { break }
      let vals = body[i].components(separatedBy: " ").compactMap { Float($0) }
      guard vals.count > zi else { continue }
      positions.append(contentsOf: [vals[xi], vals[yi], vals[zi]])
      if hasN, let nxi, let nyi, let nzi, vals.count > nzi {
        normals.append(contentsOf: [vals[nxi], vals[nyi], vals[nzi]])
      }
    }

    var faces = [Int32](); faces.reserveCapacity(header.faceCount * 3)
    for i in header.vertexCount..<(header.vertexCount + header.faceCount) {
      guard i < body.count else { break }
      let vals = body[i].components(separatedBy: " ").compactMap { Int32($0) }
      guard vals.count >= 4, vals[0] == 3 else { continue }
      faces.append(contentsOf: [vals[1], vals[2], vals[3]])
    }

    return (positions, normals, faces)
  }

  // MARK: - White OBJ writer

  private static func writeWhiteOBJ(
    positions: [Float], normals: [Float], faces: [Int32], to url: URL
  ) throws {
    let vc = positions.count / 3
    let fc = faces.count / 3
    let hasN = normals.count == positions.count

    var obj = "# ScanTest – white mesh\n"
    obj += "# \(vc) vertices, \(fc) faces\n\n"
    obj.reserveCapacity(vc * 50 + fc * 35)

    for i in 0..<vc {
      let b = i * 3
      obj += String(format: "v %.6f %.6f %.6f\n", positions[b], positions[b+1], positions[b+2])
    }

    if hasN {
      obj += "\n"
      for i in 0..<vc {
        let b = i * 3
        obj += String(format: "vn %.6f %.6f %.6f\n", normals[b], normals[b+1], normals[b+2])
      }
    }

    obj += "\n"
    for i in 0..<fc {
      let b = i * 3
      let a = faces[b] + 1, c1 = faces[b+1] + 1, c2 = faces[b+2] + 1
      if hasN {
        obj += "f \(a)//\(a) \(c1)//\(c1) \(c2)//\(c2)\n"
      } else {
        obj += "f \(a) \(c1) \(c2)\n"
      }
    }

    try obj.write(to: url, atomically: true, encoding: .utf8)
  }

  // MARK: - Helpers

  private static func sizeOf(_ plyType: String) -> Int {
    switch plyType {
    case "char", "uchar", "int8", "uint8":   return 1
    case "short", "ushort", "int16", "uint16": return 2
    case "int", "uint", "int32", "uint32", "float", "float32": return 4
    case "double", "float64":                  return 8
    default:                                   return 4
    }
  }
}
