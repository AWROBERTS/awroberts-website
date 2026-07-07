#!/usr/bin/env bash

validate_background_video() {
  local source_path="$BACKGROUND_VIDEO_SOURCE"

  echo "🔍 Validating background video source on ARM node: $source_path"

  # Run validation inside the ARM node using kubectl debug + chroot
  kubectl debug node/awr-ffmpeg -it --image=alpine -- chroot /host sh -c "
    if [ ! -f '$source_path' ]; then
      echo 'ERROR: HLS playlist not found: $source_path' >&2
      exit 1
    fi

    echo '📄 Parsing playlist for segment references…'
    playlist_dir=\$(dirname '$source_path')
    mapfile -t segments < <(grep -F '.ts' '$source_path')

    if [ \${#segments[@]} -eq 0 ]; then
      echo 'ERROR: No segments found in playlist.' >&2
      exit 1
    fi

    echo '📦 Found \${#segments[@]} segments — validating in parallel (P=8)…'

    tmp_failures=\$(mktemp)

    printf '%s\n' \"\${segments[@]}\" \
      | sed \"s|^|\$playlist_dir/|\" \
      | xargs -P8 -I{} ffprobe -v error -select_streams v:0 \
          -show_entries stream=codec_name -of csv=p=0 '{}' \
          >/dev/null 2>>\"\$tmp_failures\"

    if [ -s \"\$tmp_failures\" ]; then
      echo '❌ Segment validation failed:'
      cat \"\$tmp_failures\" >&2
      rm -f \"\$tmp_failures\"
      exit 1
    fi

    rm -f \"\$tmp_failures\"
    echo '✅ All \${#segments[@]} HLS segments validated successfully.'
  "
}
