import CoreData
import SwiftUI

/// Displays the full breakdown of a single past workout session.
///
/// Shows date, total time, form score, per-set table, and the persisted
/// `coachingSummary` Claude paragraph (never re-calls Claude — displays
/// whatever was saved at session end, or a placeholder if nil).
///
/// A delete action removes the `WorkoutSessionEntity` (cascade deletes
/// all child `ExerciseSetEntity` and `RepEntity` records automatically).
struct WorkoutDetailView: View {

    let session: WorkoutSessionEntity

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false

    // MARK: - Computed

    private var orderedSets: [ExerciseSetEntity] {
        let raw = session.sets?.allObjects as? [ExerciseSetEntity] ?? []
        return raw.sorted { $0.duration > $1.duration }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        sessionHeader
                            .padding(.top, 20)
                            .padding(.horizontal, 20)

                        setsSection
                            .padding(.top, 24)
                            .padding(.horizontal, 20)

                        coachingSection
                            .padding(.top, 24)
                            .padding(.horizontal, 20)

                        deleteButton
                            .padding(.top, 32)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 48)
                    }
                }
            }
            .navigationTitle((session.date ?? Date())
                .formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .preferredColorScheme(.dark)
            .confirmationDialog("Delete this workout?",
                                isPresented: $showDeleteConfirmation,
                                titleVisibility: .visible) {
                Button("Delete Workout", role: .destructive) { deleteSession() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove the session and all its sets.")
            }
        }
    }

    // MARK: - Session header

    private var sessionHeader: some View {
        HStack(spacing: 12) {
            summaryTile(value: formatTime(session.duration), label: "DURATION")
            summaryTile(value: "\(orderedSets.count)",
                        label: "SET\(orderedSets.count == 1 ? "" : "S")")
            summaryTile(value: String(format: "%.0f%%", session.overallFormScore * 100),
                        label: "FORM",
                        valueColor: formColor(session.overallFormScore))
        }
    }

    private func summaryTile(value: String, label: String,
                             valueColor: Color = .white) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Sets section

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SETS")

            if orderedSets.isEmpty {
                Text("No sets recorded.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(orderedSets.enumerated()), id: \.offset) { index, set in
                        setRow(index: index + 1, set: set)
                    }
                }
            }
        }
    }

    private func setRow(index: Int, set: ExerciseSetEntity) -> some View {
        let exercise = Exercise(rawValue: set.exercise ?? "")

        return HStack(spacing: 10) {
            Text("\(index)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20)

            Text(exercise?.displayName ?? (set.exercise ?? "—").capitalized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Text("\(set.repCount) reps")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 54, alignment: .trailing)

            Text(formatTime(set.duration))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 36, alignment: .trailing)

            Circle()
                .fill(formColor(set.formScore))
                .frame(width: 7, height: 7)

            Text(String(format: "%.0f%%", set.formScore * 100))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Coaching section

    private var coachingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("COACHING")

            Text(session.coachingSummary ?? "No coaching summary available for this session.")
                .font(.body)
                .foregroundStyle(session.coachingSummary != nil
                                 ? .white.opacity(0.9) : .white.opacity(0.35))
                .italic(session.coachingSummary == nil)
                .lineSpacing(4)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button { showDeleteConfirmation = true } label: {
            Label("Delete Workout", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func deleteSession() {
        context.delete(session)
        try? context.save()
        dismiss()
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.4))
            .tracking(2)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formColor(_ score: Double) -> Color {
        if score >= Constants.formScoreGreen  { return .green }
        if score >= Constants.formScoreYellow { return .yellow }
        return .red
    }
}
