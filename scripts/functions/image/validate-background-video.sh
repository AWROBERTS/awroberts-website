#!/usr/bin/env bash

validate_single_segment() {
  local seg_path="$1"
  local tmp_failures="$2"

  if [[ ! -f "$seg_path" ]]; then
    echo "❌ Missing segment file: $seg_path" >> "$tmp_failures"
    return
  fi

  if ! ffprobe -v error -select_streams v:0 \
       -show_entries stream=codec_name -of csv=p=0 \
       "$seg_path" >/dev/null 2>&1; then
    echo "❌ Corrupt or unreadable segment: $seg_path" >> "$tmp_failures"
  fi
}

validate_background_video() {
  local source_path="$BACKGROUND_VIDEO_SOURCE"

  echo "🔍 Validating background video source: $source_path"

  if [[ ! -f "$source_path" ]]; then
    echo "ERROR: HLS playlist not found: $source_path" >&2
    return 1
  fi

  echo "📄 Parsing playlist for segment references…"

  local playlist_dir
  playlist_dir="$(dirname "$source_path")"

  local segments
  mapfile -t segments < <(grep "\.ts" "$source_path")

  if [[ ${#segments[@]} -eq 0 ]]; then
    echo "ERROR: No segments found in playlist." >&2
    return 1
  fi

  echo "📦 Found ${#segments[@]} segments — validating in parallel…"

  local tmp_failures
  tmp_failures="$(mktemp)"

  export -f validate_single_segment

  printf "%s\n" "${segments[@]}" \
    | sed "s|^|$playlist_dir/|" \
    | xargs -P8 -I{} bash -c 'validate_single_segment "$1" "$2"' _ {} "$tmp_failures"

  if [[ -s "$tmp_failures" ]]; then
    echo "❌ Segment validation failed:"
    cat "$tmp_failures" >&2
    rm -f "$tmp_failures"
    return 1
  fi

  rm -f "$tmp_failures"
  echo "✅ All ${#segments[@]} HLS segments validated successfully (parallel scan)."
}
