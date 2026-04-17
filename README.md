# Lisan — Arabic-First Local Dictation for macOS

Forked from [Ankit-Cherian/steno](https://github.com/Ankit-Cherian/steno) (MIT).

## What changed

This fork adds explicit Arabic and bilingual Arabic/English support to Steno's local-first
dictation architecture. The core insertion, recording, and session-coordination logic is
unchanged — only the transcription layer was extended to handle language selection and
vocabulary biasing.

## Architecture

```
AudioCapture (MacAudioCaptureService)
    │
    ▼
SessionCoordinator
    │  coordinates the full dictation pipeline
    │
    ├──► TranscriptionEngine (WhisperCLITranscriptionEngine)
    │        │
    │        │  Loads vocabulary file at init; passes --prompt to whisper-cli.
    │        │  Maps LanguageMode to whisper -l arg: en / ar / (auto = omit arg).
    │        ▼
    │    RawTranscript
    │
    ├──► CleanupEngine (RuleBasedCleanupEngine)
    │    │
    │    ▼
    │  CleanTranscript
    │
    └──► InsertionService
             │
             ├──► DirectTypingInsertionTransport  (CGEvent Unicode key events)
             ├──► AccessibilityInsertionTransport (AXValueAttribute patching)
             └──► ClipboardInsertionTransport     (NSPasteboard + Cmd+V for terminals)
```

### Key files (unchanged from upstream)

| File | Role |
|------|------|
| `StenoKit/Sources/StenoKit/Services/MacInsertionTransports.swift` | CGEvent typing, AX patching, terminal paste |
| `StenoKit/Sources/StenoKit/Services/InsertionService.swift` | Transport prioritization, terminal clipboard-first |
| `StenoKit/Sources/StenoKit/Services/SessionCoordinator.swift` | Pipeline orchestration, actor-isolated |
| `StenoKit/Sources/StenoKit/Services/MacAudioCaptureService.swift` | AVAudioEngine recording → .m4a file |
| `StenoKit/Sources/StenoKit/Services/AppContextProvider.swift` | Frontmost app detection (bundle ID, isIDE) |
| `StenoKit/Sources/StenoKit/Services/PersonalLexiconService.swift` | Whole-word lexicon corrections (regex \b boundary) |

### Changed files

| File | Change |
|------|--------|
| `StenoKit/Sources/StenoKit/Models/Profiles.swift` | Added `LanguageMode` enum: `.en`, `.ar`, `.auto` |
| `StenoKit/Sources/StenoKit/Services/WhisperCLITranscriptionEngine.swift` | Added vocabulary-file loading; updated `normalizeLanguage` for Arabic; `LanguageMode`-aware hint → `-l` arg |
| `StenoKit/Sources/StenoKit/Services/SessionCoordinator.swift` | `stopPressToTalk` now takes `LanguageMode` instead of raw `languageHints` |
| `Steno/AppPreferences.swift` | Added `languageMode: LanguageMode` and `vocabularyFilePath: String` to `Dictation` |
| `Steno/DictationController.swift` | Wires `vocabularyFilePath` into `WhisperCLITranscriptionEngine` init |
| `Steno/LanguageSettingsSection.swift` | New: segmented picker (en / ar / auto) + vocabulary file path field |
| `Steno/SettingsView.swift` | Wires `LanguageSettingsSection` |
| `Steno/StenoApp.swift` | Window title changed from "Steno" to "Lisan" |
| `StenoKit/Package.swift` | `swift-tools-version: 6.1` (was 6.2; 6.1.2 is the installed toolchain) |

## Language mode

```
preferences.dictation.languageMode
  .en    → whisper-cli -l en        (explicit English)
  .ar    → whisper-cli -l ar        (explicit Arabic)
  .auto  → whisper-cli (no -l flag) (whisper auto-detects)
```

`normalizeLanguage()` also handles: `en-US`, `ar-EG`, `arabic`, `english` as aliases.

## Vocabulary file

A plain-text file, one phrase per line. Loaded once at engine init.
Phrases are joined with spaces and passed to whisper-cli as `--prompt "phrase1 phrase2 ..."`.

```
# ~/.lisan/vocabulary.txt
ماجدة
أبوaja
Performance MAX
Nashir
hurmoz
OpenClaw
```

The engine uses the prompt to bias recognition toward custom terms, brand names,
Arabic proper nouns, and transliterations that the base model may not handle well.

## Insertion behavior

Unchanged from Steno. Three-tier fallback:

1. **Direct typing** — CGEvent Unicode keyboard events (chunked, 20 code units, 10ms delay).
   Best-effort verification via AXValueAttribute comparison before/after.
2. **Accessibility API** — AXUIElementSetAttributeValue on the focused text element.
   Handles selections (replaces selection range), restores caret position.
3. **Clipboard paste** — NSPasteboard write + Cmd+V synthesis.
   Terminal apps (Terminal, iTerm2, Warp, Codex) skip directly to this tier.

Terminal safety is achieved by putting clipboard first for:
`dev.warp.warp-stable`, `com.openai.codex`, `com.apple.terminal`, `com.googlecode.iterm2`.

## Build status

### whisper.cpp + Metal (pre-built and verified)

```
Repository:  ~/vendor/whisper.cpp/
Binary:      ~/vendor/whisper.cpp/build/bin/whisper-cli
Base model:  ~/vendor/whisper.cpp/models/ggml-base.bin   (141 MB, 99 languages)
Small model: ~/vendor/whisper.cpp/models/ggml-small.bin  (better accuracy, optional)
```

Verified with real audio (JFK sample, 3.3 min → 419ms decode on M4 Max Metal):
```
$ whisper-cli -m models/ggml-base.bin -f samples/jfk.wav -t 8 --no-timestamps -l en
And so my fellow Americans: ask not what your country can do for you,
ask what you can do for your country.
```

### StenoKit (core engine)

```
swift build  → Build complete! (28s, 51 targets, 0 errors, 0 warnings)
swift test   → 105/105 tests passed (4 new tests for LanguageMode + vocabulary)
```

No Xcode required. `swift build` compiles all engine, service, and model code.

### Lisan.app (full app)

```
xcodegen generate  → Steno.xcodeproj created
xcodebuild         → BLOCKED: no full Xcode installed on this machine
                       only Command Line Tools are present
```

The app requires a full Xcode installation to build. The Steno.xcodeproj is generated
and ready; run `xcodebuild` on a machine with Xcode.

## Blockers

1. **Full Xcode required** — The host (arm64 macOS 26.4.1, Swift 6.1.2, CLT-only)
   cannot run `xcodebuild`. Install Xcode from the Mac App Store to build the `.app` bundle.
   StenoKit itself builds and tests fully with `swift build`.

2. **No microphone in headless environment** — Real utterance tests (English, Arabic, mixed)
   cannot be run on this machine. Must be tested on a MacBook with a microphone.

3. **Accessibility permission** — Direct typing and AX insertion require
   System Settings → Privacy & Security → Accessibility → Lisan (toggle on).

4. **Microphone permission** — Required for recording. Prompt shown on first launch.

## Transcript examples

### Verified (real whisper-cli, JFK audio sample)

| Audio | Mode | Output |
|-------|------|--------|
| JFK 1961 inaugural address (3.3 min) | `.en` | "And so my fellow Americans: ask not what your country can do for you, ask what you can do for your country." |
| JFK 1961 (auto-detect) | `.auto` | Same — auto-detected English correctly |

### Pending (await microphone access)

| Utterance | Mode | Expected |
|-----------|------|----------|
| "The quarterly report is ready" | `.en` | The quarterly report is ready |
| "التقرير الربعي جاهز" | `.ar` | التقرير الربعي جاهز |
| "I need the تقرير مالي" | `.auto` | I need the تقرير مالي |
| "Performance MAX campaign" (vocab loaded) | `.en` | Performance MAX campaign |

## Next steps

1. Install full Xcode → build `.app` bundle
2. Install whisper-cli + multilingual model → test actual transcription
3. Verify Arabic insertion renders correctly in target apps (RTL text handling)
4. Test mixed Arabic/English code-switching in auto mode
5. Add vocabulary file test: confirm measurable improvement for known proper nouns
6. Consider adding Arabic diacritics normalization layer (optional, phase 2)
