import SwiftUI
import StandardCyborgFusion
import StandardCyborgUI

struct ContentView: View {
  @StateObject private var store = ScanStore()

  @State private var showingScanner = false
  @State private var shareURL: URL?
  @State private var showingShare = false
  @State private var previewURL: URL?
  @State private var showingPreview = false

  var body: some View {
    NavigationStack {
      List {
        if store.scans.isEmpty {
          Text("No hay escaneos todavía.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(store.scans) { scan in
            VStack(alignment: .leading, spacing: 4) {
              Text(scan.url.lastPathComponent)
                .font(.headline)
              Text(scan.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
              previewURL = scan.url
              showingPreview = true
            }
            .contextMenu {
              Button("Ver") {
                previewURL = scan.url
                showingPreview = true
              }
              Button("Compartir") {
                shareURL = scan.url
                showingShare = true
              }
              Button("Borrar", role: .destructive) {
                store.delete(scan)
              }
            }
            .swipeActions {
              Button {
                shareURL = scan.url
                showingShare = true
              } label: {
                Text("Compartir")
              }
              .tint(.blue)

              Button(role: .destructive) {
                store.delete(scan)
              } label: {
                Text("Borrar")
              }
            }
          }
        }
      }
      .navigationTitle("Mis escaneos")
      .toolbar {
        Button("Nuevo escaneo") {
          showingScanner = true
        }
      }
      .onAppear {
        store.reload()
      }
      .sheet(isPresented: $showingScanner) {
        ScannerSheet(
          onFinished: { pointCloud, scanningVC in
            // Al terminar, vamos a:
            // 1) Generar un SCScene (vía preview VC del SDK) y guardarlo.
            // 2) Cerrar scanner.
            // 3) Refrescar lista y opcionalmente abrir share.

            saveResult(pointCloud: pointCloud, scanningVC: scanningVC)
          },
          onCanceled: {
            showingScanner = false
          }
        )
      }
      .sheet(isPresented: $showingShare) {
        if let shareURL {
          ShareSheet(activityItems: [shareURL])
        }
      }
      .sheet(isPresented: $showingPreview) {
        if let previewURL {
          ScenePreviewSheet(sceneURL: previewURL)
        }
      }
    }
  }

  @MainActor
  private func saveResult(pointCloud: SCPointCloud, scanningVC: ScanningViewController) {
    // Opción rápida: reutilizar el ScenePreviewViewController para obtener un SCScene.
    let previewVC = ScenePreviewViewController(
      pointCloud: pointCloud,
      meshTexturing: scanningVC.meshTexturing,
      landmarks: nil
    )

    // Aquí está el punto CLAVE: exportar.
    // En tu SDK, seguro existe writeToGLTF; OBJ hay que confirmar.
    let fileBase = "scan_\(timestamp())"

    let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let gltfURL = docsURL.appendingPathComponent("\(fileBase).gltf")

    previewVC.scScene.writeToGLTF(atPath: gltfURL.path)

    // Cerrar scanner sheet
    showingScanner = false

    store.reload()

    // Compartir automáticamente si quieres:
    shareURL = gltfURL
    showingShare = true
  }

  private func timestamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd_HHmmss"
    return f.string(from: Date())
  }
}