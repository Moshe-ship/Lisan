#!/usr/bin/env bash
#
# Real-usage validation harness for Lisan.
#
# Drives the user through a structured validation session against the apps
# Lisan needs to work in (TextEdit, Notes, Terminal, iTerm2, Messages,
# Telegram if present). For each target app + language-mode combination,
# it opens the app, waits for the human to speak, captures a pass/fail
# judgment, and records the result in a timestamped markdown report.
#
# Usage:
#   ./scripts/validation-harness.sh
#   ./scripts/validation-harness.sh --out ~/Desktop/lisan-validation.md
#
# What this is NOT: a fully-automated test. Microphone input and
# human judgment of "did the Arabic come out right" cannot be scripted
# on macOS without stubbing the audio pipeline, which would defeat the
# point of real-usage validation. What this IS: a reproducible structure
# so every release has the same validation matrix and a shareable report.

set -euo pipefail

OUT="${HOME}/Desktop/lisan-validation-$(date -u +%Y%m%dT%H%M%SZ).md"
LISAN_APP="/Applications/Lisan.app"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    -h|--help)
      sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ ! -d "$LISAN_APP" ]; then
  echo "Lisan is not installed at $LISAN_APP" >&2
  echo "Download the latest release zip, mv Lisan.app /Applications, and retry." >&2
  exit 1
fi

# --- header ---
LISAN_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$LISAN_APP/Contents/Info.plist" 2>/dev/null || echo unknown)"
LISAN_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$LISAN_APP/Contents/Info.plist" 2>/dev/null || echo unknown)"
HOST_OS="$(sw_vers -productName) $(sw_vers -productVersion)"
HOST_ARCH="$(uname -m)"

cat > "$OUT" <<EOF
# Lisan validation session — $(date -u +%Y-%m-%d\ %H:%M:%SZ)

- Lisan version: \`$LISAN_VER\` (build \`$LISAN_BUILD\`)
- Host: \`$HOST_OS / $HOST_ARCH\`

## Method

For each target app below, the harness opens the app, the human brings
Lisan into focus via the hotkey, speaks a scripted utterance, and then
records pass/fail + observed transcript. Sessions should run with
Lisan's Language set to the indicated mode.

Scripted utterances:

- **English**: "Hello world, this is the validation harness, it is working."
- **Arabic**:  "مرحباً، هذا اختبار لسان، الكلام يظهر في التطبيق."
- **Mixed**:   "اكتب للفريق that the new Arabic cleanup layer is ready."

EOF

# --- apps to test ---
# bundle-id : display-name : open-command
declare -a TARGETS=(
  "com.apple.TextEdit|TextEdit|open -a TextEdit"
  "com.apple.Notes|Notes|open -a Notes"
  "com.apple.Terminal|Terminal|open -a Terminal"
  "com.googlecode.iterm2|iTerm2|open -a iTerm"
  "com.apple.MobileSMS|Messages|open -a Messages"
  "com.tdesktop.Telegram|Telegram|open -a Telegram"
  "com.anthropic.claudefordesktop|Claude|open -a Claude"
  "com.apple.Safari|Safari (address bar)|open -a Safari"
)

declare -a MODES=("Auto-detect:auto" "English:en" "Arabic:ar")

# --- matrix loop ---
echo "## Results" >> "$OUT"
echo "" >> "$OUT"
echo "| Target | Mode | Utterance | Insertion OK? | Transcript accuracy | Notes |" >> "$OUT"
echo "|--------|------|-----------|---------------|---------------------|-------|" >> "$OUT"

for target in "${TARGETS[@]}"; do
  bid="${target%%|*}"
  rest="${target#*|}"
  name="${rest%%|*}"
  cmd="${rest#*|}"

  # Check if the app is even installed; if not, record as N/A and skip.
  app_path=""
  for candidate in /Applications /System/Applications "$HOME/Applications"; do
    if [ -d "$candidate/$name.app" ]; then app_path="$candidate/$name.app"; break; fi
  done
  if [ -z "$app_path" ] && ! mdfind "kMDItemCFBundleIdentifier == '$bid'" | grep -q .; then
    for mode in "${MODES[@]}"; do
      mode_label="${mode%:*}"
      echo "| $name | $mode_label | (all) | N/A (app not installed) | — | skipped |" >> "$OUT"
    done
    continue
  fi

  for mode in "${MODES[@]}"; do
    mode_label="${mode%:*}"
    mode_code="${mode#*:}"

    # Utterance choice by mode: en -> English, ar -> Arabic, auto -> Mixed.
    case "$mode_code" in
      en)   utt="English" ;;
      ar)   utt="Arabic" ;;
      auto) utt="Mixed" ;;
    esac

    echo ""
    echo "=============================================="
    echo "  Testing $name / mode=$mode_label / $utt utterance"
    echo "=============================================="
    echo ""
    echo "1. Opening $name..."
    eval "$cmd" || { echo "   (could not open $name — continuing)"; }
    sleep 2
    echo ""
    echo "2. Set Lisan's Language picker to: $mode_label"
    echo "   (open Lisan settings, Language section, then come back here)"
    read -rp "   press Enter when Lisan is set and $name is focused..."
    echo ""
    echo "3. Bring focus to a text field in $name."
    echo "   Hold Option, speak the $utt utterance, release."
    read -rp "   press Enter when transcription completes..."
    echo ""
    echo "Rate this run:"
    read -rp "   Insertion OK? (y/n) " insert
    read -rp "   Transcript accuracy (good/partial/bad): " acc
    read -rp "   Notes (anything unusual, press Enter if none): " notes

    case "$insert" in
      y|Y|yes|YES) insert_cell="✅" ;;
      *)           insert_cell="❌" ;;
    esac

    echo "| $name | $mode_label | $utt | $insert_cell | $acc | ${notes:-—} |" >> "$OUT"
  done
done

# --- summary ---
{
  echo ""
  echo "## Summary"
  echo ""
  total="$(grep -c '^| ' "$OUT" || true)"
  header_rows=2
  fail_count="$(grep -c '❌' "$OUT" || true)"
  pass_count="$(grep -c '✅' "$OUT" || true)"
  echo "- Insertion PASS: $pass_count"
  echo "- Insertion FAIL: $fail_count"
  echo ""
  echo "Report saved to: \`$OUT\`"
  echo ""
  echo "Next steps: attach this report to any release PR, or share"
  echo "with the AI Saudi community if validating a new Arabic workflow."
} >> "$OUT"

echo ""
echo "Validation complete. Report: $OUT"
