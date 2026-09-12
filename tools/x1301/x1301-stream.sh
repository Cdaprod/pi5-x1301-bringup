#!/usr/bin/env bash
# Own the single FFmpeg producer; MediaMTX fans it out. Example: x1301-stream.sh
set -euo pipefail
run=${X1301_RUN:-/run/x1301}; state="$run/runtime.json"
command -v ffmpeg >/dev/null || { echo 'ERROR: ffmpeg is required' >&2; exit 2; }
while :; do
  readarray -t v < <(python3 - "$state" <<'PY'
import json,sys
try: s=json.load(open(sys.argv[1]))
except (OSError,ValueError): s={}
x=s.get('source',{}).get('video',{}); a=s.get('source',{}).get('audio',{}); p=s.get('stream',{}); u=s.get('urls',{})
for value in (s.get('configured',False),x.get('device',''),x.get('width',0),x.get('height',0),x.get('source_fps',0),a.get('pcm',''),a.get('present',False),p.get('encoder',''),p.get('target_width',0),p.get('target_fps',0),p.get('bitrate',''),s.get('ports',{}).get('rtsp',8554),(x.get('device_id') or s.get('source',{}).get('identity',{}).get('device_id') or 'x1301')): print(value)
PY
)
  if [[ ${v[0]:-False} != True || -z ${v[1]:-} || -z ${v[7]:-} ]]; then sleep 2; continue; fi
  input=(-f v4l2 -input_format rgb24 -video_size "${v[2]}x${v[3]}" -framerate "${v[4]}" -i "${v[1]}")
  audio=(); map=(-map 0:v:0)
  if [[ ${v[6]} == True && -n ${v[5]} ]]; then audio=(-f alsa -i "${v[5]}"); map+=(-map 1:a:0?); fi
  filters=(); [[ ${v[8]} -gt 0 && ${v[8]} -lt ${v[2]} ]] && filters=(-vf "scale=${v[8]}:-2,fps=${v[9]}")
  codec=(-c:v "${v[7]}" -b:v "${v[10]}" -g "$(( ${v[9]%.*} * 2 ))")
  [[ ${v[7]} == libx264 ]] && codec+=(-preset veryfast -tune zerolatency)
  ffmpeg -hide_banner -nostdin -loglevel warning -thread_queue_size 8 "${input[@]}" "${audio[@]}" "${map[@]}" "${filters[@]}" "${codec[@]}" -c:a aac -ar 48000 -f rtsp -rtsp_transport tcp "rtsp://127.0.0.1:${v[11]}/${v[12]}" || true
  sleep 2
done
