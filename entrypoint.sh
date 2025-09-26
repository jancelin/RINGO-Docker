#!/usr/bin/env bash
set -euo pipefail

# ---- Params ----
IN="${INPUT:-}"              # chemin RINEX/CRINEX/RTCM dans /data (.obs/.crx/.rtcm3/.gz/.bz2/.Z)
NAV="${INPUT_NAV:-}"         # RINEX NAV optionnel (.rnx[.gz])
SERVE="${SERVE:-1}"          # 1 = sert /data:8080 après traitement
CSV="${CSV:-0}"              # 1 = génère aussi CSV rnxcsv
PUID="${PUID:-1000}"         # UID propriétaire des sorties
PGID="${PGID:-1000}"         # GID propriétaire des sorties
AUTO_NAV="${AUTO_NAV:-1}"    # 1 = auto-télécharge BRDC/BRDM si NAV absent
VERBOSE="${VERBOSE:-1}"      # 1 = logs verbeux
RINGO_TIMEOUT="${RINGO_TIMEOUT:-900}"  # timeout (s) pour ringo

# NAV mirror & preference
NAV_BASE_URL="${NAV_BASE_URL:-https://igs.bkg.bund.de/root_ftp/IGS}"
NAV_PREFER="${NAV_PREFER:-BRDC}"                 # BRDC or BRDM
BRDC_CANDS_ORDER="${BRDC_CANDS_ORDER:-WRD,IGS}"  # ordre d'essai des labels

# ---- Dev-friendly: si INPUT vide et des args sont fournis, exécuter la commande
if [[ -z "${IN:-}" && "$#" -gt 0 ]]; then
  exec "$@"
fi

# ---- Checks de base
if [[ -z "$IN" ]]; then
  echo "ERROR: set INPUT to your file under /data (e.g., INPUT=xxx.obs.gz)" >&2
  exit 1
fi
if [[ ! -f "/data/$IN" ]]; then
  echo "ERROR: /data/$IN not found" >&2
  exit 2
fi

cd /data

# Nom de fichier & base (sans extensions)
fname="$(basename -- "$IN")"

base="$fname"
# compressions
base="${base%.gz}"; base="${base%.bz2}"; base="${base%.Z}"
# formats RINEX/CRINEX
base="${base%.crx}"; base="${base%.d}"; base="${base%.o}"; base="${base%.obs}"
# RINEX v2 : .YYo / .YYO (ex: .25o)
if [[ "$base" =~ \.[0-9][0-9][oO]$ ]]; then
  base="${base%???}"   # retire .??o
fi
# RTCM dumps
base="${base%.rtcm3}"; base="${base%.RTCM3}"; base="${base%.rtcm}"; base="${base%.RTCM}"

# *** NOUVEAU *** : supprime tous les '.' terminaux (évite "nom..html")
while [[ "$base" == *"." ]]; do
  base="${base%.}"
done

[[ -z "$base" ]] && base="$fname"

# Dossier de travail dédié
outdir="$base"

# Si un FICHIER porte ce nom, on choisit un nom alternatif
if [[ -e "$outdir" && ! -d "$outdir" ]]; then
  alt="${base}_run$(date +%s)"
  echo "WARN: '$outdir' existe et n'est pas un dossier. Utilisation de '$alt'." >&2
  outdir="$alt"
fi

# Crée le dossier si nécessaire (silencieux si déjà présent)
mkdir -p "$outdir"
chown "$PUID:$PGID" "$outdir" || true

# Déplacer l'INPUT dans le sous-dossier si besoin
if [[ "$(dirname -- "$IN")" == "." ]]; then
  # L'input était à la racine: on le déplace
  mv -f -- "$fname" "$outdir/$fname"
fi
# Normaliser les chemins pour la suite (on travaille DANS outdir)
cd "$outdir"
IN="$fname"
fname="$IN"

# Déplacer un NAV fourni manuellement s'il est à la racine
if [[ -n "${NAV:-}" && -f "/data/$NAV" ]]; then
  navname="$(basename -- "$NAV")"
  if [[ "$(dirname -- "$NAV")" == "." ]]; then
    mv -f -- "/data/$NAV" "./$navname"
    chown "$PUID:$PGID" "./$navname" || true
  fi
  NAV="./$navname"
fi

# Prépare le log stderr (dans le sous-dossier)
stderr_log="${base}_qc.stderr.log"
: > "$stderr_log"
chown "$PUID:$PGID" "$stderr_log" || true

log()  { echo -e "$@"; }
vlog() { [[ "$VERBOSE" == "1" ]] && echo -e "$@" || true; }

