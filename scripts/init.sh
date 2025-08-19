#!/bin/bash

# -----------------------------------------------------------------------------
# Script d'initialisation pour Stirling-PDF
# Ce script :
#   - Copie les fichiers Tesseract OCR
#   - Installe les langues Tesseract selon la variable TESSERACT_LANGS
#   - Télécharge la version sécurisée de l'application si demandé
#   - Lance la commande passée en argument
#
# Variables d'environnement attendues :
#   TESSERACT_LANGS     : Liste de langues (ex: "fra,deu,eng")
#   DOCKER_ENABLE_SECURITY : "true" pour activer la sécurité
#   VERSION_TAG         : Tag de la version (ex: "v1.2.3")
# -----------------------------------------------------------------------------

# Activer le mode strict :
#   -e : sortir si une commande échoue
#   -u : sortir si une variable non définie est utilisée
#   -o pipefail : sortir si une commande dans un pipeline échoue
set -euo pipefail

# Fonction utilitaire pour logguer
log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*" >&1
}

error() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ERROR: $*" >&2
  exit 1
}

# ----------------------------------------------------------------------------- 
# Étape 1 : Copie des fichiers Tesseract OCR
# Ne copie que les fichiers qui n'existent pas déjà dans le volume
# -----------------------------------------------------------------------------

log "Copying original Tesseract OCR files (non-destructive copy)"

# Créer le répertoire cible si inexistant
mkdir -p /usr/share/tesseract-ocr

# Copie récursive sans écraser (-n), préservation des attributs
# On évite les erreurs si le répertoire source est vide
if [ -d "/usr/share/tesseract-ocr-original" ] && [ -n "$(ls -A /usr/share/tesseract-ocr-original 2>/dev/null)" ]; then
  cp -rn /usr/share/tesseract-ocr-original/* /usr/share/tesseract-ocr/
  log "Tesseract OCR original files copied successfully."
else
  log "No original Tesseract OCR files found or directory empty. Skipping copy."
fi

# -----------------------------------------------------------------------------
# Étape 2 : Installation des langues Tesseract OCR
# Si TESSERACT_LANGS est défini, installer les paquets correspondants
# -----------------------------------------------------------------------------

if [[ -n "${TESSERACT_LANGS:-}" ]]; then
  log "Tesseract languages requested: $TESSERACT_LANGS"

  # Convertir la liste de langues (séparées par des virgules) en tableau
  IFS=',' read -ra LANG_ARRAY <<< "$TESSERACT_LANGS"

  # Mettre à jour la liste des paquets (une fois)
  log "Updating package list for Tesseract language packs..."
  apt-get update -qq > /dev/null

  # Installer chaque langue
  for LANG in "${LANG_ARRAY[@]}"; do
    # Nettoyer les espaces autour du code langue
    LANG=$(echo "$LANG" | tr -d '[:space:]')
    if [[ -z "$LANG" ]]; then
      log "Skipping empty language entry."
      continue
    fi

    log "Installing Tesseract language: $LANG"
    if apt-get install -y --no-install-recommends "tesseract-ocr-$LANG"; then
      log "Successfully installed tesseract-ocr-$LANG"
    else
      error "Failed to install tesseract-ocr-$LANG. Check language code."
    fi
  done

  # Nettoyer le cache APT pour réduire la taille
  log "Cleaning up APT cache..."
  apt-get clean
  rm -rf /var/lib/apt/lists/*
else
  log "No Tesseract languages specified (TESSERACT_LANGS is empty or unset). Skipping language installation."
fi

# -----------------------------------------------------------------------------
# Étape 3 : Téléchargement de la version sécurisée de l'application
# Si DOCKER_ENABLE_SECURITY=true et VERSION_TAG défini, télécharger le JAR
# -----------------------------------------------------------------------------

if [[ "${DOCKER_ENABLE_SECURITY:-}" == "true" ]] && [[ -n "${VERSION_TAG:-}" ]]; then
  if [[ "$VERSION_TAG" == "alpha" ]]; then
    log "Skipping security JAR download: VERSION_TAG is 'alpha'."
  else
    SECURITY_JAR="app-security.jar"
    DOWNLOAD_URL_BASE="https://github.com/Frooodle/Stirling-PDF/releases/download/${VERSION_TAG}/Stirling-PDF-with-login.jar"

    if [[ -f "$SECURITY_JAR" ]]; then
      log "Security JAR already exists: $SECURITY_JAR. Skipping download."
    else
      log "Downloading security-enabled JAR from: $DOWNLOAD_URL_BASE"

      # Télécharger avec curl
      if curl -L -f -o "$SECURITY_JAR" "$DOWNLOAD_URL_BASE"; then
        log "Download successful: $SECURITY_JAR"
      else
        log "First download failed. Trying without 'v' prefix in tag (fallback)..."
        # Parfois le tag n'a pas de 'v' dans le nom de release
        FALLBACK_URL="https://github.com/Frooodle/Stirling-PDF/releases/download/$VERSION_TAG/Stirling-PDF-with-login.jar"
        if curl -L -f -o "$SECURITY_JAR" "$FALLBACK_URL"; then
          log "Download successful from fallback URL: $FALLBACK_URL"
        else
          error "Failed to download security JAR from both primary and fallback URLs."
        fi
      fi

      # Si le téléchargement a réussi, remplacer app.jar par un lien vers app-security.jar
      if [[ -f "$SECURITY_JAR" ]]; then
        log "Replacing app.jar with symlink to $SECURITY_JAR"
        rm -f app.jar
        ln -s "$SECURITY_JAR" app.jar
      fi
    fi
  fi
else
  if [[ "${DOCKER_ENABLE_SECURITY:-}" != "true" ]]; then
    log "Security not enabled (DOCKER_ENABLE_SECURITY != 'true'). Skipping security JAR."
  else
    log "Security enabled but VERSION_TAG is missing. Skipping download."
  fi
fi

# -----------------------------------------------------------------------------
# Étape 4 : Exécution de la commande principale
# -----------------------------------------------------------------------------

log "Starting main application: $*"
exec "$@"
