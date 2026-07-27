# OCR Factures — démo client

Interface web d'OCR pour factures fournisseurs, adossée à un workflow **n8n** appelant
**OCR.space**. Le client dépose un PDF ou une photo, et récupère un **PDF dont le texte est
sélectionnable** plus le texte brut extrait.

```
index.html            interface (fichier unique, aucun build)
ocr-workflow.json     workflow n8n à importer
export-workflow.json  workflow n8n d'export Word / Excel (Adobe)
test-webhook.sh       vérification de bout en bout du workflow
xp/                   factures d'exemple
```

## État actuel — déjà déployé

Le workflow est **importé et actif** dans le conteneur `aiwp_n8n` (n8n 2.22.6) :

| | |
|---|---|
| Workflow | *OCR Demo — OCR.space* — id `ocrDemoFactures` |
| Webhook | `http://localhost:5678/webhook/ocr` |
| Éditeur | http://localhost:5678 (`admin` / `Admin123`) |

`index.html` pointe déjà sur cette URL : **double-cliquez dessus et déposez une facture**,
il n'y a rien à configurer.

Vérification à tout moment :

```bash
./test-webhook.sh http://localhost:5678/webhook/ocr
```

```
✓ texte extrait — 1206 caractères
✓ contenu de la facture reconnu
✓ pdfBase64 commence par la signature %PDF
✓ PDF consultable — 103 Ko
✓ le PDF contient une couche texte (/Font)
```

### Réimporter après modification

n8n 2.x distingue la version **courante** (brouillon) de la version **publiée**. Le webhook sert
la version **publiée**. `import:workflow` n'écrit que la version courante et **désactive** le
workflow au passage : sans `publish:workflow`, vos modifications ne partent jamais en production
et l'ancienne version continue de répondre, silencieusement.

Les trois commandes forment un tout — n'en sautez aucune :

```bash
export MSYS_NO_PATHCONV=1                                   # Git Bash : sinon /tmp devient un chemin Windows
docker cp ocr-workflow.json aiwp_n8n:/tmp/ocr-workflow.json
docker exec aiwp_n8n n8n import:workflow --input=/tmp/ocr-workflow.json
docker exec aiwp_n8n n8n publish:workflow --id=ocrDemoFactures
docker restart aiwp_n8n                                     # le webhook est enregistré au démarrage

./test-webhook.sh http://localhost:5678/webhook/ocr         # seule preuve que c'est en ligne
```

Deux pièges :

- **`n8n update:workflow --active=true` est déprécié** et publie une version qui n'est pas
  forcément celle que vous venez d'importer. Utilisez `publish:workflow`.
- **`export:workflow` exporte le brouillon, pas la version publiée.** Il ne prouve donc rien sur
  ce qui tourne réellement. Seul `test-webhook.sh` fait foi.

Le symptôme d'une version obsolète en production : `pdfBase64` vaut `filesystem-v2` au lieu du
PDF, et l'interface affiche « Le service OCR n'a pas renvoyé de PDF ».

### Démo hors de cette machine

`localhost:5678` n'est joignable que depuis ce poste. Pour montrer la démo ailleurs, exposez n8n
(tunnel, reverse proxy) et changez la constante `WEBHOOK_URL` en haut du `<script>` de
`index.html`, ou saisissez l'URL dans le panneau *⚙ Configuration* de l'interface — elle prend le
pas sur la constante et reste mémorisée dans le navigateur.

## Export Word / Excel

Deuxième workflow, **indépendant du premier** : `export-workflow.json`. Il délègue la conversion
à **Adobe PDF Services**, qui produit un `.docx` respectant la mise en page d'origine et un
`.xlsx` où les tableaux retombent dans de vraies cellules.

Mise en service :

