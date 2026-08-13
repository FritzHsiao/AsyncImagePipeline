import SwiftUI
import AsyncImagePipeline
import AsyncImagePipelineUI

/// A scrolling grid of `RemoteImage` cells. Demonstrates deduplication (shared pipeline), disk +
/// memory caching, downsampled thumbnails, and prefetch-ahead as you scroll.
struct ImageGridView: View {
    @State private var prefetcher = Prefetcher(maxConcurrentLoads: 6)
    @State private var path = NavigationPath()
    @State private var didDeepLink = false

    private let ids = DemoData.ids
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    /// How many rows ahead to warm the cache.
    private let prefetchWindow = 12

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(ids, id: \.self) { id in
                        NavigationLink(value: id) {
                            cell(id: id)
                        }
                        .buttonStyle(.plain)
                        .onAppear { startPrefetch(around: id) }
                        .onDisappear { stopPrefetch(id) }
                    }
                }
                .padding(2)
            }
            .navigationTitle("Photos")
            .navigationDestination(for: Int.self) { id in
                DetailView(id: id)
            }
            .onAppear {
                if !didDeepLink, let id = LaunchOptions.detailID {
                    didDeepLink = true
                    path.append(id)
                }
            }
        }
    }

    private func cell(id: Int) -> some View {
        RemoteImage(request: DemoData.thumbRequest(id)) { image in
            image.resizable().scaledToFill()
        }
        .placeholder {
            Color(.secondarySystemBackground)
                .overlay(ProgressView())
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: Prefetching

    private func startPrefetch(around id: Int) {
        guard let index = ids.firstIndex(of: id) else { return }
        let upcoming = ids[index..<min(index + prefetchWindow, ids.count)]
        let requests = upcoming.map { DemoData.thumbRequest($0) }
        Task { await prefetcher.startPrefetching(requests: requests) }
    }

    private func stopPrefetch(_ id: Int) {
        let request = DemoData.thumbRequest(id)
        Task { await prefetcher.stopPrefetching(requests: [request]) }
    }
}
