# Review — `NX-lite/multi-source-input`

**Date:** 2026-05-12
**Reviewer:** Claude (Opus 4.7)
**Branch:** `NX-lite/multi-source-input` (tip `ccf9b00`, 2 commits ahead of `main`)
**Diff size:** 10 files, +614 / −68

## Stated goal

The branch is two stacked features in one PR:

1. **Multi-source input with per-source language selection.** Allow several audio inputs to run at once; group sources by recognition language so each `LiveTranscriptionSession` instance handles all sources sharing one language ("reduces overhead and avoids recognition conflicts"). Each source gets its own input-language and subtitle-language picker.
2. **Single-instance enforcement.** A second app launch detects the running instance via a flock-backed lock file, asks it to come forward through `DistributedNotificationCenter`, waits ~900 ms for ACK, and either quits itself or force-terminates the stale process and retakes the lock.

## Verdict

**Do not merge as-is.** The single-instance work is solid with minor polish needed. The multi-source feature ships a UI control (per-source subtitle language) that is wired to storage but **never read by the translation pipeline**, and the "group multiple sources into one recognizer" design feeds interleaved buffers from independent capture devices into a single `SFSpeechAudioBufferRecognitionRequest`, which is not how Apple's recognizers expect to be driven.

Two correctness issues are blockers (B1, B2). The rest are quality concerns worth fixing before merge.

---

## Blocker findings

### B1. Per-source subtitle (output) language is dead code

[AppModel.swift:249](Sources/V2SApp/App/AppModel.swift:249) defines `outputLanguageIDForSource(_:)`, and [SettingsView.swift:477+](Sources/V2SApp/UI/Settings/SettingsView.swift:477) renders a per-source subtitle picker that calls `setOutputLanguageID(_:for:)`. The override is persisted in `AppSettings.sourceOutputLanguageOverrides`. But **no caller ever reads `outputLanguageIDForSource`** outside the UI binding. The translation pipeline always uses the global `outputLanguageID`:

- Draft translation target: [AppModel.swift:1361](Sources/V2SApp/App/AppModel.swift:1361) — `let targetID = outputLanguageID`
- Committed-caption translation: [AppModel.swift:1845](Sources/V2SApp/App/AppModel.swift:1845) — `target: outputLanguageID`
- Transcript target language: [AppModel.swift:1671](Sources/V2SApp/App/AppModel.swift:1671)

**Effect:** the user can pick a different subtitle language per source in Settings; nothing changes. This is worse than not shipping the picker — it silently mis-promises a feature.

**Fix sketch:** either (a) remove the per-source subtitle picker (and the storage/migration around it) until translation routing is implemented; or (b) thread `sourceLanguageID` from `enqueueRecognizedSentence` through caption enqueueing so the translation target is `outputLanguageIDForSource(sourceForCaption)` rather than the global. Option (b) likely requires `QueuedCaption` to carry a `sourceID` (or `targetLanguageID`) and the transcript model to support heterogeneous targets.

### B2. One recognizer fed from multiple capture devices

When two sources share a language they are grouped into one `LiveTranscriptionSession`. Inside that session:

- Each mic source spawns its own `AVCaptureSession` and adds it to `microphoneCaptureSessions` ([LiveTranscriptionSession.swift:677](Sources/V2SApp/Services/LiveTranscriptionSession.swift:677)).
- Each app source spawns its own `ApplicationAudioCapture` and appends to `applicationAudioCaptures` ([LiveTranscriptionSession.swift:708](Sources/V2SApp/Services/LiveTranscriptionSession.swift:708)).
- Both paths terminate in `append(audioBuffer:)` ([LiveTranscriptionSession.swift:822](Sources/V2SApp/Services/LiveTranscriptionSession.swift:822)), which forwards each buffer to a single shared `recognitionRequest.append(...)` or the SpeechAnalyzer continuation.

The `captureQueue` serializes the calls so there is no data race, but the recognizer receives frames in **arrival order across devices** with no mixing. From the recognizer's perspective the stream alternates between speakers/devices at packet granularity. Symptoms to expect:

- Dropped/garbled words at every device switchover.
- VAD onset/offset events from one source resetting silence timers for the other ([LiveTranscriptionSession.swift:836](Sources/V2SApp/Services/LiveTranscriptionSession.swift:836)).
- The audio converter signature cache (`preprocessingConverterInputSignature`, `audioConverterInputSignature`, `modernAudioConverterInputSignature`) will thrash because each source likely has a different sample rate/channel layout, forcing a converter rebuild every other buffer.
- Captions attributed to a `sourceLabel` that concatenates all source names — there is no per-utterance attribution.

The commit message claims this design "avoids recognition conflicts" — in practice it creates them. The previous design (one session per source) was strictly more correct.

**Fix sketch:** drop the grouping. Always create one `LiveTranscriptionSession` per source. The per-language-grouping micro-optimization was not buying anything except code complexity, and it actively destroys recognition quality. (The `start(sources:)` API can stay if you want, but only call it with single-element arrays.)

---

## Significant findings

### S1. Per-source language resources are not prepared

