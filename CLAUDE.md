# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Form Coach** — iOS fitness app using computer vision to detect exercises, count reps, score form, and deliver AI coaching via Claude Haiku 4.5. All detection/counting/scoring is on-device; Claude handles language only.

**Stack:** Swift, SwiftUI, Vision framework (`VNDetectHumanBodyPoseRequest`), CoreData, CloudKit, Claude Haiku 4.5 API
**Min iOS:** 26.2 (Xcode 26 beta naming — iOS 19 release track; supersedes spec's "14+" figure) | **Bundle ID:** `com.danvo.MotionIQ` | **Swift:** 5.0

No `@available` guards are needed for any API used in this project (Vision, AVFoundation, SwiftUI, CoreData, CloudKit).

## Editors & Workflow

**VSCode** — primary editor for writing Swift code (with the Swift extension).
**Xcode** — used for: creating the project, managing the `.xcodeproj`, configuring entitlements/capabilities (CloudKit, camera permissions), running the Simulator, and submitting to TestFlight.

Typical workflow:
- Write/edit Swift files in VSCode
- Switch to Xcode to build, run the Simulator, or configure project settings
- Use Xcode's Simulator for live testing (camera input can be mocked via `AVCaptureSession` device substitution in tests)
 
## Build & Run

The Xcode project is at `MotionIQ/MotionIQ.xcodeproj`. Open `MotionIQ/` in VSCode as the workspace root.

```bash
# Build
xcodebuild -scheme MotionIQ -destination 'platform=iOS Simulator,name=iPhone 16'

# Run unit tests
xcodebuild test -scheme MotionIQ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MotionIQTests

# Run UI tests
xcodebuild test -scheme MotionIQ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MotionIQUITests
```

**In Xcode:** Open `MotionIQ/MotionIQ.xcodeproj` → Product → Run (`⌘R`) / Test (`⌘U`).

**VSCode setup:** Install the [Swift extension](https://marketplace.visualstudio.com/items?itemName=sswg.swift-lang) for SourceKit-LSP autocomplete and diagnostics. Build once in Xcode first so SourceKit-LSP can resolve symbols.

### Project Structure
```
MotionIQ/
├── MotionIQ.xcodeproj/
├── MotionIQ/               # App source (add all new Swift files here)
│   ├── MotionIQApp.swift   # @main entry point
│   ├── ContentView.swift   # Initial placeholder
│   └── Assets.xcassets/
├── MotionIQTests/          # Unit tests (XCTest)
└── MotionIQUITests/        # UI tests (XCUITest)
```

**Info.plist** is auto-generated (`GENERATE_INFOPLIST_FILE = YES`) — add custom keys via Xcode's build settings, not a manual plist file.

**Capabilities — setup order** (Signing & Capabilities tab). Because `GENERATE_INFOPLIST_FILE = YES`, there is no `Info.plist` file to edit — all `NS*UsageDescription` keys must be added via Xcode → Target → Build Settings → Custom iOS Target Properties.

| Phase | Action | Note |
|---|---|---|
| Phase 1 | Add `Privacy - Camera Usage Description` key in Build Settings | Required before any `AVCaptureSession` runs |
| Phase 2 | No new capabilities | CoreData works without entitlements; CloudKit sync not yet active |
| Phase 3 | + Capability → iCloud → check CloudKit | Creates entitlements file; default container `iCloud.com.danvo.MotionIQ` |
| Phase 4 (stretch) | + Capability → HealthKit | Adds `NSHealthShareUsageDescription` stub |

## Architecture

### Real-Time Processing Pipeline
Runs on a background `DispatchQueue` at ~30fps — **never on the main thread** (Vision requests block UI):

```
Camera frame (AVCaptureSession)
  → VNDetectHumanBodyPoseRequest
  → Joint coordinate extraction
  → Angle calculations
  → Exercise classifier (rule-based)
  → Rep counter
  → Form scorer
  → UI update (DispatchQueue.main.async)
```

### State Machine
```
idle → detecting → inSet → resting → inSet → ... → sessionEnd
```

- `idle → detecting`: Joints detected above confidence threshold
- `detecting → inSet`: Movement signature matched to known exercise
- `inSet → resting`: No movement for 3–5s (debounce timer)
- `resting → inSet`: Movement resumes, user taps "Next Set", or raises one hand >2s
- `any → sessionEnd`: Both-hands gesture / End button / 60s inactivity

### Claude Integration — Exactly 2 Calls Per Session
Claude is called **after** detection, not during. It converts structured pose data to coaching language:

1. **Post-set** (during rest): ~200 token input → 1–2 sentence micro-feedback
2. **End-of-session** (summary screen): ~400 token input → 3–5 sentence coaching paragraph

Claude does **not** handle: rep counting, exercise detection, form scoring, rest/set timing, or gesture detection.

Model: `claude-haiku-4-5-20251001` — cost ~$0.004/session.

### CoreData Schema
```
WorkoutSession → [ExerciseSet] → [Rep]
```
Use `ExerciseSet` not `Set` — `Set` conflicts with Swift's standard library.

### Gesture Detection
Wrist joint Y vs. shoulder Y coordinates each frame:
- One hand raised >2s → next set
- Both hands raised >2s → end workout confirmation

## Algorithmic Constants

Define all thresholds as `let` constants in a single `Constants.swift` file so they can be tuned without hunting through logic files.

### Joint Confidence Threshold
```swift
let jointConfidenceThreshold: Float = 0.6
```
`VNRecognizedPoint.confidence` ranges 0.0–1.0. If any key joint for a given calculation is below 0.6, **skip that frame entirely** — do not interpolate missing joints.

### Angle Calculation Utility
All angles are computed via the dot product of two vectors meeting at a joint vertex:
```swift
func angle(a: CGPoint, vertex: CGPoint, b: CGPoint) -> Double {
    let v1 = CGVector(dx: a.x - vertex.x, dy: a.y - vertex.y)
    let v2 = CGVector(dx: b.x - vertex.x, dy: b.y - vertex.y)
    let dot = v1.dx * v2.dx + v1.dy * v2.dy
    let mag = sqrt(v1.dx*v1.dx + v1.dy*v1.dy) * sqrt(v2.dx*v2.dx + v2.dy*v2.dy)
    return acos(max(-1, min(1, dot / mag))) * 180 / .pi
}
```
**Vision Y-axis is flipped** (0.0 = bottom of screen, 1.0 = top). "Hip below knee" means `hip.y < knee.y` in Vision coordinates.

### Rep Phase State Machine
A rep completes when the state cycles: `standing → descending → bottom → ascending → standing`.
Use ±10° hysteresis on all thresholds to prevent jitter at phase boundaries.

| Exercise | Joint measured | Standing threshold | Bottom threshold | Hysteresis |
|---|---|---|---|---|
| Squat | Knee angle | > 155° | < 100° | ±10° |
| Pushup | Elbow angle | > 150° | < 100° | ±10° |
| Lunge | Front knee angle | > 155° | < 105° | ±10° |

Example (squat):
```
kneeAngle > 155° AND phase == .ascending  → phase = .standing  → repCount++
kneeAngle < 155° AND phase == .standing   → phase = .descending
kneeAngle < 100° AND phase == .descending → phase = .bottom
kneeAngle > 100° AND phase == .bottom     → phase = .ascending
```

### Form Scoring Scale
Scores are `Double` 0.0–1.0 throughout; color mapping happens only at the display layer.

**Aggregation:**
- `frameScore` = mean of all check scores for that frame (1.0 = pass, 0.5 = partial, 0.0 = fail)
- `repScore` = mean of frameScores during the descending→ascending window
- `setFormScore` = mean of repScores; `sessionScore` = repCount-weighted mean of setFormScores

**UI thresholds:** ≥ 0.80 = green | 0.60–0.79 = yellow | < 0.60 = red

**Per-exercise form checks:**

Squat (side profile):
| Check | Ideal (1.0) | Partial (0.5) | Fail (0.0) |
|---|---|---|---|
| Knee angle at bottom | 85–95° | 96–110° or 75–84° | > 110° or < 75° |
| Hip below knee at bottom | `hip.y < knee.y` | — | `hip.y ≥ knee.y` |
| Back lean (hip–shoulder vs. vertical) | < 30° | 30–45° | > 45° |

Pushup (side profile):
| Check | Ideal (1.0) | Partial (0.5) | Fail (0.0) |
|---|---|---|---|
| Elbow angle at bottom | 85–95° | 96–110° or 75–84° | > 110° or < 75° |
| Hip alignment (shoulder–hip–ankle) | 170–180° | 160–169° | < 160° |
| Wrist under shoulder | wristX within ±10% of shoulderX | ±10–20% | > 20% |

Lunge (front or side):
| Check | Ideal (1.0) | Partial (0.5) | Fail (0.0) |
|---|---|---|---|
| Front knee angle at bottom | 85–100° | 101–115° | > 115° |
| Front knee tracking over foot | kneeX within ±15% of ankleX | ±15–25% | > 25% |
| Torso upright (shoulder–hip vs. vertical) | < 10° | 10–20° | > 20° |

"% of frame" = fraction of Vision's normalized 0.0–1.0 coordinate space.

### Rest Detection
Velocity-based using the hip joint (most stable landmark). More robust than position-based checks, which false-trigger on natural postural sway.
```swift
let restVelocityThreshold: Double = 0.005  // normalized units/frame
let restFrameWindow: Int = 90              // ~3s at 30fps — use 3s, not the spec's 3–5s range
let inactivityTimeout: TimeInterval = 60
```
Each frame, compute Euclidean distance the hip joint moved from the previous frame. Maintain a rolling 90-frame buffer. If the mean < `restVelocityThreshold` → fire rest state transition. Fall back to shoulder joint if hip confidence < threshold.

### Gesture Detection
```swift
let gestureHoldDuration: TimeInterval = 2.0
let gestureOffset: Double = 0.05          // wrist must be 5% of frame height above shoulder
```
Condition: `wristY > shoulderY + gestureOffset` (Vision Y is flipped — higher Y = higher on screen, so this is correct).
Reset the hold timer on **any single frame** below threshold — no grace frames. This prevents accidental triggers from brief arm raises.
One wrist satisfies → next set. Both wrists simultaneously → end workout confirmation.

### Exercise Auto-Classifier
Evaluate in this order to avoid misclassification. Lock classification after 3 consecutive matching frames; do not re-classify mid-set.

1. **Pushup** — both wrists below hip Y AND user roughly horizontal (hip–shoulder angle < 30° from horizontal)
2. **Squat** — hip Y cycling below knee Y AND user vertical (hip–shoulder angle > 60° from horizontal)
3. **Lunge** — asymmetric knees: one knee angle < 120°, contralateral > 140°, user vertical

### Key Architecture Decision: `PoseProviding` Protocol
Define this protocol **before** implementing the camera layer. `WorkoutViewModel` depends on `PoseProviding`, not `AVCaptureSession` directly. This is the single most important decision for testability — without it the entire exercise pipeline requires a physical camera to test.

```swift
protocol PoseProviding {
    var posePublisher: AnyPublisher<VNHumanBodyPoseObservation?, Never> { get }
}
// LiveCameraProvider: PoseProviding  (real camera)
// MockPoseProvider: PoseProviding    (scripted joint sequences for tests)
```

## Launch Exercise Library
3 exercises at launch — all using `VNHumanBodyPoseObservation` joint landmarks:
- **Squat** (side profile): knee ~90°, hip below knee
- **Pushup** (side profile): elbow ~90°, hip flat
- **Lunge** (front or side): front knee ~90°, torso upright

## Claude API — Swift Implementation

No official Swift SDK for Claude exists. Use `URLSession` with `async/await`.

### HTTP Client
```swift
struct ClaudeAPIClient {
    private let apiKey: String  // load from Keychain — never UserDefaults or source code
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func send(prompt: String, systemPrompt: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 256,
            "system": [["type": "text", "text": systemPrompt,
                        "cache_control": ["type": "ephemeral"]]],  // prompt caching
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ClaudeError.httpError }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let text = (json?["content"] as? [[String: Any]])?.first?["text"] as? String
        else { throw ClaudeError.parseError }
        return text
    }
}
```

### Call Site — Fire and Forget with Graceful Degradation
```swift
// Called when state transitions to .resting
func onSetEnded(_ set: ExerciseSet) {
    Task {
        do {
            let feedback = try await claudeClient.send(prompt: buildPostSetPrompt(set),
                                                       systemPrompt: systemPrompt)
            await MainActor.run { self.currentFeedback = feedback }
        } catch {
            await MainActor.run { self.currentFeedback = fallbackCue(for: set.exercise) }
        }
    }
}
```
The workout continues whether or not the API call succeeds.

### Error Handling
| Error | Behavior |
|---|---|
| Network unavailable | Show fallback cue immediately |
| HTTP 429 | Wait 5s, retry once; then fallback |
| HTTP 5xx | Fallback, log to console |
| Timeout (> 10s) | Cancel `Task`, show fallback |

**Fallback cues** (hardcoded, one per exercise):
- Squat: `"Focus on depth and keeping your chest up."`
- Pushup: `"Keep hips level and elbows at 45° from your body."`
- Lunge: `"Drive through your front heel and keep your torso upright."`

**API key storage:** Keychain only — use `Security.framework` (`SecItemAdd` / `SecItemCopyMatching`). Never `UserDefaults`, plist, or hardcoded in source.

## Known Gotchas
- Always run Vision requests on a background `DispatchQueue`, never main thread — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set, so Vision processing must be explicitly dispatched off-main
- Use `ExerciseSet` not `Set` in CoreData model — `Set` conflicts with Swift's standard library
- Joint confidence scores degrade with baggy clothing or partial visibility — surface confidence to the user
- Silhouette overlay is critical for keeping user centered in frame
- No external SPM dependencies yet — add via Xcode's File → Add Package Dependencies

## Testing Strategy

### What to Unit Test (`MotionIQTests`)
Vision and camera types cannot be tested in XCTest without a physical device. Test the pure functions that process pose data instead.

| Layer | What to test | Approach |
|---|---|---|
| Angle calculation | `angle(a:vertex:b:)` | Hardcoded `CGPoint` inputs with known expected angles (90°, 180°, 45°) |
| Rep phase state machine | Phase transitions | Feed synthetic angle sequences; assert phase changes fire at correct thresholds with hysteresis |
| Form scorer | Score output | Hardcoded joint positions; assert score falls in expected band |
| Rest detector | Triggers after N frames below threshold | Synthetic per-frame hip position arrays |
| Exercise classifier | Correct exercise identified | Hardcoded joint signatures for each exercise |
| Claude prompt builder | Prompt contains expected values | Assert on string content — no network call |
| `ClaudeAPIClient` | HTTP layer | Mock `URLSession` via `URLProtocol` subclass; test success, 429 retry, 5xx fallback |

**Key rule:** all testable units accept `CGPoint`/`Double` inputs — no Vision or AVFoundation types in function signatures. Wrap `VNHumanBodyPoseObservation` output in plain structs (e.g., `PoseData`) before passing downstream.

### What NOT to Unit Test
`AVCaptureSession` setup, `VNDetectHumanBodyPoseRequest` output, SwiftUI view layout — test these manually.

### UI Tests (`MotionIQUITests`)
Inject a `MockPoseProvider: PoseProviding` that emits scripted joint sequences to drive the state machine without a camera.

| Scenario | How |
|---|---|
| Rep counted → rest detected | Emit squat angle cycle sequence; assert rep count label updates |
| Gesture → next set | Emit wrist-above-shoulder for 2s; assert state transitions |
| Claude feedback during rest | Mock `ClaudeAPIClient` returning fixture string; assert feedback label |
| Session end → summary screen | Drive state to `sessionEnd`; assert navigation |

### Simulator Limitation
The iOS Simulator has no physical camera — the full AVCapture pipeline must be tested on a real device. Development team ID `Q2F77VA8PD` is already configured in the project.
