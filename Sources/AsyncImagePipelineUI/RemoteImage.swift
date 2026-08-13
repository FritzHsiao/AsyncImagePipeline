import SwiftUI
import AsyncImagePipeline

/// A SwiftUI view that asynchronously loads and displays an image through an ``ImagePipeline``.
///
/// Zero-config — fills its frame, resizable by default:
/// ```swift
/// RemoteImage(url: url)
///     .placeholder { ProgressView() }
/// ```
///
/// Or `AsyncImage`-style, styling the loaded image yourself:
/// ```swift
/// RemoteImage(url: url) { image in
///     image.resizable().scaledToFill()
/// }
/// .placeholder { ProgressView() }
/// .onFailure { _ in Image(systemName: "photo") }
/// ```
///
/// The load is driven by `.task(id:)`, so it is cancelled automatically when the view disappears
/// and restarted when the request's behavior changes. Deduplication and caching are handled by the
/// pipeline.
@MainActor
public struct RemoteImage<Content: View, Placeholder: View, Failure: View>: View {
    /// Rendering state.
    private enum Phase {
        case loading
        case success(PlatformImage)
        case failure(Error)
    }

    private let request: ImageRequest
    private let pipeline: ImagePipeline
    private let transform: (Image) -> Content
    private let placeholder: Placeholder
    private let failure: (Error) -> Failure

    @State private var phase: Phase = .loading

    private init(
        request: ImageRequest,
        pipeline: ImagePipeline,
        transform: @escaping (Image) -> Content,
        placeholder: Placeholder,
        failure: @escaping (Error) -> Failure
    ) {
        self.request = request
        self.pipeline = pipeline
        self.transform = transform
        self.placeholder = placeholder
        self.failure = failure
    }

    public var body: some View {
        content
            // dedupeKey (not cacheKey) so a change to behavior-affecting options — notably a switch
            // to .reloadIgnoringCache — restarts the load instead of keeping the cached phase.
            .task(id: request.dedupeKey) {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            placeholder
        case .success(let image):
            transform(Image(platformImage: image))
        case .failure(let error):
            failure(error)
        }
    }

    private func load() async {
        phase = .loading
        do {
            let container = try await pipeline.container(for: request)
            phase = .success(container.platformImage)
        } catch is CancellationError {
            // View disappeared or the request changed; keep showing the placeholder.
        } catch {
            phase = .failure(error)
        }
    }
}

// MARK: - Zero-config initializers (resizable by default)

extension RemoteImage where Content == Image, Placeholder == EmptyView, Failure == EmptyView {
    /// Loads `url` and displays it resizable, filling its frame. Style further with the
    /// `content:`-closure initializers when you need `scaledToFill`, interpolation, etc.
    public init(url: URL, pipeline: ImagePipeline = .shared) {
        self.init(request: ImageRequest(url: url), pipeline: pipeline)
    }

    /// Loads a fully-specified `request` and displays it resizable.
    public init(request: ImageRequest, pipeline: ImagePipeline = .shared) {
        self.init(
            request: request,
            pipeline: pipeline,
            transform: { $0.resizable() },
            placeholder: EmptyView(),
            failure: { _ in EmptyView() }
        )
    }
}

// MARK: - AsyncImage-style initializers (caller styles the Image)

extension RemoteImage where Placeholder == EmptyView, Failure == EmptyView {
    /// Loads `url` and hands the decoded `Image` to `content` so the caller controls rendering
    /// (`.resizable()`, `.scaledToFill()`, `.interpolation(_:)`, …).
    public init(
        url: URL,
        pipeline: ImagePipeline = .shared,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(request: ImageRequest(url: url), pipeline: pipeline, content: content)
    }

    /// Loads a fully-specified `request` and hands the decoded `Image` to `content`.
    public init(
        request: ImageRequest,
        pipeline: ImagePipeline = .shared,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            request: request,
            pipeline: pipeline,
            transform: content,
            placeholder: EmptyView(),
            failure: { _ in EmptyView() }
        )
    }
}

// MARK: - Fluent modifiers

extension RemoteImage {
    /// Sets the view shown while the image is loading.
    public func placeholder<P: View>(
        @ViewBuilder _ content: () -> P
    ) -> RemoteImage<Content, P, Failure> {
        RemoteImage<Content, P, Failure>(
            request: request,
            pipeline: pipeline,
            transform: transform,
            placeholder: content(),
            failure: failure
        )
    }

    /// Sets the view shown if the load fails (cancellation is not a failure).
    public func onFailure<F: View>(
        @ViewBuilder _ content: @escaping (Error) -> F
    ) -> RemoteImage<Content, Placeholder, F> {
        RemoteImage<Content, Placeholder, F>(
            request: request,
            pipeline: pipeline,
            transform: transform,
            placeholder: placeholder,
            failure: content
        )
    }
}
