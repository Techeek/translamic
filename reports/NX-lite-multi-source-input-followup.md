# Follow-up review — local workspace vs the two goals

**Date:** 2026-05-13
**Reviewer:** Claude (Opus 4.7)
**Base for diff:** working tree vs `origin/main`
**Comparison baseline:** the earlier review at [reports/NX-lite-multi-source-input-review.md](reports/NX-lite-multi-source-input-review.md) of `NX-lite/multi-source-input` (tip `ccf9b00`)

## Scope

The local workspace re-implements both branch goals (multi-source input with per-source language; single-instance enforcement) but with a substantially different design from what was pushed to `NX-lite/multi-source-input`. Notable structural shift: `LiveTranscriptionSession.swift` is **untouched** locally — the multi-source feature is now implemented at the `AppModel` layer by spinning up one session per source, instead of teaching the session to accept multiple capture inputs.

A new test file is also present: [Tests/V2STests/AppSettingsTests.swift](Tests/V2STests/AppSettingsTests.swift) covering legacy decode + round-trip.

## Verdict

**Both goals are reached.** All two blockers and all but one significant issue from the prior review are resolved. The remaining items are minor polish.

---

## Goal 1 — Multi-source input with per-source language selection

### B1 (per-source subtitle language was dead code) — **Resolved**

`QueuedCaption` now carries `sourceLanguageID` and `targetLanguageID`:

- [AppModel.swift:2840](Sources/V2SApp/App/AppModel.swift:2840) — struct gains both fields.
- [AppModel.swift:1641](Sources/V2SApp/App/AppModel.swift:1641) — `enqueueRecognizedSentence` accepts `source`, `sourceLanguageID`, `targetLanguageID` and stores them on the caption.
- [AppModel.swift:2392](Sources/V2SApp/App/AppModel.swift:2392) — `translatedText(for caption:)` uses `caption.sourceLanguageID` / `caption.targetLanguageID`.
- [AppModel.swift:1747](Sources/V2SApp/App/AppModel.swift:1747) — `translationExpected` test on refresh uses per-caption pair.
- [AppModel.swift:1964](Sources/V2SApp/App/AppModel.swift:1964) — `translationCoordinator.recoverSession` uses per-caption pair.

Draft translation gets the same treatment:

- [AppModel.swift:1313](Sources/V2SApp/App/AppModel.swift:1313) — `handlePartialDraft` accepts and stores `activeDraftSourceLanguageID`/`activeDraftTargetLanguageID`.
- [AppModel.swift:1430](Sources/V2SApp/App/AppModel.swift:1430) — `scheduleDraftTranslation` takes both languages as parameters; its post-await gate also checks `activeDraftSourceLanguageID == sourceLanguageID && activeDraftTargetLanguageID == targetLanguageID`, so a translation that returns after the user spoke into a different source is discarded rather than written into the wrong overlay.

Preview state also resolves: [AppModel.swift:1621](Sources/V2SApp/App/AppModel.swift:1621) — `makePreviewState(for:)` reads per-source input + output language for the sample text.

### B2 (one recognizer fed from multiple capture devices) — **Resolved**

`LiveTranscriptionSession.swift` is reverted to its single-source form (no diff vs `origin/main`). Multi-source is composed at the AppModel layer: [AppModel.swift:524](Sources/V2SApp/App/AppModel.swift:524) — `for source in selectedSources` creates one session per source, each with its own callbacks closing over the source's language pair. No more interleaved buffers into a shared `SFSpeechAudioBufferRecognitionRequest`.

Cleanup is correct: on success `liveTranscriptionSessions = startedSessions`; on throw, every `startedSessions` entry is `stop()`'d and both `liveTranscriptionSession`/`liveTranscriptionSessions` are nilled.

### S1 (per-source language resources not prepared) — **Resolved**

