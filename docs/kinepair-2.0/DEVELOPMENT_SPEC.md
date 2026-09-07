# KinePair 2.0 Development Specification

Status: Draft for implementation  
Target release: KinePair 2.0  
Product direction: UX-first major redesign  
Primary platform: iPhone / iPad, iOS/iPadOS 17+  
Public product name: KinePair  
Internal Xcode target/module: FormSync  

> Production baseline is KinePair 1.3.2. The repository snapshot inspected while preparing this document still declares `MARKETING_VERSION: 1.3.0` / build `1300` in `ios/FormSync/project.yml`; reconcile version metadata with the actual 1.3.2 production baseline before starting the 2.0 release branch. Do not change the bundle ID, StoreKit product ID, Keychain service, storage directory names, or other compatibility-sensitive identifiers.

---

## 1. Product intent

KinePair 2.0 is not an AI release.

The purpose of 2.0 is to maximize the experience of the product that already exists: selecting two videos, matching the same moment, synchronizing them, comparing them, and exporting the result.

The product should move from:

`Import -> Sync -> Compare -> Export`

as a technically capable workflow to:

`Open -> Select -> Match -> Compare`

as a near-frictionless workflow.

The core internal goal is:

> A user who already understands KinePair should be able to reach a useful synchronized comparison with minimal thought, minimal navigation, and minimal UI obstruction.

AI, automatic pose estimation, automatic form scoring, automatic synchronization, automatic phase detection, motion tracking, cloud analysis, team collaboration, and coaching automation are intentionally deferred to a future 3.0-class release.

---

## 2. Visual target

The following concept image is the primary visual direction for KinePair 2.0.

![KinePair 2.0 UX concept](./assets/kinepair-2.0-ux-concept.jpg)

This image is a direction reference, not a pixel-perfect implementation contract. Preserve the following principles rather than copying every decorative element:

1. Dark, video-first workspace.
2. Charcoal/black surfaces with high-contrast white text.
3. Lime-green accent reserved for primary actions, active controls, and important state.
4. Strong hierarchy and fewer simultaneously visible controls.
5. Large video surfaces with controls visually subordinate to the content.
6. A distinct iPad landscape workspace instead of a stretched iPhone layout.
7. Simple, athletic, practical visual language; avoid generic dashboard styling and excessive glassmorphism.
8. Rounded geometry is allowed, but cards and pills must not overwhelm the content.
9. Use SF Symbols where they improve recognition; do not add decorative icons without a functional purpose.
10. Motion should communicate state transitions and never delay comparison work.

### 2.1 Design tokens

Keep the existing `AppTheme` as the source of truth and evolve it rather than scattering colors through views.

Recommended semantic tokens:

- `backgroundPrimary`: near-black
- `backgroundSecondary`: charcoal
- `surfaceElevated`: slightly lighter charcoal
- `surfaceInteractive`: control background
- `accent`: current KinePair lime
- `accentText`: text on lime
- `textPrimary`: white / near-white
- `textSecondary`: muted gray
- `divider`: subtle neutral gray
- `destructive`: system red
- `disabled`: reduced-contrast surface/text

Spacing should use a small set of constants rather than local magic numbers.

Recommended spacing scale: 4 / 8 / 12 / 16 / 24 / 32.

---

## 3. Success criteria

2.0 should be judged primarily by workflow quality rather than number of new features.

### 3.1 Primary UX goals

- A returning user can start a new two-video comparison from launch in one obvious action.
- Two videos can be selected in one PhotosPicker interaction.
- The sync/setup screen communicates one job only: choose the matching moment in A and B.
- The main compare screen dedicates approximately 80-90% of practical visual emphasis to the videos.
- Primary playback actions remain accessible without opening a menu.
- Secondary controls are available quickly but do not permanently consume comparison space.
- Returning to the latest comparison requires one tap from Home.
- Export can be repeated with prior settings without reconfiguring every field.
- iPad landscape behaves like a dedicated analysis workspace.
- Existing 1.x session history and lifetime PRO entitlement remain usable.

### 3.2 Internal measurable targets

These are product targets, not analytics requirements. KinePair currently has no analytics/tracking and 2.0 must not add analytics merely to measure them.

Manual usability testing should target:

- launch -> PhotosPicker: 1 tap
- PhotosPicker completion -> sync setup: automatic transition where possible
- sync setup -> synchronized compare: reference point A + reference point B + Compare
- Continue Last Session: 1 tap
- switch Side / Stack / Overlay: 1 direct interaction
- quick export after first configured export: <= 2 interactions
- fullscreen enter/exit: 1 interaction each

