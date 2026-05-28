import SwiftUI

struct ExercisePickerSheet: View {
    let alreadyAddedIds: Set<UUID>
    let onConfirm: ([ExerciseModel]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    @State private var selected: Set<UUID> = []
    @State private var exercises: [ExerciseModel] = []

    var body: some View {
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    ProgressView()
                } else {
                    List {
                        ForEach(exercises, id: \.id) { exercise in
                            let isAdded = alreadyAddedIds.contains(exercise.id)
                            let isSelected = selected.contains(exercise.id)

                            HStack {
                                Text(exercise.name)
                                    .foregroundStyle(isAdded ? .secondary : .primary)
                                Spacer()
                                if isAdded {
                                    Text("Added").font(.caption).foregroundStyle(.secondary)
                                } else if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !isAdded else { return }
                                if isSelected {
                                    selected.remove(exercise.id)
                                } else {
                                    selected.insert(exercise.id)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let chosen = exercises.filter { selected.contains($0.id) }
                    onConfirm(chosen)
                    dismiss()
                } label: {
                    Text(
                        selected.isEmpty
                            ? "Select exercises"
                            : "Add \(selected.count) exercise\(selected.count == 1 ? "" : "s")"
                    )
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .bold()
                }
                .disabled(selected.isEmpty)
                .padding()
            }
            .task {
                await loadExercises()
            }
        }
    }

    @MainActor
    private func loadExercises() async {
        do {
            exercises = try dependencies.exerciseRegistry.pbExercises()
                .sorted { $0.displayOrder < $1.displayOrder }
        } catch {
            exercises = []
        }
    }
}

#Preview {
    ExercisePickerSheet(alreadyAddedIds: []) { _ in }
}
