#!/bin/bash

##########################################################
##                                                      ##
## Shell script for generating a boards manager release ##
## Created by MCUdude                                   ##
## Requires wget, jq and a bash environment             ##
##                                                      ##
##########################################################

# Called by the release workflow of the classic-debug-enabled branch with the tag,
# e.g. "bash Boards_manager_release.sh v1.5.8"; by hand as well.

AUTHOR=felias-fogg       # Github user name
REPOSITORY=ATTinyCore    # Github repo name

# Which index to write. The workflow sets INDEX_FILE: a release candidate goes
# into an index of its own, so the board manager of an ordinary user never
# offers it. Without the variable, this is the stable index, the one the README
# names.
INDEX="${INDEX_FILE:-package_drazzy.com_${REPOSITORY}_index.json}"

# The tools the platform depends on, as in the 1.5.x entries. The debug tools are
# no dependency any more since 1.5.8: they come from the AvrDebugger package,
# which the user installs separately and the platform finds as
# runtime.tools.avr-debugger.path.
AVRDUDE_VERSION="8.0-arduino.1"
MICRONUCLEUS_VERSION="2.5-azd1b"

TAG="$1"
if [ -z "$TAG" ]; then
    echo "You need to specify a tag, e.g. v1.5.8"
    exit 1
fi
DOWNLOAD_URL="https://api.github.com/repos/$AUTHOR/$REPOSITORY/tarball/$TAG"
DOWNLOADED_FILE="$TAG"
NAME="$REPOSITORY-${TAG#"v"}"
echo "Packaging ${TAG} into ${INDEX}"

# Check whether this exact version is already in the index. The archive name has
# to be matched in full: without the extension, "ATTinyCore-1.5.8" also matches
# "ATTinyCore-1.5.8-rc1.tar.bz2", and the final release would be refused because
# one of its own release candidates is in the index.
if grep -q "\"${NAME}.tar.bz2\"" "$INDEX"; then
    echo "This version is already in the index file. Nothing to do."
    exit 1
fi

# Download file
wget --no-verbose -O "${DOWNLOADED_FILE}.tar.gz" "$DOWNLOAD_URL" || exit 1

# Extract downloaded file and place it in a folder
printf "\nExtracting ${DOWNLOADED_FILE}.tar.gz to ${NAME}\n"
mkdir -p "$NAME" && tar -xzf "${DOWNLOADED_FILE}.tar.gz" -C "$NAME" --strip-components=1 || exit 1

# The platform is the avr folder of the repository: keep only that
mv "$NAME" "$NAME.full" && mv "$NAME.full/avr" "$NAME" && rm -rf "$NAME.full" "${DOWNLOADED_FILE}.tar.gz"
test -f "$NAME/platform.txt" || { echo "no platform.txt in the avr folder of ${TAG}"; exit 1; }

# Make sure there are no macOS related files added to the archive that's soon to be
# generated. dot_clean only exists on macOS; elsewhere there is nothing to clean.
if command -v dot_clean > /dev/null 2>&1; then
    dot_clean "$NAME"
fi
find "$NAME" -name "._*" -delete 2>/dev/null

# Compress folder to tar.bz2
printf "\nCompressing folder ${NAME} to ${NAME}.tar.bz2\n"
tar -cjSf "${NAME}.tar.bz2" "$NAME"
printf "Done!\n"

# Get file size on bytes
FILE_SIZE=$(wc -c "${NAME}.tar.bz2" | awk '{print $1}')

# Get SHA256 hash: shasum is a macOS thing, sha256sum a Linux one
if command -v shasum > /dev/null 2>&1; then
    SHA256="SHA-256:$(shasum -a 256 "${NAME}.tar.bz2" | awk '{print $1}')"
else
    SHA256="SHA-256:$(sha256sum "${NAME}.tar.bz2" | awk '{print $1}')"
fi

# The archive is served from this branch (gh-pages). Up to 1.5.7 the archives were
# put into the user site felias-fogg.github.io instead; those entries keep their URLs.
URL="https://${AUTHOR}.github.io/${REPOSITORY}/${NAME}.tar.bz2"

cp "$INDEX" "$INDEX.tmp"

# Add new boards release entry
jq -r                                          \
--arg version          "${TAG#"v"}"            \
--arg url              "$URL"                  \
--arg checksum         "$SHA256"               \
--arg file_size        "$FILE_SIZE"            \
--arg avrdude_ver      "$AVRDUDE_VERSION"      \
--arg micronucleus_ver "$MICRONUCLEUS_VERSION" \
--arg file_name        "${NAME}.tar.bz2"       \
'.packages[].platforms[.packages[].platforms | length] |= . +
{
  "name": "ATTinyCore (debug-configured)",
  "architecture": "avr",
  "version": $version,
  "category": "Contributed",
  "url": $url,
  "archiveFileName": $file_name,
  "checksum": $checksum,
  "size": $file_size,
  "boards": [
    {"name": "Program and debug via ISP/dw or Serial:"},
    {"name": "ATtiny841/441, ATtiny85/45/25, ATtiny43U"},
    {"name": "ATtiny84/44/24, ATtiny1634, ATtiny828"},
    {"name": "ATtiny861/461/261, ATtiny167/87"},
    {"name": "ATtiny88/48, ATtiny4313/2313"},
    {"name": "USB (Micronucleus) boards:"},
    {"name": "DigiSpark (t85), Digispark Pro (t167)"},
    {"name": "Wattuino Nano (t841), CaliforniaSTEAM (t84)"},
    {"name": "AzduinoUSB (t84, t841, t861, t1634)"},
    {"name": "If Win USB drivers not already installed, run the post_install.bat manually or DL from https://azduino.com/bin/micronucleus"}
  ],
  "toolsDependencies": [
    {
      "packager": "arduino",
      "name": "avr-gcc",
      "version": "7.3.0-atmel3.6.1-arduino7"
    },
    {
      "packager": "ATTinyCore",
      "name": "avrdude",
      "version": $avrdude_ver
    },
    {
      "packager": "ATTinyCore",
      "name": "micronucleus",
      "version": $micronucleus_ver
    }
  ]
}' "$INDEX.tmp" > "$INDEX" || { mv "$INDEX.tmp" "$INDEX"; echo "jq failed, index unchanged"; exit 1; }

# Remove files that are no longer needed (the archive stays: it is what the URL serves)
rm -rf "$NAME" "$INDEX.tmp"
