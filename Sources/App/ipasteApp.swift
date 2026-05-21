import SwiftUI

@main
struct IpasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The real preferences UI arrives in Phase 5. An empty Settings
        // scene satisfies SwiftUI's requirement for at least one scene
        // without opening any window at launch — ipaste is a menu-bar
        // agent app (see LSUIElement in Info.plist).
        Settings {
            EmptyView()
        }
    }
}
