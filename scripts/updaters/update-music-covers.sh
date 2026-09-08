#!/usr/bin/env bash

MUSIC_DIR="/home/joel/Downloads/Music/favourites"
COVERS_DIR="$MUSIC_DIR/Covers"

mkdir -p "$COVERS_DIR"

find "$MUSIC_DIR" -type f \
    \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.aac" -o -iname "*.ogg" -o -iname "*.opus" \) \
    -print0 |
while IFS= read -r -d '' file; do
    base="$(basename "${file%.*}")"
    out="$COVERS_DIR/$base.png"

    echo "Processing: $file"

    ffmpeg -y -i "$file" \
        -an \
        -map 0:v:0 \
        -frames:v 1 \
        "$out" \
        >/dev/null 2>&1 || true
done

echo
read -n 1 -rsp "Press any key to close..."
