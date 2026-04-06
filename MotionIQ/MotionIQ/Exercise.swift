/// The three exercises supported at launch.
/// Defined as a top-level shared type so FormScorer, ExerciseClassifier,
/// WorkoutStateMachine, and CoreData can all reference it without importing RepCounter.
enum Exercise: String, CaseIterable {
    case squat
    case pushup
    case lunge

    var displayName: String {
        switch self {
        case .squat:  "Squat"
        case .pushup: "Pushup"
        case .lunge:  "Lunge"
        }
    }
}
