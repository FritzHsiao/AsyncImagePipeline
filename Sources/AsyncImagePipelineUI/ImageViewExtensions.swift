import AsyncImagePipeline

#if canImport(UIKit)
import UIKit

extension UIImageView {
    private enum AssociatedKeys {
        // Associated-object storage key. `nonisolated(unsafe)` because we only take its address.
        nonisolated(unsafe) static var task: UInt8 = 0
    }

    private var aip_currentTask: Task<Void, Never>? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.task) as? Task<Void, Never> }
        set { objc_setAssociatedObject(self, &AssociatedKeys.task, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Loads `url` into the image view, showing `placeholder` until it arrives.
    ///
    /// Safe for cell reuse: each call cancels the previous in-flight load, so a recycled cell never
    /// gets a stale image from an earlier row.
    public func setImage(
        from url: URL,
        placeholder: UIImage? = nil,
        pipeline: ImagePipeline = .shared
    ) {
        setImage(from: ImageRequest(url: url), placeholder: placeholder, pipeline: pipeline)
    }

    /// Loads a fully-specified `request` into the image view.
    public func setImage(
        from request: ImageRequest,
        placeholder: UIImage? = nil,
        pipeline: ImagePipeline = .shared
    ) {
        aip_currentTask?.cancel()
        // Assign unconditionally (even when nil) so a recycled view never keeps the previous
        // row's image on screen during — or after a failure of — the new load.
        image = placeholder
        aip_currentTask = Task { [weak self] in
            let container = try? await pipeline.container(for: request)
            guard !Task.isCancelled, let self, let container else { return }
            self.image = container.platformImage
        }
    }

    /// Cancels any in-flight load started by `setImage`.
    public func cancelImageLoad() {
        aip_currentTask?.cancel()
        aip_currentTask = nil
    }
}

#elseif canImport(AppKit)
import AppKit

extension NSImageView {
    private enum AssociatedKeys {
        nonisolated(unsafe) static var task: UInt8 = 0
    }

    private var aip_currentTask: Task<Void, Never>? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.task) as? Task<Void, Never> }
        set { objc_setAssociatedObject(self, &AssociatedKeys.task, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Loads `url` into the image view, showing `placeholder` until it arrives.
    ///
    /// Safe for cell reuse: each call cancels the previous in-flight load.
    public func setImage(
        from url: URL,
        placeholder: NSImage? = nil,
        pipeline: ImagePipeline = .shared
    ) {
        setImage(from: ImageRequest(url: url), placeholder: placeholder, pipeline: pipeline)
    }

    /// Loads a fully-specified `request` into the image view.
    public func setImage(
        from request: ImageRequest,
        placeholder: NSImage? = nil,
        pipeline: ImagePipeline = .shared
    ) {
        aip_currentTask?.cancel()
        // Assign unconditionally (even when nil) so a recycled view never keeps the previous
        // row's image on screen during — or after a failure of — the new load.
        image = placeholder
        aip_currentTask = Task { [weak self] in
            let container = try? await pipeline.container(for: request)
            guard !Task.isCancelled, let self, let container else { return }
            self.image = container.platformImage
        }
    }

    /// Cancels any in-flight load started by `setImage`.
    public func cancelImageLoad() {
        aip_currentTask?.cancel()
        aip_currentTask = nil
    }
}
#endif
