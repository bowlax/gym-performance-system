import SwiftUI

struct GymPerformanceTabView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
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
        .connectLaunchPrompts()
        .onChange(of: scenePhase) { _, newPhase in
            // Throttled full cycle (≥6h since last success). No background sync (#32).
            if newPhase == .active {
                dependencies.syncCoordinator.syncOnForeground()
            }
        }
    }
}

#Preview {
    GymPerformanceTabView()
}