run_cmd() {
  local out="$1"; shift
  local tmp="${out}.tmp"
  if timeout --preserve-status --signal TERM "${RINGO_TIMEOUT}" "$@" > "$tmp" 2>>"$stderr_log"; then
    mv -f "$tmp" "$out"
    chown "$PUID:$PGID" "$out" || true
    vlog "OK -> $out"
    return 0
  else
    rm -f "$tmp" || true
    echo "ERROR running: $* (see $stderr_log)" >&2
    return 1
  fi
}

# === PRE-STEP: conversion RTCM3 -> RINEX via 'ringo rtcmgo' si INPUT est un dump RTCM ===
RTCMGO_ENABLE="${RTCMGO_ENABLE:-1}"
RTCMGO_OPTS="${RTCMGO_OPTS:-}"

is_rtcm_input=0
case "$IN" in
  *.rtcm3|*.RTCM3|*.rtcm|*.RTCM) is_rtcm_input=1 ;;
esac

if [[ "$RTCMGO_ENABLE" == "1" && $is_rtcm_input -eq 1 ]]; then
  if ! ringo rtcmgo --help >/dev/null 2>&1; then
    echo "ERROR: 'ringo rtcmgo' not available; check ringo installation." >&2
    exit 3
  fi
  vlog "RTCMGO: converting $IN to RINEX (OBS+NAV if available)..."
  base_rtcm="$base"
  out_obs="${base_rtcm}.obs"
  out_nav="${base_rtcm}.rnx"
  rm -f "$out_obs" "$out_nav" 2>/dev/null || true

  if ! ringo rtcmgo "$IN" --outobs "$out_obs" --outnav "$out_nav" $RTCMGO_OPTS 2>>"$stderr_log"; then
    echo "ERROR: ringo rtcmgo conversion failed (see $stderr_log)" >&2
    exit 4
  fi

  for f in "$out_obs" "$out_nav"; do
    [[ -f "$f" ]] && chown "$PUID:$PGID" "$f" || true
  done

  IN="$out_obs"
  fname="$IN"
  base="$base_rtcm"
  # Normalise base (pas de '.' terminal)
  while [[ "$base" == *"." ]]; do
    base="${base%.}"
  done

  vlog "RTCMGO: produced OBS=$out_obs  NAV=$out_nav (if exists)"

  if [[ -s "$out_nav" ]]; then
    NAV="$out_nav"
    AUTO_NAV="0"
    vlog "RTCMGO: using local NAV $NAV; AUTO_NAV disabled."
  fi
fi

# ---- Helpers AUTO-NAV (télécharge dans le sous-dossier courant)
_nav_get () {
  local url="$1" out="$2"
  curl -fS --retry 3 --retry-delay 2 --connect-timeout 10 -m 120 \
       -o "$out" "$url" 2>>"$stderr_log"
}

parse_year_doy_from_filename() {
  local s="$1"
  if [[ "$s" =~ ([12][0-9]{3})([0-3][0-9]{2}) ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; return 0
  fi; return 1
}

parse_year_doy_from_header() {
  local file="$1" reader="cat"
  case "$file" in
    *.gz) reader="zcat" ;; *.bz2) reader="bzcat" ;; *.Z) reader="zcat" ;; *) reader="cat" ;;
  esac
  local header="$($reader -- "$file" 2>>"$stderr_log" | head -n 200)"
  local line
  line="$(printf "%s\n" "$header" | LC_ALL=C grep -m1 'TIME OF FIRST OBS' || true)"
  if [[ -z "$line" ]]; then
    line="$(printf "%s\n" "$header" | LC_ALL=C grep -m1 'TIME OF LAST OBS' || true)"
  fi
  [[ -z "$line" ]] && return 1
  local Y M D
  Y="$(awk '{print $1}' <<<"$line")"
  M="$(awk '{print $2}' <<<"$line")"
  D="$(awk '{print $3}' <<<"$line")"
  if [[ "$Y" =~ ^[0-9]+$ && "$M" =~ ^[0-9]+$ && "$D" =~ ^[0-9]+$ ]]; then
    local DOY
    if DOY="$(date -u -d "${Y}-${M}-${D}" +%j 2>>"$stderr_log")"; then
      echo "$Y $DOY"; return 0
    fi
  fi; return 1
}

