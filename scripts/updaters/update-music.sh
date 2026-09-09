#!/usr/bin/env bash

set -euo pipefail

result_file="/tmp/music-eq-complete.$$"
mode_file="/tmp/music-eq-mode.$$"

rm -f "$result_file" "$mode_file"

export result_file
export mode_file


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


swaynag \
    -t warning \
    -y overlay \
    -m "music eq" \
    -z "process full music library" '
echo full > "$mode_file"
touch "$result_file"
' \
    -z "process single music file" '
echo single > "$mode_file"
touch "$result_file"
' &

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

    src="$HOME/Downloads/Music/favourites"

    if [[ "$input_arg" = /* ]]; then
      input="$input_arg"
    else
        input="$src/$input_arg"
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

basename="$(basename "$input")"
stem="${basename%.*}"

covers_dir="$HOME/Downloads/Music/covers"
mkdir -p "$covers_dir"

ffmpeg -y \
    -i "$input" \
    -an \
    -map 0:v:0 \
    -frames:v 1 \
    "$covers_dir/$stem.png" \
    >/dev/null 2>&1 || true

rate="$(ffprobe \
    -v error \
    -select_streams a:0 \
    -show_entries stream=sample_rate \
    -of default=noprint_wrappers=1:nokey=1 \
    "$input")"

sofa="$(find /nix/store -iname 'mit_kemar_normal_pinna.sofa' -print -quit)"

earpods_ir="$HOME/Documents/prefs/audio/output/earpods_stereo/earpods_stereo minimum phase ${rate}Hz.wav"
cloud3_ir="$HOME/Documents/prefs/audio/output/cloud3_stereo/cloud3_stereo minimum phase ${rate}Hz.wav"

out_bs2b="$HOME/Downloads/Music/favourites eq/bs2b"
out_earpods_fir="$HOME/Downloads/Music/favourites eq/earpods fir"
out_cloud3_fir="$HOME/Downloads/Music/favourites eq/cloud3 fir"

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
    -af "bs2b=fcut=700:feed=115" \
    -c:a alac \
    "$out_bs2b/${stem}.m4a"

copy_cover_and_tags "$input" "$out_bs2b/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -i "$earpods_ir" \
    -vn \
    -filter_complex "[0:a][1:a]afir" \
    -c:a alac \
    "$out_earpods_fir/${stem}.m4a"

copy_cover_and_tags "$input" "$out_earpods_fir/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -i "$cloud3_ir" \
    -vn \
    -filter_complex "[0:a][1:a]afir" \
    -c:a alac \
    "$out_cloud3_fir/${stem}.m4a"

copy_cover_and_tags "$input" "$out_cloud3_fir/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -i "$earpods_ir" \
    -vn \
    -filter_complex "[0:a]bs2b=fcut=700:feed=115[b];[b][1:a]afir" \
    -c:a alac \
    "$out_earpods_fir_bs2b/${stem}.m4a"

copy_cover_and_tags "$input" "$out_earpods_fir_bs2b/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -i "$cloud3_ir" \
    -vn \
    -filter_complex "[0:a]bs2b=fcut=700:feed=115[b];[b][1:a]afir" \
    -c:a alac \
    "$out_cloud3_fir_bs2b/${stem}.m4a"

copy_cover_and_tags "$input" "$out_cloud3_fir_bs2b/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -vn \
    -af "sofalizer=sofa=$sofa:gain=-9" \
    -ar "$rate" \
    -c:a alac \
    "$out_sofalizer/${stem}.m4a"

copy_cover_and_tags "$input" "$out_sofalizer/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -i "$earpods_ir" \
    -vn \
    -filter_complex "sofalizer=sofa=$sofa:gain=-9[s];[s][1:a]afir" \
    -ar "$rate" \
    -c:a alac \
    "$out_earpods_fir_sofalizer/${stem}.m4a"

copy_cover_and_tags "$input" "$out_earpods_fir_sofalizer/${stem}.m4a"

ffmpeg -y \
    -i "$input" \
    -i "$cloud3_ir" \
    -vn \
    -filter_complex "sofalizer=sofa=$sofa:gain=-9[s];[s][1:a]afir" \
    -ar "$rate" \
    -c:a alac \
    "$out_cloud3_fir_sofalizer/${stem}.m4a"

copy_cover_and_tags "$input" "$out_cloud3_fir_sofalizer/${stem}.m4a"

elif [[ "$mode" == "full" ]]; then

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

sofa="$(find /nix/store -iname 'mit_kemar_normal_pinna.sofa' -print -quit)"

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

    copy_cover_and_tags "$input" "$out_bs2b/${stem}.m4a"

    # earpods fir only
    ffmpeg -y \
        -i "$input" \
        -i "$earpods_ir" \
        -vn \
        -filter_complex "[0:a][1:a]afir" \
        -c:a alac \
        "$out_earpods_fir/${stem}.m4a"

    copy_cover_and_tags "$input" "$out_earpods_fir/${stem}.m4a"

    # cloud3 fir only
    ffmpeg -y \
        -i "$input" \
        -i "$cloud3_ir" \
        -vn \
        -filter_complex "[0:a][1:a]afir" \
        -c:a alac \
        "$out_cloud3_fir/${stem}.m4a"

    copy_cover_and_tags "$input" "$out_cloud3_fir/${stem}.m4a"

    # earpods fir + bs2b
    ffmpeg -y \
        -i "$input" \
        -i "$earpods_ir" \
        -vn \
        -filter_complex "[0:a]bs2b=fcut=700:feed=115[b];[b][1:a]afir" \
        -c:a alac \
        "$out_earpods_fir_bs2b/${stem}.m4a"

    copy_cover_and_tags "$input" "$out_earpods_fir_bs2b/${stem}.m4a"

    # cloud3 fir + bs2b
    ffmpeg -y \
        -i "$input" \
        -i "$cloud3_ir" \
        -vn \
        -filter_complex "[0:a]bs2b=fcut=700:feed=115[b];[b][1:a]afir" \
        -c:a alac \
        "$out_cloud3_fir_bs2b/${stem}.m4a"

    copy_cover_and_tags "$input" "$out_cloud3_fir_bs2b/${stem}.m4a"

    # sofalizer only
    ffmpeg -y \
        -i "$input" \
        -vn \
        -af "sofalizer=sofa=$sofa:gain=-9" \
        -c:a alac \
        "$out_sofalizer/${stem}.m4a"

    copy_cover_and_tags "$input" "$out_sofalizer/${stem}.m4a"

    # earpods fir + sofalizer
    ffmpeg -y \
        -i "$input" \
        -i "$earpods_ir" \
        -vn \
        -filter_complex "sofalizer=sofa=$sofa:gain=-9[s];[s][1:a]afir" \
        -c:a alac \
        "$out_earpods_fir_sofalizer/${stem}.m4a"

    copy_cover_and_tags "$input" "$out_earpods_fir_sofalizer/${stem}.m4a"

    # cloud3 fir + sofalizer
    ffmpeg -y \
        -i "$input" \
        -i "$cloud3_ir" \
        -vn \
        -filter_complex "sofalizer=sofa=$sofa:gain=-9[s];[s][1:a]afir" \
        -c:a alac \
        "$out_cloud3_fir_sofalizer/${stem}.m4a"

    copy_cover_and_tags "$input" "$out_cloud3_fir_sofalizer/${stem}.m4a"
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
