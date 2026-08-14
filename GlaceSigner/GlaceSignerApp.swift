import Foundation
import SwiftUI

@main
struct GlaceSignerApp: App {
    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-GlaceForceRightToLeft") {
            SignerSetupFlowView()
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            SignerSetupFlowView()
        }
#else
        SignerSetupFlowView()
#endif
    }
}
