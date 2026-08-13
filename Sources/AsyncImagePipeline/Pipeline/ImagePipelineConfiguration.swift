import Foundation

/// The pipeline's injectable dependencies. Every collaborator is a protocol with a production
/// default, so tests can substitute spies/fakes while `ImagePipeline.shared` uses real ones.
public struct ImagePipelineConfiguration: Sendable {
    public var dataLoader: any DataLoading
    public var memoryCache: any MemoryCaching
    public var diskCache: any DiskCaching
    public var decoder: any ImageDecoding
    public var validator: ResponseValidator

    public init(
        dataLoader: any DataLoading = URLSessionDataLoader(),
        memoryCache: any MemoryCaching = MemoryCache(),
        diskCache: any DiskCaching = DiskCache(),
        decoder: any ImageDecoding = ImageIODecoder(),
        validator: ResponseValidator = ResponseValidator()
    ) {
        self.dataLoader = dataLoader
        self.memoryCache = memoryCache
        self.diskCache = diskCache
        self.decoder = decoder
        self.validator = validator
    }
}