---

## 4. Scope

### 4.1 In scope for 2.0

- Complete Home redesign
- Faster two-video selection flow
- Dedicated sync/reference-point setup experience
- Main comparison workspace redesign
- Control hierarchy simplification
- Gesture consistency
- Fullscreen comparison mode
- iPad-specific comparison workspace
- Continue Last Session
- Improved recent/history presentation
- Quick Export using remembered export preferences
- Broader preference persistence
- Better state restoration when returning to a comparison
- Accessibility and localization pass
- UI/interaction regression tests
- Updated screenshots/onboarding/update notice for 2.0

### 4.2 Explicitly out of scope for 2.0

Do not introduce these while implementing this specification unless the scope is deliberately revised:

- AI pose estimation
- AI form scoring
- automatic joint-angle analysis
- automatic synchronization
- automatic phase/event detection
- motion tracking
- cloud upload or cloud history
- accounts/login
- team/athlete management
- messaging/chat
- social feed
- collaborative annotation
- subscription conversion
- new server/backend
- advertising
- analytics/tracking SDKs

### 4.3 Existing functional scope to preserve

2.0 must preserve the existing product capabilities unless explicitly replaced by a better interaction:

- select two local videos
- bundled sample comparison
- independent reference/sync points
- synchronized common timeline
- Side by Side / Stacked / Overlay
- play/pause and seek
- frame stepping
- playback speed
- per-video zoom/pan
- loop range
- overlay opacity/position/scale/rotation
- history persistence/reopen/delete/rename
- image export
- MP4 export
- 720p / 1080p rules
- selectable video export range and audio source
- free / full-feature trial / PRO gating
- watermark behavior
- StoreKit 2 purchase/restore
- English / Japanese / Korean
- local-only processing

---

## 5. Navigation and information architecture

The 2.0 top-level user journey should be:

```text
Home
  |-- Compare Videos
  |     `-- Select 2 Videos
  |            `-- Sync Setup
  |                   `-- Compare Workspace
  |                          |-- Fullscreen
  |                          |-- Secondary Controls
  |                          `-- Export
  |
  |-- Continue Last Session -> Compare Workspace or Sync Setup
  |-- Try Sample -> Sync Setup / Compare Workspace
  |-- History -> Session List -> Compare Workspace or Sync Setup
  `-- Settings / PRO
