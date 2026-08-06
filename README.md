# OCR Factures — démo client

Interface web d'OCR pour factures fournisseurs, adossée à un workflow **n8n** appelant
**OCR.space**. Le client dépose un PDF ou une photo, et récupère un **PDF dont le texte est
sélectionnable** plus le texte brut extrait.

```
index.html            interface (fichier unique, aucun build)
ocr-workflow.json     workflow n8n à importer
export-workflow.json  workflow n8n d'export Word / Excel (Adobe)
test-webhook.sh       vérification de bout en bout du workflow
xp/                   factures d'exemple (scans et PDF natifs)
new exp/              photos prises au téléphone, fond encombré
```

## État actuel — déjà déployé

Le workflow est **importé et actif** dans le conteneur `aiwp_n8n` (n8n 2.22.6) :

| | |
|---|---|
| Workflow | *OCR Demo — OCR.space* — id `ocrDemoFactures` |
| Webhook | `https://ocr.4prod.tn/webhook/ocr` |
| Interface | https://demo-ocr.4prod.tn (conteneur nginx, déployé par Coolify depuis ce dépôt) |
| Éditeur | http://localhost:5678 (`admin` / `Admin123`) |

Trois workflows tournent dans ce conteneur, un par bouton de l'interface :

| Workflow | id | Webhook | Sert |
|---|---|---|---|
| *OCR Demo — OCR.space* | `ocrDemoFactures` | `/webhook/ocr` | le texte et le PDF consultable |
| *Export Word / Excel — Adobe* | `adobeExportWordExcel` | `/webhook/export` | le `.docx`, et le `.xlsx` des PDF natifs |
| *Tableaux — Nemotron VL (NVIDIA)* | `tableurNemotron` | `/webhook/tableur` | le `.xlsx` des pages reconnues |

Seul `/webhook/ocr` a une URL de production vérifiée ; les deux autres n'ont été exercés que sur
le conteneur local. `/webhook/tableur` exige `NVIDIA_API_KEY` dans l'environnement du conteneur —
voir « La clé NVIDIA ».

`index.html` pointe déjà sur l'URL de production : **ouvrez l'interface et déposez une facture**,
il n'y a rien à configurer.

> Le champ *Réglages* de l'interface enregistre l'URL saisie dans `localStorage`, et cette valeur
> **prime sur `WEBHOOK_URL`**. Après un changement d'URL dans le code, vider l'entrée pour que le
> nouveau réglage s'applique : `localStorage.removeItem('ocrHook')` dans la console du navigateur.

Vérification à tout moment :

