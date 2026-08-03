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
| Webhook | `https://ocr.4prod.tn/webhook/ocr` |
| Interface | https://demo-ocr.4prod.tn (conteneur nginx, déployé par Coolify depuis ce dépôt) |
| Éditeur | http://localhost:5678 (`admin` / `Admin123`) |

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

> **Importez `ocr-workflow.local.json`, jamais `ocr-workflow.json`.** `OCRSPACE_API_KEY`
> **n'est pas définie** dans le conteneur `aiwp_n8n` (vérifié : `docker exec aiwp_n8n printenv
> OCRSPACE_API_KEY` ne renvoie rien). La version versionnée, qui lit la clé via `$env`, part donc
> en production avec une clé vide et OCR.space répond `E555: API key not valid`. C'est la copie
> locale, porteuse de la clé en clair, qui doit être importée.

```bash
export MSYS_NO_PATHCONV=1                                   # Git Bash : sinon /tmp devient un chemin Windows
docker cp ocr-workflow.local.json aiwp_n8n:/tmp/ocr-workflow.json
docker exec aiwp_n8n n8n import:workflow --input=/tmp/ocr-workflow.json
docker exec aiwp_n8n n8n update:workflow --id=ocrDemoFactures --active=true
docker exec aiwp_n8n n8n publish:workflow --id=ocrDemoFactures
docker restart aiwp_n8n                                     # le webhook est enregistré au démarrage

./test-webhook.sh http://localhost:5678/webhook/ocr         # seule preuve que c'est en ligne
```

Trois pièges :

- **`import:workflow` désactive le workflow** (« Deactivating workflow … ») et `publish:workflow`
  ne le réactive pas. Sans la ligne `update:workflow --active=true`, n8n redémarre en affichant
  `Start Active Workflows:` suivi de rien, et l'URL répond `Cannot POST /webhook/ocr`.
- **`publish:workflow` seul ne suffit donc pas**, contrairement à ce que laissait entendre cette
  page. Les deux commandes sont nécessaires, dans cet ordre : activer, puis publier.
- **`export:workflow` exporte le brouillon, pas la version publiée.** Il ne prouve donc rien sur
  ce qui tourne réellement. Seul `test-webhook.sh` fait foi.

Si la clé venait à être perdue, elle survit dans l'historique des versions de n8n :

```bash
docker exec aiwp_n8n sh -c 'grep -ao "\"name\":\"apikey\",\"value\":\"[^\"]\{6,60\}\"" ~/.n8n/database.sqlite | sort -u'
```

Le symptôme d'une version obsolète en production : `pdfBase64` vaut `filesystem-v2` au lieu du
PDF, et l'interface affiche « Le service OCR n'a pas renvoyé de PDF ».

### Démo hors de cette machine

`localhost:5678` n'est joignable que depuis ce poste. Pour montrer la démo ailleurs, exposez n8n
(tunnel, reverse proxy) et changez la constante `WEBHOOK_URL` en haut du `<script>` de
`index.html`, ou saisissez l'URL dans le panneau *⚙ Configuration* de l'interface — elle prend le
pas sur la constante et reste mémorisée dans le navigateur.

## Export Word / Excel

Les deux boutons empruntent des chemins entièrement différents :

| | Word | Excel |
|---|---|---|
| Où | `export-workflow.json` → Adobe PDF Services | `index.html`, dans le navigateur |
| Quoi | mise en page d'origine restituée | colonnes reconstruites par géométrie |
| Coût | 1 conversion Adobe | aucun quota, aucun aller-retour |

Le workflow d'export ne sert donc plus **que** le Word.

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

### Deux sources, parce qu'aucune ne suffit

Adobe sait exporter directement en `.xlsx` : **sur les factures de `xp/`, le résultat est
inutilisable**, tout le tableau atterrit dans une seule cellule. Son export **Word**, lui, balise
de vrais `<w:tbl>`. Mesuré sur les échantillons :

| | Adobe `.docx` | géométrie | retenu |
|---|---|---|---|
| `7885` | 8 tableaux exacts, `cacao& lait` intact | cellules perdues, totaux absents | **docx** |
| `6701` | 13 colonnes alignées | `Date Prix unit Prix H.T` fusionné | **docx** |
| `HENKEL` | 5 tableaux sur 7 à **une seule colonne** | 38×4 avec prix et quantités | **géométrie** |
| scan | bloc de taxes propre, **pas** les articles | les articles, pas les taxes | **les deux** |

Aucune source ne gagne partout, et un aiguillage qui tranche pour tout le document perd donc
toujours quelque chose. Les deux tournent, systématiquement :

```
PDF → Adobe → .docx → <w:tbl>                    ┐
                                                  ├→ dédoublonnage → .xlsx