New collection function: [AppModel.swift:716](Sources/V2SApp/App/AppModel.swift:716) — `selectedResourcePreparationRequirements()` returns the set of distinct speech languages plus a deduplicated, sorted list of `LanguagePairRequirement(source, target)` across all selected sources (falling back to global input/output when nothing is selected).

[AppModel.swift:813](Sources/V2SApp/App/AppModel.swift:813) — `prepareSelectedLanguageResources` now iterates both lists and dispatches one `prepareSpeechRecognitionResourceIfNeeded` / `prepareTranslationResourceIfNeeded` task per entry. Missing models for an overridden language will now surface a prompt.

Trigger paths also broaden: [AppModel.swift:91–110](Sources/V2SApp/App/AppModel.swift:91) — both `sourceLanguageOverrides` and `sourceOutputLanguageOverrides` setters call `scheduleSelectedLanguageResourcePreparation(openSystemSettingsIfNeeded: true)` when the session isn't running, so editing an override prompts the same way as editing the global.

### S2 (`activeInputLanguageID` flicker) — **Resolved**

`activeInputLanguageID` and `currentSourceLanguageID` are gone. The single global that survived (`transcriptSourceLanguageID`) now falls back to `inputLanguageID` directly ([AppModel.swift:1788](Sources/V2SApp/App/AppModel.swift:1788)). Multi-language sessions no longer toggle a global as captions arrive.

Draft side is now coherent: the language pair is captured per draft (`activeDraftSourceLanguageID`/`activeDraftTargetLanguageID`) and both setting and consuming sites compare against the pair, so a stale draft from a different source short-circuits cleanly.

### S3 (dictionary-order session start) — **Resolved**

[AppModel.swift:524](Sources/V2SApp/App/AppModel.swift:524) iterates `selectedSources` directly. `selectedSources` is `allSources.filter { selectedSourceIDs.contains($0.id) }` ([AppModel.swift:223](Sources/V2SApp/App/AppModel.swift:223)) — `allSources` order, stable across runs.

### S4 (plural rules) — **Not addressed**

[AppLocalization.swift](Sources/V2SApp/Localization/AppLocalization.swift) still ships `multipleSourcesFormat = "%d Sources"` per language without plural rules. Russian (`%d источника`), Arabic (`%d مصادر`) are still grammatically wrong for some counts. Low impact; mention only because every other plural string in the file appears to use the same straight-format approach, so this is consistent with the rest of the codebase even if not ideal.

### Translation coordinator hardening (new, not in prior review)

Mixed source→target pairs across captions stress-test the coordinator. Two changes are visible:

- [AppModel.swift:3198](Sources/V2SApp/App/AppModel.swift:3198) — `activate(pair:)` refuses to switch pair while a runner is active. The previous logic cancelled pending operations on the old pair on every switch.
- [AppModel.swift:3099](Sources/V2SApp/App/AppModel.swift:3099) — after a runner exits, the coordinator auto-activates the next pending pair if one is waiting. Prevents starvation when alternating between pairs.
- [AppModel.swift:3215](Sources/V2SApp/App/AppModel.swift:3215) — `cancelPendingOperations(except:)` removed; pairs now coexist in the queue.

These changes look necessary to support the new workload but they're substantial in their own right. Worth a focused test pass that intentionally interleaves captions with different `(source, target)` pairs.

---

## Goal 2 — Single-instance enforcement

### M1 (PID-based termination without identity check) — **Resolved**

[AppDelegate.swift:223](Sources/V2SApp/App/AppDelegate.swift:223) — `terminateSingleInstanceLockOwnerIfNeeded` now reads structured `SingleInstanceLockMetadata { pid, identifier, path }` from the lock file, requires `NSRunningApplication(processIdentifier: pid)` to succeed, and gates termination on `matchesSingleInstanceIdentity(application, metadata:)` ([AppDelegate.swift:280](Sources/V2SApp/App/AppDelegate.swift:280)), which accepts either bundle-identifier match **or** resolved bundle-path match. PID recycling no longer kills the wrong process.

