#!/usr/bin/env bash
set -u

# ── SETUP ────────────────────────────────
REPO_OWNER="${REPO_OWNER_ENV}"
REPO_NAME="${REPO_NAME_ENV}"
BRANCH="${BRANCH_ENV}"
URLS_RAW="${YT_URLS}"
read -ra URL_LIST <<< "$URLS_RAW"
TOTAL_URLS=${#URL_LIST[@]}
QUALITY="${YT_QUALITY}"
ZIP_PASSWORD="${YT_PASSWORD}"
SPLIT_MB=45
SPLIT_BYTES=$(( SPLIT_MB * 1024 * 1024 ))
BACKUP_DIR="/tmp/video_backup_$$"
mkdir -p "$BACKUP_DIR"
mkdir -p videos
> /tmp/video_info.txt

echo "Total URLs to download: $TOTAL_URLS"
echo "Quality: $QUALITY"

# ── FUNCTIONS ────────────────────────────────
sanitize_name() {
  echo "$1" | sed 's/ /-/g' | sed 's/　/-/g' | tr -s '-'
}
urlencode() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}
case "$QUALITY" in
  "audio")
    FORMAT="bestaudio"
    ;;
  "best")
    FORMAT="bestvideo+bestaudio/best"
    ;;
  "2160"|"4k")
    FORMAT="bestvideo[height=2160]+bestaudio/best[height=2160]"
    ;;
  "1440"|"2k")
    FORMAT="bestvideo[height=1440]+bestaudio/best[height=1440]"
    ;;
  "1080")
    FORMAT="bestvideo[height=1080]+bestaudio/best[height=1080]"
    ;;
  "720")
    FORMAT="bestvideo[height=720]+bestaudio/best[height=720]"
    ;;
  "480")
    FORMAT="bestvideo[height=480]+bestaudio/best[height=480]"
    ;;
  *)
    echo "❌ Unsupported quality: $QUALITY"
    exit 1
    ;;
esac

# yt-dlp + bgutil provider integration for the mweb client.
MWEB_EXTRACTOR_ARGS="youtube:player_client=mweb;youtubepot-bgutilhttp:base_url=http://127.0.0.1:4416"

