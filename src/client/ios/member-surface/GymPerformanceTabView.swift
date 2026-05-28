import SwiftUI

struct GymPerformanceTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BoardView()
                .tabItem {
                    Label("Board", systemImage: selectedTab == 0 ? "list.bullet.rectangle.portrait.fill" : "list.bullet.rectangle.portrait")
                }
                .tag(0)

            LogSessionView(switchToBoard: { selectedTab = 0 })
                .tabItem {
                    Label("Log Session", systemImage: selectedTab == 1 ? "plus.circle.fill" : "plus.circle")
                }
                .tag(1)
        }
        .tint(Color.wolfBlue)
    }
}

#Preview {
    GymPerformanceTabView()
}
