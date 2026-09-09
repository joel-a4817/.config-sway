#!/usr/bin/env bash

set -euo pipefail

result_file="/tmp/music-eq-complete.$$"
mode_file="/tmp/music-eq-mode.$$"

rm -f "$result_file" "$mode_file"

export result_file
export mode_file


# ==================================================
# DSP SETTINGS
# ==================================================

SOFA="$(find /nix/store -iname 'mit_kemar_normal_pinna.sofa' -print -quit)"

# BS2B
BS2B_FCUT="700"
BS2B_FEED="45"

# ==================================================
# SOFALIZER SETTINGS
# ==================================================

SOFA_GAIN="-9"

# Position
SOFA_ROTATION="0"
SOFA_ELEVATION="0"
SOFA_RADIUS="1"

# Processing
SOFA_TYPE="freq"
SOFA_FRAMESIZE="1024"

# HRTF behaviour
SOFA_NORMALIZE="true"
SOFA_INTERPOLATE="false"
SOFA_MINPHASE="false"

# Neighbor search
SOFA_ANGLESTEP="0.5"
SOFA_RADSTEP="0.01"

# LFE
SOFA_LFEGAIN="0"

# Leave empty to use the built-in speaker layout
SOFA_SPEAKERS=""

# ==================================================
# BUILD FILTER
# ==================================================

SOFA_FILTER="sofalizer=\
sofa=$SOFA:\
gain=${SOFA_GAIN}:\
rotation=${SOFA_ROTATION}:\
elevation=${SOFA_ELEVATION}:\
radius=${SOFA_RADIUS}:\
type=${SOFA_TYPE}:\
lfegain=${SOFA_LFEGAIN}:\
framesize=${SOFA_FRAMESIZE}:\
normalize=${SOFA_NORMALIZE}:\
interpolate=${SOFA_INTERPOLATE}:\
minphase=${SOFA_MINPHASE}:\
anglestep=${SOFA_ANGLESTEP}:\
radstep=${SOFA_RADSTEP}"

if [[ -n "$SOFA_SPEAKERS" ]]; then
    SOFA_FILTER="${SOFA_FILTER}:speakers=${SOFA_SPEAKERS}"
fi

copy_cover_and_tags() {
    local original="$1"
    local processed="$2"

    [[ -f "$original" ]] || return 0
    [[ -f "$processed" ]] || return 0

    local tmp="${processed}.tmp.m4a"

    ffmpeg -y \
        -i "$processed" \
        -i "$original" \
        -map 0:a:0 \
        -map 1:v:0? \
        -map_metadata 1 \
        -c:a copy \
        -c:v copy \
        -disposition:v attached_pic \
        "$tmp"

    mv "$tmp" "$processed"
}

# ==================================================
# PATHS
# ==================================================

SRC="$HOME/Downloads/Music/favourites"
COVERS_DIR="$HOME/Downloads/Music/covers"

OUT_BS2B="$HOME/Downloads/Music/favourites eq/bs2b"

OUT_EARPODS_FIR="$HOME/Downloads/Music/favourites eq/earpods fir"
OUT_CLOUD3_FIR="$HOME/Downloads/Music/favourites eq/cloud3 fir"

OUT_EARPODS_FIR_BS2B="$HOME/Downloads/Music/favourites eq/earpods fir + bs2b"
OUT_CLOUD3_FIR_BS2B="$HOME/Downloads/Music/favourites eq/cloud3 fir + bs2b"

OUT_SOFALIZER="$HOME/Downloads/Music/favourites eq/sofalizer"

OUT_EARPODS_FIR_SOFALIZER="$HOME/Downloads/Music/favourites eq/earpods fir + sofalizer"
OUT_CLOUD3_FIR_SOFALIZER="$HOME/Downloads/Music/favourites eq/cloud3 fir + sofalizer"

mkdir -p "$COVERS_DIR"

mkdir -p "$OUT_BS2B"

mkdir -p "$OUT_EARPODS_FIR"
mkdir -p "$OUT_CLOUD3_FIR"

mkdir -p "$OUT_EARPODS_FIR_BS2B"
mkdir -p "$OUT_CLOUD3_FIR_BS2B"

mkdir -p "$OUT_SOFALIZER"

mkdir -p "$OUT_EARPODS_FIR_SOFALIZER"
mkdir -p "$OUT_CLOUD3_FIR_SOFALIZER"



swaynag \
    -t warning \
    -y overlay \
    -m "music eq" \
-z "update music library" '
echo full > "$mode_file"
touch "$result_file"
' \
-z "extract all covers" '
echo covers > "$mode_file"
touch "$result_file"
' \
-z "process single music file" '
echo single > "$mode_file"
touch "$result_file"
'&

while [[ ! -f "$result_file" ]]; do
    sleep 0.1
done

rm -f "$result_file"

mode="$(cat "$mode_file" 2>/dev/null || true)"
rm -f "$mode_file"