1. Créer un projet sur [developer.adobe.com/document-services](https://developer.adobe.com/document-services/)
   et récupérer le *client ID* et le *client secret*.
2. Fabriquer la copie locale porteuse des clés — `*.local.json` est dans `.gitignore`, les vraies
   clés ne partent donc jamais dans git :

```bash
sed -e 's/YOUR_ADOBE_CLIENT_ID/votre-id/' \
    -e 's/YOUR_ADOBE_CLIENT_SECRET/votre-secret/' \
    export-workflow.json > export-workflow.local.json
```

3. Importer, publier et redémarrer, comme pour l'autre workflow :

```bash
export MSYS_NO_PATHCONV=1
docker cp export-workflow.local.json aiwp_n8n:/tmp/export-workflow.json
docker exec aiwp_n8n n8n import:workflow --input=/tmp/export-workflow.json
docker exec aiwp_n8n n8n publish:workflow --id=adobeExportWordExcel
docker restart aiwp_n8n
```

L'interface **ne demande pas de seconde URL** : elle remplace le dernier segment de l'URL OCR par
`/export`. `…/webhook/ocr` devient donc `…/webhook/export`, sur le même serveur.

### Pourquoi le tableur est fabriqué à partir du .docx

Adobe sait exporter directement en `.xlsx`. **Sur les factures de `xp/`, le résultat est
inutilisable** : la totalité du tableau de lignes atterrit dans une seule cellule, en-tête et
données confondues. Rien ne peut être sommé.

Son export **Word**, lui, reconnaît très bien les tableaux — 13 `<w:tbl>` sur la même facture,
dont les lignes d'articles réparties sur les 10 bonnes colonnes. Le workflow demande donc
**toujours du `.docx`** ; quand l'utilisateur a cliqué *Excel*, le nœud *Tableaux* rouvre le
`.docx` (c'est un ZIP), lit les `<w:tbl>` et les reverse dans une feuille.

Effets de bord utiles : une seule opération Adobe quel que soit le bouton, et aucun second
prestataire à contractualiser.

Deux contraintes n8n que la chaîne doit contourner — les deux échouent **en silence** :

- **`require('zlib')` est interdit** dans un nœud *Code* (`Module 'zlib' is disallowed`). Ce
  conteneur n'autorise que `NODE_FUNCTION_ALLOW_EXTERNAL=docx,pdf-lib,archiver`, et aucun module
  natif. D'où le nœud *Decompresser* (nœud *Compression* standard) plutôt qu'un dézippage maison.
- **Le nœud *Compression* ne dézippe que si `fileExtension` vaut `zip`.** Adobe étiquette son
  fichier `docx` — qui *est* un zip — et le nœud le laisse alors passer en produisant un binaire
  **vide, sans erreur**. Le nœud *Renommer* corrige l'étiquette juste avant.

Le nœud *Tableaux* énumère les entrées trouvées dans son message d'erreur : si un jour la sortie
du dézippage change de nom, l'erreur le dit au lieu de laisser deviner.

Trois points à connaître :

- **Adobe ne devine pas qu'une page est un tableau.** Le format est imposé par le bouton cliqué.
  D'où deux boutons plutôt qu'un détecteur : l'utilisateur sait ce qu'il a déposé, et si le
  résultat ne convient pas, l'autre bouton est à côté.
- **Le PDF envoyé est l'original**, pas celui reconstruit par l'OCR — Adobe fait sa propre
  reconnaissance, meilleure que celle de la chaîne OCR.space. L'étape est sautée (`ocr: false`)
  quand le document possède déjà une couche texte.
- **La conversion part au clic**, jamais au dépôt du fichier. Un document déposé mais non exporté
  ne consomme aucun quota.

## Comment ça marche

```
index.html                                    n8n
  pdf.js — lit le PDF                          ┌─────────────────────────┐
    ├─ couche texte déjà présente ?            │ Webhook  POST /ocr      │
    │    → aucun appel OCR, PDF servi tel quel │   ↓                     │
    └─ sinon : chaque page → JPEG 1600 px      │ OCR.space  moteur 2     │
         └─ POST page par page ────────────────→   isCreateSearchablePdf │
                                               │   ↓                     │
    pdf-lib — refusionne les pages ←───────────  Télécharger le PDF      │
    iframe : texte sélectionnable              │   ↓ {text, pdfBase64}   │
                                               └─────────────────────────┘
```

Trois choix méritent une explication.

**Pourquoi n8n au milieu ?** La clé OCR.space reste côté serveur, jamais dans le navigateur.

**Pourquoi découper le PDF dans le navigateur ?** Le palier gratuit d'OCR.space plafonne à
**1 Mo par fichier** et **3 pages par PDF**. Vérifié sur vos propres échantillons : `HENKEL…PDF`
(5 pages) renvoie le code d'erreur 4 — *« maximum page limit of 3 was reached »* — et le scan
`img20260716_11230272.pdf` pèse 948 Ko, à la limite. Rendre chaque page en JPEG compressé
(~200 Ko) supprime les deux plafonds d'un coup, sans abonnement.

**Pourquoi le moteur 2 ?** Le moteur 3 est plus précis mais **ne sait pas produire de PDF
consultable**, ce qui est justement le livrable demandé. Le moteur 2 gère les fonds bruités des
scans et détecte la langue seul.

**Aucun LLM dans la chaîne.** Le traitement est entièrement déterministe : rendu des pages,
OCR, refusion du PDF.

### Pourquoi `isSearchablePdfHideTextLayer`

Sans ce paramètre, OCR.space **dessine le texte reconnu par-dessus la page** : gros caractères
rouges sur pavés verts, document illisible. La couche texte est alors opaque.

Avec `isSearchablePdfHideTextLayer=true`, OCR.space insère des états graphiques `/ca 0` et
`/CA 0` (opacité de remplissage et de contour nulles) autour de ce texte : il devient invisible
mais reste sélectionnable et copiable. Le document rendu est identique à l'original.

`test-webhook.sh` vérifie la présence de ces états alpha à chaque exécution — c'est le seul
signal qui distingue les deux variantes, et l'oubli du paramètre est silencieux côté API.

**Filigrane :** le palier gratuit ajoute « Searchable PDF created by OCR.space (Free Version) »
en pied de page. Il ne disparaît qu'avec un abonnement PRO (30 $/mois).

### Un détail n8n qui compte

Cette instance stocke les binaires sur disque, pas en mémoire. Dans ce mode,
`binary.data.data` d'un nœud *Code* ne contient pas le base64 mais l'identifiant du stockage
(la chaîne `filesystem-v2`). Le nœud *Formater* passe donc par
`this.helpers.getBinaryDataBuffer(0, 'data')`, qui renvoie les octets quel que soit le mode.
Un garde-fou vérifie ensuite que le résultat commence bien par `JVBER` (`%PDF` en base64).

## Deux comportements à connaître pour la démo

**Les PDF natifs ne passent pas par l'OCR.** SFBT, GIAS et Henkel contiennent déjà une couche
texte : l'interface le détecte, affiche *« Texte natif — déjà consultable »* et retourne le
résultat instantanément, sans perte. Pour montrer la qualité de l'OCR sur ces fichiers, cochez
**« Forcer l'OCR sur les PDF déjà textuels »** avant de déposer.

**Le scan pivoté demande un clic.** Le paramètre `detectOrientation` d'OCR.space ne redresse pas
`img20260716_11323829.pdf` : le texte est bien extrait, mais dans un ordre de lecture incohérent,
parce que la page est droite et que c'est son *contenu* qui est couché. Le bouton **⟳ Pivoter**
sur la page fait tourner l'image de 90° et relance l'OCR de cette page seule.

## Recette

Auto-test des parties non triviales (plafonnement de taille JPEG, fusion multi-pages) —
ouvrir `index.html?selftest=1` et regarder la console :

```
✓ b64Bytes = taille décodée réelle
✓ canvasToJpeg plafonne le bruit à 412 Ko (max 950 Ko)
✓ fusion 3+2 pages = 5 (attendu 5)
```

Puis déposer les six échantillons de `xp/` :

| Échantillon | Attendu |
|---|---|
| `7885…FAC21MBK01681.pdf` | badge texte natif ; OCR forcé → `FAC21-MBK01681` |
| `6701…FactureN9001462628.pdf` | badge texte natif ; OCR forcé → `9001462628` |
| `HENKEL(P92)…PDF` | badge texte natif ; **OCR forcé** → 5 pages traitées puis refusionnées en un seul PDF (c'est ce cas qui prouve que la limite de 3 pages est levée) |
| `img20260716_11230272.pdf` (948 Ko) | passe malgré la limite de 1 Mo |
| `img20260716_11311808.pdf` | texte cohérent avec la facture GIAS |
| `img20260716_11323829.pdf` | ordre de lecture incohérent → **⟳ Pivoter** → correct |

Enfin, le geste qui vend la démo : télécharger le **PDF consultable**, l'ouvrir, sélectionner du
texte à la souris et le coller ailleurs.

## Limites assumées

- **500 requêtes/jour et 25 000/mois** sur la clé OCR.space gratuite ; une requête = une page.
- **500 conversions/mois** sur l'offre Adobe gratuite ; une conversion = un document jusqu'à
  50 pages. Au-delà, la tarification n'est pas publique : il faut demander un devis à Adobe.
- **Un scan converti en Word n'est jamais identique à l'original** : l'image ne contient aucune
  information de police, Word en substitue une approchante. Les PDF déjà textuels, eux, se
  convertissent très fidèlement.
- **10 Mo par PDF exporté**, marge sous la limite de charge utile de n8n (16 Mo, +33 % en base64).
- **Le tableur reprend *tous* les tableaux du document**, séparés par une ligne vide, sans choisir
  lequel est celui des articles. Sur une facture scannée, les blocs voisins peuvent se retrouver
  fusionnés dans un même tableau (vérifié sur `img20260716_11311808.pdf`) : les lignes d'articles
  restent justes, l'entourage est bruité.
- **Le bouton Excel ne vaut que pour les factures à tableau encadré.** Sur `HENKEL(P92)…`, dont le
  tableau d'articles n'a pas de filets, l'export Word rend chaque ligne d'article dans **une seule
  cellule** : le tableur en hérite et devient inexploitable. Voir « Pistes » ci-dessous.
- **Les nombres sont typés au format francophone** (`56,221` → `56.221`). Un document anglo-saxon
  (`1,234.56`) resterait du texte — le motif est dans le nœud *Tableaux*.
- **Pas d'extraction de champs structurés** (n° de facture, MF, HT/TVA/TTC, lignes) — la démo
  livre du texte et un PDF consultable. C'est l'étape suivante naturelle, via un nœud LLM.
- **Traitement séquentiel** des pages, pour garder la barre de progression lisible et rester
  sous la limite de débit.
- Un document scanné à l'envers demande un clic manuel (voir plus haut).

## Si le navigateur affiche une erreur CORS

Le nœud *Webhook* porte `allowedOrigins: "*"`, ce qui suffit dans la majorité des cas. Sur
certaines installations auto-hébergées derrière un reverse proxy, la requête préalable `OPTIONS`
n'atteint pas n8n. Deux issues :

- autoriser la méthode `OPTIONS` sur `/webhook/*` dans le reverse proxy ; ou
- éviter la requête préalable : passer `'Content-Type': 'text/plain'` dans le `fetch` de
  `index.html` et parser le corps avec un nœud *Code* en tête de workflow. Une requête simple
  ne déclenche pas de `OPTIONS`.