PDF natif → pdf.js          → {x, y, largeur}    │
scan → OCR.space (calque)   → {Left, Top, Width} ┘
```

**Arbitrage.** Quand les deux décrivent le même tableau, la version Adobe gagne : ses bornes de
cellules sont *déclarées*, celles de la géométrie *devinées*. Priorité réservée aux tableaux
Adobe réellement remplis — sur un scan il fabrique aussi des grilles de mise en page, larges et
creuses, qui évinceraient sinon un vrai tableau. Le doublon se reconnaît aux **mots** communs,
pas aux cellules : les deux sources ne découpent pas au même endroit.

Coût : **un bouton Excel = une conversion Adobe** (comme le bouton Word). La géométrie, elle, ne
coûte rien — aucun appel réseau.

Le reste de cette section décrit la moitié géométrique, seule à l'œuvre quand rien n'est balisé.

Le point délicat est la détection des colonnes. Une colonne de montants est alignée **à droite**
et n'a donc aucun bord gauche commun : on ne peut pas grouper les mots par leur `x`. On repère à
la place les **blancs verticaux**. Deux méthodes ont été essayées :

- *couloir entièrement blanc sur toute la bande* — précis sur un long tableau, mais un seul
  libellé débordant efface la frontière. Sur une facture à une seule ligne d'article (`7885`,
  `6701`) il ne restait presque aucune colonne : mesuré à **3 colonnes au lieu de 10**.
- *vote* — chaque blanc intra-ligne propose une frontière, celles que plusieurs lignes
  confirment sont retenues, et un mot à cheval est rangé par son **centre**. C'est la méthode
  retenue : `7885` retrouve ses **10 colonnes**, `6701` ses 11, et HENKEL 4 là où il n'y en avait
  aucune.

Les constantes de réglage (`ROW_TOL`, `GAP_EM`, `VOTE_FRAC`) sont regroupées en tête de section
dans `index.html` — ce sont les seules à toucher si un document sort du cadre.

Effets de bord : le bouton Excel ne consomme **aucun quota Adobe** et répond sans aller-retour
réseau, et le workflow d'export a perdu cinq nœuds (*Tableur ?*, *Renommer*, *Decompresser*,
*Tableaux*, *Feuille*) avec les deux pièges n8n qu'ils traînaient (`require('zlib')` interdit, et
le nœud *Compression* qui ne dézippe que si `fileExtension` vaut `zip`).

### Ce que contient le classeur

**Le document, et rien d'autre.** Une seule feuille, tous les blocs dans l'ordre de lecture, du
haut de la page au bas. Le client ouvre le fichier et reconnaît sa facture. Sur `7885…`, 40 lignes :

```
 1  SOCIETE GIAS INDUSTRIES
 2  SARL au capital de 20 200 000 TND  T.V.A : 1180957 F/A/M/000  Identifiant Unique
 5  SBA001 | MONOPRIX
 8  BON DE LIVRAISON - FACTURE
 9  Numéro | Date
