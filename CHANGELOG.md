# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-04-18

Four post-v0.2.3 reviewer improvements, delivered in one release.

### Added

**Product telemetry (content-leak-proof by types)**
- New `StenoKit/Services/DiagnosticsTelemetry.swift`: an actor-backed,
  file-persisted ring buffer of `DiagnosticEvent`s. The event enum is
  a closed sum type — every payload is a bounded enum or a sanitized
  controlled string (`TargetBundleID`, `PathKind`). There is no case
  that accepts free-form text. Transcript content, audio buffers, and
  vocabulary-file contents cannot be logged through this API; you would
  have to change the type definition to do it.
- Covered categories: startup failures, insertion failures, model-not-
  found, engine errors, permission denials, config validation errors,
  notarization mismatch.
- `FileDiagnosticsStorage` appends JSON-lines to
  `~/Library/Application Support/Lisan/diagnostics.jsonl`, capacity-
  capped at 200 events in-memory.
- New `Steno/DiagnosticsSettingsSection.swift`: Settings → Diagnostics
  view with per-event summary, category icons, copy-for-support button,
  and clear-all. Empty state reassures the user that nothing sensitive
  is collected.
- 13 new tests covering record/read/clear, capacity FIFO, bundle-id
  sanitization (rejects spaces, Arabic, emoji, HTML, truncates at 128),
  home-directory redaction in `PathKind`, file round-trip, corrupt-line
  resilience, Codable round-trip, and a type-level content-leak invariant
  that lists every existing case so a new one without a sanitized payload
  can't slip in unreviewed.
- `DictationController` wires one initial telemetry callsite (hotkey
  registration failure) to prove the end-to-end; more sites will be
  wired as we instrument the pipeline.

**Latency benchmark**
- New `scripts/benchmark-latency.sh`: measures whisper-cli wall-clock
  time per `(model, language-mode)` combination across N runs, emits
  markdown + JSON reports with p50 / p95 / min / max. Answers "how fast"
  without claiming to answer "how accurate" — accuracy lives in
  StenoBenchmarkCLI. Reference run on JFK sample / ggml-base / 3 runs
  shows ~585 ms p50 across en / ar / auto (language hint has no latency
  cost, only accuracy implications).

