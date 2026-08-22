#!/usr/bin/env bash
set -u

set +e
BACKUP_DIR=$(cat /tmp/backup_dir_path.txt)
source /tmp/env_vars.txt
REPO_OWNER=${REPO_OWNER_ENV}
REPO_NAME=${REPO_NAME_ENV}
BRANCH=${BRANCH_ENV}
mapfile -t URL_LIST < /tmp/yt_urls.txt

sub_download() {
  local MODE=$1; local OUT="$2"; local SURL="$3";
  local SUB_DIR=$(dirname "$OUT")
  sub_count() { find "$SUB_DIR" -type f \( -name "*.vtt" -o -name "*.srt" \) 2>/dev/null | wc -l; }
  fa_count()  { find "$SUB_DIR" -type f \( -name "*.fa.vtt" -o -name "*.fa.srt" \) 2>/dev/null | wc -l; }
  en_count()  { find "$SUB_DIR" -type f \( -name "*.en.vtt" -o -name "*.en.srt" \) 2>/dev/null | wc -l; }
  sub_flags() {
    case $MODE in
      all)        echo "--write-sub --sub-langs fa,en";;
      fa-native)  echo "--write-sub --sub-langs fa";;
      fa-auto)    echo "--write-auto-sub --sub-langs fa";;
      en-auto)    echo "--write-auto-sub --sub-langs en";;
      auto-both)  echo "--write-auto-sub --sub-langs en,fa";;
    esac
  }
  SFLAGS=$(sub_flags)
  COMMON_SUB="--sub-format vtt/srt/best --convert-subs vtt --skip-download --no-playlist --no-check-certificates --output ${OUT}"
  for METHOD in 1 2 3 4 5 6 7 8; do
    echo "  [subtitle] method $METHOD ..."
    case $METHOD in
       1) yt-dlp --proxy "socks5://127.0.0.1:1080" --extractor-args "youtube:player_client=web" --js-runtimes deno --remote-components ejs:github --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" --add-header "Accept-Language:en-US,en;q=0.9" $SFLAGS $COMMON_SUB "$SURL" 2>&1 || true;;
       2) yt-dlp --proxy "socks5://127.0.0.1:1080" --extractor-args "youtube:player_client=web" --js-runtimes deno --remote-components ejs:npm --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" --add-header "Accept-Language:en-US,en;q=0.9" $SFLAGS $COMMON_SUB "$SURL" 2>&1 || true;;
       3) yt-dlp --proxy "socks5://127.0.0.1:1080" --extractor-args "youtube:player_client=web,mweb,android_vr" --js-runtimes deno --remote-components ejs:github $SFLAGS $COMMON_SUB "$SURL" 2>&1 || true;;
       4) yt-dlp --proxy "socks5://127.0.0.1:1080" --extractor-args "youtube:player_client=mweb" $SFLAGS $COMMON_SUB "$SURL" 2>&1 || true;;
       5) yt-dlp --proxy "socks5://127.0.0.1:1080" --extractor-args "youtube:player_client=android_vr" $SFLAGS $COMMON_SUB "$SURL" 2>&1 || true;;
       6) yt-dlp --extractor-args "youtube:player_client=web" --js-runtimes deno --remote-components ejs:github $SFLAGS $COMMON_SUB "$SURL" 2>&1 || true;;
       7) yt-dlp --extractor-args "youtube:player_client=mweb" $SFLAGS $COMMON_SUB "$SURL" 2>&1 || true;;
       8) yt-dlp --proxy "socks5://127.0.0.1:1080" --extractor-args "youtube:player_client=android" --user-agent "Mozilla/5.0 (Linux; Android 12; SM-S906N Build/QP1A.190711.020) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36" $SFLAGS $COMMON_SUB "$SURL" 2>&1 || true;;
    esac
    if [ "$MODE" = "fa-native" ] || [ "$MODE" = "fa-auto" ]; then
      [ "$(fa_count)" -gt 0 ] && { echo "  [subtitle] ✅ success with method $METHOD"; return 0; }
    elif [ "$MODE" = "en-auto" ]; then
      [ "$(en_count)" -gt 0 ] && { echo "  [subtitle] ✅ success with method $METHOD"; return 0; }
    elif [ "$MODE" = "auto-both" ]; then
      if [ "$(en_count)" -gt 0 ] && [ "$(fa_count)" -gt 0 ]; then
        echo "  [subtitle] ✅ success with method $METHOD (both en+fa downloaded)"; return 0;
      fi
    else
      [ "$(sub_count)" -gt 0 ] && { echo "  [subtitle] ✅ success with method $METHOD"; return 0; }
    fi
    sleep 1
  done
  return 1
}

