import SwiftUI

@main
struct AsyncImagePipelineDemoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var selection = LaunchOptions.initialTab

    var body: some View {
        TabView(selection: $selection) {
            ImageGridView()
                .tag(0)
                .tabItem { Label("Grid", systemImage: "square.grid.3x3") }

            DownsampleDemoView()
                .tag(1)
                .tabItem { Label("Downsample", systemImage: "arrow.down.right.and.arrow.up.left") }
        }
    }
}

/// Optional launch overrides (via environment) so the demo can open on a given screen — handy for
/// scripted screenshots. `DEMO_TAB=0|1`, `DEMO_DETAIL=<id>`.
enum LaunchOptions {
    static var initialTab: Int {
        Int(ProcessInfo.processInfo.environment["DEMO_TAB"] ?? "") ?? 0
    }
    static var detailID: Int? {
        ProcessInfo.processInfo.environment["DEMO_DETAIL"].flatMap(Int.init)
    }
}