10  FAC21-MBK01681 | 10/02/2021
15  Cod | Désignation | Qté | Unité | Poids | P.U.H.T | Remise | M.HT | Taxe | MTTC
16  PFV0535 | Crème DUO biscuit cacao& lait | 2,000 | CAR | 4,1 | 31,234 | 10% | 56,221 | …
19  BRUT.H.T | Escompte | NET.H.T | Total Taxes | Total TTC
20  56,221 |  | 56,221 | 10,682 | 67,503
28  SOIXANTE-SEPT DINARS ET CINQ CENT TROIS MILLIMES
30  Net à payer | 67,503
34  Conditions générales de vente
40  Siège Social : Rue Lac Taba…
```

Chaque bloc commence colonne A, séparé du suivant par une ligne vide, entouré de filets qui
reprennent les cadres de la facture. Deux blocs côte à côte sur le papier se retrouvent l'un sous
l'autre — c'est le prix d'une feuille lisible.

**Rien n'est ajouté qui ne soit sur le document** : ni colonne calculée, ni somme de contrôle, ni
feuille de synthèse. Une seule feuille annexe, `Texte`, garde le texte brut par page pour vérifier
une cellule douteuse sans rouvrir le PDF.

**Le texte hors tableau compte aussi.** Le nom du fournisseur, le montant en toutes lettres, les
conditions de vente et le pied de page ne sont dans aucun tableau : ils sont lus dans les
paragraphes du `.docx`. Deux pièges à connaître, sans quoi le résultat est inexploitable :

- Adobe range le contenu dans des **zones de texte**, donc `SOCIETE GIAS INDUSTRIES` n'est pas un
  paragraphe de premier niveau mais un `txbxContent` imbriqué. On parcourt donc tous les `w:p`, à
  n'importe quelle profondeur, hors `w:tbl`.
- Word écrit **chaque dessin deux fois** (`mc:Choice` et `mc:Fallback`), et un paragraphe
  conteneur porte la concaténation de ses enfants. Sans écarter les conteneurs et dédoublonner
  les textes, la feuille se terminait par des pavés du genre
  `CodeBaseTauxMt TaxeTVA 19%56,221…`.

**L'ordre de lecture** est rétabli en repérant chaque bloc parmi les mots situés : la géométrie
connaît déjà sa page et son ordonnée, un tableau `.docx` est retrouvé par le texte de ses
premières cellules, une ligne de texte par ses mots pris un à un. Quand le repérage échoue, le
bloc reste juste après le précédent — l'ordre du `document.xml` est déjà le bon.

**Si la conversion Adobe échoue**, le tableur sort quand même : géométrie seule, moins de blocs,
colonnes devinées. L'interface le dit en orange. Une dégradation silencieuse passerait pour le
résultat normal ; c'est arrivé une fois en recette, sur un aléa réseau.

Sur `7885`, le classeur contient désormais **tout** ce que porte la facture : les 10 colonnes
d'articles, le bloc `Code / Base / Taux / Mt Taxe`, le bloc `BRUT.H.T … Total TTC`, le
`Droit de timbre`, et `Net à payer`. Il n'en sortait auparavant que le tableau d'articles.

La colonne **`Écart qté×PU`** est la raison d'être du classeur : elle recalcule chaque ligne
(remise comprise, sinon toute ligne remisée serait signalée à tort) et passe en rouge dès que le
résultat s'écarte de plus d'un centime du montant lu. Une somme de contrôle est ajoutée sous la
colonne des montants. C'est ce qui distingue un tableur qu'on doit croire d'un tableur qui
**dit où l'OCR s'est trompé**.

Trois points à connaître :

- **L'entête est devinée**, pas déclarée : première ligne portant un libellé connu (`Qté`,
  `P.U.`, `Montant`…) *et* suivie d'une ligne chiffrée. Les deux conditions se rattrapent l'une
  l'autre — sans la première, une ligne de méta (« Référence commande… ») passait pour l'entête ;
  sans la seconde, le bloc de totaux gagnait contre la vraie entête d'articles.
- **Le PDF envoyé à Adobe est l'original**, pas celui reconstruit par l'OCR. L'étape est sautée
  (`ocr: false`) quand le document possède déjà une couche texte.
- **La conversion part au clic**, jamais au dépôt du fichier.

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
✓ tableau sans filets → 4 lignes × 4 colonnes (attendu 4 × 4)
✓ le bloc adresse reste hors du tableau d'articles
✓ calque OCR → 4 lignes × 4 colonnes (attendu 4 × 4)
✓ typeCell(007) → "007"
✓ unzipEntry restitue l'entrée à l'identique
✓ gridSpan déroulé → ["A","B fusionnée","","D"]
✓ doublon arbitré en faveur du .docx → 2 tableaux gardés
✓ ordre de lecture rétabli → Fournisseur → Designation → BRUT.H.T
✓ ligne de texte replacée en tête → SOCIETE FOURNISSEUR SARL
✓ une ligne de données n'est pas prise pour une entête
```

