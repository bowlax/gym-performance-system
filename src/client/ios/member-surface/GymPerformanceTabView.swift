import SwiftUI

struct GymPerformanceTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BoardView()
                .tabItem { Label("Board", systemImage: "trophy.fill") }
                .tag(0)

            LogSessionView(switchToBoard: { selectedTab = 0 })
                .tabItem { Label("Log Session", systemImage: "plus.square.fill") }
                .tag(1)
        }
    }
}

#Preview {
    GymPerformanceTabView()
}