auto_nav_try() {
  local YEAR="$1" DOY="$2" ok=0
  local brdc_dir="${NAV_BASE_URL}/BRDC/${YEAR}/${DOY}"
  local brdm_dir_a="${NAV_BASE_URL}/BRDM/${YEAR}"
  local brdm_dir_b="${NAV_BASE_URL}/BRDM/${YEAR}/${DOY}"

  local BRDC_LIST=()
  [[ "$BRDC_CANDS_ORDER" == *"WRD"* ]] && BRDC_LIST+=("BRDC00WRD_R_${YEAR}${DOY}0000_01D_MN.rnx.gz")
  [[ "$BRDC_CANDS_ORDER" == *"IGS"* ]] && BRDC_LIST+=("BRDC00IGS_R_${YEAR}${DOY}0000_01D_MN.rnx.gz")
  local BRDM_LIST=("BRDM00DLR_S_${YEAR}${DOY}0000_01D_MN.rnx.gz")

  try_brdc() {
    for f in "${BRDC_LIST[@]}"; do
      local url="${brdc_dir}/${f}"; [[ "$VERBOSE" == "1" ]] && echo "AUTO_NAV try: $url"
      if _nav_get "$url" "$f"; then NAV="$f"; ok=1; return 0; fi
    done; return 1
  }
  try_brdm() {
    for dir in "$brdm_dir_a" "$brdm_dir_b"; do
      for f in "${BRDM_LIST[@]}"; do
        local url="${dir}/${f}"; [[ "$VERBOSE" == "1" ]] && echo "AUTO_NAV try: $url"
        if _nav_get "$url" "$f"; then NAV="$f"; ok=1; return 0; fi
      done
    done; return 1
  }

  if [[ "$NAV_PREFER" == "BRDM" ]]; then try_brdm || try_brdc || true
  else                                   try_brdc || try_brdm || true
  fi

  if [[ $ok -eq 1 ]]; then
    chown "$PUID:$PGID" "$NAV" || true
    [[ "$VERBOSE" == "1" ]] && echo "AUTO_NAV downloaded: $NAV"
    return 0
  fi
  echo "WARN: AUTO_NAV failed (see $stderr_log)" >&2; return 1
}

# ---- AUTO-NAV (si NAV manquant)
if [[ -z "${NAV:-}" || ! -f "$NAV" ]]; then
  if [[ "$AUTO_NAV" == "1" ]]; then
    YEAR=""; DOY=""
    if parse_year_doy_from_filename "$fname" >/dev/null; then
      read YEAR DOY < <(parse_year_doy_from_filename "$fname")
      vlog "YEAR/DOY from filename: $YEAR / $DOY"
    else
      if parse_year_doy_from_header "$IN" >/dev/null; then
        read YEAR DOY < <(parse_year_doy_from_header "$IN")
        vlog "YEAR/DOY from RINEX header: $YEAR / $DOY"
      fi
    fi
    if [[ -n "$YEAR" && -n "$DOY" ]]; then
      auto_nav_try "$YEAR" "$DOY" || true
    else
      echo "WARN: Could not determine YEAR/DOY for AUTO_NAV." >&2
    fi
  fi
fi

# ---- Traitement RINGO (dans le sous-dossier)
log "=== RINGO QC on: $IN ==="
if [[ -n "${NAV:-}" && -f "$NAV" ]]; then
  vlog "Using NAV: $NAV"
  run_cmd "${base}_qc.log" ringo qc "$IN" "$NAV" || true
else
  echo "NOTE: No NAV provided. Some QC/Viewer modes may fail." >&2
  run_cmd "${base}_qc.log" ringo qc "$IN" || true
fi

log "=== Generate HTML5 viewers ==="
if [[ -n "${NAV:-}" && -f "$NAV" ]]; then
  run_cmd "${base}.html"    ringo viewer "$IN" "$NAV"          || true
  run_cmd "${base}_qc.html" ringo viewer --qcmode "$IN" "$NAV" || true
else
  run_cmd "${base}.html"    ringo viewer "$IN"                 || true
  run_cmd "${base}_qc.html" ringo viewer --qcmode "$IN"        || true
fi

if [[ "$CSV" == "1" ]]; then
  log "=== CSV outputs ==="
  run_cmd "${base}_data.csv" ringo rnxcsv "$IN"          || true
  run_cmd "${base}_qc.csv"   ringo rnxcsv --qcmode "$IN" || true
fi

# ---- Serve (optionnel) : on sert /data (la liste montre les sous-dossiers)
if [[ "$SERVE" == "1" ]]; then
  vlog "Serving /data at http://0.0.0.0:8080"
  exec python3 -m http.server 8080 --bind 0.0.0.0 --directory /data
fi