Le tableau de l'auto-test est **sans filets et à montants alignés à droite** : c'est exactement ce
que l'ancienne lecture des `<w:tbl>` ne savait pas voir.

Puis déposer les six échantillons de `xp/` :

| Échantillon | Attendu |
|---|---|
| `7885…FAC21MBK01681.pdf` | badge texte natif ; OCR forcé → `FAC21-MBK01681` |
| `6701…FactureN9001462628.pdf` | badge texte natif ; OCR forcé → `9001462628` |
| `HENKEL(P92)…PDF` | badge texte natif ; **OCR forcé** → 5 pages traitées puis refusionnées en un seul PDF (c'est ce cas qui prouve que la limite de 3 pages est levée) |
| `img20260716_11230272.pdf` (948 Ko) | passe malgré la limite de 1 Mo |
| `img20260716_11311808.pdf` | texte cohérent avec la facture GIAS |
| `img20260716_11323829.pdf` | ordre de lecture incohérent → **⟳ Pivoter** → correct |

Puis le bouton **⬇ Excel** sur `7885…`, en gardant le PDF ouvert à côté. Le classeur se lit de
haut en bas comme la facture : le fournisseur, le client, le numéro, la ligne d'article sur ses
10 colonnes, les totaux, le montant en toutes lettres, `Net à payer 67,503`, les conditions de
vente, le pied de page.

C'est le geste qui vend la démo : rien à expliquer, le client compare les deux à l'écran.

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
- **Le tableau retenu est celui qui score le mieux, pas celui qui est juste.** Sur une mise en
  page où un bloc voisin est aussi grand, aussi chiffré et aussi rempli que les articles,
  l'onglet `Lignes` peut désigner le mauvais. Rien n'est perdu — les autres tableaux sont sur les
  onglets suivants — mais l'onglet d'accueil serait faux. À vérifier sur un document inconnu.
- **Le seuil de dédoublonnage vaut 0,6 mot commun.** Deux tableaux réellement distincts qui
  partagent l'essentiel de leur vocabulaire (mêmes entêtes, mêmes libellés d'articles) seraient
  fusionnés en un seul, le mieux noté. Non observé sur `xp/`, mais c'est le réglage à regarder si
  un tableau disparaît sans raison.
- **Le bouton Excel consomme une conversion Adobe.** Il n'en consommait aucune dans la version
  purement géométrique. C'est le prix des bornes de cellules exactes, et le quota reste de
  500 conversions/mois.
- **HENKEL reste partiellement plat.** Chaque article y occupe 4 à 5 lignes physiques
  (désignation, conversion UTR/UC, quantité et prix, EAN, remise) : la géométrie retrouve bien
  4 colonnes, mais rassembler ces lignes en un article par ligne demanderait des règles propres à
  ce fournisseur. C'était **une seule cellule par ligne** avec l'ancienne chaîne.
- **La locale décimale est déduite du document** (`56,221` → `56.221`), en comptant qui l'emporte
  de la virgule ou du point. Un document panachant les deux conventions se trompera.
- **Restent volontairement du texte** : les codes à zéro initial (`007`), les suites de plus de
  12 chiffres (EAN, RIB — un nombre les afficherait en notation scientifique) et tout ce qui ne
  correspond à aucun motif connu.
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
