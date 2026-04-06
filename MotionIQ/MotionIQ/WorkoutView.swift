import SwiftUI

struct WorkoutView: View {

    @State private var viewModel = WorkoutViewModel()
    @State private var showLegend = true

    var body: some View {
        ZStack {
            // Layer 1: Camera feed
            CameraPreviewView(session: viewModel.cameraProvider.captureSession)
                .ignoresSafeArea()

            // Layer 2: Skeleton overlay
            SkeletonOverlayView(pose: viewModel.currentPose)
                .ignoresSafeArea()

            // Layer 3: Top bar — legend toggle + session timer
            VStack(spacing: 0) {
                topBar
                    .padding(.top, 52)
                    .padding(.horizontal, 16)

                if showLegend {
                    legendCard
                        .padding(.top, 8)
                        .padding(.leading, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
            }
            .animation(.easeInOut(duration: 0.2), value: showLegend)

            // Layer 4: Form cue banner
            VStack {
                Spacer().frame(height: showLegend ? 220 : 110)
                if viewModel.workoutState == .inSet, let cue = viewModel.activeCueText {
                    cueBanner(text: cue)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.activeCueText)

            // Layer 5: Set overview (resting only, above bottom HUD)
            if viewModel.workoutState == .resting && !viewModel.completedSets.isEmpty {
                VStack {
                    Spacer()
                    setOverview
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .frame(maxHeight: .infinity)
                .padding(.bottom, 240)
                .animation(.easeInOut(duration: 0.3), value: viewModel.workoutState)
            }

            // Layer 6: Main bottom HUD
            VStack {
                Spacer()
                mainHUD
                    .padding(.bottom, 48)
                    .padding(.horizontal, 16)
            }

            // Layer 7: Pause overlay
            if viewModel.workoutState == .paused {
                pauseOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.workoutState)
        .onAppear  { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            // Legend toggle
            Button {
                showLegend.toggle()
            } label: {
                Image(systemName: showLegend ? "info.circle.fill" : "info.circle")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            // Session timer — only shown once workout is running
            if viewModel.workoutState != .idle {
                VStack(spacing: 1) {
                    Text(formatTime(viewModel.sessionElapsed))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("TOTAL")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            // Set count badge
            if !viewModel.completedSets.isEmpty {
                Text("SET \(viewModel.completedSets.count + (viewModel.workoutState == .inSet ? 1 : 0))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            } else {
                Color.clear.frame(width: 44, height: 36)
            }
        }
    }

    // MARK: - Legend card

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXERCISES")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(2)
            HStack(spacing: 10) {
                ForEach(Exercise.allCases, id: \.self) { ex in
                    Text(ex.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.15), in: Capsule())
                }
            }

            Divider().background(.white.opacity(0.2))

            Text("GESTURES")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(2)
            VStack(alignment: .leading, spacing: 4) {
                gestureRow(icon: "xmark",           label: "Cross arms (hold 2s) → Pause")
                gestureRow(icon: "hand.raised.fill", label: "Both arms up (hold 2s) → Next Set")
                gestureRow(icon: "hand.point.up.fill", label: "Right fist up (hold 2s) → End Workout")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 260)
    }

    private func gestureRow(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Cue banner

    private func cueBanner(text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.red.opacity(0.85), in: Capsule())
    }

    // MARK: - Set overview

    private var setOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SETS SO FAR")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(2)

            ForEach(Array(viewModel.completedSets.enumerated()), id: \.offset) { index, set in
                HStack {
                    Text("Set \(index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 40, alignment: .leading)

                    Text(set.exercise.displayName)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 56, alignment: .leading)

                    Text("\(set.repCount) reps")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 52, alignment: .leading)

                    Text(formatTime(set.duration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, alignment: .leading)

                    Spacer()

                    // Form score dot
                    Circle()
                        .fill(formColor(set.averageFormScore))
                        .frame(width: 8, height: 8)
                    Text(String(format: "%.0f%%", set.averageFormScore * 100))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Main HUD

    @ViewBuilder
    private var mainHUD: some View {
        switch viewModel.workoutState {
        case .idle:
            startHUD
        case .detecting:
            detectingHUD
        case .inSet:
            inSetHUD
        case .resting:
            restingHUD
        case .paused:
            EmptyView()   // pause overlay handles this
        case .sessionEnd:
            sessionEndHUD
        }
    }

    // MARK: - Start HUD (idle)

    private var startHUD: some View {
        hudCard {
            VStack(spacing: 12) {
                Text("Ready to Start")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Step into frame so the skeleton appears, then start.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                controlButton(label: "Start Workout", icon: "play.fill", color: .green.opacity(0.85)) {
                    viewModel.startWorkout()
                }
                Text("Or raise both arms for 2s")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Detecting HUD

    private var detectingHUD: some View {
        hudCard {
            VStack(spacing: 8) {
                Text("Detecting exercise…")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Begin your exercise — squats, pushups, or lunges")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - In-set HUD

    private var inSetHUD: some View {
        hudCard {
            VStack(spacing: 6) {
                if let exercise = viewModel.currentExercise {
                    Text(exercise.displayName.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(3)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(spacing: 2) {
                        Text("\(viewModel.repCount)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("REPS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.7))
                            .tracking(4)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.currentRepPhase.displayName)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                        Text(formatTime(viewModel.setElapsed))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.bottom, 8)
                }

                formScoreBar

                // Physical buttons
                HStack(spacing: 10) {
                    controlButton(label: "Pause", icon: "pause.fill", color: .white.opacity(0.2)) {
                        viewModel.togglePause()
                    }
                    controlButton(label: "Finish Set", icon: "checkmark", color: .blue.opacity(0.7)) {
                        viewModel.startNextSet()
                    }
                    controlButton(label: "End", icon: "stop.fill", color: .red.opacity(0.7)) {
                        viewModel.endWorkout()
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Resting HUD

    private var restingHUD: some View {
        hudCard {
            VStack(spacing: 10) {
                Text("REST")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(4)

                Text(formatTime(viewModel.restElapsed))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                if let last = viewModel.completedSets.last {
                    HStack(spacing: 12) {
                        statPill(value: "\(last.repCount)", label: "REPS")
                        statPill(value: formatTime(last.duration), label: "SET TIME")
                        statPill(value: String(format: "%.0f%%", last.averageFormScore * 100),
                                 label: "FORM",
                                 color: formColor(last.averageFormScore))
                    }
                }

                HStack(spacing: 10) {
                    controlButton(label: "Next Set", icon: "play.fill", color: .green.opacity(0.7)) {
                        viewModel.startNextSet()
                    }
                    controlButton(label: "End", icon: "stop.fill", color: .red.opacity(0.7)) {
                        viewModel.endWorkout()
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Session end HUD

    private var sessionEndHUD: some View {
        hudCard {
            VStack(spacing: 10) {
                Text("Workout Complete")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text(formatTime(viewModel.sessionElapsed))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if !viewModel.completedSets.isEmpty {
                    Divider().background(.white.opacity(0.2))
                    HStack(spacing: 16) {
                        statPill(value: "\(viewModel.completedSets.count)", label: "SETS")
                        statPill(value: "\(viewModel.completedSets.map(\.repCount).reduce(0, +))",
                                 label: "TOTAL REPS")
                        let avgForm = viewModel.completedSets.map(\.averageFormScore).reduce(0, +) /
                            Double(viewModel.completedSets.count)
                        statPill(value: String(format: "%.0f%%", avgForm * 100),
                                 label: "AVG FORM",
                                 color: formColor(avgForm))
                    }
                }
            }
        }
    }

    // MARK: - Pause overlay

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)

                Text("PAUSED")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .tracking(4)

                Text("Cross arms again to resume")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 12) {
                    controlButton(label: "Resume", icon: "play.fill", color: .green.opacity(0.8)) {
                        viewModel.togglePause()
                    }
                    controlButton(label: "End Workout", icon: "stop.fill", color: .red.opacity(0.8)) {
                        viewModel.endWorkout()
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Reusable components

    private var formScoreBar: some View {
        HStack(spacing: 6) {
            Text("FORM")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .tracking(2)
            RoundedRectangle(cornerRadius: 3)
                .fill(viewModel.formScoreColor)
                .frame(width: 60, height: 6)
                .animation(.easeInOut, value: viewModel.formScoreColor.description)
        }
    }

    private func statPill(value: String, label: String, color: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func controlButton(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color, in: Capsule())
        }
    }

    private func hudCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

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

// MARK: - Phase display

private extension RepCounter.Phase {
    var displayName: String {
        switch self {
        case .standing:   "STAND"
        case .descending: "DOWN ↓"
        case .bottom:     "HOLD"
        case .ascending:  "UP ↑"
        }
    }
}