**Real-usage validation harness**
- New `scripts/validation-harness.sh`: drives a reproducible validation
  pass across TextEdit, Notes, Terminal, iTerm2, Messages, Telegram,
  Claude, Safari — three language modes each — and records human
  pass/fail into a timestamped markdown report. Honestly manual
  (microphone + human judgment can't be scripted) but the structure is
  the audit artifact.

**Bilingual splitter: URL / email / hashtag / mention awareness**
- `BilingualSentenceSplitter.classify` now strips URL, email, hashtag,
  and `@mention` runs before counting Latin letters, so an Arabic
  sentence with one embedded URL doesn't flip to `.mixed`.
- `BilingualSentenceSplitter.split` now treats `.` as a sentence
  terminator only when followed by whitespace or end-of-string.
  URLs (`lisan.app`), emails (`mousa@example.com`), and decimals (`2.5`)
  stay in a single chunk. 6 new tests cover these cases plus the
  "URL-only content is `.other`, not `.english`" edge case.

**Four more vocabulary packs**
- `packs/saudi-government.txt` — Absher, Tawakkalna, SFDA, ZATCA, SDAIA,
  MISA, Vision 2030, NEOM, Qiddiya, Diriyah, Roshn, Misk, etc.
- `packs/medical-arabic.txt` — specialties, conditions, procedures,
  anatomy, common clinical phrases.
- `packs/tech-bilingual.txt` — Kubernetes, GraphQL, LLM / embedding /
  RAG / quantization / MLX / whisper.cpp, and Arabic AI terminology.
- `packs/islamic-terms.txt` — greetings, prayer times, surah names, the
  short Juz Amma surahs, core Islamic concepts (iman, taqwa, sabr, etc).
- `packs/README.md` updated to list the full 10-pack catalog.

### Tests
198/198 passing (was 179).

### Migration notes
- Existing preferences.json is forward-compatible.
- `DiagnosticsTelemetry` lazy-creates its file on first use; no
  migration needed.
- Splitter API shape unchanged; callers see improved classification
  with no code changes.

## [0.2.3] - 2026-04-17

### Added
- `scripts/lint-logging.sh` — enforces `LOGGING_POLICY.md` by grepping for
  Logger / `print` / `NSLog` calls that reference user-content variable
  names (text, phrase, vocabulary, lexicon, transcript, prompt, audioURL,
  etc.) without `privacy: .private` or `.sensitive`. Also bans `NSLog`
  entirely (no privacy API).
- CI lint job: `.github/workflows/swift-tests.yml` now runs
  `scripts/lint-logging.sh` on every push and PR. Logging policy
  violations fail the build.
- Install-smoke job added to `.github/workflows/verify-release.yml`:
  after the six security gates pass, the job copies the released
  `Lisan.app` into `/Applications`, sanity-checks the bundle structure,
  verifies Info.plist fields (bundle ID, CFBundleName, mic usage
  description), confirms codesign TeamIdentifier + Identifier match
  expected values, launches the binary for 3 seconds to exercise dyld
  + hardened runtime + notarization ticket loading without requiring
  interactive TCC approval, and checks bundle size stays within bounds
  (500KB–50MB) so a future accidental model bundle blows the smoke,
  not the user's disk.
- End-to-end automated release pipeline: the 5 secrets required by
  `.github/workflows/release.yml` are now configured on the repo
  (`APPLE_DEVELOPER_ID_P12_BASE64`, `APPLE_DEVELOPER_ID_P12_PASSWORD`,
  `APPLE_NOTARY_APPLE_ID`, `APPLE_NOTARY_PASSWORD`,
  `APPLE_NOTARY_TEAM_ID`). Pushing a `v*` tag now triggers a full
  build → sign → notarize → staple → package → publish cycle on
  `macos-latest` without any local action.

### Renamed
- `Steno/Steno.debug.entitlements` → `Steno/Lisan.debug.entitlements`
- `Steno/Steno.release.entitlements` → `Steno/Lisan.release.entitlements`
- `project.yml` and `scripts/package-release.sh` reference the new paths.
- Deeper renames (Xcode target `Steno` → `Lisan`, source dir `Steno/` →
  `Lisan/`, scheme, `Contents/MacOS/Steno` → `Contents/MacOS/Lisan`)
  intentionally deferred — they break the upstream-merge lane with
  `Ankit-Cherian/steno`. Planned for v0.3.0 as a dedicated rename release
  with a migration note.

### Migration notes
No preferences schema or behavior changes. Projects that included
`Steno/Steno.*.entitlements` in a script need to update the path to
`Steno/Lisan.*.entitlements`.

## [0.2.2] - 2026-04-17

### Security
- Logger subsystems renamed from `io.stenoapp.*` to `io.lisanapp.*` so log
  attribution matches the app identity. Privacy qualifiers (`.private` on
  paths, `.public` on counts) preserved.
- Entitlements split into `Lisan.debug.entitlements` and `Lisan.release.entitlements`
  with per-configuration wiring in `project.yml`. Debug-only signing
  relaxations can no longer leak into Release builds.
- Release entitlements unchanged (still `device.audio-input` only).

### Added
- `RELEASE_VERIFICATION.md` — six-command post-release audit cycle.
- `LOGGING_POLICY.md` — what Lisan is allowed to log, what it never logs,
  OSLog subsystem map, audit grep.
- `SMOKE_TEST.md` — seven-item post-install behavior checklist.
- `.github/workflows/verify-release.yml` — CI job downloads the latest
  release asset and runs the six gates on every `release: published`.
- `.github/workflows/release.yml` — documented secrets-gated release
  pipeline (build → sign → notarize → staple → package → publish).

### Changed
- `THIRD_PARTY_NOTICES.md` now explicitly credits upstream Steno and
  Ankit Cherian's MIT license alongside whisper.cpp.
- `LICENSE` carries both copyright lines (Lisan fork + upstream Steno).

### Migration notes
No preferences schema changes from v0.2.1. Console.app filters previously
set against `io.stenoapp.*` should be updated to `io.lisanapp.*`.

## [0.2.1] - 2026-04-17

### Security
- Production-distribution-grade release: Developer ID Application signing
  (Team `VSL9H2F2D3`), Apple-notarized with ticket stapled, hardened
  runtime, timestamped. `spctl -a -vv` reports
  `accepted, source=Notarized Developer ID`.
- Removed `com.apple.security.cs.allow-dyld-environment-variables`
  entitlement. Was inherited from upstream; allowed DYLD_* env injection
  which weakens the hardened runtime. Release entitlements reduced to
  `com.apple.security.device.audio-input` only.
- Release asset re-packaged with `ditto -c -k --sequesterRsrc --keepParent`
  so AppleDouble xattr metadata no longer scatters as `._*` companions
  inside the bundle on plain `unzip`. This was the bug in the first v0.2.1
  artifact that failed `codesign --verify --deep --strict` on reviewers'
  machines.
- `scripts/package-release.sh` codifies the full build → sign → notarize
  → staple → package flow with a mandatory self-verify pass before
  emitting the zip. Packaging regressions now fail the build, not the
  audit.

### Changed
- `LaunchAtLoginService` inspects `SMAppService.mainApp.status` on failure
  and surfaces actionable errors (`.requiresApproval` → open Login Items
  pane; `.notFound` → install in `/Applications`). Previously just the
  opaque `Operation not permitted`.

### Migration notes
First release signed with Developer ID. Upgrading from v0.2.0 triggers
one re-prompt for Microphone / Accessibility / Input Monitoring because
the signing identity changed. Future rebuilds signed with the same cert
preserve TCC grants.

## [0.2.0] - 2026-04-17

### Added
- Arabic cleanup layer in StenoKit:
  - `BilingualSentenceSplitter` tags chunks `.arabic` / `.english` /
    `.mixed` / `.other` by Unicode letter ratio.
  - `ArabicNormalizer` — toggleable transforms (harakat, tatweel, alef,
    ya, ta marbuta, waw-hamza, digit conversion). Ported from Aamil's
    `ArabicSearchNormalizer`, re-scoped for dictation.
  - `ArabicPunctuator` — ASCII `,` `;` `?` → Arabic `،` `؛` `؟` inside
    Arabic chunks only; English chunks untouched.
  - `BilingualCleanupEngine` wraps base `CleanupEngine`, routes per-chunk.
    Fast-paths to base when no Arabic detected (zero English-only cost).
- Vocabulary pack loader accepts a directory; reads every `.txt`
  alphabetically, dedupes, joins with spaces. `#` comments ignored.
- Six seed packs in `packs/`: `msa-business`, `khaleeji-common`,
  `shami-common`, `saudi-places`, `gcc-brands`, `agency-bilingual`.
- Arabic settings section with live preview, grouped toggles (always-safe
  vs advanced), and digit-mode picker.
- Language-mode picker copy rewritten so users understand Auto picks one
  language per recording, not per word.

### Changed
- Full Steno → Lisan rename of user-facing strings: menu bar, onboarding,
  permissions panel, window title, `CFBundleName`, `CFBundleDisplayName`,
  mic usage description. Internal identifiers (StenoKit Swift package,
  target name, source directory) preserved.

### Tests
- 179/179 passing. 74 new tests across the Arabic layer + vocab loader.

### Migration notes
First Lisan release forked from Steno. Preferences schema adds
`dictation.languageMode`, `dictation.vocabularyFilePath`,
`dictation.bilingualCleanupEnabled`, `dictation.arabicOptions`, and
`dictation.arabicPunctuationEnabled` — all with backwards-compatible
defaults via `decodeIfPresent`.

## [0.1.10] - 2026-03-17

### Changed
- Settings cards now stretch to full width for consistent alignment across all sections.
- Replaced the insertion priority drag list with a grouped container using compact reorder controls and internal dividers.
- Cleanup style picker rows use fixed-width label columns for consistent alignment across all four pickers.
- Engine file-path fields use monospaced type with middle truncation for readability.
- Tightened spacing between entry rows in word corrections and text shortcuts.
- Grouped helper captions closer to their associated controls in recording and media sections.
- Added a divider above Save & Apply for clearer separation from settings content.
- Recording mic button now uses a two-ring staggered ripple pulse, a softer diffuse glow shadow, and a larger button size to better fill the Record tab.
- Mic button responds to presses with a spring scale-down for tactile feedback.
- Replaced the classic status-dot overlay with a waveform capsule featuring animated frequency bars, gradient fills, layered shadows, and SF Symbol icons for terminal states.
- Overlay auto-dismiss extended from 1.5 seconds to 2.0 seconds for better readability of result states.
- Overlay entrance uses staggered bar scale-up and a staged text fade for smoother first-show animation.
- Added a brief green background flash on successful text insertion for clearer confirmation feedback.
- Removed the non-functional expand/collapse chevron from history transcript rows; tap the text directly to expand or collapse.
- Global hands-free key picker now includes F1–F12 alongside the existing F13–F20 options, so MacBook users can assign their built-in function keys without an external keyboard.
- Hands-free key picker sections labeled by keyboard type with updated setup guidance.
- Onboarding feature tour now shows a generic hands-free setup tip instead of a hardcoded key name.

## [0.1.9] - 2026-03-11

### Changed
- Added a repository acknowledgment for `whisper.cpp` and a dedicated `THIRD_PARTY_NOTICES.md` file with the upstream MIT notice.

### Fixed
- Updated the in-app `Test Setup` check to launch `whisper-cli` with the same dynamic-library environment as real dictation, so local whisper.cpp builds validate correctly from Settings.
- Surfaced stderr when the setup check fails, making local whisper.cpp configuration errors easier to diagnose.

## [0.1.8] - 2026-03-11

### Changed
- Enabled whisper.cpp voice activity detection when a VAD model is available and kept the derived VAD model path aligned with the selected Whisper model.
- Surfaced VAD setup guidance in onboarding, settings, and setup docs so silence and background-noise suppression are easier to configure correctly.
- Balanced local cleanup now preserves intentional uses of "you know" while still removing filler cases and press-to-talk starts capture before optional media interruption to avoid clipping the first words.

### Fixed
- Added a no-speech session path and overlay state so empty captures do not insert junk text.
- Stripped known whisper artifact markers before insertion and history persistence.
- Tightened macOS main-actor shutdown, overlay, and MediaRemote callback paths to keep the app stable under Swift 6/Xcode concurrency analysis.

### Tests
- Added regression coverage for artifact stripping, no-speech gating, VAD flag forwarding/model-path sync, and contextual "you know" cleanup and ranking.

## [0.1.7] - 2026-03-03

### Changed
- Hardened hotkey lifecycle and shutdown behavior to avoid late callback execution during stop/quit, including idempotent teardown and eager overlay window warm-up.
- Updated synthetic event routing so insertion and paste remain configurable through `STENO_SYNTH_EVENT_TAP`, while media keys use a dedicated tap resolver with HID as the default.
- Improved subprocess execution reliability by streaming pipe output during process lifetime, adding cancellation escalation safeguards, and caching whisper process environment setup at engine initialization.
- Optimized local cleanup and replacement paths by precompiling reusable regexes, caching lexicon/snippet regexes with cache invalidation on mutation, and preserving longest-first lexicon ordering as an explicit invariant.
- Reduced history persistence overhead by removing pretty-printed JSON output formatting.

### Fixed
- Restored reliable media pause/resume behavior during dictation by routing media key posting through a dedicated HID-default tap path.
- Prevented event-tap re-enable thrash with debounce handling after timeout/user-input tap disable events.
- Added defensive teardown behavior for overlay timers and hotkey monitor resources during object deinitialization.
- Prevented potential deadlocks and cancellation stalls in process execution paths when child processes ignore graceful termination.

### Tests
- Added media key tap routing regression coverage for default, override, and invalid environment values.
- Hardened cancellation regression coverage to verify bounded completion when subprocesses ignore `SIGTERM`.

## [0.1.6] - 2026-03-03

### Added
- Added `Steno/Steno.entitlements` and wired entitlements via `project.yml` for microphone access and DYLD environment behavior needed by local `whisper.cpp` builds.
- Added `StenoKitTestSupport` as a dedicated package target for test doubles used by `StenoKitTests`.

### Changed
- Updated insertion transport internals to use private event source state, async pacing (`Task.sleep`), and best-effort caret restoration after accessibility insertion.
- Updated permission and window behavior paths to be more predictable on macOS 13/14+, including safer main-window targeting and refreshed input-monitoring recheck flow.
- Moved persistent storage fallbacks for preferences/history to `~/Library/Application Support` (instead of temp storage) and reduced path visibility in logs.
- Updated app activation and SwiftUI `onChange` call sites to align with modern macOS APIs.

### Fixed
- Audio capture now surfaces recorder preparation/encoding failures and cleans temporary files on early failure paths.
- MediaRemote bridge teardown now drains callback queue before unloading framework handles.
- Overlay status-dot color transitions now animate through Core Animation transactions and respect live accessibility display option updates.
- Improved lock/continuation safety documentation in cancellation-sensitive concurrency paths.

### Removed
- Removed dead `TokenEstimator` utility.
- Removed production-exposed test adapter definitions from `StenoKit` main target and relocated them to `StenoKitTestSupport`.

## [0.1.5] - 2026-02-28

### Added
- Refreshed macOS app icon artwork in `Steno/Assets.xcassets/AppIcon.appiconset`.

### Changed
- Pivoted cleanup to local-only. Steno now runs transcription and cleanup fully on-device with no cloud cleanup mode.
- Removed API key onboarding/settings flow and cloud-mode status messaging to simplify setup and avoid mixed local/cloud behavior.
- Settings now use a draft-and-apply flow to avoid mutating preferences during view updates.
- Press-to-talk now attempts media interruption before starting audio capture.

### Fixed
- Media interruption detection now requires corroborating now-playing data before trusting playback-state-only signals. This prevents false `notPlaying` decisions when MediaRemote returns fallback state values with missing playback rate (including browser `Operation not permitted` probe paths).
- Weak-positive playback signals now require a short confirmation pass before sending play/pause, reducing phantom media launches when no audio is active.
- Preserved unknown-state safety behavior so playback control is skipped when media state is not trustworthy.

### Removed
- OpenAI cleanup integration (`OpenAICleanupEngine`) and remote cleanup wiring (`RemoteCleanupEngine`).
- Cloud budget and model-tier plumbing (`BudgetGuard`, cloud cleanup decision types, and cloud-only tests).

### Breaking for StenoKit Consumers
- `CleanupEngine.cleanup` removed the `tier` parameter.
- `CleanTranscript` removed `modelTier`.
- Cloud cleanup engines and budget types were removed from the package surface.

### Notes
- This release consolidates the media interruption hotfix work and local-only cleanup pivot into one tagged release (`v0.1.5`).

## [0.1.2] - 2026-02-23

### Added
- First-pass macOS app icon set in `Steno/Assets.xcassets/AppIcon.appiconset` with a stenography-inspired glyph

### Removed
- Tracked generated Xcode project files (`Steno.xcodeproj/*`) from source control

## [0.1.1] - 2026-02-21

### Added
- Benchmark tooling in `StenoKit` via `StenoBenchmarkCLI` and `StenoBenchmarkCore` (manifest parsing, run orchestration, scoring, report generation, and pipeline validation gates)
- Local cleanup candidate generation and ranking (`RuleBasedCleanupCandidateGenerator`, `LocalCleanupRanker`, and `CleanupRanking`)
- Polished README screenshots (`assets/record.png`, `assets/history.png`, `assets/settings-top.png`, and `assets/settings-bottom.png`)

### Changed
- Rule-based cleanup flow now integrates ranking-focused post-processing refinements for better transcript quality
- Onboarding and settings screens use clearer plain-language copy for first-run setup and configuration
- `README.md`, `QUICKSTART.md`, and `CONTRIBUTING.md` were reworked for clearer user and contributor onboarding

### Fixed
- Balanced filler cleanup preserves meaning-bearing uses of "like"
- Media interruption handling avoids phantom playback launches from stale/weak-positive playback signals

### Removed
- Security audit workflow and related badge from repository CI/docs

### Tests
- Expanded benchmark validation tests for scorer/report/pipeline gates
- Added cleanup accuracy and ranking behavior coverage
- Added media interruption regression coverage for stale signal handling
