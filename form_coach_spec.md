# Form Coach — Project Specification

> Verified against Apple Developer documentation and Anthropic API pricing as of March 2026.

---

## Overview

iOS fitness app that uses the camera to automatically detect exercises, count reps, score form, log sets, and deliver AI coaching — all without the user touching their phone during a workout.

**Stack:** Swift, SwiftUI, Vision framework, CoreData, CloudKit, Claude Haiku 4.5 API
**Min iOS:** 26.2 (Xcode 26 beta / iOS 19 release track)
**Timeline:** 4 weeks
**Deploy:** TestFlight → App Store

---

## How It Works — Full User Flow

### 1. Start Workout
- User taps **Start Workout**
- Setup screen: select camera angle (side profile for squats/pushups, front for lunges)
- App shows a body silhouette overlay — user steps into frame until skeleton aligns
- Once joint confidence threshold is met → **3-second countdown** → workout begins

### 2. During a Set (Real-Time Detection Loop)
Runs on a background `DispatchQueue` at ~30fps:

```
Camera frame → VNDetectHumanBodyPoseRequest → joint coordinates
→ angle calculations → exercise classifier → rep counter → form scorer
→ UI update (rep count, form indicator, cue text)
```

- **Rep counted** when angle cycles: down phase → bottom → up phase = 1 rep
- **Form scored** each frame: angles compared to thresholds → green / yellow / red indicator
- **Cue text** appears if form breaks: *"Go deeper"* / *"Keep back straight"*
- **Exercise auto-detected** from joint movement signature (no manual selection needed)

### 3. End of Set — Rest Period
- User stops moving for **3–5 seconds** → debounce fires → state: `resting`
- Rest timer starts counting up on screen
- **Claude called here** → micro-feedback appears during rest (see Claude section)
- User sees: reps, form score, rest timer, Claude feedback

### 4. Starting Next Set
Three ways to resume:
- **Just move** — classifier detects movement → auto-transitions to `inSet`
- **Tap "Next Set"** button to skip rest early
- **Gesture** — raise one hand above shoulder for 2 seconds → next set starts

### 5. Ending the Workout
Three ways to end:
- **Gesture** — raise both hands above head for 2 seconds → confirmation prompt
- **Button** — persistent "End Workout" button always on screen
- **Inactivity** — 60+ seconds of stillness in rest state → prompt: *"Done for today?"*

### 6. Post-Workout Summary
- Summary screen: total time, exercises, sets, reps, form score, PRs
- **Claude called here** → coaching paragraph appears (see Claude section)
- User can save, share, or dismiss

---

## State Machine

```
idle → detecting → inSet → resting → inSet → ... → sessionEnd
```

| Transition | Trigger |
|---|---|
| `idle → detecting` | Joints detected above confidence threshold |
| `detecting → inSet` | Movement signature matched to known exercise |
| `inSet → resting` | No movement for 3–5s (debounce timer) |
| `resting → inSet` | Movement resumes OR user taps / gestures |
| `any → sessionEnd` | Both-hands gesture / End button / 60s inactivity prompt |

---

## Gesture Controls

| Gesture | Action |
|---|---|
| One hand raised above shoulder, held 2s | Start next set |
| Both hands raised above head, held 2s | End workout (confirmation prompt) |
| Tap "Next Set" button | Skip rest, start next set |
| Tap "End Workout" button | End workout |

Gestures detected via Vision: wrist joint Y coordinates compared to shoulder Y coordinates each frame.

---

## Claude Integration — Exactly 2 Calls Per Session

Claude handles **language only**. All detection, counting, and scoring is on-device.

