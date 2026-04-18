# Logging policy

Lisan processes voice and transcribed text. That means logs are a privacy
surface — careless logging could leak spoken content, file paths, or
identity-bearing state into Console.app and sysdiagnose archives.

This document defines what Lisan is allowed to log and how.

## Invariants (never broken by any contribution)

1. **Transcript text (raw or cleaned) is never logged at any level.**
   Not in `debug`, `info`, `notice`, `error`, `fault`, `print`, or `NSLog`.
2. **Audio file contents are never logged.** Paths to captured audio files
   may appear only with `privacy: .private` and only when surfacing errors.
3. **Vocabulary file contents are never logged.** The file path may appear
   with `privacy: .private` in error context only.
4. **Voice, audio, and transcript content never leave the device.**
   The only outbound HTTP Lisan makes is to Hugging Face
   (`huggingface.co/ggerganov/whisper.cpp/resolve/main/…`) when the
   user explicitly clicks **Download** on a whisper model in Settings
   → Engine. That request is a plain GET for a binary model file with
   no body, no query string, no cookies, no identifying headers
   beyond the standard URLSession user agent. No speech, no
   transcript, no settings, and no telemetry are ever transmitted.
   If additional network code is ever added, it MUST (a) be opt-in at
   the moment of use, (b) log only URL hosts and HTTP status, not
   bodies or paths, and (c) be documented in this file before merge.
5. **Personal paths (anything under `/Users/...`) default to `privacy: .private`.**
   `OSLog` then substitutes `<private>` in Console unless the user has
   explicitly enabled private-data logging on their Mac for debugging.

## Allowed logging

- State transitions (recording started, recording ended, insertion method used)
- Counts, durations, booleans (token counts, assertion counts, success flags)
- Error domains and `localizedDescription` from system errors
- Signing / notarization metadata surfaced by Apple APIs (already public)
- Permission states (granted / denied / requires-approval)

All allowed fields are marked `privacy: .public` only when they cannot
identify the user.

## Disallowed logging (review will reject)

- `Self.logger.debug("Transcript: \(raw.text)")` — NEVER
- `print(preferences.dictation.vocabularyFilePath)` — NEVER
- `logger.info("User said: \(cleanedText)")` — NEVER
- `logger.error("Audio at \(audioURL.path, privacy: .public)")` — use `.private`
- `logger.debug("Lexicon entry: term=\(term) preferred=\(preferred)")` — NEVER
  (lexicon entries can reveal employer names, client names, personal terms)

## Subsystems

Lisan uses two `OSLog` subsystems, both under the Lisan namespace:

| Subsystem | Source module | Category example |
|-----------|---------------|------------------|
| `io.lisanapp.lisan`     | app layer (`Steno/`)       | `AppPreferencesStore` |
| `io.lisanapp.stenokit`  | engine layer (`StenoKit/`) | `Diagnostics` |

Split kept so engine logs (reusable in a future CLI / embedding) can be
filtered independently from the GUI app's logs.

## Where logs go

- **No file-based logging.** Lisan does not write logs to disk. All
  logging goes through `OSLog`, which the system manages under its
  standard privacy rules.
- **Console.app** shows logs if the user has enabled "Include Debug
  Messages" or launched Console with admin privileges.
- **sysdiagnose** archives may capture Lisan logs. Anything we log CAN
  end up in a support bundle shared with Apple. That is the bar every
  log line must meet.

## Audit script

```bash
# Any new log line must survive this grep:
grep -rnE "print\(|NSLog\(|logger\.(debug|info|notice|error|fault)" \
    Steno/ StenoKit/Sources/ \
  | grep -vE "privacy: \.(private|sensitive|public)"
```

Public values without a `privacy:` qualifier are allowed ONLY when the
value is a compile-time string literal or a constant that cannot contain
user data (e.g., `"Session started"`).

## CI check (future)

A `lint-logging.sh` script can be wired into CI to flag any new log call
that references `raw.text`, `text:`, `phrase`, `vocabulary`, `lexicon`,
`transcript`, or `prompt` without `privacy: .private`.

## On-disk retention

Lisan writes two local files under `~/Library/Application Support/`:

| File | Contents | Retention | Permissions |
|---|---|---|---|
| `Steno/transcript-history.json` | `rawText` + `cleanText` per dictation | 30 days (pruned on every append) OR disabled via Settings → General → Save transcript history | `0600`, excluded from iCloud/Time Machine backup |
| `Lisan/diagnostics.jsonl` | Closed sum-type event records (no transcript content) | Hard cap of 1000 lines on disk; rotates to 500 when exceeded | `0600` |

Users can disable transcript persistence entirely; the file is removed
when the toggle flips off, and entries live only in memory for that
session. Diagnostics file retention is bounded regardless of user
setting since the events themselves contain no content.

## History

- 2026-04-17 — Policy established. All existing calls audited: no
  transcript / audio / vocabulary content logged. Paths are `.private`.
  Counts and state booleans are `.public`.
- 2026-04-18 — Updated section 4 to reflect the v0.3.6+ model downloader
  (user-initiated GET of whisper model binaries from Hugging Face; no
  speech or user data transmitted). Added on-disk retention table
  documenting `transcript-history.json` 30-day retention +  `0600`
  permissions + backup exclusion, and `diagnostics.jsonl` 1000-line
  hard cap with rotation to 500.