[AppModel.swift:709](Sources/V2SApp/App/AppModel.swift:709) — `scheduleSelectedLanguageResourcePreparation` only consults the global `inputLanguageID`/`outputLanguageID`. Setting a per-source override does not trigger `prepareSpeechRecognitionResourceIfNeeded` for that language, so a user who picks French for one source while the global is English may see a first-run failure when the French model is missing, with no "open System Settings" prompt.

**Fix:** loop over the distinct languages in `selectedSources.map(languageID(for:))` and prepare each.

### S2. `activeInputLanguageID` flickers under multi-language sessions

[AppModel.swift:489](Sources/V2SApp/App/AppModel.swift:489): `activeInputLanguageID = selectedLanguageIDs.count == 1 ? selectedLanguageIDs.first : nil` — multi-language case sets it to nil, falling back to global `inputLanguageID` via `currentSourceLanguageID` ([AppModel.swift:1658](Sources/V2SApp/App/AppModel.swift:1658)).

Then in both `enqueueRecognizedSentence` and `handlePartialDraft` ([AppModel.swift:1542,1255](Sources/V2SApp/App/AppModel.swift:1255)), every incoming caption/draft overwrites `activeInputLanguageID = sourceLanguageID`. With two languages active, every caption flips `currentSourceLanguageID`, which drives:

- `shouldReserveDraftTranslationSlot` ([AppModel.swift:1663](Sources/V2SApp/App/AppModel.swift:1663))
- Transcript header language ([AppModel.swift:1667](Sources/V2SApp/App/AppModel.swift:1667))
- Draft translation source language ([AppModel.swift:1360](Sources/V2SApp/App/AppModel.swift:1360))

so a caption arriving in one language will translate the *other* language's pending draft text against the wrong source. The bug is small in practice (most utterances finalize quickly) but real, and it surfaces obviously in transcript headers that toggle.

**Fix:** drop the global `activeInputLanguageID` for multi-language sessions; track per-source state in the caption queue and overlay state instead. Pairs with B1 (caption needs a source attribution to translate correctly anyway).

### S3. Dictionary-order session start

[AppModel.swift:520](Sources/V2SApp/App/AppModel.swift:520) — `for (langID, sources) in groupedSources` iterates a `Dictionary`, whose order is not stable. Captions thus arrive with nondeterministic latency ordering and the "first" session retained in `liveTranscriptionSession` ([AppModel.swift:557](Sources/V2SApp/App/AppModel.swift:557)) varies between runs. Probably not user-visible but makes bug reports harder.

**Fix:** sort the keys; or iterate `selectedSources` directly once B2 is addressed.

### S4. `multipleSourcesFormat` ignores plural rules

[AppLocalization.swift](Sources/V2SApp/Localization/AppLocalization.swift): `"multipleSourcesFormat": "%d Sources"` etc. The Russian entry (`"%d источника"`) is wrong for 1 / 5+ / 11+ forms, and Arabic has six plural categories. These should be `.stringsdict` plural rules or a hand-rolled selector. Less important than the others but the existing localization infrastructure does pluralization properly elsewhere — this is a regression in localization quality.

---

## Single-instance enforcement — findings

The flock + DistributedNotification design is sound. The main flow is:
acquire lock → install observer → release on terminate. On second launch: try lock, if held → notify + wait 900 ms for ACK → quit self; if no ACK → terminate stale by PID, wait 2 s, retake lock.

### M1. PID-based termination is not identity-checked

[AppDelegate.swift:213](Sources/V2SApp/App/AppDelegate.swift:213) — `terminateSingleInstanceLockOwnerIfNeeded` reads the stored PID from the lock metadata, checks `kill(pid, 0) == 0`, and `SIGTERM`s it. The lock file *also* stores `identifier=` and `path=`, but those are never verified. If the PID has been recycled by macOS to an unrelated process between the previous v2s crash and this launch, v2s will kill the wrong process.

**Fix:** before calling `terminateExistingApplications` / `kill`, confirm `NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == singleInstanceIdentifier` or check the metadata's `path=` against `NSRunningApplication.bundleURL`. Bail out silently if the identity doesn't match.

### M2. 0.9 s synchronous wait on launch main thread

[AppDelegate.swift:113](Sources/V2SApp/App/AppDelegate.swift:113) — `RunLoop.current.run(mode: .default, before: ...)` is invoked from `applicationDidFinishLaunching`. Acceptable, but the user sees up to 0.9 s of dock-bounce/no-window before the second instance exits or proceeds. Worth considering whether `acknowledgedPID == nil` could be detected faster (e.g., 300 ms is usually plenty since the receiver is a local distributed notification).

### M3. Dead branch — or near-dead

[AppDelegate.swift:23](Sources/V2SApp/App/AppDelegate.swift:23) — the `else if singleInstanceLockDescriptor < 0, handOffToExistingInstanceIfPossible()` branch can only fire when `acquireSingleInstanceLock()` returned `true` *without* setting a descriptor, which only happens when `singleInstanceLockURL()` returned `nil` (Application Support unwritable). That's a real failure mode worth a comment so future readers don't read it as a bug. Today the code silently degrades to "no lock at all" if the directory is unwritable, which is probably the right trade — just label it.

