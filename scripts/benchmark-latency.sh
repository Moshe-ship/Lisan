#!/usr/bin/env bash
#
# Per-language, per-model latency benchmark for Lisan's transcription path.
#
# Measures wall-clock time for whisper-cli to transcribe a given audio file
# under each combination of:
#   - model:    ggml-base.bin, ggml-small.bin (and any others present)
#   - language: en, ar, auto
# across N runs each, then emits a matrix (markdown + JSON) with p50 / p95
# latency per combination.
#
# Usage:
#   ./scripts/benchmark-latency.sh [--audio PATH] [--runs 5] [--out report.md]
#
# Defaults:
#   --audio  ~/vendor/whisper.cpp/samples/jfk.wav  (ships with whisper.cpp v1.8)
#   --runs   5
#   --out    ./benchmark-report.md
#
# Prereq: ~/vendor/whisper.cpp/build/bin/whisper-cli exists and at least
# one model file in ~/vendor/whisper.cpp/models/ggml-*.bin
#
# Note: accuracy benchmarking requires a reference transcript and WER/CER
# scoring, which is scoped to StenoBenchmarkCLI (see StenoKit). This script
# is latency only — it answers "how fast" not "how accurate."

set -euo pipefail

AUDIO="$HOME/vendor/whisper.cpp/samples/jfk.wav"
RUNS=5
OUT="./benchmark-report.md"
WHISPER="$HOME/vendor/whisper.cpp/build/bin/whisper-cli"
MODELS_DIR="$HOME/vendor/whisper.cpp/models"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --audio) AUDIO="$2"; shift 2 ;;
    --runs)  RUNS="$2";  shift 2 ;;
    --out)   OUT="$2";   shift 2 ;;
    -h|--help)
      sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ ! -x "$WHISPER" ]; then
  echo "whisper-cli not found at $WHISPER" >&2
  echo "Build whisper.cpp first (cmake -B build -DGGML_METAL=1 && cmake --build build --config Release)" >&2
  exit 1
fi
if [ ! -f "$AUDIO" ]; then
  echo "audio file not found: $AUDIO" >&2
  exit 1
fi

# Collect available multilingual models (ggml-base.bin, ggml-small.bin, etc).
# Skip -en suffixed models since the language benchmark needs Arabic support.
MODELS=()
for f in "$MODELS_DIR"/ggml-*.bin; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  case "$base" in
    *-en.bin) continue ;;
    *silero*) continue ;;
    *for-tests*) continue ;;
    ggml-*.bin) MODELS+=("$f") ;;
  esac
done
if [ "${#MODELS[@]}" -eq 0 ]; then
  echo "no multilingual models found in $MODELS_DIR" >&2
  exit 1
fi

LANGS=(en ar auto)

# Temp dir for per-run stdout capture.
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# quantile $p FILE   — compute percentile from a file of decimal values (one per line)
quantile() {
  local p="$1" file="$2"
  sort -n "$file" | awk -v p="$p" '
    BEGIN { c = 0 }
    { a[c++] = $1 }
    END {
      if (c == 0) { print "0"; exit }
      idx = (c - 1) * p
      lo = int(idx); hi = lo + 1
      frac = idx - lo
      if (hi >= c) hi = c - 1
      printf("%.0f\n", a[lo] + (a[hi] - a[lo]) * frac)
    }'
}

audio_basename="$(basename "$AUDIO")"
echo "# Lisan latency benchmark"                                     >  "$OUT"
echo                                                                 >> "$OUT"
echo "Audio: \`$audio_basename\`"                                    >> "$OUT"
echo "Runs per combination: \`$RUNS\`"                               >> "$OUT"
echo "Host: \`$(sw_vers -productName) $(sw_vers -productVersion) / $(uname -m)\`" >> "$OUT"
echo "Date: \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"                      >> "$OUT"
echo                                                                 >> "$OUT"
echo "## Latency matrix (milliseconds)"                              >> "$OUT"
echo                                                                 >> "$OUT"
echo "| Model | Language | p50 | p95 | min | max |"                 >> "$OUT"
echo "|-------|----------|-----|-----|-----|-----|"                 >> "$OUT"

# Accumulate a JSON report alongside.
JSON_OUT="${OUT%.md}.json"
{
  echo "{"
  echo "  \"audio\": \"$audio_basename\","
  echo "  \"runs\": $RUNS,"
  echo "  \"results\": ["
} > "$JSON_OUT"
first=1

for model in "${MODELS[@]}"; do
  model_name="$(basename "$model" .bin)"
  for lang in "${LANGS[@]}"; do
    times_file="$TMPD/${model_name}-${lang}.txt"
    : > "$times_file"

    for i in $(seq 1 "$RUNS"); do
      args=("-m" "$model" "-f" "$AUDIO" "--no-timestamps" "-t" "8")
      [ "$lang" != "auto" ] && args+=("-l" "$lang")

      start_ns="$(python3 -c 'import time; print(time.time_ns())')"
      "$WHISPER" "${args[@]}" >/dev/null 2>&1 || true
      end_ns="$(python3 -c 'import time; print(time.time_ns())')"
      elapsed_ms="$(( (end_ns - start_ns) / 1000000 ))"
      echo "$elapsed_ms" >> "$times_file"
    done

    p50="$(quantile 0.5 "$times_file")"
    p95="$(quantile 0.95 "$times_file")"
    min_v="$(sort -n "$times_file" | head -1)"
    max_v="$(sort -n "$times_file" | tail -1)"

    echo "| \`$model_name\` | \`$lang\` | $p50 | $p95 | $min_v | $max_v |" >> "$OUT"

    [ "$first" -eq 1 ] && first=0 || echo "    ," >> "$JSON_OUT"
    {
      echo "    {"
      echo "      \"model\":    \"$model_name\","
      echo "      \"language\": \"$lang\","
      echo "      \"p50_ms\":   $p50,"
      echo "      \"p95_ms\":   $p95,"
      echo "      \"min_ms\":   $min_v,"
      echo "      \"max_ms\":   $max_v,"
      echo "      \"samples\":  [$(paste -sd, "$times_file")]"
      echo "    }"
    } >> "$JSON_OUT"
  done
done

{
  echo "  ]"
  echo "}"
} >> "$JSON_OUT"

echo                                                                                  >> "$OUT"
echo "## Notes"                                                                       >> "$OUT"
echo                                                                                  >> "$OUT"
echo "- JFK sample (English speech) is used by default. Swap with \`--audio\` to"     >> "$OUT"
echo "  measure against your own recording."                                          >> "$OUT"
echo "- Forcing \`-l ar\` on English audio intentionally stresses the wrong-language" >> "$OUT"
echo "  path; latency stays similar but transcript quality collapses (see"            >> "$OUT"
echo "  LanguageSettingsSection copy in the app)."                                    >> "$OUT"
echo "- Accuracy scoring (WER/CER) is out of scope for this script. Use"              >> "$OUT"
echo "  \`swift run StenoBenchmarkCLI\` for the accuracy pipeline."                   >> "$OUT"

echo                         >> "$OUT"
echo "JSON report: \`$JSON_OUT\`" >> "$OUT"

echo "Wrote $OUT and $JSON_OUT"
