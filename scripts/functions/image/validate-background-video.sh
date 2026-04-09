#!/usr/bin/env bash

validate_background_video() {
  local source_path="$BACKGROUND_VIDEO_SOURCE"

  echo "🔍 Validating background video source: $source_path"

  if [[ ! -f "$source_path" ]]; then
    echo "ERROR: HLS playlist not found: $source_path" >&2
    return 1
  fi

  echo "📄 Parsing playlist for segment references…"

  # Determine the directory containing the playlist
  local playlist_dir
  playlist_dir="$(dirname "$source_path")"

  # Extract segment list from playlist
  local segments
  mapfile -t segments < <(grep "\.ts" "$source_path")

  if [[ ${#segments[@]} -eq 0 ]]; then
    echo "ERROR: No segments found in playlist." >&2
    return 1
  fi

  echo "📦 Found ${#segments[@]} segments — validating each with ffprobe…"

  local bad_segments=0

  for seg in "${segments[@]}"; do
    local seg_path="$playlist_dir/$seg"

    if [[ ! -f "$seg_path" ]]; then
      echo "❌ Missing segment file: $seg_path"
      ((bad_segments++))
      continue
    fi

    # ffprobe validation (fast, safe)
    if ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
        -of csv=p=0 "$seg_path" >/dev/null 2>&1; then
      echo "❌ Corrupt or unreadable segment: $seg_path"
      ((bad_segments++))
    fi
  done

  if [[ $bad_segments -gt 0 ]]; then
    echo "❌ Segment validation failed — $bad_segments bad segment(s) detected." >&2
    return 1
  fi

  echo "✅ All ${#segments[@]} HLS segments validated successfully."
}