```

Navigation should remain shallow. Avoid adding tabs solely to separate a small number of functions.

### 5.1 Navigation rule

When the user leaves a real comparison, persist state before dismissing. Reopening must reconstruct the same practical workspace as closely as possible.

If a session has valid sync points and was last in synchronized mode, reopening may return directly to the Compare Workspace.

If one or both sync points are missing, reopening must return to Sync Setup.

---

## 6. Screen specifications

## 6.1 Home

### Purpose

Answer one question immediately: "What do I do now?"

### Required hierarchy

1. KinePair brand/title
2. Primary `Compare Videos` action
3. `Continue Last Session` if a session exists
4. `Try Sample`
5. History entry
6. Small settings / PRO affordances

### Primary action

`Compare Videos` is the dominant element and opens a PhotosPicker configured for exactly two videos.

### Continue Last Session

Display only when at least one persisted real comparison exists.

Recommended contents:

- thumbnail if inexpensive to generate/cache
- current title
- last updated time/date
- optional concise state, e.g. `Synced` or `Set reference points`

Do not require the user to enter History first.

Implementation can derive this from `CompareSessionStore.listSessions().first` because sessions are already sorted by `updatedAt` descending. Do not add a new persistence model unless needed.

### History

Show a concise row such as `History` plus count. Existing free/trial/PRO visibility rules remain authoritative.

### PRO

PRO promotion should not compete visually with the main comparison action. It may remain a lower-priority card/row or settings item.

### Empty state

When no history exists, do not show a large empty-history block. `Compare Videos` and `Try Sample` should carry the screen.

### Acceptance criteria

- A new comparison starts from one obvious primary control.
- Continue appears when appropriate.
- No modal explanation is required to understand the screen.
- Settings and PRO are reachable without dominating the layout.
- Home remains usable in all three localizations.

---

## 6.2 Video selection

### Purpose

Obtain exactly two videos and establish A/B order with minimal friction.

### Default behavior

Use one multi-selection PhotosPicker with a maximum selection count of 2.

If exactly two videos are selected:

- begin loading both concurrently using the existing service behavior
- show lightweight progress
- automatically continue to the ready/sync flow after successful persistence, unless an explicit confirmation screen is needed for reliability

### A/B representation

After loading, represent videos as `A` and `B` / left and right.

Provide one direct Swap action.

Do not require separate `Choose Left` and `Choose Right` picker flows.

### Error handling

- 0 selected: remain on Home / picker dismissal is not an error
- 1 selected: prompt to select one more video without discarding the first if PhotosPicker behavior allows
- load failure: identify the failed video generically and provide retry/reselect
- insufficient local storage: present a clear actionable error

### Data behavior

Continue to create/persist the session using existing `CompareSessionStore` semantics. Do not keep long-lived PhotosPicker references in persisted session data.

### Acceptance criteria

- two videos are picked in one selection interaction
- order can be swapped without re-picking
- loading does not block the UI without feedback
- failed selection never silently creates a broken session

---

## 6.3 Sync Setup

### Purpose

The user must understand that the only required task is:

> Set the same moment in both videos.

All nonessential analysis controls should be removed from this screen.

### Layout

Portrait iPhone:

- compact title/instruction
- video A
- minimal A scrub/frame controls
- `Set A` / localized equivalent
- video B
- minimal B scrub/frame controls
- `Set B`
- primary `Compare` action anchored near bottom

Landscape / iPad may show A and B side-by-side.

### Controls allowed in setup

Keep only controls needed to find and set a reference point:

- play/pause per video
- scrub
- frame step
- set/reset reference point
- swap A/B
- replace video
- Compare

Do not expose Loop, Overlay adjustment, Export, detailed display settings, or unrelated preferences here.

### Reference-point state

Each video must visibly show one of:

- Not set
- Set

After both are set, the `Compare` action becomes visually primary/enabled.

### Frame stepping

For UX consistency, frame-step controls should use the current configured step width. If a PRO-only step is unavailable for a limited user, use an allowed step rather than presenting a broken control.

### Gesture behavior

A direct horizontal drag/scrub gesture over the video may be introduced if it can be implemented without conflicting with horizontal pan when zoomed. Gesture priority must be deterministic.

Recommended rule:

- scale == 1: horizontal drag can scrub
- scale > 1: one-finger drag pans; timeline scrub remains on the scrubber

Do not ship an ambiguous gesture where the same motion unpredictably pans or seeks.

### Starting comparison

`Compare` should call the existing synchronized comparison entry logic and respect trial consumption rules.

Sample comparison must continue to avoid consuming a trial use.

### Acceptance criteria

- a first-time user can infer the goal without opening Help
- the screen does not feel like the full comparison workspace
- reference state is unmistakable
- comparison cannot start until both reference points exist
- starting comparison preserves current StoreKit/trial semantics

---

## 6.4 Compare Workspace - iPhone

### Purpose

Make the videos the product.

### Visual hierarchy

Practical target: 80-90% of attention/usable surface should be video and timeline, not permanent control chrome.

### Always-visible primary controls

Keep a compact primary transport/control layer:

- play/pause
- timeline/scrubber
- current/total normalized time
- display mode switch
- playback speed
- frame-step entry/direct controls
- fullscreen
- more/secondary controls
- export access

Exact icon placement can adapt by orientation, but the hierarchy must remain consistent.

### Display mode switch

Side / Stack / Overlay must be reachable in one interaction from the workspace.

Switching display mode must preserve the comparison timeline and player synchronization.

Existing PRO gating for Overlay remains.

### Secondary controls

Move less frequently used controls into a bottom sheet, compact drawer, or context panel:

- loop setup
- exact frame-step width
- per-video adjustment/reset
- overlay settings
- replace/swap
- video info
- advanced export entry

Opening this panel must not navigate away from the comparison.

### Play/pause interaction

A tap on an unobstructed video surface may toggle synchronized play/pause. Controls must still provide an explicit accessible button.

### Zoom/pan

Preserve independent per-video zoom/pan.

Recommended gestures:

- pinch: zoom selected/touched video
- drag while zoomed: pan
- double tap: reset framing for the touched video

If double tap conflicts with another existing action, prioritize reset framing and document it in onboarding/help.

### Fullscreen

Add a fullscreen mode that removes nonessential chrome.

Fullscreen shows:

- video(s)
- minimal timeline
- play/pause
- unobtrusive exit affordance

A tap may reveal/hide controls.

Fullscreen state is transient and does not need persistence across app termination.

### Orientation

Portrait and landscape both remain supported on iPhone.

Landscape should favor horizontal video area and reduce labels before reducing video size.

### Acceptance criteria

- user can play, seek, switch mode, change speed, frame-step, and export without leaving comparison
- secondary tools do not permanently crowd videos
- display-mode switching does not visually jump to a different timeline position
- zoom/pan remains independent per video
- fullscreen is functional in portrait and landscape

---

## 6.5 Compare Workspace - iPad

### Purpose

Treat iPad landscape as an analysis workspace rather than a scaled iPhone screen.

### Landscape default

Recommended structure:

```text
+--------------------------------------------------------------+
| Top bar: KinePair / session title                    Export  |
+------------------------------------------+-------------------+
|                                          | View Mode         |
|                                          | Side Stack Overlay|
|              VIDEO AREA                  |                   |
|                                          | Playback          |
|                                          | Loop              |
|                                          | Frame Step        |
|                                          | Adjust Videos     |
|                                          | Video Info        |
|                                          |                   |
+------------------------------------------+-------------------+
| Timeline / transport controls                                |
+--------------------------------------------------------------+
```

Suggested ratio: video 70-80%, control sidebar 20-30%.

### Sidebar

The sidebar can expose more controls than iPhone because it does not need to obscure the video.

Recommended items:

- View Mode
- Playback speed
- Loop status/settings
- Frame Step
- Adjust Videos
- Overlay controls when Overlay is active
- Video Info
- Export

### Portrait iPad

Use an adaptive layout closer to large-iPhone behavior, but preserve larger video surfaces and comfortable spacing.

### Multitasking

The UI must remain coherent when the iPad window is not full-screen. Use size classes / geometry rather than hard-coded iPad screen dimensions.

### Acceptance criteria

- landscape layout is clearly optimized for tablet
- sidebar never forces videos into unusably small dimensions
- shrinking the window gracefully transitions layout
- all controls remain keyboard/accessibility reachable where applicable

---

## 6.6 Export

### Purpose

Preserve advanced export capability while making repeat export faster.

### Two paths

#### Quick Export

Use the last valid export preset and proceed directly to export confirmation/progress.

If no prior preset exists, Quick Export opens detailed Export for initial configuration.

#### Export Options

Allow the existing configuration set:

- Image / Video
- Current frame / Full / Loop as valid for format
- 720p / 1080p
- audio source for video
- Photos / Share destination where appropriate

Respect current free/trial/PRO gating.

### Remembered settings

Persist the user's last valid export choices separately from per-session comparison data.

Do not persist transient output URLs, export progress, or temporary files.

### Progress

Keep progress and cancellation for video export.

Leaving the progress UI must not imply that a canceled export completed.

### Acceptance criteria

- after one configured export, a repeat export does not require full reconfiguration
- invalid combinations cannot be saved as the quick preset
- PRO restrictions remain identical or stricter, never accidentally bypassed
- Photos permission is requested only when saving to Photos

---

## 6.7 History

### Purpose

History supports continuation, not file management for its own sake.

### List

Each row should prioritize:

- title
- representative thumbnail(s) if practical
- last updated timestamp
- sync/setup state

Existing rename/delete behavior stays available through context actions or a secondary gesture/menu. Double-tap rename may remain for compatibility but should not be the only discoverable way to rename.

### Free/trial/PRO behavior

Preserve existing history access rules. Hidden prior sessions must not be deleted merely because the user is currently in a limited tier.

### Continue behavior

Opening a valid synced session should return to comparison with saved settings/timeline. Incomplete sessions return to Sync Setup.

---

## 6.8 Settings and PRO

Keep Settings secondary to the comparison workflow.

Recommended groups:

- Defaults
  - playback speed
  - display mode
  - frame-step width
  - reset comparison defaults
- Export
  - remembered quick export preset / reset
- KinePair PRO
  - status
  - purchase
  - restore
- About
  - privacy policy
  - version
  - help

Do not turn Settings into a dashboard.

StoreKit 2 remains the entitlement authority.

---

## 7. Interaction system

2.0 should define a consistent interaction vocabulary.

### 7.1 Proposed gestures

| Gesture | Setup | Synced comparison | Zoomed video |
|---|---|---|---|
| Tap video | play/pause selected video | play/pause both | play/pause both |
| Pinch | zoom selected video | zoom selected video | adjust zoom |
| Drag video | optional scrub at scale 1 | optional scrub at scale 1 | pan |
| Double tap | reset selected framing | reset selected framing | reset framing |
| Drag timeline | scrub selected/common timeline | scrub common timeline | scrub common timeline |

Gesture behavior must be implemented centrally enough that A/B panes do not drift into different interaction rules.

### 7.2 Haptics

Use subtle system haptics for discrete state-setting actions where useful:

- reference point set
- loop start/end set
- mode lock/selection

Do not haptic on every frame step or continuous scrub.

### 7.3 Motion

Recommended transitions: 150-250 ms, system-native easing.

Avoid decorative animation during playback.

---

## 8. State model and data model changes

The key requirement is backward compatibility. 2.0 should avoid rewriting `CompareSession` unless a persistent feature genuinely requires it.

## 8.1 Existing persisted models to retain

Retain the existing structure and decoding behavior for:

- `CompareSession`
- `CompareSessionSlot`
- `CompareSessionVideo`
- `CompareSettings`
- `OverlaySettings`
- trial usage storage
- StoreKit entitlement cache

Existing session JSON must remain decodable after 2.0.

### 8.2 CompareSession

No mandatory schema change is required for the core UX redesign.

Current `updatedAt` is sufficient for `Continue Last Session` if it is reliably updated whenever practical comparison state is persisted.

Required implementation audit:

- confirm every state-changing path that should affect recency updates `updatedAt`
- ensure exiting/reopening preserves display mode, playback rate, step width, loop, overlay settings, sync points, zoom/pan, compare mode, and timeline as currently intended

Optional additive field only if needed:

```swift
var lastOpenedAt: Date?
```

Prefer not to add this unless `updatedAt` semantics prove insufficient.

If added, decode it with a default/nil path so 1.x JSON remains valid.

### 8.3 New global preference model

Add a small Codable preference representation or equivalent `SettingsStore` keys.

Recommended model:

```swift
struct ComparisonDefaults: Codable, Equatable {
    var playbackRate: PlaybackRate = .normal
    var displayMode: DisplayMode = .sideBySide
    var stepSeconds: Double = 0.1
}
```

This replaces the current concept of remembering only playback rate and display mode with a coherent comparison-default set.

Migration behavior:

- if old `lastPlaybackRate` exists, seed `playbackRate`
- if old `lastDisplayMode` exists, seed `displayMode`
- otherwise use current defaults
- new `stepSeconds` defaults to 0.1
- do not remove legacy keys until at least one stable migration path is verified

### 8.4 New Quick Export preset

Recommended persisted model:

```swift
struct QuickExportPreset: Codable, Equatable {
    var format: ExportFormat
    var range: ExportRange
    var resolution: ExportResolution
    var audioSource: ExportAudioSource
    var destination: ExportDestination
}
```

`includesWatermark` must NOT be persisted as a user preference. It is derived at runtime from entitlement/trial state.

The preset must be validated against current access rights and current session conditions before use.

Examples:

- limited user with stored 1080p preset -> downgrade/show paywall according to product rule; never silently bypass entitlement
- no valid loop -> stored Loop range cannot execute; fall back to export options or Full depending on format
- image export -> audio source ignored/normalized to `.none`

### 8.5 Transient UI state

Do not persist these in session JSON:

- fullscreen on/off
- secondary sheet open/closed
- control auto-hide state
- current hover/focus state
- export progress
- PhotosPicker items
- temporary error/toast text
- current drag gesture state

### 8.6 Selection draft

Selection state may be represented as a transient model for cleaner architecture:

```swift
struct VideoPairDraft {
    var first: PhotosPickerItem?
    var second: PhotosPickerItem?
}
```

Do not serialize this model.

---

## 9. Architecture changes

The AVFoundation synchronization engine should not be rewritten merely to support the redesign.

### 9.1 Preserve

Keep these responsibilities largely intact:

- `PlayerSyncService`: synchronized AVPlayer control
- `ExportService`: image/video rendering and output
- `PurchaseManager`: StoreKit 2 and trial access
- `CompareSessionStore`: local session persistence
- `VideoPickerService`: media loading
- `CompareViewModel`: comparison-domain state and playback operations

Refactor only where current UI coupling prevents clean screen separation.

### 9.2 View decomposition

`HomeView.swift` and `CompareView.swift` are currently large. 2.0 should reduce monolithic view complexity.

Recommended new/extracted views:

```text
Views/
  Home/
    HomeView.swift
    HomePrimaryAction.swift
    ContinueSessionCard.swift
    RecentHistoryRow.swift

  Selection/
    VideoPairSelectionView.swift
    VideoSelectionCard.swift

  Sync/
    SyncSetupView.swift
    SyncVideoPane.swift
    ReferencePointControl.swift

  Compare/
    CompareWorkspaceView.swift
    CompareVideoStage.swift
    CompactTransportBar.swift
    DisplayModeSwitcher.swift
    SecondaryControlsSheet.swift
    FullscreenCompareView.swift
    FrameStepControl.swift
    LoopControls.swift
    VideoAdjustmentControls.swift

  iPad/
    IPadCompareWorkspace.swift
    CompareControlSidebar.swift

  Export/
    ExportOptionsView.swift
    QuickExportButton.swift
    ExportProgressView.swift
