#!/bin/bash
#
# Fabrique dist/Navloom-<version>.dmg, prêt à publier :
#   1. archive Release, signée avec le certificat auto-signé ;
#   2. vérifie que la signature n'est pas ad-hoc (sinon les autorisations sautent à chaque version) ;
#   3. crée le DMG avec sa fenêtre d'installation (fond, icônes placées, raccourci Applications) ;
#   4. signe le DMG.
#
# Prérequis : brew install create-dmg
# Usage     : ./scripts/make-dmg.sh   (depuis n'importe où)
#
# La première fois, macOS demande d'autoriser le Terminal à piloter le Finder :
# create-dmg s'en sert pour placer les icônes dans la fenêtre. Accepte.

set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Yohan Janolin Code Signing"
BUILD="build/release"
ARCHIVE="$BUILD/Navloom.xcarchive"
STAGE="$BUILD/dmg"
BACKGROUND="$BUILD/background.tiff"

step() { printf '\n\033[1;35m▸ %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

command -v create-dmg >/dev/null || fail "create-dmg est introuvable. Installe-le avec : brew install create-dmg"
security find-identity -p codesigning | grep -q "$IDENTITY" \
    || fail "Certificat « $IDENTITY » introuvable dans le trousseau."

step "Archive Release"
rm -rf "$BUILD"
mkdir -p "$BUILD" dist
# « generic » : app universelle (Apple Silicon + Intel), comme « Any Mac » dans Xcode.
xcodebuild -project Navloom.xcodeproj -scheme Navloom -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" archive -quiet

APP="$ARCHIVE/Products/Applications/Navloom.app"
[ -d "$APP" ] || fail "Navloom.app introuvable dans l'archive."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
echo "Navloom $VERSION (build $BUILD_NUMBER)"

step "Vérification de la signature"
codesign --verify --strict --deep "$APP" || fail "La signature de l'app est invalide."
REQUIREMENT=$(codesign -d -r- "$APP" 2>&1 | grep "designated" || true)
echo "$REQUIREMENT"
[[ "$REQUIREMENT" == *"certificate leaf"* ]] \
    || fail "L'app n'est pas signée avec le certificat : les utilisateurs perdraient leurs autorisations à chaque version."

step "Fond de la fenêtre (1x + Retina)"
tiffutil -cathidpicheck Design/dmg/background.png Design/dmg/background@2x.png -out "$BACKGROUND"

step "Création du DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Navloom.app"
DMG="dist/Navloom-$VERSION.dmg"
rm -f "$DMG"

VOLICON=()
[ -f "$APP/Contents/Resources/AppIcon.icns" ] && VOLICON=(--volicon "$APP/Contents/Resources/AppIcon.icns")

# Fenêtre de 660 × 400 points de contenu (la hauteur inclut la barre de titre).
# Les positions des icônes correspondent à la flèche dessinée dans le fond.
create-dmg \
    --volname "Navloom $VERSION" \
    ${VOLICON[@]+"${VOLICON[@]}"} \
    --background "$BACKGROUND" \
    --window-pos 200 120 \
    --window-size 660 428 \
    --icon-size 128 \
    --text-size 13 \
    --icon "Navloom.app" 180 200 \
    --hide-extension "Navloom.app" \
    --app-drop-link 480 200 \
    "$DMG" "$STAGE"

step "Signature du DMG"
codesign --sign "$IDENTITY" "$DMG"
codesign --verify "$DMG"

step "Terminé"
echo "$(pwd)/$DMG"
shasum -a 256 "$DMG"
