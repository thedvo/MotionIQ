import CoreData

/// Owns the CoreData stack. Access via PersistenceController.shared.
///
/// IMPORTANT — before building, create the CoreData model in Xcode:
///   File → New → File → Data Model → name it "MotionIQ"
///   Add entities exactly as below, then build once so NSManagedObject subclasses generate.
///
/// Entities & attributes:
///
///   WorkoutSessionEntity
///     id               UUID     (required)
///     date             Date     (required)
///     duration         Double   (required)
///     overallFormScore Double   (required)
///     coachingSummary  String   (optional)  ← nil until Phase 3 Claude call
///     → sets           [ExerciseSetEntity]  (to-many, cascade delete, inverse: session)
///
///   ExerciseSetEntity
///     id               UUID     (required)
///     exercise         String   (required)   ← Exercise.rawValue
///     repCount         Int32    (required)
///     duration         Double   (required)
///     restDuration     Double   (required)
///     formScore        Double   (required)
///     flaggedReps      Int32    (required)
///     → session        WorkoutSessionEntity (to-one, nullify, inverse: sets)
///     → reps           [RepEntity]          (to-many, cascade delete, inverse: set)
///
///   RepEntity
///     id               UUID     (required)
///     formScore        Double   (required)
///     flaggedJoints    String   (required)   ← comma-separated FormFlag rawValues
///     timestamp        Date     (required)
///     → set            ExerciseSetEntity    (to-one, nullify, inverse: reps)
///
/// Relationship delete rules: Session → Sets and Set → Reps both use Cascade.
struct PersistenceController {

    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    /// viewContext is the main-thread context for all reads and writes.
    var viewContext: NSManagedObjectContext { container.viewContext }

    private init() {
        container = NSPersistentCloudKitContainer(name: "MotionIQ")

        // CloudKit sync will activate once the iCloud capability is added in Phase 3.
        // The container is configured now so the schema doesn't need migration later.

        container.loadPersistentStores { _, error in
            if let error {
                // In production this would be handled gracefully;
                // during development a crash surfaces the problem immediately.
                fatalError("CoreData store failed to load: \(error)")
            }
        }

        // Automatically merge changes from CloudKit into the view context (Phase 3)
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Save the view context. No-op if there are no pending changes.
    func save() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // Surface save errors loudly during development
            assertionFailure("CoreData save failed: \(error)")
        }
    }
}
