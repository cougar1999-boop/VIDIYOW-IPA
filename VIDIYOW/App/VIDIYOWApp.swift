import SwiftUI

@main
struct VIDIYOWApp: App {
    var body: some Scene {
        WindowGroup {
            WebPlayerView()
                .preferredColorScheme(.dark)
        }
    }
}
