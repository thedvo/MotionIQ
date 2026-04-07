import SwiftUI

/// Root view. Tab 1 is the live workout camera; Tab 2 is workout history.
///
/// The camera tab is always loaded so AVCaptureSession initialises once —
/// switching to History stops the camera via WorkoutView.onDisappear and
/// restarts it on return via onAppear.
struct ContentView: View {
    var body: some View {
        TabView {
            WorkoutView()
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }

            WorkoutHistoryView()
                .tabItem {
                    Label("History", systemImage: "calendar")
                }
        }
        .tint(.green)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
