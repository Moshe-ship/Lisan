# Vocabulary packs

Plain-text phrase files that bias Whisper toward correct transcription of
proper nouns, dialect words, and domain terms that the base model often
gets wrong. Load a single file or point Lisan at this directory to layer
multiple packs.

## How to use

1. Settings → Language → Vocabulary file
2. Enter the path to a `.txt` file OR this `packs/` directory
3. Save & Apply

When you point at a directory, Lisan reads every `.txt` file alphabetically,
dedupes phrases, and joins them with spaces as `--prompt` to whisper-cli.
Lines starting with `#` are comments.

## Included packs

| File                   | Content                                         |
|------------------------|-------------------------------------------------|
| `msa-business.txt`     | Modern Standard Arabic business / office terms  |
| `khaleeji-common.txt`  | Khaleeji (Gulf) dialect staples                 |
| `shami-common.txt`     | Levantine (Shami) dialect staples               |
| `saudi-places.txt`     | Saudi cities, districts, landmarks              |
| `gcc-brands.txt`       | Common GCC consumer / telecom / banking brands  |
| `agency-bilingual.txt` | Digital-marketing / agency vocabulary (AR + EN) |

## Writing your own pack

- One phrase per line
- UTF-8, no BOM
- `# any line like this` is a comment
- Keep it short — Whisper truncates long prompts
- Include spelling variants you care about (e.g., `Mohammad` AND `Muhammad`)

## Contributions

Open a PR with new packs. Keep them focused (one domain per file). Do not
include PII, private contacts, or client-confidential terms.
