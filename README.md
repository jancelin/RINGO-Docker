
# RINGO-QC Docker — QC & Viewer HTML5 pour RINEX/CRINEX

Ce bundle Docker permet :

* d’exécuter le **contrôle qualité (QC)** RINGO sur un fichier **RINEX/CRINEX** (compressé ou non),
* de **télécharger automatiquement** le fichier **RINEX NAV (BRDC 01D)** correspondant (détection via le nom ou **l’entête RINEX**) ou de le fabriquer si l'on utilise un log au format RTCM3,
* de générer un **viewer HTML5** interactif,
* d’écrire tous les fichiers de sortie dans un dossier **`./data/`** (propriété UID\:GID = **1000:1000**).

## 1) Prérequis

* Docker & Docker Compose installés
* Accès Internet sortant (pour l'installation et surtout l’auto-NAV BRDC)
* OS Linux/WSL ou macOS

## 2) Arborescence du projet

```
.
├─ Dockerfile
├─ docker-compose.yml
├─ entrypoint.sh
└─ data/                 # ← créez ce dossier (vos RINEX/CRINEX ici)
```

Créez le dossier `data` si besoin :

```bash
mkdir -p data
```

## 3) Build de l’image

```bash
docker compose build --no-cache
```

## 4) Utilisation

### 4.1 Traitement “one-shot” (QC + HTML, puis sortie)

Placez votre fichier dans `./data/` puis lancez :

```bash
docker compose run --rm -T \
  -e INPUT=<mon_fichier_rinex_or_crinex> \
  -e AUTO_NAV=1 \
  -e SERVE=0 \
  ringo
```
## 4.2 Traiter un fichier **RTCM3** brut (conversion auto en RINEX + QC)

Lancement du log d'une base du réseau Centipede-RTK

```bash
str2str -in ntrip://centipede:centipede@crtk.net:2101/CT02 -out file://CT02.RTCM3
```

Placez votre dump RTCM3 dans `./data/` (ex. `CT02.rtcm3`) puis lancez :

```bash
docker compose run --rm -T \
  -e INPUT=CT02.rtcm3 \
  -e RTCMGO_ENABLE=1 \
  -e AUTO_NAV=1 \
  -e SERVE=0 \
  -e VERBOSE=1 \
  ringo
```
## 4.3 Convertir un log GNSS avant Traitement

```bash
convbin data/2025-09-24_13-23-34_GNSS-1.sbf -v 4.00 -r sbf \
        -hc CentiCheck -hm CT02 \
        -od -os -oi -ot -ti 1 -tt 0 \
        -o data/2025-09-24_13-23-34_GNSS-1.25o
```
Puis:
```bash
docker compose run --rm -T \
  -e INPUT=CT02.rtcm3 \
  -e RTCMGO_ENABLE=1 \
  -e AUTO_NAV=1 \
  -e SERVE=0 \
  -e VERBOSE=1 \
  ringo
```

Exemples :

```bash
# Exemple 1 h (CRINEX) — détecte YYYY/DDD dans le nom
docker compose run --rm -T \
  -e INPUT=A61300FRA_S_20252650900_01H_01S_MO.crx.gz \
  -e AUTO_NAV=1 \
  -e SERVE=0 \
  ringo

# Exemple 24 h (RINEX 3.04) — lit la date dans l’entête TIME OF FIRST OBS
docker compose run --rm -T \
  -e INPUT=2025-09-24-CT02_1s_full.obs \
  -e AUTO_NAV=1 \
  -e SERVE=0 \
  -e VERBOSE=1 \
  ringo
```

**Résultats** dans `./data/myfile` :

* `*_qc.log` — rapport texte QC,
* `*_qc.html` — viewer QC,
* `*.html` — viewer Observations,
* `*_qc.stderr.log` — diagnostics,
* `BRDC00WRD_R_YYYYDDD0000_01D_MN.rnx.gz` — nav auto-téléchargé ou généré si log RTCM3.

> Si votre fichier couvre **deux jours**, l’auto-NAV prend d’abord le BRDC du **jour de début**. Au besoin, fournissez manuellement le BRDC du jour suivant via `INPUT_NAV` (voir plus bas).

### 4.2 Lancer avec serveur web (consultation directe des HTML)

```bash
docker compose run --rm -T \
  -e INPUT=<mon_fichier_rinex_or_crinex> \
  ringo
# puis ouvrez http://localhost:8080
```

### 4.3 Forcer un NAV spécifique (sans auto-download)

```bash
# Placez le NAV dans ./data puis :
docker compose run --rm -T \
  -e INPUT=<mon_fichier_rinex_or_crinex> \
  -e INPUT_NAV=BRDC00WRD_R_20252670000_01D_MN.rnx.gz \
  -e AUTO_NAV=0 \
  -e SERVE=0 \
  ringo
```

### 4.4 Générer aussi des CSV (rnxcsv)

```bash
docker compose run --rm -T \
  -e INPUT=<mon_fichier_rinex_or_crinex> \
  -e AUTO_NAV=1 \
  -e CSV=1 \
  -e SERVE=0 \
  ringo
```

## 5) Variables d’environnement utiles

* `INPUT` (obligatoire) : chemin relatif sous `/data` vers le RINEX/CRINEX (ex. `A613...crx.gz`, `2025-09-24-CT02_1s_full.obs`).
* `AUTO_NAV` (défaut `1`) : tente de récupérer **BRDC 01D** chez BKG. Détecte la date via `YYYYDDD` **ou** via l’**entête RINEX**.
* `INPUT_NAV` : fournit un **NAV** manuel (désactivez l’auto-NAV avec `AUTO_NAV=0`).
* `SERVE` (`1`|`0`) : sert `/data` sur `http://localhost:8080` (si `1`).
* `CSV` (`1`|`0`) : export CSV `rnxcsv` (observations + QC).
* `VERBOSE` (`1`|`0`) : traces supplémentaires (URLs testées, etc.).
* `NAV_BASE_URL` : miroir NAV (défaut BKG : `https://igs.bkg.bund.de/root_ftp/IGS`).
* `NAV_PREFER` (`BRDC`|`BRDM`) : ordre de préférence.
* `BRDC_CANDS_ORDER` (défaut `WRD,IGS`) : ordre d’essai des noms BRDC.
* `PUID`/`PGID` (défaut `1000`/`1000`) : propriétaire des fichiers générés.
* `RTCMGO_ENABLE` : converti un fichier de log rtcm3 en rinex avant traitement.

> Tous les **fichiers générés** dans `./data/` sont en **1000:1000** par défaut (modifiable via `PUID/PGID`).

## 6) Dépannage rapide

* **Fichiers `*_qc.html` ou `*_qc.log` vides**
  Consultez `*_qc.stderr.log`. Souvent : *“no nav file found”*.
  ➜ Vérifiez connexion Internet, et que l’auto-NAV a bien trouvé **YEAR/DOY** (activez `VERBOSE=1`).
  ➜ Sinon, fournissez `INPUT_NAV` manuellement.

* **Erreur réseau au téléchargement NAV**
  Essayez un autre miroir via `NAV_BASE_URL`, ou fournissez `INPUT_NAV`.

* **Gros fichiers (24 h)**
  Le viewer HTML peut être volumineux (centaines de Mo). Préférez l’ouverture locale via votre navigateur.

---

## 7) Comprendre le **log QC** (`*_qc.log`)

Le log texte résume l’analyse QC par constellation et par satellite :

* **En-tête & métadonnées**

  * Nom du RINEX analysé (Obs), NAV utilisé (BRDC/BRDM), dates de début/fin, matériel (Marker/Receiver/Antenna), constellations présentes.

* **Statistiques globales**

  * `Number of obs epochs` (ex. 3600 pour 1 h @1 Hz), `Observation rate`, `N obs data (>10°)`.

* **Table par satellite (“For each satellite”)**

  * **STD(MP1/MP2/MP5)** : écart-type des **combinaisons Multipath** par bande (mètre). Plus petit = mieux.
  * **slips/nobs (MP1, MP2, MP5, GF, MW)** : nombre de **cycle slips** détectés / nombre de mesures.
  * **IOD(L1)** : changements d’Issue-of-Data observés (navigation).

* **Résumé par constellation**

  * Moyennes des **STD(MP\*)**, totaux **slips/nobs** pour GF & MW, etc.

**Rappels méthodes** :

* **MPx (Multipath)** : indicateur des multi-trajets par bande (L1/L2/L5, E1/E5a/E5b, …).
* **GF (Geometry-Free)** : combinaison de phase sensible à l’ionosphère ; **sauts** = slips.
* **MW (Melbourne-Wübbena)** : sensible aux incohérences code/phase ; **sauts** = slips.

---

## 8) Lire les **graphiques** (viewer `*.html` et `*_qc.html`)

* **MP1 / MP2 / MP5**

  * Valeur **en mètres** ; nuage resserré autour de 0 = très peu de multi-trajets.
  * **Points orange** = **cycle slips** détectés sur la bande correspondante.

* **GF (Geometry-Free)**

  * Courbe souvent lisse avec l’élévation (variation ionosphérique). **Sauts** = slips.

* **MW (Melbourne-Wübbena)**

  * Série quasi-plate en régime normal ; **sauts** ou dispersion = slips/bruit code.

* **IOD1**

  * Marque les **changements d’éphémérides/horloge** (pas forcément anormaux).

* **Élévation**

  * Trajectoire en gris ; à basse élévation, le bruit & MP augmentent typiquement.

**Bonnes pratiques de lecture** :

* Comparez **MP** entre bandes : L5/E5 ont souvent de meilleurs MP que L1/L2.
* Les **slips** se concentrent souvent à **basse élévation** ou lors de **gaps**.
* Contrôlez que les bandes attendues (ex. **GPS L5**) sont **peuplées** (sinon revoir la conversion RTCM→RINEX).

---

## 9) Exemples de flux de travail

### Comparer deux fichiers sur la **même heure**

1. **Extraire 1 h** d’un RINEX 24 h (RTKLIB) :

   ```bash
   convbin 2025-09-22-CT02_1s_full.obs \
     -r rinex \
     -o CT02_20252650900_01H_01S.obs \
     -v 3.04 \
     -f 3 \
     -ts 2025/09/22 09:00:00 \
     -te 2025/09/22 10:00:00
   ```
2. **QC sur le CRINEX de référence** (auto-NAV) :

   ```bash
   docker compose run --rm -T \
     -e INPUT=A61300FRA_S_20252650900_01H_01S_MO.crx.gz \
     -e AUTO_NAV=1 \
     -e SERVE=0 \
     ringo
   ```
3. **QC sur le RINEX extrait** (forcer le **même NAV**) :

   ```bash
   docker compose run --rm -T \
     -e INPUT=CT02_20252650900_01H_01S.obs \
     -e INPUT_NAV=BRDC00WRD_R_20252650000_01D_MN.rnx.gz \
     -e AUTO_NAV=0 \
     -e SERVE=0 \
     ringo
   ```
4. Ouvrez les deux `*_qc.html` pour comparer **MP**, **GF/MW slips**, **IOD**, **présence des 3 bandes**.

---

## 10) Notes

* L’auto-NAV tente d’abord `BRDC00WRD_R_YYYYDDD0000_01D_MN.rnx.gz`, puis `BRDC00IGS_...`.
* Vous pouvez fixer un autre miroir via `NAV_BASE_URL`.
* Tous les fichiers sortants sont chown **1000:1000** (modifiables via `PUID/PGID`).
* Le viewer 24 h peut être volumineux (ouverture lente dans le navigateur).

---

**Bon QC !**

## Licence & Crédits

### Code de ce dépôt

Le contenu **de ce dépôt** (scripts, Dockerfile, entrypoint, documentation) est sous licence  
**GNU Affero General Public License v3.0 (AGPL-3.0)**.

- Voir le fichier [`LICENSE`](./LICENSE) (AGPL-3.0).  
- L’AGPL impose que toute utilisation via un service réseau donne accès au **code source complet** de la version en service, y compris les **modifications locales** apportées aux fichiers de ce dépôt.

> ⚠️ Cette licence s’applique **uniquement** au code que nous publions ici.  
> Les composants tiers téléchargés au build (ex. RINGO) restent couverts par **leurs propres conditions**.

---

### RINGO (tiers, téléchargé au build)

Ce dépôt **n’inclut pas** le binaire RINGO. Au moment du `docker compose build`, RINGO est téléchargé depuis la source officielle de la **Geospatial Information Authority of Japan (GSI)**.

- **RINGO** © GSI — Conditions : **GSI Website Terms of Use (v2.0)** / Public Data License v1.0 (PDL 1.0, compatible CC BY 4.0) ; attribution et indication des modifications requises.  
- Source : https://terras.gsi.go.jp/software/ringo/en/  
- Texte des conditions GSI : https://www.gsi.go.jp/ENGLISH/page_e30286.html  
- Les **logos/symboles** GSI ne sont **pas** couverts : ne pas les republier dans ce dépôt.

**Attribution recommandée** à inclure dans vos rapports/produits qui utilisent RINGO via ce projet :

> *“This work uses RINGO provided by the Geospatial Information Authority of Japan (GSI), subject to the GSI Website Terms of Use (v2.0) / PDL 1.0. Source: https://terras.gsi.go.jp/software/ringo/en/ . Modifications: orchestration scripts (Docker/entrypoint) to perform QC and HTML viewers generation.”*

**Auteurs RINGO**: Satoshi Kawamoto, Naofumi Takamatsu, Satoshi Abe (GSI).  
Publication associée : Kawamoto et al., *Earth, Planets and Space*, 2023 (doi: 10.1186/s40623-023-01811-w).

> 🔎 Pratique : en construisant l’image, vous acceptez les **Terms of Use** de GSI pour RINGO.  
> Ce dépôt **ne publie aucune image Docker** ni binaire RINGO : chacun **construit localement**.

---
### Mention d’assistance via ChatGPT

> *“Portions of the scripts and documentation were drafted with assistance from ChatGPT (OpenAI). Final design, verification, and responsibility for the code rest with the maintainers.”*

---

### Remarques juridiques

- **Compatibilité de licences** : le **code du dépôt** est sous **AGPL-3.0** ; **RINGO** reste sous les **Terms of Use GSI / PDL 1.0** — il n’est ni re-licencié ni inclus dans ce dépôt.  
- **Redistribution** : si vous redistribuez des artefacts contenant RINGO (ex. images Docker), assurez l’**attribution** GSI et le respect des **Terms of Use** ; ce dépôt n’en publie pas.  
- **Logos/symboles** GSI : exclus des conditions ouvertes — ne pas les utiliser ici.  
- **Non-conseil juridique** : ces informations sont fournies à titre indicatif, sans constituer un avis juridique.
