import SwiftUI
import AsyncImagePipeline
import AsyncImagePipelineUI

/// Loads the same 3000×3000 source two ways: downsampled to a thumbnail, and at full resolution.
/// Both come from one URL but have different cache keys (downsample size differs), so each is a
/// distinct entry — illustrating that the thumbnail never allocates the full-size bitmap.
struct DownsampleDemoView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("The same 3000×3000 image, decoded two ways.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    card(
                        title: "Downsampled → 120×120 pt",
                        subtitle: "ImageIO thumbnailing decodes straight to size.",
                        request: ImageRequest(
                            url: DemoData.largeURL,
                            options: .init(downsampleSize: CGSize(width: 120, height: 120), scale: 3)
                        )
                    )

                    card(
                        title: "Full-size decode",
                        subtitle: "Entire bitmap decoded, then scaled down for display.",
                        request: ImageRequest(url: DemoData.largeURL)
                    )
                }
                .padding()
            }
            .navigationTitle("Downsampling")
        }
    }

    private func card(title: String, subtitle: String, request: ImageRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)

            RemoteImage(request: request) { image in
                image.resizable().scaledToFit()
            }
            .placeholder {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 220)
                    .overlay(ProgressView())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