The `runningApplicationsForSingleInstance()` helper ([AppDelegate.swift:159](Sources/V2SApp/App/AppDelegate.swift:159)) also falls back to scanning `NSWorkspace.shared.runningApplications` by resolved bundle path when there's no bundle identifier (dev/unsigned builds), which is a nice belt-and-braces for the same identity question on the hand-off path.

### M3 (dead-looking branch when lockURL is nil) — **Resolved**

[AppDelegate.swift:24](Sources/V2SApp/App/AppDelegate.swift:24) — comment added explaining the fall-through: "If Application Support is unavailable we cannot keep a flock lock, but a best-effort handoff still avoids opening duplicate windows."

### M2, M5 — **Unchanged (acceptable)**

0.9 s synchronous wait on launch and best-effort force-terminate after 1.2 s remain as designed.

### Lock metadata format

[AppDelegate.swift:217](Sources/V2SApp/App/AppDelegate.swift:217) now serialises metadata via a joined array and reads it back with explicit `pid=` / `identifier=` / `path=` prefixes ([AppDelegate.swift:240](Sources/V2SApp/App/AppDelegate.swift:240)). Resolves the `path=` line being unparseable if the path itself contained `=` (the original code stopped at the first `=` per line).

---

## Smaller items from the prior review

| Item | Status |
|------|--------|
| `AppSettings.init` lacks defaults for new fields | **Resolved** — new fields have `= []` / `= [:]` defaults at [AppSettings.swift:57–60](Sources/V2SApp/Models/AppSettings.swift:57). |
| `selectedSourceIDs.sorted().first` tie-break is alphabetical | **Resolved** — `preferredPrimarySourceID(for:)` at [AppModel.swift:700](Sources/V2SApp/App/AppModel.swift:700) prefers the current `selectedSourceID` if still in the set, otherwise the first in `allSources` order (user-visible order). |
| `catch` cleanup double-stop | **Resolved** — single path: stop each `startedSessions`, then `liveTranscriptionSession = nil; liveTranscriptionSessions.removeAll()`. |
| Sequential permission prompts in multi-source start | **Unchanged** — still sequential since sessions are started serially. Minor UX nit. |
| `SourceMultiSelectPicker` menu auto-closes on each toggle | **Unchanged** — same `Menu`-with-buttons approach as the branch. |

## New surface to spot-check

- [Tests/V2STests/AppSettingsTests.swift](Tests/V2STests/AppSettingsTests.swift) — covers legacy `selectedSourceID` → `selectedSourceIDs` migration and round-trip of all three new fields. Good. No test yet for: language-resource preparation deduplication across overlapping `(source, target)` pairs; the new coordinator queueing behaviour when alternating pairs.
- `orderedSelectedSourceIDs()` ([AppModel.swift:707](Sources/V2SApp/App/AppModel.swift:707)) preserves `allSources` order in persisted settings, then appends any IDs not in `allSources` (e.g., a disconnected source the user previously selected) sorted alphabetically. Persists a sensible recovery state.

## Bottom line

- Goal 1 (multi-source + per-source language): the implementation is now correctly wired end-to-end — recognizers per source, captions carry their own language pair, translation pipeline reads from the caption, resource preparation covers all overrides, and there is no flickering global active-language. All blockers from the prior review are gone.
- Goal 2 (single-instance): identity-checked termination closes the only blocking concern. The rest of the design (flock + DistributedNotification handshake with PID-ACK arbitration) is intact and reads correctly.

Recommended before merge:
1. Build and run the test target (the new `AppSettingsTests` were not exercised in this review).
2. Manual smoke test of two simultaneous sources with different `(input, output)` language pairs, watching for: correct per-caption translation, no draft cross-contamination, language-resource prompts firing once per missing override.
3. Manual smoke test of double-launch on a signed build to confirm the bundle-identifier path in `matchesSingleInstanceIdentity`.

No remaining blockers identified.
