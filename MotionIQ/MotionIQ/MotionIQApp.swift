import SwiftUI

@main
struct MotionIQApp: App {

    private let persistence = PersistenceController.shared

    init() {
        KeychainHelper.save(apiKey: "REMOVED")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
    }
}
