import CoreData
import Foundation

/// Listens to WorkoutStateMachine events and persists completed sets and sessions to CoreData.
///
/// Wire up by calling attach(to:) after creating the state machine.
/// All CoreData writes happen on the main context — no background context needed at this scale.
final class WorkoutLogger {

    private let persistence: PersistenceController
    private var currentSessionEntity: NSManagedObject?
    private var sessionStartTime: Date?

    /// Retained after the session saves so `updateCoachingSummary(_:)` can
    /// write the async Claude result back to the correct CoreData object.
    private var lastSessionObjectID: NSManagedObjectID?

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    /// Appends the logger's handlers to the state machine's callback arrays.
    /// Uses append (not assignment) so WorkoutViewModel can also subscribe
    /// without overwriting the logger's handlers.
    func attach(to machine: WorkoutStateMachine) {
        machine.onSetCompleted.append { [weak self] set in
            self?.handleSetCompleted(set, machine: machine)
        }
        machine.onSessionEnded.append { [weak self] in
            self?.handleSessionEnded(machine: machine)
        }
    }

    /// Called by WorkoutViewModel after the end-of-session Claude call resolves.
    /// Looks up the saved session by its CoreData object ID and writes the
    /// coaching summary, then saves. No-op if the session was never persisted.
    func updateCoachingSummary(_ text: String) {
        guard let oid = lastSessionObjectID else { return }
        let context = persistence.viewContext
        guard let session = try? context.existingObject(with: oid) else { return }
        session.setValue(text, forKey: "coachingSummary")
        persistence.save()
    }

    // MARK: - Handlers

    private func handleSetCompleted(_ set: CompletedSet, machine: WorkoutStateMachine) {
        let context = persistence.viewContext

        // Create session entity on first set if it doesn't exist yet
        if currentSessionEntity == nil {
            sessionStartTime = machine.sessionStartTime ?? Date()
            let session = NSEntityDescription.insertNewObject(
                forEntityName: "WorkoutSessionEntity", into: context)
            session.setValue(UUID(), forKey: "id")
            session.setValue(sessionStartTime, forKey: "date")
            session.setValue(0.0, forKey: "duration")
            session.setValue(0.0, forKey: "overallFormScore")
            // coachingSummary left nil — Phase 3 fills this in
            currentSessionEntity = session
        }

        // Create ExerciseSetEntity
        let setEntity = NSEntityDescription.insertNewObject(
            forEntityName: "ExerciseSetEntity", into: context)
        setEntity.setValue(UUID(),               forKey: "id")
        setEntity.setValue(set.exercise.rawValue, forKey: "exercise")
        setEntity.setValue(Int32(set.repCount),  forKey: "repCount")
        setEntity.setValue(set.duration,         forKey: "duration")
        setEntity.setValue(0.0,                  forKey: "restDuration")  // updated when rest ends
        setEntity.setValue(set.averageFormScore, forKey: "formScore")
        setEntity.setValue(Int32(0),             forKey: "flaggedReps")
        setEntity.setValue(currentSessionEntity, forKey: "session")

        persistence.save()
    }

    private func handleSessionEnded(machine: WorkoutStateMachine) {
        guard let sessionEntity = currentSessionEntity,
              let startTime = sessionStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)
        let overallScore = machine.completedSets.isEmpty ? 0.0 :
            machine.completedSets.map { $0.averageFormScore }.reduce(0, +) /
            Double(machine.completedSets.count)

        sessionEntity.setValue(duration,      forKey: "duration")
        sessionEntity.setValue(overallScore,  forKey: "overallFormScore")

        persistence.save()

        // Retain the object ID so updateCoachingSummary(_:) can find it later
        // after the async Claude end-of-session call resolves.
        lastSessionObjectID = currentSessionEntity?.objectID
        currentSessionEntity = nil
        sessionStartTime = nil
    }
}
