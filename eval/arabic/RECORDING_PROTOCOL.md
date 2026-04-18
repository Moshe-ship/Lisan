# Arabic eval — recording protocol

## Why this exists

Without a fixed audio set + reference transcripts, every "Arabic got
better!" claim is vibes. The four manifests in this directory each list
short utterances with a ground-truth transcript. Once audio exists for
each sample, the benchmark CLI produces a real WER/CER/latency report
per bucket, per model, and per configuration.

Four buckets, 80 utterances total:

| Manifest | Count | Focus |
|---|---|---|
| `msa.json` | 30 | Modern Standard Arabic (fusha). Business, formal speech, scripted tone. |
| `dialect-shami.json` | 15 | Levantine (Syria / Lebanon / Palestine / Jordan). Everyday spoken idiom. |
| `dialect-khaleeji.json` | 15 | Gulf (Saudi, Emirates, Kuwait). Everyday spoken idiom. |
| `mixed.json` | 20 | Bilingual Arabic ↔ English within a single sentence (professional code-switch). |

## How to record

### Environment

- Quiet room. A laptop fan and light street noise is fine, but avoid
  clear background speech or music.
- Wear-or-clamp the mic you actually dictate with. If you use AirPods
  in production, record with AirPods. If you use the built-in mic,
  record with the built-in mic. Recording conditions must match live
  conditions.
- 16 kHz mono WAV is the canonical format (that's what whisper expects
  internally anyway). If you record at higher rates, that's fine —
  whisper resamples.

### Per utterance

1. Open the manifest you're recording for (e.g. `msa.json`).
2. Read the `audioPath` field for the sample — record your WAV to that
   exact relative path under `eval/arabic/audio/`.
3. Speak the `referenceText` field naturally. Do not over-enunciate.
   Do not pause mid-sentence. Speak it as you would in real
   conversation.
4. If you make a mistake, re-record the whole clip from scratch. Do
   not splice.
5. Keep clips under ~8 seconds. This matches typical press-to-talk use
   and is where whisper's auto-detect weakness shows up most.

### Practical recording command

```bash
# Per-clip, using the built-in mic:
cd eval/arabic/audio
rec -r 16000 -c 1 -b 16 msa-001.wav
#          sample-rate  mono  16-bit
```

If you prefer Audacity / QuickTime, export as `16-bit PCM mono WAV` at
16 kHz.

## How to run the benchmark

Once one or more buckets has audio:

```bash
cd /path/to/Lisan-local
swift run StenoBenchmarkCLI \
    --manifest eval/arabic/msa.json \
    --whisper-cli ~/vendor/whisper.cpp/build/bin/whisper-cli \
    --model ~/vendor/whisper.cpp/models/ggml-small.bin \
    --output eval/results/msa-small-$(date +%Y%m%d).json
```

Swap `--model` to compare Small vs Medium vs Base. The CLI emits a
JSON report with per-sample WER/CER plus aggregates and latency
percentiles.

## What "good" looks like

Targets are honest, not aspirational. Today's numbers (on `base`
model, before recording audio) are unknown. After recording and running
`small` as the baseline, we expect:

| Bucket | Baseline target WER | Stretch target WER |
|---|---|---|
| MSA | ≤ 15% | ≤ 10% |
| Shami | ≤ 25% | ≤ 18% |
| Khaleeji | ≤ 25% | ≤ 18% |
| Mixed | ≤ 30% | ≤ 22% |

Dialect and mixed WERs will always be higher than MSA because whisper
was trained on mostly MSA Arabic and English-bias content. These
numbers are what we plot progress against, not what ships on day one.

## Adding a new utterance

1. Add an entry to the appropriate manifest with a unique `id` and
   `audioPath` (`audio/<id>.wav`).
2. Record the clip per the protocol above.
3. Commit both the manifest change and the new WAV.

Keep utterances short, natural, and representative of real user
dictation — not phonetically-loaded tongue twisters.
