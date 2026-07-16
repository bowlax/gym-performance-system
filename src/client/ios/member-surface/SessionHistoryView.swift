import SwiftUI

struct SessionHistoryView: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var sessions: [SessionModel] = []
    @State private var sessionHasPB: [UUID: Bool] = [:]
    @State private var sessionExerciseNames: [UUID: String] = [:]
    @State private var sessionPendingDelete: SessionModel?
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sessions, id: \.id) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            row(session)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                sessionPendingDelete = session
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Session History")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete this session? This cannot be undone.", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let sessionPendingDelete {
                    deleteSession(sessionPendingDelete)
                }
            }
            Button("Cancel", role: .cancel) {
                sessionPendingDelete = nil
            }
        }
        .alert("Unable to Delete Session", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .task(id: dependencies.refreshID) {
            await loadSessions()
        }
    }

    private func row(_ session: SessionModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.date, style: .date).font(.headline)
                Spacer()
                if sessionHasPB[session.id] == true {
                    Text("PB")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.pbYellow.opacity(0.25), in: Capsule())
                }
            }
            Text(sessionExerciseNames[session.id] ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: "calendar.badge.clock",
            message: "No sessions logged yet"
        )
    }

    private func deleteSession(_ session: SessionModel) {
        do {
            try dependencies.memberPerformance.deleteSession(
                id: session.id,
                memberId: dependencies.memberId
            )
            sessionPendingDelete = nil
            dependencies.refresh()
        } catch {
            deleteError = error.localizedDescription
            sessionPendingDelete = nil
        }
    }

    @MainActor
    private func loadSessions() async {
        do {
            let fetched = try dependencies.performanceDataAccess.fetchSessions(memberId: dependencies.memberId)
                .sorted { $0.date > $1.date }
            sessions = fetched

            var hasPB: [UUID: Bool] = [:]
            var names: [UUID: String] = [:]

            for session in fetched {
                let entries = try dependencies.performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
                var exerciseNames: [String] = []
                var sessionContainsPB = false

                for entry in entries {
                    guard let exercise = try dependencies.exerciseRegistry.exercise(id: entry.exerciseId) else {
                        continue
                    }
                    exerciseNames.append(exercise.name)

                    let sets = try dependencies.performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
                    let derived = try dependencies.memberPerformance.deriveExerciseReadState(
                        memberId: dependencies.memberId,
                        exerciseId: entry.exerciseId
                    )
                    if sets.contains(where: { derived.badgeIds.contains($0.id.uuidString) }) {
                        sessionContainsPB = true
                    }
                }

                hasPB[session.id] = sessionContainsPB
                names[session.id] = exerciseNames.joined(separator: ", ")
            }

            sessionHasPB = hasPB
            sessionExerciseNames = names
        } catch {
            sessions = []
            sessionHasPB = [:]
            sessionExerciseNames = [:]
        }
    }
}

#Preview {
    NavigationStack { SessionHistoryView() }
}
