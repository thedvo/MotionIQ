import SwiftUI

/// Full-screen post-workout summary shown after the user ends a session.
///
/// Data flow:
/// - Reads completed set data and session duration from `WorkoutViewModel`
///   (already in memory — no CoreData fetch needed here).
/// - `claudeSessionFeedback` / `isLoadingSessionFeedback` are set async by
///   `WorkoutViewModel.handleSessionEnd()` which fired before this screen appeared.
/// - Dismiss triggers `WorkoutView.onDismiss` which resets the ViewModel.
struct SessionSummaryView: View {

    let viewModel: WorkoutViewModel

    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed

    private var sets: [CompletedSet] { viewModel.completedSets }

    private var totalReps: Int { sets.map(\.repCount).reduce(0, +) }

    private var overallFormScore: Double {
        guard !sets.isEmpty else { return 0 }
        return sets.map(\.averageFormScore).reduce(0, +) / Double(sets.count)
    }

    /// Per-exercise summary: exercise → (setCount, totalReps, avgFormScore)
    private var exerciseSummaries: [(exercise: Exercise, sets: Int, reps: Int, form: Double)] {
        Dictionary(grouping: sets, by: \.exercise).map { exercise, exSets in
            let totalReps = exSets.map(\.repCount).reduce(0, +)
            let avgForm   = exSets.map(\.averageFormScore).reduce(0, +) / Double(exSets.count)
            return (exercise, exSets.count, totalReps, avgForm)
        }.sorted { $0.reps > $1.reps }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 60)
                        .padding(.horizontal, 24)

                    statsRow
                        .padding(.top, 28)
                        .padding(.horizontal, 24)

                    if !viewModel.personalRecords.isEmpty {
                        prSection
                            .padding(.top, 24)
                            .padding(.horizontal, 24)
                    }

                    exerciseBreakdown
                        .padding(.top, 24)
                        .padding(.horizontal, 24)

                    coachingSection
                        .padding(.top, 24)
                        .padding(.horizontal, 24)

                    doneButton
                        .padding(.top, 32)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 48)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Workout Complete")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text(formatTime(viewModel.sessionElapsed))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text("Total time")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(value: "\(sets.count)", label: "SETS")
            statCard(value: "\(totalReps)", label: "REPS")
            statCard(value: String(format: "%.0f%%", overallFormScore * 100),
                     label: "FORM",
                     valueColor: formColor(overallFormScore))
        }
    }

    private func statCard(value: String, label: String,
                          valueColor: Color = .white) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - PR section

    private var prSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PERSONAL RECORDS")

            ForEach(viewModel.personalRecords, id: \.self) { pr in
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.yellow)
                    Text(pr)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Exercise breakdown

    private var exerciseBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("EXERCISES")

            VStack(spacing: 1) {
                ForEach(Array(exerciseSummaries.enumerated()), id: \.offset) { _, summary in
                    HStack {
                        Text(summary.exercise.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Spacer()

                        Text("\(summary.sets) set\(summary.sets == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 48, alignment: .trailing)

                        Text("\(summary.reps) reps")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 54, alignment: .trailing)

                        Circle()
                            .fill(formColor(summary.form))
                            .frame(width: 8, height: 8)
                            .padding(.leading, 8)

                        Text(String(format: "%.0f%%", summary.form * 100))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 32, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Coaching section

    private var coachingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("COACHING")

            Group {
                if viewModel.isLoadingSessionFeedback {
                    loadingPlaceholder
                } else if let feedback = viewModel.claudeSessionFeedback {
                    Text(feedback)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(4)
                        .transition(.opacity)
                } else {
                    Text("No coaching summary available.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.4))
                        .italic()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .animation(.easeInOut(duration: 0.4), value: viewModel.claudeSessionFeedback)
        }
    }

    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.12))
                    .frame(height: 14)
                    .frame(maxWidth: i == 2 ? 180 : .infinity)
            }
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - Done button

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
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
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formColor(_ score: Double) -> Color {
        if score >= Constants.formScoreGreen  { return .green }
        if score >= Constants.formScoreYellow { return .yellow }
        return .red
    }
}
