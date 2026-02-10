import SwiftUI
import StandardCyborgFusion

struct ContentView: View {
  @StateObject private var store = ScanStore()

  @State private var showingScanner = false
  @State private var shareURL: URL?
  @State private var showingShare = false
  @State private var previewURL: URL?
  @State private var showingPreview = false
  @State private var isProcessing = false

  var body: some View {
    NavigationStack {
      ZStack {
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
          .disabled(isProcessing)
        }
        .onAppear {
          store.reload()
        }
        .sheet(isPresented: $showingScanner) {
          ScannerSheet(
            onFinished: { pointCloud, _ in
              saveResult(pointCloud: pointCloud)
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

        // Processing overlay
        if isProcessing {
          Color.black.opacity(0.45)
            .ignoresSafeArea()
          VStack(spacing: 12) {
            ProgressView()
              .scaleEffect(1.3)
            Text("Generando mesh…")
              .font(.headline)
          }
          .padding(28)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
      }
    }
  }

  // MARK: - Meshing pipeline

  private func saveResult(pointCloud: SCPointCloud) {
    showingScanner = false
    isProcessing = true

    let fileBase = "scan_\(timestamp())"
    let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let objURL = docsURL.appendingPathComponent("\(fileBase).obj")

    DispatchQueue.global(qos: .userInitiated).async {
      let ok = MeshOBJExporter.buildAndExport(pointCloud: pointCloud, to: objURL)

      DispatchQueue.main.async {
        isProcessing = false
        if ok {
          store.reload()
          shareURL = objURL
          showingShare = true
        }
      }
    }
  }

  private func timestamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd_HHmmss"
    return f.string(from: Date())
  }
}
