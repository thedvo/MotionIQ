import SwiftUI

/// Main workout screen: camera feed + skeleton overlay + rep counter.
/// Phase 1: squat detection only, no state machine, no session logging.
struct WorkoutView: View {

    // @State ensures WorkoutViewModel (and its camera session) persists across re-renders.
    @State private var viewModel = WorkoutViewModel()

    var body: some View {
        ZStack {
            // Layer 1: Live camera feed (fills screen)
            CameraPreviewView(session: viewModel.cameraProvider.captureSession)
                .ignoresSafeArea()

            // Layer 2: Skeleton overlay — confirms Vision is detecting the body correctly
            SkeletonOverlayView(pose: viewModel.currentPose)
                .ignoresSafeArea()

            // Layer 3: Rep count HUD
            VStack {
                Spacer()
                repCountHUD
                    .padding(.bottom, 60)
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private var repCountHUD: some View {
        VStack(spacing: 6) {
            Text("\(viewModel.repCount)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text("REPS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.7))
                .tracking(4)

            Text(viewModel.currentPhase.displayName)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .animation(.easeInOut, value: viewModel.currentPhase)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
