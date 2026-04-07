import CoreData
import SwiftUI

/// Monthly calendar view showing days that have completed workout sessions.
/// Tapping a day navigates to `WorkoutDetailView` for that session.
///
/// Uses `@FetchRequest` so the list re-renders automatically whenever
/// CoreData is updated (e.g. after CloudKit sync delivers a new session).
struct WorkoutHistoryView: View {

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\WorkoutSessionEntity.date, order: .reverse)],
        animation: .default
    )
    private var sessions: FetchedResults<WorkoutSessionEntity>

    @State private var displayedMonth: Date = {
        let cal = Calendar.current
        let now = Date()
        return cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
    }()

    @State private var selectedSession: WorkoutSessionEntity?

    private let calendar = Calendar.current
    private let columns  = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if sessions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            monthNavigator
                                .padding(.horizontal, 20)

                            weekdayHeader
                                .padding(.horizontal, 20)

                            calendarGrid
                                .padding(.horizontal, 20)

                            Divider()
                                .background(.white.opacity(0.1))
                                .padding(.horizontal, 20)

                            sessionList
                                .padding(.horizontal, 20)
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .sheet(item: $selectedSession) { session in
                WorkoutDetailView(session: session)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))
            Text("No workouts yet")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.5))
            Text("Complete a workout to see it here.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Month navigator

    private var monthNavigator: some View {
        HStack {
            Button { shiftMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.white.opacity(0.1), in: Circle())
            }

            Spacer()

            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .animation(nil, value: displayedMonth)

            Spacer()

            Button { shiftMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canAdvanceMonth ? .white : .white.opacity(0.3))
                    .padding(8)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .disabled(!canAdvanceMonth)
        }
    }

    private var canAdvanceMonth: Bool {
        let current = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        return displayedMonth < current
    }

    // MARK: - Weekday header

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                Text(day)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Calendar grid

    private var calendarGrid: some View {
        let days = daysInMonth()
        let workoutDates = workoutDaySet()

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<firstWeekdayOffset(), id: \.self) { _ in
                Color.clear.frame(height: 40)
            }

            ForEach(days, id: \.self) { date in
                let hasWorkout = workoutDates.contains(dayKey(for: date))
                let session    = sessionsOnDay(date).first
                let isToday    = calendar.isDateInToday(date)

                Button {
                    if let s = session { selectedSession = s }
                } label: {
                    ZStack {
                        Circle()
                            .fill(hasWorkout ? .green.opacity(0.25) : .clear)
                            .overlay(
                                Circle().strokeBorder(
                                    isToday ? .white.opacity(0.5) : .clear,
                                    lineWidth: 1.5)
                            )

                        VStack(spacing: 2) {
                            Text("\(calendar.component(.day, from: date))")
                                .font(.system(size: 14, weight: isToday ? .bold : .regular))
                                .foregroundStyle(hasWorkout ? .white : .white.opacity(0.5))

                            if hasWorkout {
                                Circle().fill(Color.green).frame(width: 4, height: 4)
                            }
                        }
                    }
                    .frame(height: 44)
                }
                .disabled(session == nil)
            }
        }
    }

    // MARK: - Session list (current month)

    private var sessionList: some View {
        let monthSessions = sessionsInDisplayedMonth()
        return Group {
            if monthSessions.isEmpty {
                Text("No workouts this month")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(monthSessions) { session in
                        sessionRow(session)
                            .onTapGesture { selectedSession = session }
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: WorkoutSessionEntity) -> some View {
        let date  = session.date ?? Date()
        let dur   = session.duration
        let score = session.overallFormScore
        let sets  = session.sets?.count ?? 0

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.weekday(.wide).month().day())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(sets) set\(sets == 1 ? "" : "s") · \(formatTime(dur))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Circle()
                .fill(formColor(score))
                .frame(width: 8, height: 8)
            Text(String(format: "%.0f%%", score * 100))
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))

            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Calendar helpers

    private func daysInMonth() -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let first = calendar.date(from: calendar.dateComponents([.year, .month],
                                                                       from: displayedMonth))
        else { return [] }
        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: first)
        }
    }

    private func firstWeekdayOffset() -> Int {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month],
                                                                       from: displayedMonth))
        else { return 0 }
        return (calendar.component(.weekday, from: first) - 1 + 7) % 7
    }

    private func workoutDaySet() -> Set<String> {
        Set(sessions.compactMap { s -> String? in
            guard let date = s.date else { return nil }
            return dayKey(for: date)
        })
    }

    private func sessionsOnDay(_ date: Date) -> [WorkoutSessionEntity] {
        let key = dayKey(for: date)
        return sessions.filter { s in
            guard let d = s.date else { return false }
            return dayKey(for: d) == key
        }
    }

    private func sessionsInDisplayedMonth() -> [WorkoutSessionEntity] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        return sessions.filter { s in
            guard let d = s.date else { return false }
            return interval.contains(d)
        }
    }

    private func dayKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func shiftMonth(by value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth)
            ?? displayedMonth
    }

    // MARK: - Helpers

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