### M4. Identifier sanitization

[AppDelegate.swift:158](Sources/V2SApp/App/AppDelegate.swift:158): builds a sanitized filename by mapping every non-`[A-Za-z0-9.-]` to `_`. Fine, but `singleInstanceIdentifier` falls back to `"local.\(executableName)"` only when bundle identifier is empty — that fallback is unreachable for a packaged macOS app and fine for dev builds.

### M5. Force-quit destroys in-flight work in the held instance

The hand-off path quits the new instance after the running instance ACKs (good). The fallback `terminateExistingApplications` (used when no ACK arrives) will `terminate()` and then `forceTerminate()` after 1.2 s. If the held instance is alive but momentarily blocked on the main thread (heavy transcript export, system permission prompt), the user will lose unsaved transcript state. Probably acceptable for the "I think it's frozen, let me restart it" use case but worth documenting in the commit message.

---

## Smaller items

- [AppSettings.swift:36](Sources/V2SApp/Models/AppSettings.swift:36) — legacy migration: `selectedSourceIDs` defaults to `[selectedSourceID]` when missing. Good. But the new `init(selectedSourceID:selectedSourceIDs:...)` no longer has a default for `selectedSourceIDs`, which is a source-breaking change for any test or future code constructing `AppSettings` literally. Acceptable given the only direct call site is `AppSettings.default`, but worth a default parameter to keep the call surface non-fragile.
- [AppModel.swift:455](Sources/V2SApp/App/AppModel.swift:455) — `selectedSourceIDs.sorted().first` is used as the "primary source" tiebreak. Sorting by string ID is arbitrary; if the legacy `selectedSourceID` is preserved this is rarely hit, but it's a surprising fallback (alphabetical, not selection order). Consider `selectedSources.first?.id` (uses `allSources` order, which is the order shown to the user).
- [AppModel.swift:540](Sources/V2SApp/App/AppModel.swift:540) — the `catch` path calls `stop()` on each started session **and** `stopLiveTranscriptionSessions()`. The latter already iterates `liveTranscriptionSessions`, which at that point is still empty (assignment happens only on success), so the per-session `stop()` loop is the only thing doing work. Tidy this up to one path.
- [LiveTranscriptionSession.swift:268](Sources/V2SApp/Services/LiveTranscriptionSession.swift:268) — `for source in sources { try await requestRequiredPermissions(for: source) }` is sequential. If multiple sources of different categories are picked, the user sees permission prompts one after another. Minor UX nit.
- [QuickSettingsControls.swift:60+](Sources/V2SApp/UI/Shared/QuickSettingsControls.swift:60) — `SourceMultiSelectPicker` uses a `Menu` that auto-closes on every selection, so picking multiple sources requires reopening the menu each time. Likely a regression in UX vs. a popover or list. SwiftUI workaround is `MenuStyle` + `Button`s that keep the menu open, or move to a popover; worth a usability pass.
- README quarantine snippet is unrelated to either feature in this branch and could ride a separate doc-only commit.

## Suggested merge order

1. Decide whether per-source subtitle language is in scope. If yes, implement caption-level target routing (B1) and gate B1+S2 together. If no, strip the picker, the `sourceOutputLanguageOverrides` field, and the localized rows.
2. Replace the grouped-recognizer design with one session per source (B2). This also unblocks S2's per-source state since each session naturally has one input language and one output language.
3. Address S1 (resource preparation across overrides) and S4 (plurals).
4. Land the single-instance commit separately with the M1 identity check and an M3 comment. It is otherwise good to ship.

## Files touched

| File | Concern level |
|------|---------------|
| [Sources/V2SApp/Models/AppSettings.swift](Sources/V2SApp/Models/AppSettings.swift) | Low — clean migration |
| [Sources/V2SApp/App/AppModel.swift](Sources/V2SApp/App/AppModel.swift) | High — B1, S1, S2, S3 |
| [Sources/V2SApp/Services/LiveTranscriptionSession.swift](Sources/V2SApp/Services/LiveTranscriptionSession.swift) | High — B2 |
| [Sources/V2SApp/UI/Settings/SettingsView.swift](Sources/V2SApp/UI/Settings/SettingsView.swift) | Medium — exposes broken control (B1) |
| [Sources/V2SApp/UI/Shared/QuickSettingsControls.swift](Sources/V2SApp/UI/Shared/QuickSettingsControls.swift) | Low — small UX nit |
| [Sources/V2SApp/UI/StatusBar/StatusBarPopoverView.swift](Sources/V2SApp/UI/StatusBar/StatusBarPopoverView.swift) | Low |
| [Sources/V2SApp/Localization/AppLocalization.swift](Sources/V2SApp/Localization/AppLocalization.swift) | Low — S4 plurals |
| [Sources/V2SApp/App/AppDelegate.swift](Sources/V2SApp/App/AppDelegate.swift) | Medium — M1 identity check |
| README.md / README.zh-CN.md | None — unrelated doc tweak |