URL_INDEX=0
while IFS='|' read -r ORIGINAL_NAME FOLDER_NAME; do
  URL_INDEX=$((URL_INDEX + 1)); URL="${URL_LIST[$((URL_INDEX - 1))]}";
  [ -z "$FOLDER_NAME" ] && continue
  SUBTITLE_DIR="$BACKUP_DIR/${FOLDER_NAME}/subtitle"; mkdir -p "$SUBTITLE_DIR";
  OUT_TMPL="${SUBTITLE_DIR}/%(title)s"
  echo "Downloading subtitles for: $FOLDER_NAME"
  sub_download "all" "$OUT_TMPL" "$URL" || true
  EN_COUNT=$(find "$SUBTITLE_DIR" -type f \( -name "*.en.vtt" -o -name "*.en.srt" \) 2>/dev/null | wc -l)
  FA_COUNT=$(find "$SUBTITLE_DIR" -type f \( -name "*.fa.vtt" -o -name "*.fa.srt" \) 2>/dev/null | wc -l)
  if [ "$EN_COUNT" -eq 0 ] || [ "$FA_COUNT" -eq 0 ]; then
    sub_download "auto-both" "$OUT_TMPL" "$URL" || true
  fi
  SUB_COUNT=$(find "$SUBTITLE_DIR" -type f 2>/dev/null | wc -l)
  if [ "$SUB_COUNT" -eq 0 ]; then
    echo "  (no subtitles available for this video)"
    rmdir "$SUBTITLE_DIR" 2>/dev/null || true
  else
    echo ""
    echo "→ Subtitle files downloaded ($SUB_COUNT file(s)):"
    find "$SUBTITLE_DIR" -type f 2>/dev/null | while read -r SUB_FILE; do
      echo "  • $(basename "$SUB_FILE")"
    done

    # Create subtitle.zip inside the video folder (not inside subtitle/)
    ZIP_PATH="$BACKUP_DIR/${FOLDER_NAME}/subtitle.zip"
    echo ""
    echo "→ Zipping subtitles → subtitle.zip ..."

    # Zip with error handling - don't fail if zip has issues
    if (cd "$SUBTITLE_DIR" && zip -j "$ZIP_PATH" ./* 2>&1); then
      rm -rf "$SUBTITLE_DIR"

      if [ -f "$ZIP_PATH" ]; then
        ZIP_SIZE_MB=$(echo "scale=2; $(stat -c%s "$ZIP_PATH" 2>/dev/null || echo 0) / 1024 / 1024" | bc 2>/dev/null || echo "0.00")
        echo "✅ subtitle.zip created (${ZIP_SIZE_MB} MB)"
      else
        echo "⚠️  Failed to create subtitle.zip - continuing without subtitles"
        rm -rf "$SUBTITLE_DIR" 2>/dev/null || true
        continue
      fi
    else
      echo "⚠️  Zip command failed - continuing without subtitles"
      rm -rf "$SUBTITLE_DIR" 2>/dev/null || true
      continue
    fi

    # Build the raw download link for subtitle.zip - with error handling
    FOLDER_ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$FOLDER_NAME" 2>/dev/null || echo "$FOLDER_NAME")
    SUB_ZIP_ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('subtitle.zip', safe=''))" 2>/dev/null || echo "subtitle.zip")
    SUB_RAW_LINK="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/videos/${FOLDER_ENCODED}/${SUB_ZIP_ENCODED}"

    # Patch the existing README.md — insert subtitle section after Video Information, before Download Links
    README_FILE="$BACKUP_DIR/${FOLDER_NAME}/README.md"
    if [ -f "$README_FILE" ]; then
      # Write a temp file with the subtitle section
      SUB_SECTION_FILE=$(mktemp 2>/dev/null || echo "/tmp/sub_section_$")
      if [ -n "$SUB_SECTION_FILE" ]; then
        {
          printf '%s\n' ""
          printf '%s\n' "---"
          printf '%s\n' ""
          printf '%s\n' "## 🔤 Subtitles"
          printf '%s\n' ""
          printf '%s\n' "| # | File | Link |"
          printf '%s\n' "|---|------|------|"
          printf '%s\n' "| 1 | \`subtitle.zip\` | [Download](${SUB_RAW_LINK}) |"
          printf '%s\n' ""
          printf '%s\n' "> Contains all available subtitle languages. Extract to get \`.vtt\` files."
        } > "$SUB_SECTION_FILE" 2>/dev/null || true

        # Find line number of "## Download Link" section (works for both "## Download Links" and "## Download Link")
        DOWNLOAD_LINE=$(grep -n "^## Download Link" "$README_FILE" 2>/dev/null | head -1 | cut -d: -f1)
        if [ -n "$DOWNLOAD_LINE" ] && [ "$DOWNLOAD_LINE" -gt 0 ] 2>/dev/null; then
          # Find the "---" separator right before "## Download Link" (should be 2 lines before)
          INSERT_AT=$((DOWNLOAD_LINE - 2))
          if [ "$INSERT_AT" -lt 1 ]; then
            INSERT_AT=$((DOWNLOAD_LINE - 1))
          fi
          if head -n "$INSERT_AT" "$README_FILE" > "${README_FILE}.tmp" 2>/dev/null; then
            cat "$SUB_SECTION_FILE" >> "${README_FILE}.tmp" 2>/dev/null || true
            printf '\n' >> "${README_FILE}.tmp" 2>/dev/null || true
            tail -n "+$((INSERT_AT + 1))" "$README_FILE" >> "${README_FILE}.tmp" 2>/dev/null || true
            mv "${README_FILE}.tmp" "$README_FILE" 2>/dev/null && echo "README patched with subtitle section (after Video Information)." || echo "⚠️  README patch failed, but continuing..."
          fi
        else
          # Fallback: No "Download Link" section found — just append
          cat "$SUB_SECTION_FILE" >> "$README_FILE" 2>/dev/null && echo "README appended with subtitle download link." || echo "⚠️  README append failed, but continuing..."
        fi
        rm -f "$SUB_SECTION_FILE" 2>/dev/null || true
      fi
    fi
  fi
done < /tmp/video_info.txt

echo ""
echo "Subtitle download phase complete."
echo "=== Final backup dir structure ==="
find "$BACKUP_DIR" -type f 2>/dev/null | sort || true

# Re-enable exit on error for subsequent steps
set -e

# Ensure this step always exits successfully, even if some subtitles failed
echo "✅ Subtitle step completed - any failures were handled gracefully"
exit 0

