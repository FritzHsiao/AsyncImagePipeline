import SwiftUI
import AsyncImagePipeline
import AsyncImagePipelineUI

/// Full-size detail view. The toolbar button flips the request to `.reloadIgnoringCache`, which
/// changes the request's `dedupeKey` and so makes `RemoteImage` restart the load — a force refresh
/// that bypasses both cache layers.
struct DetailView: View {
    let id: Int

    @State private var reloadToken = 0

    var body: some View {
        ScrollView {
            RemoteImage(request: request) { image in
                image.resizable().scaledToFit()
            }
            .placeholder {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
            .onFailure { _ in
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash").font(.largeTitle)
                    Text("Couldn't load")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 300)
            }
            .padding()
        }
        .navigationTitle("Photo \(id)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reloadToken += 1
                } label: {
                    Label("Force reload", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var request: ImageRequest {
        // Alternating tokens flip the policy so each tap yields a fresh dedupeKey → a real reload.
        let policy: CachePolicy = reloadToken % 2 == 0 ? .memoryAndDisk : .reloadIgnoringCache
        return ImageRequest(url: DemoData.fullURL(id), options: .init(cachePolicy: policy))
    }
}
