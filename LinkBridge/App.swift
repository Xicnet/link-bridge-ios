import SwiftUI

@main
struct LinkBridgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text("LinkBridge")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }
}
