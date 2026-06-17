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

    private var defaultReps: Int? {
        exercise.targetReps
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
            guard let defaultReps, value.reps == nil else { return }
            updateValue { $0.reps = defaultReps }
        }
    }

    private func updateValue(_ transform: (inout SetDraftValue) -> Void) {
        var updated = value
        transform(&updated)
        value = updated
    }

    private func optionalBinding<T>(_ keyPath: WritableKeyPath<SetDraftValue, T?>) -> Binding<T?> {
        Binding(
            get: { value[keyPath: keyPath] },
            set: { newValue in
                updateValue { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var weightField: some View {
        HStack(spacing: 4) {
            TextField("kg", value: optionalBinding(\.weight), format: .number)
            .keyboardType(.decimalPad)
            .inputValueStyle()
            .inputFieldSurface()
            .selectAllOnFocus()
            Text("kg").captionLabelStyle()
        }
    }

    @ViewBuilder
    private var repsField: some View {
        HStack(spacing: 4) {
            TextField("reps", value: optionalBinding(\.reps), format: .number)
            .keyboardType(.numberPad)
            .inputValueStyle()
            .inputFieldSurface()
            .selectAllOnFocus()
            Text("reps").captionLabelStyle()
        }
    }

    private var distanceField: some View {
        HStack(spacing: 4) {
            TextField("m", value: optionalBinding(\.distance), format: .number)
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
                get: { value.weight.map { Int($0) } },
                set: { newValue in
                    updateValue { $0.weight = newValue.map(Double.init) }
                }
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
            TextField("sec", value: optionalBinding(\.timeSeconds), format: .number)
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
                    get: { value.timeSeconds.map { $0 / 60 } },
                    set: { minutes in
                        updateValue {
                            let seconds = ($0.timeSeconds ?? 0) % 60
                            $0.timeSeconds = (minutes ?? 0) * 60 + seconds
                        }
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
                    get: { value.timeSeconds.map { $0 % 60 } },
                    set: { seconds in
                        updateValue {
                            let minutes = ($0.timeSeconds ?? 0) / 60
                            $0.timeSeconds = minutes * 60 + (seconds ?? 0)
                        }
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
