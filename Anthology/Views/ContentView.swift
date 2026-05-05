import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: BridgeStore

    var body: some View {
        Group {
            if store.server == nil {
                PairingView()
            } else {
                SessionListView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.server?.id)
    }
}

#Preview {
    ContentView()
        .environmentObject(BridgeStore())
}
