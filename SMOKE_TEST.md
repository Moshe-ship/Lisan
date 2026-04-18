# Smoke test checklist

Green security gates (see `RELEASE_VERIFICATION.md`) prove the binary
is trustworthy. This document proves the binary actually **works** —
that a user who downloads it, installs it, grants permissions, and
holds the hotkey gets real text on their screen.

Every release must pass all 7 items below on a clean Mac (or after
revoking previous TCC grants via `tccutil reset All io.lisanapp.lisan`).

## Prereqs

- Fresh macOS 13+ install or `tccutil reset All io.lisanapp.lisan`
- Network to download the release zip once
- Microphone present (internal or external)

## 1. Install from release asset

```bash
cd "$(mktemp -d)"
gh release download v0.3.0 --repo Moshe-ship/Lisan --pattern "Lisan-v0.3.0.zip"
unzip -q Lisan-v0.3.0.zip
mv Lisan-v0.3.0/Lisan.app /Applications/
mkdir -p ~/vendor
ln -sf "$(pwd)/Lisan-v0.3.0/vendor/whisper.cpp" ~/vendor/whisper.cpp
```

✅ PASS when: `/Applications/Lisan.app` exists and `~/vendor/whisper.cpp/build/bin/whisper-cli` resolves.

## 2. First launch opens cleanly

```bash
open /Applications/Lisan.app
```

✅ PASS when:
- No Gatekeeper dialog ("Apple cannot verify this developer")
- No crash on launch
- Onboarding window appears showing "Lisan" in window title and Dock

## 3. Microphone permission prompt

Click through onboarding until the Permissions screen, click "Grant" next to Microphone.

✅ PASS when:
- macOS native dialog appears asking for Microphone access
- After clicking OK, pill flips from red ✗ to green ✓
- The Permissions screen description says "Lisan" (not "Steno")

## 4. Accessibility permission prompt

Click "Grant" next to Accessibility.

✅ PASS when:
- macOS opens System Settings → Privacy & Security → Accessibility
- Lisan is either auto-added or can be added via `+` / drag from /Applications
- After toggling on, the app's pill flips to green (may require quit + relaunch once)

## 5. Input Monitoring permission prompt

Click "Grant" next to Input Monitoring.

✅ PASS when:
- macOS opens System Settings → Privacy & Security → Input Monitoring
- Lisan appears or can be added
- After toggling on, pill flips to green

## 6. End-to-end dictation round trip

1. Open any text field (TextEdit new document, Notes, Messages)
2. Hold **Option** key
3. Say: "Hello world, this is a test."
4. Release Option

✅ PASS when:
- Transcription engine runs (waveform or status overlay appears briefly)
- The exact spoken English text appears in the focused field within ~1 second
- Word count reasonable (no hallucinated filler)

### Arabic round trip

1. Settings → Language → **Auto-detect**
2. Focus a text field
3. Hold Option, say: "مرحباً هذا لسان"
4. Release

✅ PASS when:
- Arabic text appears in the field (not garbage English phonemes)
- Arabic punctuation convention applied (if a `?` was emitted, it should be `؟`)

## 7. Settings persistence

1. Settings → Arabic → toggle "Fold teh marbuta" ON
2. Click **Save & Apply**
3. Quit Lisan (Cmd+Q)
4. Relaunch `/Applications/Lisan.app`
5. Go back to Settings → Arabic

✅ PASS when:
- "Fold teh marbuta" is still ON (preference survived restart)
- Live preview reflects that setting

## Reporting

If any step fails:
1. Grab the exact step number that failed
2. Capture the relevant Console.app output filtered on subsystem `io.lisanapp.lisan` (see `LOGGING_POLICY.md` for allowed content)
3. Open a GitHub issue at https://github.com/Moshe-ship/Lisan/issues with:
   - macOS version (`sw_vers -productVersion`)
   - Lisan version (About window, or `mdls -name kMDItemVersion /Applications/Lisan.app`)
   - Step that failed and what you saw instead
   - Optional: Console excerpt (no transcript content — per logging policy there should be none in logs anyway)

## Automated hook (future)

A Swift Testing target running against the built app bundle can automate
steps 1, 2, and 7. Steps 3–6 require real microphone + human speech and
are intentionally manual for now.

## History

- 2026-04-17 — Checklist created for v0.3.0. All 7 items pass locally on macOS 26.3 with a fresh notarized install.
