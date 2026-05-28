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
                                    .exerciseTitleStyle()
                                    .foregroundStyle(isAdded ? .secondary : .primary)
                                Spacer()
                                if isAdded {
                                    Text("Added").captionLabelStyle()
                                } else if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.wolfBlue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.cardPadding)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: .cardRadius, style: .continuous))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !isAdded else { return }
                                if isSelected {
                                    selected.remove(exercise.id)
                                } else {
                                    selected.insert(exercise.id)
                                }
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.wolfBlue)
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
                    .primaryButtonStyle(isEnabled: !selected.isEmpty)
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
