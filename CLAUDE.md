# CLAUDE.md

OCR demo for supplier invoices: a single-file browser UI driving n8n workflows.
No build step, no package.json, no node_modules. Three CDN `<script>` tags and
that is the entire dependency list.

## Where the knowledge lives

`README.md` is the deep document — architecture, tuned constants and the reasoning
behind them, deploy commands, measured limits. **It is written for you, not for the
user.** They do not read it. Read it before changing anything non-trivial; it will
save you from re-deriving decisions that were already settled with measurements.

This file holds only what the README does not: how to work here.

## The three pipelines

All three are now documented in the README — the tableur path was confirmed
permanent on 2026-08-04 and written up under « Le tableur ». There is no
deliberate documentation gap left. If you find drift now, it is real drift:
raise it.

| pipeline | workflow | webhook | model |
|---|---|---|---|
| OCR + PDF consultable | `ocrDemoFactures` | `/webhook/ocr` | none, deterministic |
| Word, and Excel of native PDFs | `adobeExportWordExcel` | `/webhook/export` | none, Adobe |
| Excel of recognised pages | `tableurNemotron` | `/webhook/tableur` | `nvidia/nemotron-nano-12b-v2-vl` |

The vision model is the **only** non-deterministic step in the repo, and it is
confined to the Excel button (`llmXlsx` → `buildXlsx` in `index.html`). Say so
when it matters: OCR, the searchable PDF and the Word export never touch it.

## README policy

- **Only permanent changes get documented.** An experiment stays out of the README,
  however finished it looks.
- **Do not decide permanence yourself.** Ask. Default to leaving the README alone.
- **Periodically remind the user** when undocumented drift has piled up — list what
  is now missing or false and ask which parts have become permanent. They want the
  reminder; they will not think to ask.
- When a change *is* confirmed permanent, its README update lands with it, not later.

## The recurring correction: stop adding things

This is the one thing the user pushes back on. Ponytail is not decoration here.

- **No new dependencies.** Not npm, not a CDN script, not a framework. The stack is
  pdf.js, pdf-lib, OpenCV.js — nothing joins it. `buildXlsx` writes a valid `.xlsx`
  with a hand-rolled CRC32 and stored-method ZIP precisely so no zip library is
  needed. Match that bar.
- **No build step.** `index.html` is served as a static file by nginx (see
  `Dockerfile`). It must keep working when opened over `file://`.
- **No abstraction for one caller.** The codebase is flat functions. Keep it flat.
- Mark deliberate corner-cuts with a `ponytail:` comment naming the ceiling — there
  are existing ones to match.

## Deploying to n8n

You may run the deploy. **Take a reversible checkpoint first** — the user asked for
this explicitly.

```bash
git add -A && git commit -m "point de reprise avant déploiement"   # the rollback
cp ocr-workflow.json "$SCRATCH/ocr-workflow.before.json"           # if not committing

export MSYS_NO_PATHCONV=1
docker cp ocr-workflow.json aiwp_n8n:/tmp/ocr-workflow.json
docker exec aiwp_n8n n8n import:workflow --input=/tmp/ocr-workflow.json
docker exec aiwp_n8n n8n publish:workflow --id=ocrDemoFactures
docker restart aiwp_n8n

./test-webhook.sh http://localhost:5678/webhook/ocr    # the only proof it is live
```

All four commands or none. `import:workflow` writes the **draft** and deactivates
the workflow; without `publish:workflow` the old version keeps answering, silently.
Never report a deploy as done without the `test-webhook.sh` output.

Workflow ids: `ocrDemoFactures`, `adobeExportWordExcel`, `tableurNemotron`.
Container `aiwp_n8n` is running. Keys come from `$env` inside n8n
(`OCRSPACE_API_KEY`, `NVIDIA_API_KEY`, Adobe pair in `export-workflow.local.json`).
`*.local.json` files hold real keys and are gitignored — no special handling needed
beyond keeping them out of commits.

**`$env` is not fed from this repo.** The container's environment comes from a
Compose stack that lives elsewhere: `C:\Users\LENOVO\Desktop\ai-wp-generator\`
(`.env` + the `environment:` block of the `n8n` service). Two consequences:

- Adding a key means editing **two files outside this repo**, then
  `docker compose -f ".../docker-compose.yml" up -d n8n`.
- **`docker restart aiwp_n8n` will not pick up a new variable** — env is fixed at
  container creation, so a restart silently replays the old environment and the
  fix looks like it failed. Only `up -d` recreates it. Workflows survive; they
  are in the named volume `ai-wp-generator_n8n_data`.

A workflow built in the editor carries a **random id**, so importing the repo file
does not replace it — it creates a duplicate fighting for the same webhook path.
`unpublish:workflow` the intruder first. This bit us with `E2iaoYSofC6PzrA1` vs
`tableurNemotron`; the former is unpublished, not deleted.

`test-webhook.sh` only covers `/webhook/ocr`. For `/tableur` the equivalent proof is
a real POST of `{imageBase64: "data:image/jpeg;base64,…", texte}` — the image
**must** be a data URL, the node rejects bare base64.

## Verifying browser code

You cannot open a browser, so `index.html?selftest=1` is not yours to run. Split it:

- **Pure logic → run it in node** (`node --version` → v26.3.0, available). Copy the
  function into a scratch file, call it, report the actual output. `crc32`, `typed`,
  `orderQuad`, `toSibling`, `b64Bytes` and the ZIP writer are all reachable this way.
- **Canvas / OpenCV / pdf.js → write the assertion, the user runs it.** Add it to the
  `?selftest=1` block and say so plainly: *"assertion written, run `?selftest=1` to
  confirm."* **Never claim a browser check passed.** You did not see it.

Test bar: one runnable check per piece of non-trivial logic, in the existing
`?selftest=1` block. No framework, no test runner, no new files.

## Sample files

`xp/` — scans and native PDFs (gitignored). `new exp/` — phone photos on cluttered
backgrounds. These are the regression suite. Any change to the scanify/detectQuad
constants must be justified against them with real numbers, not reasoning — that is
how every constant in `index.html:330-348` was set.

## Conventions

- **French** for code comments, UI strings, commit messages, and the README. This
  file is the only English one.
- Comments explain *why*, especially why a naive alternative failed. Several
  comments record measured failures; that is the house style, keep it.
- Commit messages: imperative present, French, no scope prefix
  (`Pointe l'interface sur le webhook de production`).

## Trajectory

Client demo now; production only if the client bites. Stay lazy today, but avoid
choices that would be expensive to undo — no schema lock-in, no data model that
assumes single-user. Do not preemptively build auth, persistence or multi-tenancy.