```

Exact folder names are flexible; separation of responsibilities is not.

### 9.3 CompareViewModel boundaries

Do not duplicate playback logic across `SyncSetupView` and `CompareWorkspaceView`.

Both screens should operate on one comparison-domain state source.

Possible approaches:

- keep a single `CompareViewModel` and expose two UI phases
- add a thin coordinator that owns one `CompareViewModel`

Do not create independent AVPlayers for setup and comparison if it causes reloads or loss of position during the transition.

### 9.4 HomeViewModel

Add derived state/action for the latest visible session:

```swift
var latestSession: CompareSession? { sessions.first }
```

Ensure `refreshSessions(hasExpandedHistoryAccess:)` is called when entitlement/trial state changes.

---

## 10. Access control / monetization constraints

2.0 is not a monetization redesign.

Preserve:

- 3 full-feature real comparison trial uses
- sample comparison does not consume trial
- limited free feature set
- existing KinePair PRO lifetime non-consumable
- verified StoreKit 2 transactions as authority
- existing product ID `formsync.pro.lifetime`

UI redesign must never cause feature gates to be evaluated only at view visibility. Gate the action/domain operation as well.

Example: hiding a 1080p button is insufficient; export request construction must still validate access.

---

## 11. Privacy and storage constraints

2.0 must remain local-first.

Required:

- no video upload
- no account requirement
- no tracking
- no analytics SDK
- no advertising SDK
- no new media permission unless necessary
- temporary export files cleaned according to current behavior
- existing Privacy Manifest remains accurate after changes

If new APIs introduce a Required Reason API category, update `PrivacyInfo.xcprivacy` before release.

---

## 12. Accessibility

2.0 is a redesign and should include an accessibility pass rather than preserving visual-only assumptions.

Required:

- all icon-only controls have explicit accessibility labels
- minimum practical touch target ~44x44 pt
- active mode cannot be indicated by color alone
- disabled state is communicated semantically
- Dynamic Type is supported for non-video UI without catastrophic overlap
- VoiceOver order follows the visual workflow
- video A/B labels are spoken consistently
- controls auto-hidden in fullscreen can be restored without requiring vision
- Reduce Motion is respected for nonessential transitions

---

## 13. Localization

English, Japanese, and Korean remain supported.

Requirements:

- all new user-facing strings use `Localizable.xcstrings`
- no hard-coded English in SwiftUI views
- button widths/layouts tolerate Japanese/Korean expansion
- `A` / `B` can remain language-neutral labels
- screenshot UI tests should continue to run for all three languages
- update onboarding/update notice content in all locales

---

## 14. Performance requirements

UX improvements are invalid if they make video interaction feel slower.

Targets:

- entering Compare from Sync Setup should reuse loaded players/assets wherever possible
- display-mode switching must not reload source media
- fullscreen transition must not recreate the comparison session
- opening/closing secondary controls must not pause playback unless a specific operation requires it
- scrubbing should remain responsive and use the existing seek coalescing/cancellation mechanisms
- thumbnails must not block main-thread launch/home rendering
- iPad layout must not instantiate duplicate hidden player trees

Avoid adding continuous heavy visual effects over AVPlayer surfaces.

---

## 15. Error-state requirements

Every workflow must have a recoverable error path.

### Video loading

- display clear message
- allow reselect
- never leave `isLoading` stuck

### Missing persisted file

- remove/mark invalid session from visible history according to current behavior
- return to Home/History safely

### Export failure

- retain comparison state
- distinguish cancellation from failure
- allow retry

### StoreKit unavailable

- comparison remains usable at the user's verified access level
- purchase UI reports unavailable state without blocking core free workflow

### Photos save permission denied

- offer Share when feasible
- do not repeatedly force permission prompts

---

## 16. Testing strategy

## 16.1 Unit tests

Preserve existing tests and add coverage for:

- migration of comparison defaults from legacy keys
- quick export preset validation
- quick export cannot bypass PRO
- latest-session selection
- session resume phase (setup vs synced)
- sample still does not consume trial
- 1.x session JSON still decodes
- optional new fields decode when absent
- invalid loop preset behavior

## 16.2 UI tests

Add/refresh flows:

1. Fresh launch -> onboarding -> Home
2. Home -> Try Sample
3. Home -> Compare Videos -> two selected videos -> Sync Setup
4. Set A -> Set B -> Compare
5. Side -> Stack -> Overlay gate/access
6. play/pause -> scrub -> frame step
7. enter/exit fullscreen
8. secondary controls sheet
9. export options
10. Continue Last Session
11. History open/delete/rename
12. iPad landscape workspace
13. Japanese screenshots
14. English screenshots
15. Korean screenshots

### 16.3 Manual device testing

At minimum verify on:

- smallest supported practical iPhone screen class
- current standard iPhone
- large iPhone
- iPad portrait
- iPad landscape
- iPad multitasking/narrow window

Test real high-frame-rate and long videos, not only bundled samples.

---

## 17. Implementation order

The order below is intentional. Avoid redesigning every screen simultaneously.

### Phase 0 - Baseline and safety

1. Confirm production 1.3.2 source is fully represented in GitHub.
2. Reconcile `project.yml` version/build metadata with 1.3.2.
3. Tag or otherwise preserve the 1.3.2 baseline.
4. Create a 2.0 development branch.
5. Run current unit/UI tests before structural changes.
6. Confirm a release build compiles without signing.
7. Archive sample 1.x session JSON fixtures for migration tests.

Exit criteria: known-good baseline with reproducible build/tests.

### Phase 1 - Design system / shared primitives

1. Refine `AppTheme` semantic tokens.
2. Introduce shared spacing/control sizing.
3. Build primary/secondary button styles.
4. Build reusable compact icon control style.
5. Build `DisplayModeSwitcher` and generic control row primitives.
6. Verify Dynamic Type and localization early.

Exit criteria: reusable components can reproduce the concept direction without screen-specific style duplication.

### Phase 2 - Home + Continue

1. Simplify Home hierarchy.
2. Implement dominant Compare Videos action.
3. Implement Continue Last Session.
4. Reduce History/PRO/Settings visual priority.
5. Preserve onboarding/update notice behavior until 2.0 copy is ready.

Exit criteria: returning user reaches picker or last session in one tap.

### Phase 3 - Selection flow

1. Keep one two-item PhotosPicker flow.
2. Improve loading/progress state.
3. Add/standardize A/B swap.
4. Transition directly to Sync Setup after successful loading.
5. Validate failure/reselect behavior.

Exit criteria: no separate left/right picking workflow and no unnecessary confirmation screen.

### Phase 4 - Extract and redesign Sync Setup

1. Split setup UI from full comparison UI while reusing one model/player state.
2. Limit controls to reference-point tasks.
3. Make Set A / Set B state clear.
4. Make Compare become primary after both are set.
5. Preserve trial consumption timing.
6. Preserve sample semantics.

Exit criteria: setup screen has one obvious job and all existing sync precision remains available.

### Phase 5 - iPhone Compare Workspace

1. Create video-first stage.
2. Add compact primary transport controls.
3. Add one-interaction mode switch.
4. Move secondary tools to sheet/drawer.
5. Preserve all PRO gates.
6. Verify mode switching preserves timeline.
7. Verify no player re-creation during simple UI transitions.

Exit criteria: all existing comparison functions remain usable with materially less permanent chrome.

### Phase 6 - Gestures + fullscreen

1. Standardize tap play/pause.
2. Preserve pinch zoom.
3. Standardize pan behavior.
4. Add double-tap framing reset.
5. Resolve scrub vs pan gesture precedence.
6. Implement fullscreen control auto-hide/reveal.
7. Add accessibility alternatives for gestures.

Exit criteria: gesture behavior is deterministic and documented.

### Phase 7 - iPad workspace

1. Implement adaptive landscape sidebar.
2. Reuse compare components rather than duplicate logic.
3. Support portrait.
4. Test compact multitasking widths.
5. Verify player surfaces are not duplicated.

Exit criteria: iPad feels intentionally designed and remains stable across window sizes.

### Phase 8 - Export UX

1. Add persisted `QuickExportPreset`.
2. Build Quick Export entry.
3. Reorganize detailed Export options.
4. Validate stored preset against entitlement/session state.
5. Preserve progress/cancel/share/Photos behavior.

Exit criteria: repeat export is faster and access control remains correct.

### Phase 9 - Preference persistence / restoration

1. Add `ComparisonDefaults` or equivalent keys.
2. Migrate legacy playback/display defaults.
3. Add step-width persistence.
4. Audit session `updatedAt` behavior.
5. Verify Continue restores correct phase and state.
6. Reset Defaults action clears only intended settings.

Exit criteria: frequent users stop reconfiguring the same controls every session.

### Phase 10 - polish, migration, release

1. Full regression test of StoreKit/trial/history/export.
2. Decode 1.x session fixtures.
3. Accessibility audit.
4. English/Japanese/Korean copy pass.
5. New 2.0 onboarding/update notice.
6. Generate new App Store screenshots from final UI.
7. Verify Privacy Manifest.
8. Verify support/privacy URLs in production metadata.
9. Update README and release checklist.
10. Set `MARKETING_VERSION: 2.0.0` and build number only at release preparation stage.

Exit criteria: release candidate behaves correctly for fresh installs, existing free users, active trial users, and existing lifetime PRO purchasers.

---

## 18. Suggested code-change map

Likely files to modify heavily:

- `FormSync/Views/HomeView.swift`
- `FormSync/Views/CompareView.swift`
- `FormSync/ViewModels/HomeViewModel.swift`
- `FormSync/ViewModels/CompareViewModel.swift`
- `FormSync/Services/SettingsStore.swift`
- `FormSync/Models/CompareSettings.swift`
- `FormSync/Utilities/AppTheme.swift`
- `FormSync/Localizable.xcstrings`
- `FormSyncUITests/FormSyncScreenshotUITests.swift`

Files that should preferably receive limited behavioral changes:

- `FormSync/Services/PlayerSyncService.swift`
- `FormSync/Services/ExportService.swift`
- `FormSync/Services/PurchaseManager.swift`
- `FormSync/Services/TrialUsageStore.swift`
- `FormSync/Services/VideoPickerService.swift`

Changes to the second group require a concrete behavior need or bug fix, not cosmetic refactoring.

---

## 19. Compatibility rules

These rules are release blockers.

Do not rename without a dedicated migration:

- Xcode target/module `FormSync`
- bundle ID `com.yamamasutaro.formsync`
- StoreKit product ID `formsync.pro.lifetime`
- Keychain service derived from the existing bundle identifier
- application-support storage directory `FormSync/Sessions`

Do not invalidate existing session JSON.

Do not convert existing lifetime PRO users into a new entitlement model in 2.0.

Do not delete hidden history as a consequence of UI gating.

---

## 20. Definition of Done for KinePair 2.0

2.0 is ready only when all of the following are true:

- Home has one dominant comparison action.
- Continue Last Session works.
- two videos are selected in one picker flow.
- Sync Setup is visually/functionally separated from the full Compare Workspace.
- A/B reference points remain precise and reliable.
- Compare Workspace is video-first.
- Side / Stack / Overlay switch directly and preserve timeline.
- all current playback/frame/loop/overlay features remain accessible according to entitlement.
- fullscreen works.
- iPad landscape has a dedicated workspace layout.
- Quick Export works and cannot bypass access control.
- major preferences are remembered.
- existing 1.x sessions reopen.
- existing lifetime PRO purchases restore.
- trial-use count remains compatible.
- sample comparison remains free of trial consumption/history side effects.
- image/video export behavior remains correct.
- local-only/privacy behavior remains intact.
- English, Japanese, Korean are complete.
- accessibility checks pass.
- unit/UI regression tests pass.
- new App Store screenshots and 2.0 release copy match the final implementation.

---

## 21. 2.0 vs 3.0 boundary

The product roadmap boundary should remain explicit during implementation.

### KinePair 2.0

**Comparison experience is completed.**

The user chooses what to compare, chooses the matching moment, and makes the judgment. KinePair removes operational friction.

### KinePair 3.0 candidate direction

**Comparison work becomes assisted/automated.**

Possible future areas:

- automatic synchronization assistance
- pose/keypoint detection
- motion/point tracking
- automatic phase suggestions
- assisted measurement
- difference visualization derived from detected motion

None of these are prerequisites for 2.0 and they must not delay the UX redesign.

---

## 22. Final product rule

When making implementation decisions, prefer the option that satisfies this order:

1. Comparison video remains visible and large.
2. The next action is obvious.
3. Frequent actions take fewer interactions.
4. Existing user data and purchases remain safe.
5. Advanced controls remain available without dominating the interface.
6. iPhone and iPad use the same product logic but device-appropriate layouts.
7. New complexity is rejected unless it improves the core compare workflow.

The defining principle for KinePair 2.0 is:

> No-friction video comparison.
