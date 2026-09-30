# AsyncImagePipeline

A modern async image-loading library for Apple platforms, built concurrency-first. Think Kingfisher, but designed around Swift Concurrency from the ground up: an **actor**-orchestrated pipeline, `async/await` everywhere, structured cancellation, and protocol-based dependency injection for testability.

- **Swift Concurrency** — `async/await` end to end, no callbacks
- **Actor-based thread safety** — the pipeline, disk cache, and prefetcher are actors; no locks
- **Layered caching** — in-memory (`NSCache`) over disk (`FileManager`, LRU + TTL)
- **Request deduplication** — concurrent requests for the same image share one load
- **Cancellation** — reference-counted, so cancelling one caller never starves its siblings
- **Downsampling** — ImageIO thumbnailing decodes straight to the target size (never allocates the full bitmap)
- **Prefetching** — bounded-concurrency cache warming
- **SwiftUI + UIKit/AppKit** — `RemoteImage`, `UIImageView`/`NSImageView.setImage(from:)`
- **Testable** — every collaborator is an injectable protocol

## Requirements

- iOS 16+ / macOS 13+
- Swift 5.9+ (built with `StrictConcurrency=complete`)

## Installation

Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/FritzHsiao/AsyncImagePipeline.git", from: "1.0.0")
]
```

Then depend on the product(s) you need:

```swift
.target(name: "MyApp", dependencies: [
    "AsyncImagePipeline",     // core
    "AsyncImagePipelineUI",   // RemoteImage, image-view extensions, Prefetcher
])
```

## Quick start

```swift
import AsyncImagePipeline

let image = try await ImagePipeline.shared.image(for: url)
```

SwiftUI:

```swift
import AsyncImagePipelineUI

RemoteImage(url: url)
    .placeholder { ProgressView() }
```

UIKit:

```swift
import AsyncImagePipelineUI

imageView.setImage(from: url, placeholder: UIImage(named: "placeholder"))
```

## Core API

### Loading

```swift
// Simple
let image = try await ImagePipeline.shared.image(for: url)

// Fully specified
let request = ImageRequest(
    url: url,
    processors: [RoundCornerProcessor(radius: 12)],
    options: .init(
        cachePolicy: .memoryAndDisk,
        priority: .high,
        downsampleSize: CGSize(width: 200, height: 200),
        scale: UIScreen.main.scale
    )
)
let image = try await ImagePipeline.shared.image(for: request)
```

### Cache policy

| Policy | Reads memory | Reads disk | Writes memory | Writes disk |
|---|:---:|:---:|:---:|:---:|
| `.memoryAndDisk` (default) | ✓ | ✓ | ✓ | ✓ |
| `.memoryOnly` | ✓ | | ✓ | |
| `.diskOnly` | | ✓ | | ✓ |
| `.reloadIgnoringCache` | | | ✓ | ✓ |
| `.none` | | | | |

### Downsampling

Set `downsampleSize` to decode large downloads straight to display size — the full-resolution bitmap is never allocated:

```swift
let request = ImageRequest(
    url: url,
    options: .init(downsampleSize: CGSize(width: 100, height: 100), scale: 2)
)
```

### Processors

Built-in: `ResizeProcessor(targetPixelSize:)` and `RoundCornerProcessor(radius:)`. Processors run in order after decoding and participate in the cache key.

Write your own by conforming to `ImageProcessing`:

```swift
struct GrayscaleProcessor: ImageProcessing {
    let identifier = "grayscale"
    func process(_ container: ImageContainer) throws -> ImageContainer {
        // transform container.cgImage, return a new ImageContainer
    }
}
```

> The `identifier` must uniquely describe the processor **and its configuration** — it's folded into the cache key so differently-configured processors don't collide.

### Cache management

```swift
ImagePipeline.shared.clearMemoryCache()
await ImagePipeline.shared.clearDiskCache()
ImagePipeline.shared.removeMemoryCachedImage(for: request)
```

## SwiftUI: `RemoteImage`

Zero-config — resizable, fills its frame:

```swift
RemoteImage(url: url)
    .placeholder { ProgressView() }
    .onFailure { _ in Image(systemName: "photo") }
```

`AsyncImage`-style — you control how the loaded image renders:

```swift
RemoteImage(url: url) { image in
    image.resizable().scaledToFill()
}
.placeholder { ProgressView() }
.clipped()
```

The load is driven by `.task(id:)`, so it cancels automatically when the view disappears and restarts when the request's behavior changes (e.g. switching to `.reloadIgnoringCache`).

## UIKit / AppKit

```swift
imageView.setImage(from: url, placeholder: UIImage(named: "placeholder"))
imageView.cancelImageLoad()
```

Safe for cell reuse: each call cancels the previous in-flight load and resets the image, so a recycled cell never shows a stale image — even if the new load fails. The identical API is available on `NSImageView`.

## Prefetching

```swift
let prefetcher = Prefetcher(pipeline: .shared, maxConcurrentLoads: 5)

// e.g. from a UICollectionViewDataSourcePrefetching callback
await prefetcher.startPrefetching(urls: upcomingURLs)
await prefetcher.stopPrefetching(urls: scrolledAwayURLs)
```

Loads run at low priority with bounded concurrency and share the pipeline's deduplication, so prefetching an image that's already on screen (or already prefetched) costs nothing extra.

## Dependency injection & testing

Every collaborator is a protocol with a production default, wired through `ImagePipelineConfiguration`:

```swift
let pipeline = ImagePipeline(configuration: .init(
    dataLoader: MockDataLoader(...),   // any DataLoading
    memoryCache: MemoryCache(),        // any MemoryCaching
    diskCache: DiskCache(...),         // any DiskCaching
    decoder: ImageIODecoder(),         // any ImageDecoding
    validator: ResponseValidator()
))
```

`DataLoading` is the network seam — inject a fake and the whole suite runs offline, with no real requests.

## Architecture

```
ImagePipeline (actor)              // orchestration, memory→disk→network
├── DeduplicatingTaskPool (actor)  // coalescing + ref-counted cancellation
├── ImageRequest                   // url + processors + options; cacheKey / dedupeKey
├── MemoryCache        (MemoryCaching)  // NSCache, cost = bytes
├── DiskCache (actor)  (DiskCaching)    // FileManager, SHA-256 keys, LRU + TTL
├── URLSessionDataLoader (DataLoading)  // + ResponseValidator (HTTP status / content-type)
├── ImageIODecoder     (ImageDecoding)  // decode + thumbnail downsample
└── ImageProcessing[]                   // Resize, RoundCorner, custom

AsyncImagePipelineUI
├── RemoteImage                    // SwiftUI
├── UIImageView / NSImageView.setImage(from:)
└── Prefetcher (actor)             // bounded-concurrency cache warming
```

Two keys distinguish content from behavior:

- **`cacheKey`** — content identity (URL + scale + downsample size + processors). Used for cache reads/writes.
- **`dedupeKey`** — `cacheKey` + cache policy. Used to coalesce in-flight requests and as `RemoteImage`'s reload identity, so requests whose *caching behavior* differs (a force-reload vs a normal load) never share one load.

## Running the tests

```bash
swift build
swift test
```

> **Note:** if `swift test` reports `no such module 'XCTest'`, your `xcode-select` points at the Command Line Tools, which don't bundle XCTest. Point it at a full Xcode for the test run only:
>
> ```bash
> DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
> ```

## License

MIT — see [LICENSE](LICENSE).