```bash
./test-webhook.sh https://ocr.4prod.tn/webhook/ocr
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

### La clé NVIDIA

`/webhook/tableur` lit `NVIDIA_API_KEY` par `$env`. **Les variables d'environnement de n8n ne
sont pas dans ce dépôt** : elles viennent de la pile Compose qui héberge le conteneur,
`C:\Users\LENOVO\Desktop\ai-wp-generator\` — une ligne dans `.env`, une ligne dans le bloc
`environment:` du service `n8n` de `docker-compose.yml`, comme les clés Groq et Gemini voisines.

```bash
docker compose -f "C:/Users/LENOVO/Desktop/ai-wp-generator/docker-compose.yml" up -d n8n
docker exec aiwp_n8n printenv NVIDIA_API_KEY      # la preuve avant de relancer quoi que ce soit
```

**`docker restart aiwp_n8n` ne suffit pas** — et c'est le piège : les variables d'environnement
sont figées à la *création* du conteneur, un redémarrage rejoue donc l'ancien environnement. Il
faut `up -d`, qui recrée le conteneur. Les workflows survivent, ils sont dans le volume nommé
`ai-wp-generator_n8n_data`.

Signature d'une clé absente : le nœud *Nemotron* envoie `Authorization: Bearer ` vide, et NVIDIA
répond **HTTP 500** avec

```
Missing request extension: Extension of type `headers::common::authorization::Authorization<…Bearer>`
```

qui ne ressemble en rien à une erreur d'authentification. Les trois cas ont été distingués à la
main : clé vide → 500 et ce message ; clé fausse → 403 `Authorization failed` ; en-tête absent →
401 `Header of type authorization was missing`.

### Un workflow créé dans l'éditeur porte un id aléatoire

`tableur-workflow.json` déclare `tableurNemotron`. La version bricolée dans l'éditeur portait
`E2iaoYSofC6PzrA1` : importer le fichier ne la remplaçait donc pas, il créait un **second**
workflow revendiquant le même chemin `/webhook/tableur`. Il faut dépublier l'intrus avant de
publier le bon, sinon le chemin reste pris :

```bash
docker exec aiwp_n8n n8n unpublish:workflow --id=E2iaoYSofC6PzrA1
docker exec aiwp_n8n n8n import:workflow --input=/tmp/tableur-workflow.json
docker exec aiwp_n8n n8n publish:workflow --id=tableurNemotron
docker restart aiwp_n8n
```

`E2iaoYSofC6PzrA1` est dépublié, pas supprimé — à jeter depuis l'éditeur une fois la confiance
établie.

### Démo hors de cette machine

`localhost:5678` n'est joignable que depuis ce poste. Pour montrer la démo ailleurs, exposez n8n
(tunnel, reverse proxy) et changez la constante `WEBHOOK_URL` en haut du `<script>` de
`index.html`, ou saisissez l'URL dans le panneau *⚙ Configuration* de l'interface — elle prend le
pas sur la constante et reste mémorisée dans le navigateur.

## Le redressement « scanner »

Une photo prise au téléphone arrive avec la nappe autour, la page de travers et
une ombre en travers du papier. Comme **le PDF consultable est fabriqué à partir
de l'image envoyée**, tout ce qui traîne dans la photo atterrit dans le livrable —
et dans le `.docx` qui en découle. D'où une étape unique, dans le navigateur,
juste avant l'envoi : *redresser, puis blanchir*. Une seule correction, quatre
sorties assainies (PDF, texte, Word, Excel).

C'est **OpenCV.js**, chargé depuis `docs.opencv.org` au premier document à
reconnaître (≈ 10 Mo, ensuite en cache). Aucun appel payant : le traitement est
local. Si le téléchargement échoue, l'image part telle quelle et l'interface le
dit — la démo continue, dégradée.

### Le rendu : ce qui marche à tous les coups

Quatre étapes, dont trois ont été obtenues en corrigeant une version naïve qui
rendait un texte gris et mou. Chacune vaut d'être comprise avant d'être touchée.

**1. Aplatir l'éclairage** en divisant la page par une estimation de son fond.
Le fond est estimé par une **fermeture morphologique**, pas par un flou. Un noyau
plus large qu'un caractère fait disparaître le texte et ne laisse que le papier ;
un flou, lui, est *tiré vers le bas par le texte*, sous-estime le papier dans les
zones denses, et la division y délave les lettres. C'était la cause du texte gris
des premières versions — le défaut était le plus visible là où il y avait le plus
à lire.

**2. Étaler le contraste sur la luminance seule.** Étirer les trois canaux
séparément applique un gain d'environ 2,5 au bruit de chrominance JPEG du papier
et le tache de rose. Passer par TSV laisse la teinte intacte.

Les points noir et blanc viennent du **seuil d'Otsu**, pas d'un percentile. Otsu
sépare l'encre du papier sans rien présumer de leur *proportion*, et c'est tout
l'intérêt : sur un bon de livraison presque vide, un percentile bas tombe en
plein sur le papier et l'étalement grise la page entière. Mesuré sur les
échantillons du dépôt plus deux pages synthétiques, éparse et chargée :

| | percentile 3 % | seuil d'Otsu |
|---|---|---|
| `Tunisianet.jpeg` | 168 | 216 |
| `WhatsApp…28.jpeg` | 126 | 199 |
| `invoice.jpeg` | 149 | 192 |
| page à 2 % de texte | **250** ← tombe sur le papier | 192 |
| page à 30 % de texte | 128 | 197 |

Le percentile varie de 126 à 250 selon le document ; Otsu reste entre 192 et 216
sur les mêmes. C'est exactement l'invariance recherchée.

**3. Neutraliser le papier, raviver ce qui est coloré.** Sous un plancher de
saturation — papier, texte noir, bruit de compression — la saturation tombe à
zéro ; le logo Tunisianet et le tampon bleu passent largement au-dessus et
ressortent. C'est tout le principe du rendu « couleur » d'un scanner de
téléphone.

**4. Masque flou.** La photo est déjà passée par la compression du téléphone :
la finesse perdue ne revient pas, seule son *apparence* se rattrape.

Effet secondaire utile : les filigranes pâles (PEUGEOT, RENAULT, KIA sur la
facture Ford) passent sous le point noir et disparaissent — autant de bruit en
moins pour l'OCR.

### Recadrage : pourquoi il refuse souvent, et pourquoi c'est voulu

Trois détails, dont aucun ne se devine :

- **La basse résolution est le filtre.** L'analyse tourne en 400 px de large. Ce
  n'est pas une économie : à 800 px, la broderie d'une nappe en dentelle produit
  plus d'arêtes que la feuille et le bord du papier se noie. Réduire puis flouter
  fort transforme le tissu en aplat.
- **La dilatation referme l'anneau**, sinon un bord interrompu par un pli reste
  une courbe ouverte que `findContours` ignore.
- **`RETR_EXTERNAL` plus l'enveloppe convexe écartent le tableau.** Le cadre noir
  du tableau d'articles est net, convexe et large : mis en concurrence, il gagne
  contre le bord réel du papier. Une fois l'anneau du papier refermé autour de
  lui, il n'est plus un contour externe du tout.

Reste que **sur un fond clair, le bord du papier n'existe pas dans l'image**. Sur
`new exp/Tunisianet.jpeg` — feuille blanche sur nappe blanche — le côté gauche ne
produit littéralement aucun contraste. L'enveloppe convexe le referme quand même
par une diagonale à travers le vide, et le redressement bascule la page de
travers. Aucun réglage ne fait voir une arête qui n'est pas là.

D'où le contrôle qui décide de tout : un quadrilatère n'est retenu que si ses
quatre côtés **longent vraiment une arête**. Mesuré sur les échantillons :

| échantillon | appui des quatre côtés | verdict |
|---|---|---|
| `new exp/invoice.jpeg` | 0,33 · 1 · 1 · 1 | refusé — le côté faible rognait le n° de commande |
| `new exp/Tunisianet.jpeg` | 0 · 0,2 · 0,2 · 0 | refusé |
| `new exp/WhatsApp…28.jpeg` | 0,17 · 0,13 · 0,38 · 0,67 | refusé |
| `xp/img20260716_11311808.pdf` | 1 · 1 · 1 · 1 | refusé sur l'**aire** : 38 % du cadre, c'est un tableau |

Deux garde-fous pour deux dangers : la **moyenne** écarte les quadrilatères
inventés, le **minimum** écarte ceux dont trois côtés sont justes et le quatrième
tiré à travers le vide. Un troisième, l'**aire**, écarte les cadres de tableau —
seul cas où l'appui vaut 1 partout alors que le résultat est faux.

Les seuils sont sévères **exprès** : un recadrage qui rogne du texte est
irrattrapable, un recadrage refusé laisse le blanchiment acquis et le bouton
*⤢ Recadrer* à portée de clic. Sur les neuf échantillons du dépôt, aucun ne
passe : le recadrage automatique ne se déclenche que sur fond franchement
contrasté (papier clair sur table sombre). **Pour la démo, posez le document sur
une surface sombre** — ou recadrez à la main, c'est un glissement de quatre coins.

### Recadrage manuel

Une photo, c'est une page : quand la détection refuse, l'éditeur de coins s'ouvre
tout seul avant l'OCR — inutile de dépenser un appel sur un cadrage à refaire.
Un PDF de cinq pages, lui, ouvrirait cinq fois la boîte : pour ceux-là le bouton
*⤢ Recadrer* est disponible page par page, à côté de *⟳ Pivoter*.

## Export Word / Excel

Deuxième workflow, **indépendant du premier** : `export-workflow.json`. Il délègue la conversion
à **Adobe PDF Services**, qui produit un `.docx` respectant la mise en page d'origine et un
`.xlsx` où les tableaux retombent dans de vraies cellules.

> Fidèle sur un PDF natif ou un scan à plat. **Sur une photo, la conversion se dégrade nettement** :
> zones douteuses rendues en rognures d'image, découpage en colonnes instable. Les mesures et la
> sortie envisagée sont en « Limites assumées » et « Pistes ».

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

> **Ce trajet n'est plus le trajet principal.** Depuis « Le tableur », le bouton *Excel* passe
> par la lecture de la page, et ne retombe sur ce qui suit que pour un **PDF natif**, dont
> aucune page n'a d'image à lire. Le reste de la section décrit ce repli, qui marche toujours.

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
- **Ce qui part chez Adobe dépend du texte *visible*, pas du format.** La bonne question n'est
  pas « est-ce un PDF ? » mais « porte-t-il déjà du texte visible ? ». Un PDF natif part tel
  quel : sa couche texte se convertit fidèlement, la réencoder en pixels ne ferait que perdre
  de l'information (`ocr: false`). Tout le reste — photo comme scan — part sous forme de pages
  **redressées**, réassemblées par pdf-lib, et Adobe refait sa propre reconnaissance.

  Envoyer plutôt le PDF consultable d'OCR.space paraît pourtant évident : sa couche texte
  existe bel et bien, pdf.js en extrait 209 éléments correctement placés sur `Tunisianet.jpeg`.
  Mesuré sur cette photo, même image redressée, trois envois au webhook d'export :

  | Envoyé à Adobe | `ocrLang` | Images | Caractères | `<w:tbl>` |
  |---|---|---|---|---|
  | pages redressées, image nue *(en place)* | oui | 18 (420 Ko) | 56 118 | 2 |
  | PDF consultable OCR.space | non | 1 (page entière) | **52** | 0 |
  | PDF consultable OCR.space | oui | 1 (page entière) | **52** | 0 |

  Ces 52 caractères sont le filigrane, et rien d'autre : `Searchable PDF created by OCR.space
  (Free Version)`. **Adobe jette le texte invisible** (mode de rendu 3) : il y voit un artefact
  d'OCR, pas du contenu — et il ne re-reconnaît pas une page qui porte déjà du texte, même
  avec `ocrLang`. Il ne reste alors que l'image. Le même mur attend toute couche texte qu'on
  fabriquerait soi-même en `opacity: 0`.
- **La conversion part au clic**, jamais au dépôt du fichier. Un document déposé mais non exporté
  ne consomme aucun quota.

## Le tableur — lecture de la page par un modèle de vision

Le bouton *Excel* ne passe plus par Adobe. `exportDoc` appelle d'abord `llmXlsx`, et ne retombe
sur la chaîne Adobe que si celle-ci renvoie `null` — c'est-à-dire pour un PDF **natif**, dont
aucune page n'a d'image à lire.

| | |
|---|---|
| Workflow | *Tableaux — Nemotron VL (NVIDIA)* — id `tableurNemotron` |
| Webhook | `POST /webhook/tableur` |
| Modèle | `nvidia/nemotron-nano-12b-v2-vl`, via `integrate.api.nvidia.com` |
| Clé | `NVIDIA_API_KEY`, lue par `$env` dans le nœud *Nemotron* |

Contrat, une page par appel :

```
→ { imageBase64: "data:image/jpeg;base64,…", texte: "<texte OCR de la page>" }
← { ok: true, tables: [ { titre: "Tableau 1", lignes: [["Référence","Désignation",…], …] } ],
    usage: { … } }
