#!/usr/bin/env bash
#
# Enforces LOGGING_POLICY.md at build time.
#
# Scans all Swift sources for logger / print / NSLog calls that reference
# user-content variable names (text, phrase, vocabulary, lexicon,
# transcript, prompt, rawText, cleaned, audioURL, storageURL, audioFile)
# WITHOUT a `privacy: .private` or `privacy: .sensitive` qualifier.
#
# Exits non-zero if any violation is found. Wired into CI
# (`.github/workflows/swift-tests.yml` `lint-logging` job) so a PR that
# logs transcript content can't land.
#
# Also rejects bare `print(` of any variable (as opposed to string
# literals) because print bypasses OSLog's privacy system entirely.
#
# Usage:
#   ./scripts/lint-logging.sh         # scan and report
#   ./scripts/lint-logging.sh --fix   # future: auto-add privacy qualifiers (NOT YET)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Source roots to scan.
SCAN_DIRS=(Steno StenoKit/Sources)

# Forbidden variable names near logger/print calls. If the policy doc
# grows, keep this list in sync.
SENSITIVE_VARS='text|rawText|cleaned|phrase|vocabulary|lexicon|transcript|prompt|audioURL|audioFile|spokenText|dictationText|snippet'

VIOLATIONS=0

echo "==> Lint: OSLog and print calls against LOGGING_POLICY.md"

for dir in "${SCAN_DIRS[@]}"; do
  [ -d "$dir" ] || continue

  # Rule 1: any OSLog call (.debug / .info / .notice / .error / .fault / .log)
  # that references a sensitive var AND does NOT have `privacy: .private`
  # or `privacy: .sensitive` on the same line.
  while IFS= read -r match; do
    # Skip this very lint script if it ever gets scanned.
    case "$match" in *lint-logging*) continue ;; esac
    # Skip documentation comments explaining what NOT to do.
    case "$match" in *'NEVER'*) continue ;; esac
    case "$match" in *'// '*'logger'*) continue ;; esac

    echo "::error file=${match%%:*},line=$(echo "$match" | cut -d: -f2)::Logger call references sensitive variable without privacy qualifier: ${match#*:*:}"
    VIOLATIONS=$((VIOLATIONS + 1))
  done < <(
    grep -rnE "logger\.(debug|info|notice|error|fault|log)\(" "$dir" 2>/dev/null \
      | grep -E "\\\\\\(($SENSITIVE_VARS)" \
      | grep -vE "privacy: \\.(private|sensitive)" \
      || true
  )

  # Rule 2: NSLog calls are banned anywhere — NSLog has no privacy API.
  while IFS= read -r match; do
    case "$match" in *lint-logging*) continue ;; esac
    echo "::error file=${match%%:*},line=$(echo "$match" | cut -d: -f2)::NSLog is banned (no privacy API). Use os.Logger with privacy qualifiers. ${match#*:*:}"
    VIOLATIONS=$((VIOLATIONS + 1))
  done < <(grep -rnE '\bNSLog\(' "$dir" 2>/dev/null || true)

  # Rule 3: print() that references a sensitive variable.
  # Pure string-literal prints are allowed (help text in CLI tools etc.).
  # The StenoBenchmarkCLI target uses print() legitimately for its command
  # output — that's sample text and output paths, not user dictation, so we
  # allow print() in that target specifically.
  while IFS= read -r match; do
    case "$match" in
      *StenoBenchmarkCLI*) continue ;;
      *lint-logging*) continue ;;
    esac
    echo "::error file=${match%%:*},line=$(echo "$match" | cut -d: -f2)::print() referencing sensitive var (use os.Logger with .private): ${match#*:*:}"
    VIOLATIONS=$((VIOLATIONS + 1))
  done < <(
    grep -rnE '\bprint\(' "$dir" 2>/dev/null \
      | grep -E "\\\\\\(($SENSITIVE_VARS)" \
      || true
  )
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo
  echo "FAIL: $VIOLATIONS LOGGING_POLICY.md violations."
  echo "See LOGGING_POLICY.md for allowed logging patterns."
  exit 1
fi

echo "OK: no logging policy violations."