if [[ "$mode" == "single" ]]; then
    echo
    echo "enter filename from favourites or absolute path:"
    read -r input_arg


    if [[ "$input_arg" = /* ]]; then
      input="$input_arg"
    else
        input="$SRC/$input_arg"
    fi

    if [[ ! -f "$input" ]]; then
        echo
        echo "file not found:"
        echo "$input"
        echo
        read -n 1 -rsp "Press any key to close..."
        exit 1
    fi

echo
echo "selected:"
echo "$input"

FILE_BASENAME="$(basename "$input")"
stem="${FILE_BASENAME%.*}"

ffmpeg -y \
    -i "$input" \
    -an \
    -map 0:v:0 \
    -frames:v 1 \
    "$COVERS_DIR/$stem.png" \
    >/dev/null 2>&1 || true

rate="$(ffprobe \
    -v error \
    -select_streams a:0 \
    -show_entries stream=sample_rate \
    -of default=noprint_wrappers=1:nokey=1 \
    "$input")"

earpods_ir="$HOME/Documents/prefs/audio/output/earpods_stereo/earpods_stereo minimum phase ${rate}Hz.wav"
cloud3_ir="$HOME/Documents/prefs/audio/output/cloud3_stereo/cloud3_stereo minimum phase ${rate}Hz.wav"

echo
echo "input:"
echo "$input"
echo
echo "rate:"
echo "$rate"
echo
echo "output:"
echo "$HOME/Downloads/Music/favourites eq"
echo

ffmpeg -y \
    -i "$input" \
    -vn \
    -af "bs2b=fcut=${BS2B_FCUT}:feed=${BS2B_FEED}" \
    -c:a alac \
    "$OUT_BS2B/${stem}.m4a"

copy_cover_and_tags "$input" "$OUT_BS2B/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -i "$earpods_ir" \
    -vn \
    -filter_complex "[0:a][1:a]afir" \
    -c:a alac \
    "$OUT_EARPODS_FIR/${stem}.m4a"

copy_cover_and_tags "$input" "$OUT_EARPODS_FIR/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -i "$cloud3_ir" \
    -vn \
    -filter_complex "[0:a][1:a]afir" \
    -c:a alac \
    "$OUT_CLOUD3_FIR/${stem}.m4a"

copy_cover_and_tags "$input" "$OUT_CLOUD3_FIR/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -i "$earpods_ir" \
    -vn \
    -filter_complex "[0:a]bs2b=fcut=${BS2B_FCUT}:feed=${BS2B_FEED}[b];[b][1:a]afir" \
    -c:a alac \
    "$OUT_EARPODS_FIR_BS2B/${stem}.m4a"

copy_cover_and_tags "$input" "$OUT_EARPODS_FIR_BS2B/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -i "$cloud3_ir" \
    -vn \
    -filter_complex "[0:a]bs2b=fcut=${BS2B_FCUT}:feed=${BS2B_FEED}[b];[b][1:a]afir" \
    -c:a alac \
    "$OUT_CLOUD3_FIR_BS2B/${stem}.m4a"

copy_cover_and_tags "$input" "$OUT_CLOUD3_FIR_BS2B/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -vn \
    -af "${SOFA_FILTER}" \
    -ar "$rate" \
    -c:a alac \
    "$OUT_SOFALIZER/${stem}.m4a"

copy_cover_and_tags "$input" "$OUT_SOFALIZER/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -i "$earpods_ir" \
    -vn \
    -filter_complex "${SOFA_FILTER}[s];[s][1:a]afir" \
    -ar "$rate" \
    -c:a alac \
    "$OUT_EARPODS_FIR_SOFALIZER/${stem}.m4a"

copy_cover_and_tags "$input" "$OUT_EARPODS_FIR_SOFALIZER/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -i "$cloud3_ir" \
    -vn \
    -filter_complex "${SOFA_FILTER}[s];[s][1:a]afir" \
    -ar "$rate" \
    -c:a alac \
    "$OUT_CLOUD3_FIR_SOFALIZER/${stem}.m4a"

copy_cover_and_tags "$input" "$OUT_CLOUD3_FIR_SOFALIZER/${stem}.m4a"



# Covers




elif [[ "$mode" == "covers" ]]; then

    echo "extracting covers..."

    find "$SRC" -type f \
        \( -iname "*.m4a" -o \
           -iname "*.mp3" -o \
           -iname "*.flac" -o \
           -iname "*.aac" -o \
           -iname "*.ogg" -o \
           -iname "*.opus" \
        \) \
        -print0 |
    while IFS= read -r -d '' file; do

        base="$(basename "${file%.*}")"
        out="$COVERS_DIR/$base.png"

        echo "cover: $base"

        ffmpeg -y \
            -i "$file" \
            -an \
            -map 0:v:0 \
            -frames:v 1 \
            "$out" \
            >/dev/null 2>&1 || true

    done



#Full library



elif [[ "$mode" == "full" ]]; then

echo
echo "[0] Keep existing files (exit)"
echo
echo "[1] earpods fir"
echo "[2] cloud3 fir"
echo "[3] bs2b"
echo "[4] earpods fir + bs2b"
echo "[5] cloud3 fir + bs2b"
echo "[6] sofalizer"
echo "[7] earpods fir + sofalizer"
echo "[8] cloud3 fir + sofalizer"
echo
echo "[9] Update ALL folders"
echo

read -rp "Selection: " PROFILE_SELECTION

PROFILE_SELECTION="${PROFILE_SELECTION// /}"

if [[ "$PROFILE_SELECTION" == "0" ]]; then
    echo "Keeping existing files."
    exit 0
fi

if [[ "$PROFILE_SELECTION" == "9" ]]; then
    PROFILE_SELECTION="1,2,3,4,5,6,7,8"
fi

for item in ${PROFILE_SELECTION//,/ }; do
    if ! [[ "$item" =~ ^[1-8]$ ]]; then
        echo "Invalid selection: $item"
        exit 1
    fi
done

selected() {
    local wanted="$1"

    [[ ",${PROFILE_SELECTION}," == *",$wanted,"* ]]
}

process_file() {
    local input="$1"

    local file_basename
    file_basename="$(basename "$input")"

    local stem
    stem="${file_basename%.*}"

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
    echo "processing: $file_basename"

    # earpods fir only
    if selected 1; then

        ffmpeg -y \
            -i "$input" \
            -i "$earpods_ir" \
            -vn \
            -filter_complex "[0:a][1:a]afir" \
            -c:a alac \
            "$OUT_EARPODS_FIR/${stem}.m4a"

        copy_cover_and_tags "$input" "$OUT_EARPODS_FIR/${stem}.m4a"

    fi

    # cloud3 fir only
    if selected 2; then

        ffmpeg -y \
            -i "$input" \
            -i "$cloud3_ir" \
            -vn \
            -filter_complex "[0:a][1:a]afir" \
            -c:a alac \
            "$OUT_CLOUD3_FIR/${stem}.m4a"

        copy_cover_and_tags "$input" "$OUT_CLOUD3_FIR/${stem}.m4a"

    fi

    # bs2b only (bauer)
    if selected 3; then

        ffmpeg -y \
            -i "$input" \
            -vn \
            -af "bs2b=fcut=${BS2B_FCUT}:feed=${BS2B_FEED}" \
            -c:a alac \
            "$OUT_BS2B/${stem}.m4a"

        copy_cover_and_tags "$input" "$OUT_BS2B/${stem}.m4a"

    fi

    # earpods fir + bs2b
    if selected 4; then

        ffmpeg -y \
            -i "$input" \
            -i "$earpods_ir" \
            -vn \
            -filter_complex "[0:a]bs2b=fcut=${BS2B_FCUT}:feed=${BS2B_FEED}[b];[b][1:a]afir" \
            -c:a alac \
            "$OUT_EARPODS_FIR_BS2B/${stem}.m4a"

        copy_cover_and_tags "$input" "$OUT_EARPODS_FIR_BS2B/${stem}.m4a"

    fi

    # cloud3 fir + bs2b
    if selected 5; then

        ffmpeg -y \
            -i "$input" \
            -i "$cloud3_ir" \
            -vn \
            -filter_complex "[0:a]bs2b=fcut=${BS2B_FCUT}:feed=${BS2B_FEED}[b];[b][1:a]afir" \
            -c:a alac \
            "$OUT_CLOUD3_FIR_BS2B/${stem}.m4a"

        copy_cover_and_tags "$input" "$OUT_CLOUD3_FIR_BS2B/${stem}.m4a"

    fi

    # sofalizer only
    if selected 6; then

        ffmpeg -y \
            -i "$input" \
            -vn \
            -af "${SOFA_FILTER}" \
            -c:a alac \
            "$OUT_SOFALIZER/${stem}.m4a"

        copy_cover_and_tags "$input" "$OUT_SOFALIZER/${stem}.m4a"

    fi

    # earpods fir + sofalizer
    if selected 7; then

        ffmpeg -y \
            -i "$input" \
            -i "$earpods_ir" \
            -vn \
            -filter_complex "${SOFA_FILTER}[s];[s][1:a]afir" \
            -c:a alac \
            "$OUT_EARPODS_FIR_SOFALIZER/${stem}.m4a"

        copy_cover_and_tags "$input" "$OUT_EARPODS_FIR_SOFALIZER/${stem}.m4a"

    fi

    # cloud3 fir + sofalizer
    if selected 8; then

        ffmpeg -y \
            -i "$input" \
            -i "$cloud3_ir" \
            -vn \
            -filter_complex "${SOFA_FILTER}[s];[s][1:a]afir" \
            -c:a alac \
            "$OUT_CLOUD3_FIR_SOFALIZER/${stem}.m4a"

        copy_cover_and_tags "$input" "$OUT_CLOUD3_FIR_SOFALIZER/${stem}.m4a"

    fi

}

mapfile -d '' files < <(
find "$SRC" -type f \( \
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