has_media_output() {
  find "$1" -maxdepth 1 -type f \(               -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mkv" -o -iname "*.mp3"             \) -print -quit 2>/dev/null | grep -q .
}

cleanup_download_dir() {
  local DIR="$1"
  find "$DIR" -maxdepth 1 -type f \(
    -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mkv" -o -iname "*.mp3"               -o -iname "*.part" -o -iname "*.ytdl" -o -iname "*.jpg" -o -iname "*.webp"             \) -delete 2>/dev/null || true
}

verify_download_quality() {
  local DIR="$1"
  local TARGET="$2"

  if [ "$TARGET" = "best" ] || [ "$TARGET" = "audio" ]; then
    return 0
  fi

  local found=false
  local file actual

  while IFS= read -r -d '' file; do
    found=true
    actual=$(ffprobe -v error -select_streams v:0                 -show_entries stream=height -of csv=p=0 "$file" 2>/dev/null | head -n1 || true)

    if [[ "$actual" =~ ^[0-9]+$ ]] && [ "$actual" -eq "$TARGET" ]; then
      echo "✅ Verified video height: ${actual}p (requested ${TARGET}p)"
      return 0
    fi

    echo "⚠️ Rejecting output: $(basename "$file") has video height '${actual:-unknown}', requested ${TARGET}p"
  done < <(find "$DIR" -maxdepth 1 -type f \(
    -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mkv"
  \) -print0)

  if [ "$found" = false ]; then
    echo "❌ No video file produced."
  fi
  return 1
}

download_video() {
  local METHOD=$1
  local URL=$2
  local TMP_DIR=$3

  echo "Trying download method $METHOD..."
  cleanup_download_dir "$TMP_DIR"

  if [ "$QUALITY" = "audio" ]; then
    COMMON_FLAGS="--extract-audio --audio-format mp3 --audio-quality 0 --write-thumbnail --convert-thumbnails jpg --no-cache-dir --output ${TMP_DIR}/%(title)s.%(ext)s --no-part --no-playlist --retries 5 --fragment-retries 5 --no-check-certificates --concurrent-fragments 8 --buffer-size 16K --http-chunk-size 10M --progress --newline"
  elif [ "$QUALITY" = "best" ]; then
    COMMON_FLAGS="--merge-output-format mp4 --format-sort res,+codec:vp9.1,+size --write-thumbnail --convert-thumbnails jpg --no-cache-dir --output ${TMP_DIR}/%(title)s.%(ext)s --no-part --no-playlist --retries 5 --fragment-retries 5 --no-check-certificates --concurrent-fragments 8 --buffer-size 16K --http-chunk-size 10M --progress --newline"
  else
    COMMON_FLAGS="--merge-output-format mp4 --write-thumbnail --convert-thumbnails jpg --no-cache-dir --output ${TMP_DIR}/%(title)s.%(ext)s --no-part --no-playlist --retries 5 --fragment-retries 5 --no-check-certificates --concurrent-fragments 8 --buffer-size 16K --http-chunk-size 10M --progress --newline"
  fi

  case $METHOD in
    1)
      yt-dlp --proxy "socks5://127.0.0.1:1080" --format "$FORMAT" $COMMON_FLAGS                   --extractor-args "$MWEB_EXTRACTOR_ARGS"                   --js-runtimes deno --remote-components ejs:github "$URL"
      ;;
    2)
      yt-dlp --proxy "socks5://127.0.0.1:1080" --format "$FORMAT" $COMMON_FLAGS                   --extractor-args "$MWEB_EXTRACTOR_ARGS"                   --js-runtimes deno --remote-components ejs:npm "$URL"
      ;;
    3)
      yt-dlp --proxy "socks5://127.0.0.1:1080" --format "$FORMAT" $COMMON_FLAGS                   --extractor-args "$MWEB_EXTRACTOR_ARGS"                   --js-runtimes deno --remote-components ejs:github "$URL"
      ;;
    4)
      yt-dlp --proxy "socks5://127.0.0.1:1080" --format "$FORMAT" $COMMON_FLAGS                   --extractor-args "$MWEB_EXTRACTOR_ARGS" "$URL"
      ;;
    5)
      yt-dlp --proxy "socks5://127.0.0.1:1080" --format "$FORMAT" $COMMON_FLAGS                   --extractor-args "youtube:player_client=web"                   --js-runtimes deno --remote-components ejs:github "$URL"
      ;;
    6)
      yt-dlp --proxy "socks5://127.0.0.1:1080" --format "$FORMAT" $COMMON_FLAGS                   --extractor-args "youtube:player_client=web"                   --js-runtimes deno --remote-components ejs:npm "$URL"
      ;;
    7)
      yt-dlp --format "$FORMAT" $COMMON_FLAGS                   --extractor-args "$MWEB_EXTRACTOR_ARGS" "$URL"
      ;;
    8)
      yt-dlp --format "$FORMAT" $COMMON_FLAGS                   --extractor-args "youtube:player_client=android"                   --user-agent "Mozilla/5.0 (Linux; Android 12; SM-S906N Build/QP1A.190711.020) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36" "$URL"
      ;;
    *)
      echo "Unknown download method: $METHOD"
      return 2
      ;;
  esac

  if ! has_media_output "$TMP_DIR"; then
    echo "❌ yt-dlp exited without a media output."
    return 1
  fi

  return 0
}

RANDOM_WORDS=("alpha" "beta" "gamma" "delta" "epsilon" "zeta" "theta" "kappa" "lambda" "sigma" "omega" "nova" "star" "moon" "sun" "sky" "cloud" "river" "ocean" "mountain")
get_random_word() { echo "${RANDOM_WORDS[$RANDOM % ${#RANDOM_WORDS[@]}]}_$RANDOM"; }
get_unique_folder() {
  local BASE_PATH="$1"; local NAME="$2";
  if [ ! -d "$BASE_PATH/$NAME" ] && [ ! -d "$BACKUP_DIR/$NAME" ]; then echo "$NAME"; return; fi
  local RANDOM_SUFFIX=$(get_random_word)
  while [ -d "$BASE_PATH/${NAME}_${RANDOM_SUFFIX}" ] || [ -d "$BACKUP_DIR/${NAME}_${RANDOM_SUFFIX}" ]; do RANDOM_SUFFIX=$(get_random_word); done
  echo "${NAME}_${RANDOM_SUFFIX}"
}
normalize_youtube_url() {
  local INPUT_URL="$1"
  if [[ "$INPUT_URL" =~ youtu\.be/([a-zA-Z0-9_-]+) ]]; then
    VIDEO_ID="${BASH_REMATCH[1]}"; VIDEO_ID="${VIDEO_ID%%\?*}";
    echo "https://www.youtube.com/watch?v=${VIDEO_ID}"
  else
    echo "$INPUT_URL"
  fi
}

