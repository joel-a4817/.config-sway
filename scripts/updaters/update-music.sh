#!/usr/bin/env bash

set -euo pipefail

RESULT_FILE="/tmp/music-eq-complete.$$"
MODE_FILE="/tmp/music-eq-mode.$$"

rm -f "$RESULT_FILE" "$MODE_FILE"

export RESULT_FILE
export MODE_FILE

swaynag \
    -t warning \
    -y overlay \
    -m "music EQ" \
    -z "Process Full Music Library" '
echo full > "$MODE_FILE"
touch "$RESULT_FILE"
' \
    -z "Process Single Music File" '
echo single > "$MODE_FILE"
touch "$RESULT_FILE"
' &

while [[ ! -f "$RESULT_FILE" ]]; do
    sleep 0.1
done

rm -f "$RESULT_FILE"

MODE="$(cat "$MODE_FILE" 2>/dev/null || true)"
rm -f "$MODE_FILE"

if [[ "$MODE" == "single" ]]; then
    echo
    echo "Enter filename from favourites OR absolute path:"
    read -r INPUT_ARG

    SRC="$HOME/Downloads/Music/favourites"

    if [[ "$INPUT_ARG" = /* ]]; then
      INPUT="$INPUT_ARG"
    else
        INPUT="$SRC/$INPUT_ARG"
    fi

    if [[ ! -f "$INPUT" ]]; then
        echo
        echo "File not found:"
        echo "$INPUT"
        echo
        read -n 1 -rsp "Press any key to close..."
        exit 1
    fi

echo
echo "Selected:"
echo "$INPUT"

BASENAME="$(basename "$INPUT")"
STEM="${BASENAME%.*}"

covers_dir="$HOME/Downloads/Music/covers"
mkdir -p "$covers_dir"

ffmpeg -y \
    -i "$INPUT" \
    -an \
    -map 0:v:0 \
    -frames:v 1 \
    "$covers_dir/$STEM.png" \
    >/dev/null 2>&1 || true

RATE="$(ffprobe \
    -v error \
    -select_streams a:0 \
    -show_entries stream=sample_rate \
    -of default=noprint_wrappers=1:nokey=1 \
    "$INPUT")"

SOFA="$(find /nix/store -iname 'MIT_KEMAR_normal_pinna.sofa' -print -quit)"

EARPODS_IR="$HOME/Documents/prefs/audio/output/earpods_stereo/earpods_stereo minimum phase ${RATE}Hz.wav"
CLOUD3_IR="$HOME/Documents/prefs/audio/output/cloud3_stereo/cloud3_stereo minimum phase ${RATE}Hz.wav"

OUT="$HOME/Downloads/Music/test-output/$STEM"

mkdir -p "$OUT"

echo
echo "Input:"
echo "$INPUT"
echo
echo "Rate:"
echo "$RATE"
echo
echo "Output:"
echo "$OUT"
echo

ffmpeg -y \
    -i "$INPUT" \
    -vn \
    -af "bs2b=fcut=700:feed=115" \
    -c:a alac \
    "$OUT/${STEM} - bs2b.m4a"

ffmpeg -y \
    -i "$INPUT" \
    -i "$EARPODS_IR" \
    -vn \
    -filter_complex "[0:a][1:a]afir" \
    -c:a alac \
    "$OUT/${STEM} - earpods fir.m4a"

ffmpeg -y \
    -i "$INPUT" \
    -i "$CLOUD3_IR" \
    -vn \
    -filter_complex "[0:a][1:a]afir" \
    -c:a alac \
    "$OUT/${STEM} - cloud3 fir.m4a"

ffmpeg -y \
    -i "$INPUT" \
    -i "$EARPODS_IR" \
    -vn \
    -filter_complex "[0:a]bs2b=fcut=700:feed=115[b];[b][1:a]afir" \
    -c:a alac \
    "$OUT/${STEM} - earpods fir + bs2b.m4a"

ffmpeg -y \
    -i "$INPUT" \
    -i "$CLOUD3_IR" \
    -vn \
    -filter_complex "[0:a]bs2b=fcut=700:feed=115[b];[b][1:a]afir" \
    -c:a alac \
    "$OUT/${STEM} - cloud3 fir + bs2b.m4a"

ffmpeg -y \
    -i "$INPUT" \
    -vn \
    -af "sofalizer=sofa=$SOFA:gain=-9" \
    -ar "$RATE" \
    -c:a alac \
    "$OUT/${STEM} - sofalizer.m4a"

ffmpeg -y \
    -i "$INPUT" \
    -i "$EARPODS_IR" \
    -vn \
    -filter_complex "sofalizer=sofa=$SOFA:gain=-9[s];[s][1:a]afir" \
    -ar "$RATE" \
    -c:a alac \
    "$OUT/${STEM} - earpods fir + sofalizer.m4a"

ffmpeg -y \
    -i "$INPUT" \
    -i "$CLOUD3_IR" \
    -vn \
    -filter_complex "sofalizer=sofa=$SOFA:gain=-9[s];[s][1:a]afir" \
    -ar "$RATE" \
    -c:a alac \
    "$OUT/${STEM} - cloud3 fir + sofalizer.m4a"

echo
echo "Output folder:"
echo "$OUT"

elif [[ "$MODE" == "full" ]]; then

music_dir="$HOME/Downloads/Music/favourites"
covers_dir="$HOME/Downloads/Music/covers"

mkdir -p "$covers_dir"

echo "extracting covers..."

find "$music_dir" -type f \
    \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.aac" -o -iname "*.ogg" -o -iname "*.opus" \) \
    -print0 |
while ifs= read -r -d '' file; do
    base="$(basename "${file%.*}")"
    out="$covers_dir/$base.png"

    echo "cover: $base"

    ffmpeg -y \
        -i "$file" \
        -an \
        -map 0:v:0 \
        -frames:v 1 \
        "$out" \
        >/dev/null 2>&1 || true
done

src="$HOME/Downloads/Music/favourites"

SOFA="$(find /nix/store -iname 'MIT_KEMAR_normal_pinna.sofa' -print -quit)"

out_earpods_fir="$HOME/Downloads/Music/favourites eq/earpods fir"
out_cloud3_fir="$HOME/Downloads/Music/favourites eq/cloud3 fir"

out_bs2b="$HOME/Downloads/Music/favourites eq/bs2b"
out_earpods_fir_bs2b="$HOME/Downloads/Music/favourites eq/earpods fir + bs2b"
out_cloud3_fir_bs2b="$HOME/Downloads/Music/favourites eq/cloud3 fir + bs2b"

out_sofalizer="$HOME/Downloads/Music/favourites eq/sofalizer"
out_earpods_fir_sofalizer="$HOME/Downloads/Music/favourites eq/earpods fir + sofalizer"
out_cloud3_fir_sofalizer="$HOME/Downloads/Music/favourites eq/cloud3 fir + sofalizer"

mkdir -p "$out_bs2b"
mkdir -p "$out_earpods_fir"
mkdir -p "$out_cloud3_fir"
mkdir -p "$out_earpods_fir_bs2b"
mkdir -p "$out_cloud3_fir_bs2b"

mkdir -p "$out_sofalizer"
mkdir -p "$out_earpods_fir_sofalizer"
mkdir -p "$out_cloud3_fir_sofalizer"

process_file() {
    local input="$1"

    local basename
    basename="$(basename "$input")"

    local stem
    stem="${basename%.*}"

    local rate
    rate="$(ffprobe \
        -v error \
        -select_streams a:0 \
        -show_entries stream=sample_rate \
        -of default=noprint_wrappers=1:nokey=1 \
        "$input")"

    local earpods_ir
    earpods_ir="$HOME/Documents/prefs/audio/output/earpods_stereo/earpods_stereo minimum phase ${rate}Hz.wav"

    local cloud3_ir
    cloud3_ir="$HOME/Documents/prefs/audio/output/cloud3_stereo/cloud3_stereo minimum phase ${rate}Hz.wav"

    echo
    echo "processing: $basename"

    # bs2b only (bauer)
    ffmpeg -y \
        -i "$input" \
        -vn \
        -af "bs2b=fcut=700:feed=115" \
        -c:a alac \
        "$out_bs2b/${stem}.m4a"

    # earpods fir only
    ffmpeg -y \
        -i "$input" \
        -i "$earpods_ir" \
        -vn \
        -filter_complex "[0:a][1:a]afir" \
        -c:a alac \
        "$out_earpods_fir/${stem}.m4a"

    # cloud3 fir only
    ffmpeg -y \
        -i "$input" \
        -i "$cloud3_ir" \
        -vn \
        -filter_complex "[0:a][1:a]afir" \
        -c:a alac \
        "$out_cloud3_fir/${stem}.m4a"

    # earpods fir + bs2b
    ffmpeg -y \
        -i "$input" \
        -i "$earpods_ir" \
        -vn \
        -filter_complex "[0:a]bs2b=fcut=700:feed=115[b];[b][1:a]afir" \
        -c:a alac \
        "$out_earpods_fir_bs2b/${stem}.m4a"

    # cloud3 fir + bs2b
    ffmpeg -y \
        -i "$input" \
        -i "$cloud3_ir" \
        -vn \
        -filter_complex "[0:a]bs2b=fcut=700:feed=115[b];[b][1:a]afir" \
        -c:a alac \
        "$out_cloud3_fir_bs2b/${stem}.m4a"

    # sofalizer only
    ffmpeg -y \
        -i "$input" \
        -vn \
        -af "sofalizer=sofa=$SOFA:gain=-9" \
        -c:a alac \
        "$out_sofalizer/${stem}.m4a"

    # earpods fir + sofalizer
    ffmpeg -y \
        -i "$input" \
        -i "$earpods_ir" \
        -vn \
        -filter_complex "sofalizer=sofa=$SOFA:gain=-9[s];[s][1:a]afir" \
        -c:a alac \
        "$out_earpods_fir_sofalizer/${stem}.m4a"

    # cloud3 fir + sofalizer
    ffmpeg -y \
        -i "$input" \
        -i "$cloud3_ir" \
        -vn \
        -filter_complex "sofalizer=sofa=$SOFA:gain=-9[s];[s][1:a]afir" \
        -c:a alac \
        "$out_cloud3_fir_sofalizer/${stem}.m4a"
}

mapfile -d '' files < <(
find "$src" -type f \( \
    -iname "*.m4a" -o \
    -iname "*.aac" -o \
    -iname "*.mp3" -o \
    -iname "*.flac" -o \
    -iname "*.wav" -o \
    -iname "*.ogg" -o \
    -iname "*.opus" \
\) -print0
)

for file in "${files[@]}"; do
    process_file "$file"
done

fi

echo
read -n 1 -rsp "Press any key to close..."