### Call 1 — Post-Set Micro Feedback
**When:** Immediately after each set ends (user is resting anyway — latency doesn't matter)  
**Input (~200 tokens):**
```json
{
  "exercise": "squat",
  "repCount": 10,
  "avgKneeAngle": 105,
  "targetKneeAngle": 90,
  "flaggedReps": 3,
  "flagReasons": ["insufficient depth", "forward lean"]
}
```
**Output (~100 tokens):** 1–2 sentence cue displayed during rest  
*Example: "Good effort — you're not quite hitting depth yet. Focus on sitting back into your heels on the next set."*

### Call 2 — End-of-Session Coaching Summary
**When:** After user ends workout, while summary screen loads  
**Input (~400 tokens):**
```json
{
  "sessionDuration": 2400,
  "exercises": [
    { "name": "squat", "sets": 3, "totalReps": 30, "avgFormScore": 0.74 },
    { "name": "pushup", "sets": 2, "totalReps": 20, "avgFormScore": 0.88 }
  ],
  "personalRecords": ["pushup rep PR: 12"],
  "flaggedPatterns": ["squat depth consistently low"]
}
```
**Output (~200 tokens):** 3–5 sentence coaching summary displayed on summary screen

### What Claude Does NOT Do
- ❌ Real-time rep counting
- ❌ Exercise detection
- ❌ Form scoring
- ❌ Rest/set timing
- ❌ Gesture detection

### Cost
- ~$0.004 per session (less than half a cent)
- ~$0.08/month at 20 workouts/month
- Model: **Claude Haiku 4.5** — $1.00 input / $5.00 output per million tokens

---

## Exercise Library (Launch — 3 Exercises)

| Exercise | Camera Angle | Key Joints | Form Checks |
|---|---|---|---|
| Squat | Side profile | Hip, knee, ankle, shoulder | Knee ~90°, hip below knee, back upright |
| Pushup | Side profile | Shoulder, elbow, wrist, hip | Elbow ~90°, hip flat, wrist under shoulder |
| Lunge | Front or side | Hip, both knees, ankles | Front knee ~90°, back knee drops, torso upright |

---

## Data Schema (CoreData)

```
WorkoutSession
├── id, date, duration, overallFormScore
├── coachingSummary: String?   ← persisted end-of-session Claude paragraph
└── sets: [ExerciseSet]

ExerciseSet
├── id, exercise, repCount, duration, restDuration, formScore, flaggedReps
└── reps: [Rep]

Rep
└── id, formScore, flaggedJoints[], timestamp
```

> Use `ExerciseSet` not `Set` — `Set` conflicts with Swift's standard library.
> `coachingSummary` is saved to CoreData immediately after the end-of-session Claude call resolves. If the call fails, it remains nil and the history card shows a placeholder.

---

## Workout History

Users can review past workouts organized by calendar month. No video is stored — records contain workout data and the AI coaching summary only.

### History Screen
- **Entry point:** tab or nav item from the main screen (always accessible, not just post-workout)
- **Month view:** calendar grid; days with a completed workout show a dot indicator
- **Tapping a day** → Workout Detail screen for that session

### Workout Detail Screen
Displays everything saved in `WorkoutSession`:
- Date, total duration, overall form score
- Per-exercise breakdown: exercise name, sets completed, total reps, avg form score
- Claude coaching summary paragraph (or "No coaching summary available" if nil)
- **Delete button** — confirmation alert → deletes the `WorkoutSession` and all child `ExerciseSet` and `Rep` records via CoreData cascade delete

### Data Rules
- No video stored at any point — only structured CoreData records
- `coachingSummary` is the persisted Claude paragraph from the end-of-session call; the history screen never re-calls Claude
- CloudKit sync (Phase 3) makes history available across the user's devices automatically
- Deletion propagates to CloudKit on next sync

### Phase Placement
- **Phase 2:** CoreData schema includes `coachingSummary` from the start (even though Claude isn't integrated yet — field is just nil)
- **Phase 3:** History screen UI built alongside the session summary screen; delete functionality included

---

## Known Limitations (Plan Around These)

| Issue | Mitigation |
|---|---|
| Baggy clothing obscures joints | Setup guide warns user; show joint confidence score |
| User near frame edges drops accuracy | Silhouette overlay keeps user centered |
| Vision requests block UI if on main thread | Always run on background `DispatchQueue` |
| CoreData naming conflict | Use `ExerciseSet`, not `Set` |

---

## Implementation Phases

### Phase 1 — Week 1: Vision Foundation
- [ ] Xcode project + SwiftUI navigation shell
- [ ] `AVCaptureSession` camera feed
- [ ] `VNDetectHumanBodyPoseRequest` on background thread
- [ ] Skeleton overlay on camera feed
- [ ] Joint angle calculation utilities
- [ ] Rep counter for squat
- [ ] Silhouette alignment guide + 3s countdown

### Phase 2 — Week 2: Detection + Logging
- [ ] Form thresholds + scoring for all 3 exercises
- [ ] Real-time form cues (text overlay)
- [ ] Rule-based exercise classifier
- [ ] State machine (idle → detecting → inSet → resting)
- [ ] Debounce timer for rest detection
- [ ] Gesture detection (one hand / both hands)
- [ ] CoreData schema + passive workout logging

### Phase 3 — Week 3: Summary + Claude
- [ ] Rest timer UI + "Next Set" button
- [ ] Session summary screen
- [ ] PR detection (compare current session totals against stored WorkoutSessions)
- [ ] Workout History screen — monthly calendar view with day indicators
- [ ] Workout Detail screen — per-session breakdown with Claude summary and delete
- [ ] Claude Haiku 4.5 API — post-set call
- [ ] Claude Haiku 4.5 API — end-of-session call; persist result to `coachingSummary`
- [ ] Prompt caching for system prompt
- [ ] iCloud sync via CloudKit

### Phase 4 — Week 4: Polish + Ship
- [ ] Onboarding flow + camera permission
- [ ] Edge cases: partial visibility, mid-set pauses, bad lighting
- [ ] App icon, launch screen, UI refinement
- [ ] TestFlight build + distribution
- [ ] Stretch: HealthKit integration, streak tracking, exercise library expansion

---

## Resume Bullets

- **Built a real-time AI fitness coach** using Apple's Vision framework for on-device body pose detection, implementing joint angle calculation and a rule-based exercise classifier to auto-detect exercises with per-rep form scoring.
- **Engineered a passive workout logging system** with a state machine that automatically detects sets, rest periods, and exercise transitions — logging structured session data with CoreData and iCloud sync.
- **Integrated gesture controls** using Vision joint coordinates to start, pause, and end workout sessions hands-free.
- **Designed an LLM coaching pipeline** using Claude Haiku 4.5, converting structured pose data into actionable coaching at under half a cent per session.