# ── MAIN LOOP ────────────────────────────────
URL_INDEX=0
for URL in "${URL_LIST[@]}"; do
  URL_INDEX=$((URL_INDEX + 1))
  URL=$(normalize_youtube_url "$URL")
  echo "============================================================"
  echo "Processing URL $URL_INDEX / $TOTAL_URLS : $URL"
  echo "============================================================"
  TMP_DIR="tmp_downloads_${URL_INDEX}"
  mkdir -p "$TMP_DIR"
  DOWNLOAD_SUCCESS=false
  for METHOD in 1 2 3 4 5 6 7 8; do
    cleanup_download_dir "$TMP_DIR"

    if download_video "$METHOD" "$URL" "$TMP_DIR"; then
      if verify_download_quality "$TMP_DIR" "$QUALITY"; then
        echo "✅ Download successful with method $METHOD"
        DOWNLOAD_SUCCESS=true
        break
      fi

      echo "⚠️ Method $METHOD produced an invalid quality; retrying..."
      cleanup_download_dir "$TMP_DIR"
    else
      echo "⚠️ Method $METHOD failed; retrying..."
    fi

    sleep 3
  done
  if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "❌ All download methods failed for URL: $URL — skipping."; rm -rf "$TMP_DIR"; continue;
  fi
  find "$TMP_DIR" -name "*.part" -delete
  for FILE in "$TMP_DIR"/*; do
    [ -f "$FILE" ] || continue
    if [[ "$FILE" == *.jpg ]] || [[ "$FILE" == *.webp ]]; then continue; fi
    SIZE=$(stat -c%s "$FILE"); BASENAME=$(basename "$FILE"); FILENAME_NO_EXT="${BASENAME%.*}"; EXT="${BASENAME##*.}";
    FILENAME_NO_EXT=$(sanitize_name "$FILENAME_NO_EXT")
    FINAL_FOLDER_NAME=$(get_unique_folder "videos" "$FILENAME_NO_EXT")
    mkdir -p "$BACKUP_DIR/${FINAL_FOLDER_NAME}"
    THUMB_FILE=$(ls "$TMP_DIR"/*.jpg 2>/dev/null | head -1)
    if [ -n "$THUMB_FILE" ] && [ -f "$THUMB_FILE" ]; then cp "$THUMB_FILE" "$BACKUP_DIR/${FINAL_FOLDER_NAME}/thumbnail.jpg"; fi
    echo "${FILENAME_NO_EXT}|${FINAL_FOLDER_NAME}" >> /tmp/video_info.txt
    FOLDER_ENCODED=$(urlencode "${FINAL_FOLDER_NAME}")
    if [ "$SIZE" -gt "$SPLIT_BYTES" ]; then
      ARCHIVE_BASE="$BACKUP_DIR/${FINAL_FOLDER_NAME}/${FINAL_FOLDER_NAME}"
      if [ -n "$ZIP_PASSWORD" ]; then
        7z a -tzip -v${SPLIT_MB}m -p"${ZIP_PASSWORD}" -mx=0 "${ARCHIVE_BASE}.zip" "$FILE"
      else
        zip -0 -s ${SPLIT_MB}m "${ARCHIVE_BASE}.zip" "$FILE"
      fi
      PART_COUNT=$(ls "$BACKUP_DIR/${FINAL_FOLDER_NAME}/"*.zip "$BACKUP_DIR/${FINAL_FOLDER_NAME}/"*.z[0-9]* 2>/dev/null | wc -l)
      echo "Created $PART_COUNT parts"

      TOTAL_SIZE=0
      for part_file in "$BACKUP_DIR/${FINAL_FOLDER_NAME}"/*; do
        if [ -f "$part_file" ]; then
          PART_SIZE=$(stat -c%s "$part_file")
          TOTAL_SIZE=$((TOTAL_SIZE + PART_SIZE))
        fi
      done
      TOTAL_SIZE_MB=$(echo "scale=2; $TOTAL_SIZE / 1024 / 1024" | bc)

      DOWNLOAD_LINKS_MD=""
      LINK_NUM=0
      for part_file in $(ls "$BACKUP_DIR/${FINAL_FOLDER_NAME}/"*.zip "$BACKUP_DIR/${FINAL_FOLDER_NAME}/"*.z[0-9]* 2>/dev/null | sort -V); do
        if [ -f "$part_file" ]; then
          PART_BASENAME=$(basename "$part_file")
          PART_ENCODED=$(urlencode "${PART_BASENAME}")
          RAW_LINK="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/videos/${FOLDER_ENCODED}/${PART_ENCODED}"
          LINK_NUM=$((LINK_NUM + 1))
          DOWNLOAD_LINKS_MD="${DOWNLOAD_LINKS_MD}| ${LINK_NUM} | \`${PART_BASENAME}\` | [Download](${RAW_LINK}) |"$'\n'
        fi
      done

      MAIN_ZIP="${FINAL_FOLDER_NAME}.zip"

      README_FILE="$BACKUP_DIR/${FINAL_FOLDER_NAME}/README.md"
      {
        printf '%s\n' "# ${FILENAME_NO_EXT}"
        printf '%s\n' ""

        # Add thumbnail if it exists (width=250)
        if [ -f "$BACKUP_DIR/${FINAL_FOLDER_NAME}/thumbnail.jpg" ]; then
          THUMB_ENCODED=$(urlencode "thumbnail.jpg")
          THUMB_RAW_LINK="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/videos/${FOLDER_ENCODED}/${THUMB_ENCODED}"
          printf '%s\n' "<div align=\"center\">"
          printf '%s\n' "  <picture>"
          printf '%s\n' "    <img src=\"thumbnail.jpg\" width=\"250\" />"
          printf '%s\n' "  </picture>"
          printf '%s\n' "</div>"
          printf '%s\n' ""
          printf '%s\n' "<br>"
          printf '%s\n' ""
        fi

        printf '%s\n' "---"
        printf '%s\n' ""
        printf '%s\n' "## Video Information"
        printf '%s\n' ""
        printf '%s\n' "| Property | Value |"
        printf '%s\n' "|----------|-------|"
        printf '%s\n' "| **Video Name** | \`${FILENAME_NO_EXT}\` |"
        printf '%s\n' "| **Original Link** | [YouTube Video](${URL}) |"
        printf '%s\n' "| **Total Size** | **${PART_COUNT} parts** - **${TOTAL_SIZE_MB} MB** |"
        printf '%s\n' "| **Quality** | **${QUALITY}** |"
        printf '%s\n' "| **Status** | **Complete (100%)** |"
        if [ -n "$ZIP_PASSWORD" ]; then
          printf '%s\n' "| **Password Protected** | **YES** |"
        else
          printf '%s\n' "| **Password Protected** | **NO** |"
        fi
        printf '%s\n' ""
        printf '%s\n' "---"
        printf '%s\n' ""
        printf '%s\n' "## Download Links"
        printf '%s\n' ""
        printf '%s\n' "> ⬇️ Download **all parts**, then open \`${MAIN_ZIP}\` — the other parts are found automatically."
        printf '%s\n' ""
        printf '%s\n' "| # | File | Link |"
        printf '%s\n' "|---|------|------|"
        printf '%s' "${DOWNLOAD_LINKS_MD}"
        printf '%s\n' ""
        printf '%s\n' "---"
        printf '%s\n' ""
        printf '%s\n' "## How to Extract"
        printf '%s\n' ""
        printf '%s\n' "Download all parts into the **same folder**, then:"
        printf '%s\n' ""
        if [ -n "$ZIP_PASSWORD" ]; then
          printf '%s\n' "| OS | Steps |"
          printf '%s\n' "|----|-------|"
          printf '%s\n' "| **Windows** | Right-click \`${MAIN_ZIP}\` → *Extract Here* (needs [7-Zip](https://www.7-zip.org/) or WinRAR) → enter password |"
          printf '%s\n' "| **Mac** | Open with [Keka](https://www.keka.io/) → enter password |"
          printf '%s\n' "| **Linux** | \`unzip ${MAIN_ZIP}\` or right-click → Extract → enter password |"
          printf '%s\n' "| **Android** | Use [ZArchiver](https://play.google.com/store/apps/details?id=ru.zdevs.zarchiver) → tap \`${MAIN_ZIP}\` → enter password |"
        else
          printf '%s\n' "| OS | Steps |"
          printf '%s\n' "|----|-------|"
          printf '%s\n' "| **Windows** | Double-click \`${MAIN_ZIP}\` — opens in Explorer, WinRAR, or 7-Zip automatically |"
          printf '%s\n' "| **Mac** | Double-click \`${MAIN_ZIP}\` — extracts with Archive Utility or The Unarchiver |"
          printf '%s\n' "| **Linux** | \`unzip ${MAIN_ZIP}\` or right-click → Extract Here (Ark/File Manager) |"
          printf '%s\n' "| **Android** | Tap \`${MAIN_ZIP}\` in your file manager — or use [ZArchiver](https://play.google.com/store/apps/details?id=ru.zdevs.zarchiver) |"
        fi
        printf '%s\n' ""
        printf '%s\n' "---"
        printf '%s\n' ""
        printf '%s\n' "*This tool was created by OurtubeCracked*"
      } > "$README_FILE"

      echo "Created README.md"

    else
      if [ -n "$ZIP_PASSWORD" ]; then
        echo "$BASENAME - creating password-protected zip archive"

        zip -0 -P "${ZIP_PASSWORD}" \
          "$BACKUP_DIR/${FINAL_FOLDER_NAME}/${FINAL_FOLDER_NAME}.zip" \
          "$FILE"

        SIZE_MB=$(echo "scale=2; $SIZE / 1024 / 1024" | bc)
        FILE_ENCODED=$(urlencode "${FINAL_FOLDER_NAME}.zip")
        RAW_LINK="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/videos/${FOLDER_ENCODED}/${FILE_ENCODED}"

        README_FILE="$BACKUP_DIR/${FINAL_FOLDER_NAME}/README.md"
        {
          printf '%s\n' "# ${FILENAME_NO_EXT}"
          printf '%s\n' ""

          # Add thumbnail if it exists (width=250)
          if [ -f "$BACKUP_DIR/${FINAL_FOLDER_NAME}/thumbnail.jpg" ]; then
            THUMB_ENCODED=$(urlencode "thumbnail.jpg")
            THUMB_RAW_LINK="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/videos/${FOLDER_ENCODED}/${THUMB_ENCODED}"
            printf '%s\n' "<div align=\"center\">"
            printf '%s\n' "  <picture>"
            printf '%s\n' "    <img src=\"${THUMB_RAW_LINK}\" alt=\"Video Thumbnail\" width=\"250\" />"
            printf '%s\n' "  </picture>"
            printf '%s\n' "</div>"
            printf '%s\n' ""
            printf '%s\n' "<br>"
            printf '%s\n' ""
          fi

          printf '%s\n' "---"
          printf '%s\n' ""
          printf '%s\n' "## Video Information"
          printf '%s\n' ""
          printf '%s\n' "| Property | Value |"
          printf '%s\n' "|----------|-------|"
          printf '%s\n' "| **Video Name** | \`${FILENAME_NO_EXT}\` |"
          printf '%s\n' "| **Original Link** | [YouTube Video](${URL}) |"
          printf '%s\n' "| **Total Size** | **1 archive** - **${SIZE_MB} MB** |"
          printf '%s\n' "| **Quality** | **${QUALITY}** |"
          printf '%s\n' "| **Status** | **Complete (100%)** |"
          printf '%s\n' "| **Password Protected** | **YES** |"
          printf '%s\n' ""
          printf '%s\n' "---"
          printf '%s\n' ""
          printf '%s\n' "## Download Link"
          printf '%s\n' ""
          printf '%s\n' "| # | File | Link |"
          printf '%s\n' "|---|------|------|"
          printf '%s\n' "| 1 | \`${FINAL_FOLDER_NAME}.zip\` | [Download](${RAW_LINK}) |"
          printf '%s\n' ""
          printf '%s\n' "---"
          printf '%s\n' ""
          printf '%s\n' "## How to Extract"
          printf '%s\n' ""
          printf '%s\n' "| OS | Steps |"
          printf '%s\n' "|----|-------|"
          printf '%s\n' "| **Windows** | Double-click \`${FINAL_FOLDER_NAME}.zip\` → enter password |"
          printf '%s\n' "| **Mac** | Double-click → enter password (or use [The Unarchiver](https://theunarchiver.com/)) |"
          printf '%s\n' "| **Linux** | \`unzip ${FINAL_FOLDER_NAME}.zip\` → enter password |"
          printf '%s\n' "| **Android** | Tap the file in your file manager → enter password |"
          printf '%s\n' ""
          printf '%s\n' "---"
          printf '%s\n' ""
          printf '%s\n' "*This tool was created by OurtubeCracked*"
        } > "$README_FILE"

        echo "Created password-protected zip archive and README.md"

      else
        echo "$BASENAME - copying directly (no archive needed)"

        cp "$FILE" "$BACKUP_DIR/${FINAL_FOLDER_NAME}/${FINAL_FOLDER_NAME}.${EXT}"

        SIZE_MB=$(echo "scale=2; $SIZE / 1024 / 1024" | bc)
        FILE_ENCODED=$(urlencode "${FINAL_FOLDER_NAME}.${EXT}")
        RAW_LINK="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/videos/${FOLDER_ENCODED}/${FILE_ENCODED}"

        README_FILE="$BACKUP_DIR/${FINAL_FOLDER_NAME}/README.md"
        {
          printf '%s\n' "# ${FILENAME_NO_EXT}"
          printf '%s\n' ""

          # Add thumbnail if it exists (width=250)
          if [ -f "$BACKUP_DIR/${FINAL_FOLDER_NAME}/thumbnail.jpg" ]; then
            THUMB_ENCODED=$(urlencode "thumbnail.jpg")
            THUMB_RAW_LINK="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/videos/${FOLDER_ENCODED}/${THUMB_ENCODED}"
            printf '%s\n' "<div align=\"center\">"
            printf '%s\n' "  <picture>"
            printf '%s\n' "    <img src=\"${THUMB_RAW_LINK}\" alt=\"Video Thumbnail\" width=\"250\" />"
            printf '%s\n' "  </picture>"
            printf '%s\n' "</div>"
            printf '%s\n' ""
            printf '%s\n' "<br>"
            printf '%s\n' ""
          fi

          printf '%s\n' "---"
          printf '%s\n' ""
          printf '%s\n' "## Video Information"
          printf '%s\n' ""
          printf '%s\n' "| Property | Value |"
          printf '%s\n' "|----------|-------|"
          printf '%s\n' "| **Video Name** | \`${FILENAME_NO_EXT}\` |"
          printf '%s\n' "| **Original Link** | [YouTube Video](${URL}) |"
          printf '%s\n' "| **Total Size** | **1 file** (no split) - **${SIZE_MB} MB** |"
          printf '%s\n' "| **Quality** | **${QUALITY}** |"
          printf '%s\n' "| **Status** | **Complete (100%)** |"
          printf '%s\n' "| **Password Protected** | **NO** |"
          printf '%s\n' ""
          printf '%s\n' "---"
          printf '%s\n' ""
          printf '%s\n' "## Download Link"
          printf '%s\n' ""
          printf '%s\n' "| # | File | Link |"
          printf '%s\n' "|---|------|------|"
          printf '%s\n' "| 1 | \`${FINAL_FOLDER_NAME}.${EXT}\` | [Download](${RAW_LINK}) |"
          printf '%s\n' ""
          printf '%s\n' "---"
          printf '%s\n' ""
          printf '%s\n' "Ready to use — no extraction needed!"
          printf '%s\n' ""
          printf '%s\n' "---"
          printf '%s\n' ""
          printf '%s\n' "*This tool was created by OurtubeCracked*"
        } > "$README_FILE"

        echo "Copied file and created README.md"
      fi
    fi
  done
  rm -rf "$TMP_DIR"
done
echo "$BACKUP_DIR" > /tmp/backup_dir_path.txt
echo "REPO_OWNER_ENV=${REPO_OWNER_ENV}" > /tmp/env_vars.txt
echo "REPO_NAME_ENV=${REPO_NAME_ENV}" >> /tmp/env_vars.txt
echo "BRANCH_ENV=${BRANCH_ENV}" >> /tmp/env_vars.txt
printf "%s\n" "${URL_LIST[@]}" > /tmp/yt_urls.txt

