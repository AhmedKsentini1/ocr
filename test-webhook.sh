#!/usr/bin/env bash
# Vérifie que le workflow n8n répond correctement de bout en bout.
#
#   ./test-webhook.sh https://votre-n8n/webhook/ocr
#
# Envoie une facture d'exemple au webhook et contrôle que la réponse
# contient du texte ET un PDF consultable valide.
set -u

HOOK="${1:-}"
[ -z "$HOOK" ] && { echo "usage: $0 <url-webhook-n8n>"; exit 2; }

SAMPLE="${2:-xp/7885_20210726_124046_FAC21MBK01681.pdf}"
OUT="${3:-resultat-consultable.pdf}"   # PDF produit, conservé pour inspection
[ -f "$SAMPLE" ] || { echo "échantillon introuvable : $SAMPLE"; exit 2; }

cd "$(dirname "$0")"
# dossier local : mktemp -d renvoie un chemin POSIX que node ne résout pas
# correctement sous Git Bash (Windows).
TMP=".ocrtest"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

echo "→ POST $HOOK  ($SAMPLE)"

node -e '
const fs = require("fs");
const b64 = fs.readFileSync(process.argv[1]).toString("base64");
fs.writeFileSync(process.argv[2], JSON.stringify({
  filename: require("path").basename(process.argv[1]),
  page: 1,
  imageBase64: "data:application/pdf;base64," + b64,
}));
' "$SAMPLE" "$TMP/req.json"

CODE=$(curl -s -X POST "$HOOK" \
  -H "Content-Type: application/json" \
  --data-binary "@$TMP/req.json" \
  -o "$TMP/res.json" -w "%{http_code}")

echo "→ HTTP $CODE"
[ "$CODE" = "200" ] || { echo "✗ ÉCHEC : le webhook n'a pas répondu 200."; \
  echo "  Workflow activé ? URL de production (pas /webhook-test/) ?"; \
  head -c 400 "$TMP/res.json"; echo; exit 1; }

node -e '
const fs = require("fs");
let r;
try { r = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
catch { console.error("✗ ÉCHEC : réponse non-JSON."); process.exit(1); }

let bad = 0;
const ok = (c, m) => { console.log((c ? "✓" : "✗ ÉCHEC") + " " + m); if (!c) bad++; };

if (!r.ok) { console.error("✗ ÉCHEC : " + (r.error || "erreur inconnue")); process.exit(1); }

const text = (r.text || "").trim();
ok(text.length > 50, `texte extrait — ${text.length} caractères`);
ok(/FAC21|GIAS|MONOPRIX/i.test(text), "contenu de la facture reconnu");

const pdf = r.pdfBase64 || "";
ok(pdf.startsWith("JVBER"), "pdfBase64 commence par la signature %PDF");

const bytes = Buffer.from(pdf, "base64");
ok(bytes.length > 1000, `PDF consultable — ${Math.round(bytes.length / 1024)} Ko`);
ok(bytes.includes(Buffer.from("/Font")), "le PDF contient une couche texte (/Font)");

// Sans isSearchablePdfHideTextLayer, OCR.space dessine le texte reconnu en rouge
// vif par-dessus la page. Les états alpha 0 sont la preuve qu il est invisible.
const s = bytes.toString("latin1");
ok(/<<\/ca 0>>/.test(s) && /<<\/CA 0>>/.test(s),
   "couche texte invisible (alpha 0) — pas de surimpression rouge");

fs.writeFileSync(process.argv[2], bytes);
console.log("\nPDF enregistré : " + process.argv[2]);

console.log("\n--- début du texte extrait ---");
console.log(text.split("\n").slice(0, 6).join("\n"));

process.exit(bad ? 1 : 0);
' "$TMP/res.json" "$OUT"
