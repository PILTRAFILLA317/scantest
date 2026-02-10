import Foundation
import StandardCyborgFusion

@MainActor
final class ScanStore: ObservableObject {
  struct ScanFile: Identifiable, Hashable {
    let id: String
    let url: URL
    let createdAt: Date
  }

  @Published private(set) var scans: [ScanFile] = []

  private var docsURL: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
  }

  func reload() {
    let fm = FileManager.default
    let urls = (try? fm.contentsOfDirectory(
      at: docsURL,
      includingPropertiesForKeys: [.creationDateKey],
      options: [.skipsHiddenFiles]
    )) ?? []

    let scanURLs = urls.filter { $0.pathExtension.lowercased() == "obj" || $0.pathExtension.lowercased() == "gltf" }

    let files: [ScanFile] = scanURLs.compactMap { url in
      let values = try? url.resourceValues(forKeys: [.creationDateKey])
      let date = values?.creationDate ?? Date.distantPast
      return ScanFile(id: url.lastPathComponent, url: url, createdAt: date)
    }
    .sorted { $0.createdAt > $1.createdAt }

    scans = files
  }

  func delete(_ scan: ScanFile) {
    try? FileManager.default.removeItem(at: scan.url)
    reload()
  }
}