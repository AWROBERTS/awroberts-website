#!/usr/bin/env bash

validate_background_video() {
  local media_file="/var/www/$BACKGROUND_VIDEO_FILENAME"

  if [[ ! -f "$media_file" ]]; then
    echo "ERROR: background video file not found: $media_file" >&2
    return 1
  fi

  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "ERROR: ffprobe is not installed" >&2
    return 1
  fi

  local video_codec audio_stream_count
  video_codec="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$media_file" | head -n 1)"
  audio_stream_count="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$media_file" | wc -l | tr -d ' ')"

  if [[ -z "$video_codec" ]]; then
    echo "ERROR: no video stream found in $media_file" >&2
    return 1
  fi

  if [[ "$video_codec" != "h264" ]]; then
    echo "ERROR: expected h264 video, got '$video_codec' in $media_file" >&2
    return 1
  fi

  if [[ "$audio_stream_count" -gt 0 ]]; then
    echo "WARN: audio stream(s) found in $media_file; HLS job will ignore them" >&2
  fi

  echo "Background video validation passed: $media_file ($video_codec, audio streams: $audio_stream_count)"
}