```

`llmXlsx` enchaîne les pages, insère une ligne vide entre deux tableaux et passe le tout à
`buildXlsx`. Le classeur est écrit **sans aucune dépendance** : `zipStore` produit un ZIP en
méthode *stored*, `crc32` calcule les sommes de contrôle, `typed` retype les nombres au format
francophone. Un `.xlsx` est un ZIP de XML — le fabriquer à la main coûte moins cher qu'ajouter
une bibliothèque au dépôt.

### Pourquoi un modèle plutôt que de la géométrie

Reconstruire les colonnes à partir des positions de mots **ne converge pas**, c'est mesuré : la
projection par corridors rend **1 colonne**, le regroupement des bords gauches en rend **15**.
Les pages portent deux tableaux de géométries différentes plus de la prose. Et avec `isTable`,
les `Lines` d'OCR.space ne sont pas des lignes visuelles mais des fragments ordonnés par
colonne — les lignes se reconstruisent par `Top`.

### Les quatre réglages, et ce qu'ils corrigent

Chacun vient d'un échec mesuré sur les photos de `new exp/` et `xp/`.

- **L'image *et* le texte OCR partent ensemble.** Avec l'image seule, le modèle **omet purement
  et simplement le tableau des articles** — il ne rend que la ligne d'en-tête. Avec les deux, il
  le rend ligne par ligne. Le texte fait foi pour les caractères, l'image pour la mise en page.
- **Pas de `response_format`.** Le décodage guidé de ce point d'accès tombe en panne dès le
  **deuxième appel** d'une série — HTTP 500 `EngineCore`, ou du JSON malformé — sur schéma
  imbriqué. D'où des lignes `n°|cellule|cellule` découpées côté workflow.
- **L'exemple de la consigne est abstrait** (`1|cellule|cellule`) et non plus une ligne de
  facture plausible. Avec l'ancien exemple concret, le modèle l'a **recopié tel quel comme s'il
  s'agissait de données** : sur `new exp/invoice.jpeg` — un reçu de paiement TUNTRUST — il a
  rendu `W920 | SOURIS SANS FIL | 3`, c'est-à-dire l'exemple, sur un document qui ne le contient
  pas. Des montants inventés sur une pièce comptable : le pire des échecs, il a l'air juste.
- **Toutes les lignes d'un tableau portent le même nombre de cellules.** Sans la consigne, le
  modèle saute les cellules vides d'une exécution à l'autre ; comme le découpage se fait sur le
  nombre de colonnes, `new exp/total.jpg` éclatait en **9 tableaux** au lieu de 4, son tableau de
  produits coupé en trois.

### Le numéro de ligne ne veut rien dire

La consigne demande de préfixer chaque ligne du **numéro du tableau**. Mesuré sur cinq photos, le
modèle numérote tantôt les tableaux (`1,1,2`), tantôt chaque ligne (`1` à `11`), tantôt rien du
tout (tout à `1`). Grouper là-dessus rendait **onze « tableaux » d'une ligne** pour une facture
qui en compte trois — un classeur inutilisable.

Le nœud *Sortie* ne s'en sert donc plus que comme **marque de début de ligne**, et découpe sur le
changement du nombre de colonnes. Ce filtre gagne son couvert deux fois : sur une exécution,
le modèle s'est emballé et a produit **438 lignes vides** à la suite (124 s, `max_tokens` épuisé)
— aucune ne commence par un chiffre suivi d'une barre, toutes ont été jetées.

Après réglage, le tableau des articles ressort **entier** sur `Tunisianet.jpeg`, `total.jpg` et
`WhatsApp…10.17.28`.

### Ce qu'il faut relire avant de s'en servir

**La sortie n'est pas de qualité comptable.** À température 0, sur le même document, le code de
TVA a été lu `T00`, `TOO`, `TO7`, `T07` et `T02` selon les exécutions, et les séparateurs
décimaux se mélangent dans un même tableau. En face, les **totaux sont stables et cohérents**
(257,542 + 17,958 = 275,500), et le modèle récupère parfois ce que l'OCR a perdu : sur
`Tunisianet.jpeg` la colonne *Quantité* manquait du texte OCR, il a lu `3` sur l'image
(7,943 × 3 = 23,829 pour 23,832 imprimé).

Deux tableaux voisins de **même largeur** fusionnent, par construction. Voir le `ponytail:` du
nœud *Sortie*.

## Comment ça marche

```
index.html                                    n8n
  pdf.js — lit le PDF                          ┌─────────────────────────┐
    ├─ couche texte déjà présente ?            │ Webhook  POST /ocr      │
    │    → aucun appel OCR, PDF servi tel quel │   ↓                     │
    └─ sinon : chaque page → JPEG 1600 px      │ OCR.space  moteur 2     │
         └─ OpenCV.js — redresse et blanchit   │   isCreateSearchablePdf │
              └─ POST page par page ───────────→   ↓                     │
                                               │ Télécharger le PDF      │
    pdf-lib — refusionne les pages ←───────────  ↓ {text, pdfBase64}     │
    iframe : texte sélectionnable              └─────────────────────────┘
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

