import SwiftUI

struct ExerciseCard: View {
    @Binding var draft: DraftExercise
    let currentPB: PersonalBestModel?
    let onRemove: () -> Void

    private let maxSets = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(draft.exercise.name).font(.headline)
                Spacer()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Text(currentPBText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(draft.sets.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 8) {
                    Text("Set \(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)

                    SetInputRow(value: $draft.sets[index], exercise: draft.exercise)
                }
            }

            if draft.sets.count < maxSets {
                Button {
                    draft.sets.append(SetDraftValue.initial(for: draft.exercise))
                } label: {
                    Label("Add set", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var currentPBText: String {
        if let currentPB {
            return "Current PB: \(PBFormatter.formatPB(currentPB, exercise: draft.exercise))"
        }
        return "No PB yet"
    }
}

struct SetInputRow: View {
    @Binding var value: SetDraftValue
    let exercise: ExerciseModel

    private var isCableRow: Bool {
        exercise.name == "Cable Row"
    }

    private var fixedReps: Int? {
        exercise.pbRule == .heaviestWeightAtReps ? exercise.targetReps : nil
    }

    var body: some View {
        Group {
            switch exercise.measurementType {
            case .weightAndReps:
                if isCableRow {
                    HStack { stackField; repsField }
                } else {
                    HStack { weightField; repsField }
                }
            case .weightAndTime:
                HStack { weightField; rawSecondsField }
            case .timeOnly:
                mmssTimeField
            case .distanceOnly:
                distanceField
            case .repsOnly:
                repsField
            case .weightAndDistance:
                HStack { weightField; distanceField }
            }
        }
        .onAppear {
            if let fixedReps, value.reps == nil {
                value.reps = fixedReps
            }
        }
    }

    private var weightField: some View {
        HStack(spacing: 4) {
            TextField(
                "kg",
                value: Binding(
                    get: { value.weight ?? 0 },
                    set: { value.weight = $0 == 0 ? nil : $0 }
                ),
                format: .number
            )
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .selectAllOnFocus()
            Text("kg").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var repsField: some View {
        if let fixedReps {
            HStack(spacing: 4) {
                Text("\(fixedReps)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
                Text("reps").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                TextField(
                    "reps",
                    value: Binding(
                        get: { value.reps ?? 0 },
                        set: { value.reps = $0 == 0 ? nil : $0 }
                    ),
                    format: .number
                )
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .selectAllOnFocus()
                Text("reps").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var distanceField: some View {
        HStack(spacing: 4) {
            TextField(
                "m",
                value: Binding(
                    get: { value.distance ?? 0 },
                    set: { value.distance = $0 == 0 ? nil : $0 }
                ),
                format: .number
            )
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .selectAllOnFocus()
            Text("m").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var stackField: some View {
        TextField(
            "stack",
            value: Binding(
                get: { Int(value.weight ?? 0) },
                set: { value.weight = $0 == 0 ? nil : Double($0) }
            ),
            format: .number
        )
        .keyboardType(.numberPad)
        .textFieldStyle(.roundedBorder)
        .selectAllOnFocus()
    }

    private var rawSecondsField: some View {
        HStack(spacing: 4) {
            TextField(
                "sec",
                value: Binding(
                    get: { value.timeSeconds ?? 0 },
                    set: { value.timeSeconds = $0 == 0 ? nil : $0 }
                ),
                format: .number
            )
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .selectAllOnFocus()
            Text("s").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var mmssTimeField: some View {
        HStack(spacing: 4) {
            TextField(
                "mm",
                value: Binding(
                    get: { (value.timeSeconds ?? 0) / 60 },
                    set: { minutes in
                        let seconds = (value.timeSeconds ?? 0) % 60
                        value.timeSeconds = minutes * 60 + seconds
                    }
                ),
                format: .number
            )
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 60)
            .selectAllOnFocus()
            Text(":")
            TextField(
                "ss",
                value: Binding(
                    get: { (value.timeSeconds ?? 0) % 60 },
                    set: { seconds in
                        let minutes = (value.timeSeconds ?? 0) / 60
                        value.timeSeconds = minutes * 60 + seconds
                    }
                ),
                format: .number
            )
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 60)
            .selectAllOnFocus()
        }
    }
}

#Preview {
    StatefulPreview()
        .padding()
}

private struct StatefulPreview: View {
    @State var draft = DraftExercise(exercise: ExerciseModel.seedData[0])

    var body: some View {
        ExerciseCard(draft: $draft, currentPB: nil, onRemove: {})
    }
}
