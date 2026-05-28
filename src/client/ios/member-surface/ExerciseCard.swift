import SwiftUI

struct ExerciseCard: View {
    @Binding var draft: DraftExercise
    let currentPB: PersonalBestModel?
    let onRemove: () -> Void

    private let maxSets = 3

    var body: some View {
        VStack(alignment: .leading, spacing: .cardSpacing) {
            HStack {
                Text(draft.exercise.name)
                    .exerciseTitleStyle()
                Spacer()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Text(currentPBText)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(currentPB == nil ? Color.secondary : Color.wolfBlue)

            ForEach(Array(draft.sets.enumerated()), id: \.offset) { index, _ in
                if index > 0 {
                    Divider()
                        .overlay(Color.primary.opacity(0.06))
                }

                HStack(spacing: 8) {
                    Text("Set \(index + 1)")
                        .captionLabelStyle()
                        .frame(width: 44, alignment: .leading)

                    SetInputRow(value: $draft.sets[index], exercise: draft.exercise)
                }
            }

            if draft.sets.count < maxSets {
                Button {
                    draft.sets.append(SetDraftValue.initial(for: draft.exercise))
                } label: {
                    Label("Add set", systemImage: "plus")
                        .font(.system(.subheadline, design: .rounded))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.wolfBlue)
            }
        }
        .padding(.cardPadding)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: .cardRadius, style: .continuous))
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
            .inputValueStyle()
            .inputFieldSurface()
            .selectAllOnFocus()
            Text("kg").captionLabelStyle()
        }
    }

    @ViewBuilder
    private var repsField: some View {
        if let fixedReps {
            HStack(spacing: 4) {
                Text("\(fixedReps)")
                    .inputValueStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .inputFieldSurface()
                Text("reps").captionLabelStyle()
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
                .inputValueStyle()
                .inputFieldSurface()
                .selectAllOnFocus()
                Text("reps").captionLabelStyle()
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
            .inputValueStyle()
            .inputFieldSurface()
            .selectAllOnFocus()
            Text("m").captionLabelStyle()
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
        .inputValueStyle()
        .inputFieldSurface()
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
            .inputValueStyle()
            .inputFieldSurface()
            .selectAllOnFocus()
            Text("s").captionLabelStyle()
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
            .inputValueStyle()
            .inputFieldSurface()
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
            .inputValueStyle()
            .inputFieldSurface()
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