**Aucun LLM dans la chaîne OCR.** Le trajet ci-dessus est entièrement déterministe : rendu des
pages, OCR, refusion du PDF. Le même texte, le même PDF, à chaque exécution.

**L'export Excel, lui, passe par un modèle de vision** depuis l'ajout du tableur — voir
« Le tableur ». C'est la seule étape non déterministe du dépôt, et elle est confinée à ce
bouton : ni l'OCR, ni le PDF consultable, ni l'export Word ne la traversent.

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
✓ canvasToJpeg plafonne le bruit à 511 Ko (max 950 Ko)
✓ fusion 3+2 pages = 5 (attendu 5)
✓ toExportUrl(…/webhook/ocr) → …/webhook/export
✓ orderQuad rétablit l'ordre tl, tr, br, bl
✓ coins détectés à 4.2 px près (max 12)
✓ page redressée 491×645, rapport 0.761 (attendu ≈ 0,762)
✓ PDF d'export : 1 page de 40×60 pt
✓ rendu scan : coin le plus ombré 255 (attendu > 225), texte le plus noir 0 (< 70)
```

Deux de ces contrôles gardent un piège précis :

- **Le témoin positif du recadrage** (feuille penchée sur fond sombre, que la
  détection doit accepter). Comme elle refuse sur tous les échantillons réels du
  dépôt — à raison —, c'est le seul contrôle qui prouve que le chemin
  d'acceptation fonctionne encore.
- **Le rendu scan** est délibérément mesuré sur une page **éparse** : une seule
  ligne de texte sur un dégradé d'ombre. C'est le cas qui a fait tomber la
  version à percentile (fond rendu à 188 au lieu de 255). Ne pas le remplacer par
  une page bien remplie : ça ne testerait plus rien.

Puis les photos de `new exp/` — l'éditeur de coins doit s'ouvrir tout seul :

| Échantillon | Attendu |
|---|---|
| `Tunisianet.jpeg` | éditeur ouvert ; coins glissés → page d'équerre, nappe et pied disparus, logo orange conservé |
| `WhatsApp…28.jpeg` | idem ; tampon bleu et filigranes conservés |
| `invoice.jpeg` | idem ; vérifier que le n° `TUNTRUST-36845695` n'est **pas** rogné à droite |

Puis les six échantillons de `xp/` :

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
- **Le recadrage automatique ne se déclenche que sur fond contrasté.** Sur les neuf
  échantillons du dépôt, il refuse partout — c'est le comportement voulu, pas une panne
  (voir « Recadrage : pourquoi il refuse souvent »). Le blanchiment, lui, s'applique
  toujours. Poser le document sur une surface sombre, ou glisser les quatre coins.
- **Le redressement est une transformation plane.** Il corrige l'inclinaison et la
  perspective, jamais le gondolage du papier : sur `new exp/Tunisianet.jpeg`, la feuille est
  froissée et le texte reste légèrement ondulé une fois la page remise d'équerre. Corriger
  cela demanderait un maillage déformable, pas une homographie.
- **10 Mo par PDF exporté**, marge sous la limite de charge utile de n8n (16 Mo, +33 % en base64).
- **Le tableur reprend *tous* les tableaux du document**, séparés par une ligne vide, sans choisir
  lequel est celui des articles. Sur une facture scannée, les blocs voisins peuvent se retrouver
  fusionnés dans un même tableau (vérifié sur `img20260716_11311808.pdf`) : les lignes d'articles
  restent justes, l'entourage est bruité.
- **Le bouton Excel ne vaut que pour les factures à tableau encadré.** Sur `HENKEL(P92)…`, dont le
  tableau d'articles n'a pas de filets, l'export Word rend chaque ligne d'article dans **une seule
  cellule** : le tableur en hérite et devient inexploitable. Voir « Pistes » ci-dessous.
- **Le `.docx` d'une photo contient des rognures d'image — c'est la résolution, pas Adobe.**
  Les zones que sa reconnaissance juge douteuses ne sont pas rendues en texte, elles
  atterrissent comme images. Trois envois au même webhook, seule l'entrée change :

  | envoyé à Adobe | résolution | rognures | caractères | `<w:tbl>` | `.docx` |
  |---|---|---|---|---|---|
  | `Tunisianet.jpeg` en taille native | 900×1600 (~109 DPI) | **18** | 1 343 | **0** | 110 Ko |
  | la même, agrandie puis blanchie | 1600×2844 | **18** | — | 2 | 449 Ko |
  | `xp/img20260716_11311808.pdf` d'origine | 1654×2338 (~200 DPI) | **0** | 2 295 | **5** | 18 Ko |

  L'hypothèse « Adobe n'a jamais reçu de vrais pixels » est donc **fausse** : à taille native,
  le compte de rognures ne bouge pas. En dessous de ~150 DPI, Adobe refuse de s'engager sur du
  texte, et aucun réglage de la chaîne ne le fera changer d'avis. À 200 DPI, le même service
  rend 5 tableaux et zéro rognure.

  **Les quatre photos du dépôt font exactement 1600 px sur le grand côté** — la recompression
  de WhatsApp. Le plafond de qualité est donc posé avant que le fichier n'atteigne
  l'application. Le geste qui vaut plus que tout réglage : **envoyer la photo d'origine**
  (en *document*, pas en *photo*), ou passer par un scanner. Une capture 12 Mpx est à ~360 DPI
  sur A4, le régime de la troisième ligne.

  Deux conséquences dans le code : `renderImageCanvas` **n'agrandit plus jamais** (l'ancien
  facteur 1,78 gonflait les rognures de 92 Ko à 420 Ko sans rien changer au résultat), et un
  PDF scanné non retouché part **tel quel** chez Adobe au lieu d'être réencodé en JPEG.
- **Les nombres sont typés au format francophone** (`56,221` → `56.221`). Un document anglo-saxon
  (`1,234.56`) resterait du texte — le motif est dans le nœud *Tableaux*.
- **Pas d'extraction de champs structurés** (n° de facture, MF, HT/TVA/TTC) — la démo livre du
  texte, un PDF consultable et, pour l'Excel, des tableaux transcrits. Les *champs* nommés
  restent à faire ; le modèle de vision du tableur est déjà en place pour les rendre.
- **Traitement séquentiel** des pages, pour garder la barre de progression lisible et rester
  sous la limite de débit.
- Un document scanné à l'envers demande un clic manuel (voir plus haut).

## Pistes

### Fabriquer le .docx et le .xlsx nous-mêmes, sans Adobe

Les deux limites précédentes — rognures d'image dans le Word, tableaux sans filets perdus dans
l'Excel — sont deux symptômes d'une même chose : **Adobe reconstruit à partir des pixels un
tableau que nous détenons déjà**. Deux mesures le montrent :

- pdf.js extrait **209 éléments de texte correctement positionnés** du PDF consultable ;
- `isTable: true` (nœud OCR, `ocr-workflow.json`) fait revenir le texte **déjà délimité** :
  tabulation entre colonnes, CRLF entre lignes.

  ```
  BL / Facture\t\r\ntunisianet\tC0071211\t26122190\tđu\t15/06/2026\t\r\nKNOWLEDGE WARE\t\r\n
  ```

Un `.docx` est un ZIP contenant un `document.xml` ; un `.xlsx` de même. Les deux se fabriquent
dans le navigateur à partir de ce texte : paragraphes et vrais `<w:tbl>` d'un côté, découpage
sur `\t` / `\r\n` de l'autre.

Ce que cela règle :

- **aucune image dans le `.docx`**, par construction — les rognures deviennent impossibles ;
- **le découpage en colonnes devient déterministe**, il ne dépend plus des pixels ;
- **les tableaux sans filets passent** : la détection d'OCR.space ne s'appuie pas sur les
  traits, donc le cas `HENKEL(P92)…` cesse d'écraser chaque ligne dans une cellule unique ;
- le filigrane disparaît (il est dans le PDF, pas dans le texte), la limite des 500 conversions
  par mois disparaît, l'export devient instantané au lieu de 7 à 12 s d'aller-retour, et la
  démo redevient réellement à 0 $.

**Le prix à payer**, et il est réel : le `.docx` devient du **texte et des tableaux propres,
pas un fac-similé**. Ni logos, ni polices, ni positionnement d'origine. C'est le bon côté du
marché tant que le Word sert à retravailler le contenu ; c'est une perte sèche si quelqu'un
attend qu'il *ressemble* à la facture.

### Extraction de champs structurés

Voir la limite correspondante ci-dessus : un modèle lisant le texte OCR rendrait `n° de facture`,
`MF` et `HT/TVA/TTC`. Les **lignes d'articles**, elles, sont déjà rendues par le tableur — c'est
le même appel qui servirait, avec une consigne de plus.

À contraindre à **extraire, jamais déduire** (`null` quand le champ est absent), et à afficher à
côté du texte brut : sur un document financier, un montant plausible inventé est le pire des
échecs, il a l'air juste. Ce n'est pas une crainte théorique ici — voir « L'exemple de la
consigne est abstrait » : le modèle a déjà rendu une ligne d'articles entièrement fausse parce
qu'elle traînait dans la consigne.

Ce n'est plus à 0 $ — compter environ 0,003 $ par facture sur le palier le moins cher.

## Si le navigateur affiche une erreur CORS

Le nœud *Webhook* porte `allowedOrigins: "*"`, ce qui suffit dans la majorité des cas. Sur
certaines installations auto-hébergées derrière un reverse proxy, la requête préalable `OPTIONS`
n'atteint pas n8n. Deux issues :

- autoriser la méthode `OPTIONS` sur `/webhook/*` dans le reverse proxy ; ou
- éviter la requête préalable : passer `'Content-Type': 'text/plain'` dans le `fetch` de
  `index.html` et parser le corps avec un nœud *Code* en tête de workflow. Une requête simple
  ne déclenche pas de `OPTIONS`.
