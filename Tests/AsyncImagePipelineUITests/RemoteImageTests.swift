import SwiftUI
import XCTest
@testable import AsyncImagePipeline
@testable import AsyncImagePipelineUI

/// Compile/type-check coverage for the fluent `RemoteImage` API. Rendering behavior needs a host
/// app or snapshot harness; here we verify the builder chain composes and yields a `View`.
@MainActor
final class RemoteImageTests: XCTestCase {

    func testBareInitIsAView() {
        let view = RemoteImage(url: UIFixtures.url(1))
        assertIsView(view)
    }

    func testPlaceholderAndFailureChain() {
        let view = RemoteImage(url: UIFixtures.url(1))
            .placeholder { ProgressView() }
            .onFailure { _ in Image(systemName: "photo") }
        assertIsView(view)
    }

    func testContentClosureStylesImage() {
        // AsyncImage-style: caller controls how the loaded image renders.
        let view = RemoteImage(url: UIFixtures.url(1)) { image in
            image.resizable().scaledToFill()
        }
        .placeholder { ProgressView() }
        assertIsView(view)
    }

    func testContentClosureWithRequestAndPipeline() {
        let loader = CountingLoader(payload: UIFixtures.pngData(), response: UIFixtures.response())
        let pipeline = UIFixtures.pipeline(loader: loader)
        let view = RemoteImage(
            request: ImageRequest(url: UIFixtures.url(1)),
            pipeline: pipeline
        ) { image in
            image.resizable().interpolation(.high)
        }
        .onFailure { _ in Color.red }
        assertIsView(view)
    }

    func testRequestInitWithCustomPipeline() {
        let loader = CountingLoader(payload: UIFixtures.pngData(), response: UIFixtures.response())
        let pipeline = UIFixtures.pipeline(loader: loader)
        let request = ImageRequest(
            url: UIFixtures.url(1),
            options: .init(downsampleSize: CGSize(width: 40, height: 40))
        )
        let view = RemoteImage(request: request, pipeline: pipeline)
            .placeholder { Color.gray }
        assertIsView(view)
    }

    private func assertIsView<V: View>(_ value: V) {
        XCTAssertNotNil(value.body)
    }

    // MARK: Reload identity (P2)

    func testReloadPolicyChangesTaskIdentity() {
        let base = ImageRequest(url: UIFixtures.url(1))
        let reload = ImageRequest(
            url: UIFixtures.url(1),
            options: .init(cachePolicy: .reloadIgnoringCache)
        )
        // Same content key, but the UI load identity must differ so a switch to reload restarts.
        XCTAssertEqual(base.cacheKey, reload.cacheKey)
        XCTAssertNotEqual(base.dedupeKey, reload.dedupeKey)
    }

    func testPriorityDoesNotChangeTaskIdentity() {
        let low = ImageRequest(url: UIFixtures.url(1), options: .init(priority: .low))
        let high = ImageRequest(url: UIFixtures.url(1), options: .init(priority: .high))
        // Priority is a scheduling hint; it should not restart display.
        XCTAssertEqual(low.dedupeKey, high.dedupeKey)
    }
}

#if canImport(AppKit)
import AppKit

/// Verifies the reuse-safety fix (P1): assigning `image` unconditionally so a recycled view does
/// not keep the previous row's image. Exercised on the AppKit (`NSImageView`) branch, which mirrors
/// the UIKit implementation.
@MainActor
final class ImageViewReuseTests: XCTestCase {
    func testSetImageWithoutPlaceholderClearsPreviousImage() {
        let view = NSImageView()
        view.image = NSImage(size: NSSize(width: 4, height: 4))
        XCTAssertNotNil(view.image)

        // A loader that never resolves in time — we only care about the synchronous reset.
        let loader = CountingLoader(
            payload: UIFixtures.pngData(),
            response: UIFixtures.response(),
            delay: .seconds(5)
        )
        let pipeline = UIFixtures.pipeline(loader: loader)

        view.setImage(from: UIFixtures.url(2), pipeline: pipeline)
        // The old image is cleared immediately, before the new load completes.
        XCTAssertNil(view.image, "Reused view must not keep the previous image")

        view.cancelImageLoad()
    }

    func testSetImageAppliesPlaceholderImmediately() {
        let view = NSImageView()
        let placeholder = NSImage(size: NSSize(width: 2, height: 2))

        let loader = CountingLoader(
            payload: UIFixtures.pngData(),
            response: UIFixtures.response(),
            delay: .seconds(5)
        )
        let pipeline = UIFixtures.pipeline(loader: loader)

        view.setImage(from: UIFixtures.url(3), placeholder: placeholder, pipeline: pipeline)
        XCTAssertTrue(view.image === placeholder)

        view.cancelImageLoad()
    }
}
#endif
