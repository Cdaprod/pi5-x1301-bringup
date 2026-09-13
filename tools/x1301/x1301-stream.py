#!/usr/bin/env python3
"""Run one FFmpeg producer with encoder fallback and atomic telemetry.

Example: /usr/local/lib/x1301/x1301-stream.py
"""
import json, os, signal, subprocess, sys, time
from pathlib import Path
from x1301lib import atomic_json, now, read_json

RUN = Path(os.environ.get("X1301_RUN", "/run/x1301"))
RUNTIME = RUN / "runtime.json"
running = True

def stop(*_):
    global running
    running = False

def encoder_candidates(state):
    usable = read_json(Path(os.environ.get("X1301_VAR", "/var/lib/x1301")) / "capabilities.json", {}).get("encoders", {})
    order = ["h264_v4l2m2m", "h264_vaapi", "h264_nvenc", "libx264", "libopenh264"]
    return [name for name in order if usable.get(name)]

def command(state, encoder):
    source = state["source"]; video = source["video"]; audio = source["audio"]; stream = state["stream"]
    args = ["ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "warning", "-stats_period", "1",
            "-thread_queue_size", "8", "-f", "v4l2", "-input_format", "rgb24", "-video_size", f"{video['width']}x{video['height']}",
            "-framerate", str(video["source_fps"]), "-i", video["device"]]
    maps = ["-map", "0:v:0"]
    if audio.get("present") and audio.get("validated") and audio.get("plughw_pcm"):
        args += ["-f", "alsa", "-i", audio["plughw_pcm"]]; maps += ["-map", "1:a:0?"]
    filterspec = []
    if stream.get("target_width", 0) < video["width"]: filterspec.append(f"scale={stream['target_width']}:-2")
    if stream.get("target_fps", 0) < video["source_fps"]: filterspec.append(f"fps={stream['target_fps']}")
    filters = ["-vf", ",".join(filterspec)] if filterspec else []
    codec = ["-c:v", encoder, "-b:v", stream["bitrate"], "-g", str(max(1, int(stream["target_fps"]) * 2))]
    if encoder == "libx264": codec += ["-preset", "veryfast", "-tune", "zerolatency"]
    destination = f"rtsp://127.0.0.1:{state['ports']['rtsp']}/x1301"
    return args + maps + filters + codec + ["-c:a", "aac", "-ar", "48000", "-progress", "pipe:1", "-f", "rtsp", "-rtsp_transport", "tcp", destination]

def publish(path, values): atomic_json(RUN / path, {"schema": 1, "timestamp": now(), **values})

def supervise(state, encoder):
    generation = state["mode_generation"]
    publish("stream.json", {"state": "starting", "encoder": encoder, "mode_generation": generation})
    process = subprocess.Popen(command(state, encoder), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
    progress = {}; started = time.monotonic()
    assert process.stdout
    for line in process.stdout:
        key, _, value = line.strip().partition("="); progress[key] = value
        if key != "progress": continue
        frame = int(progress.get("frame", "0") or 0); fps = float(progress.get("fps", "0") or 0)
        common = {"mode_generation": generation, "encoder": encoder, "frame_counter": frame, "stream_fps": fps,
                  "bitrate": progress.get("bitrate"), "speed": progress.get("speed"), "drop_frames": int(progress.get("drop_frames", "0") or 0), "dup_frames": int(progress.get("dup_frames", "0") or 0)}
        publish("stream.json", {"state": "running", **common})
        if state["stream"].get("target_fps", 0) >= state["source"]["video"]["source_fps"]:
            publish("capture.json", {"mode_generation": generation, "capture_fps": fps, "frame_counter": frame, "measurement": "unthrottled_ffmpeg_input"})
        current = read_json(RUNTIME, {})
        if not running or not current.get("configured") or current.get("mode_generation") != generation:
            process.terminate(); break
        progress = {}
    try: return process.wait(timeout=3), time.monotonic() - started
    except subprocess.TimeoutExpired: process.kill(); return process.wait(), time.monotonic() - started

def main():
    signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
    while running:
        state = read_json(RUNTIME, {})
        if not state.get("configured"):
            publish("stream.json", {"state": "waiting", "mode_generation": state.get("mode_generation", 0)}); time.sleep(2); continue
        candidates = encoder_candidates(state)
        if not candidates:
            publish("stream.json", {"state": "error", "error": "no validated H.264 encoder", "mode_generation": state.get("mode_generation", 0)}); time.sleep(10); continue
        for encoder in candidates:
            if not running: break
            rc, elapsed = supervise(state, encoder)
            current = read_json(RUNTIME, {})
            if current.get("mode_generation") != state.get("mode_generation") or not current.get("configured"): break
            publish("stream.json", {"state": "fallback", "encoder": encoder, "error": f"encoder exited {rc} after {elapsed:.1f}s", "mode_generation": state["mode_generation"]})
        time.sleep(2)
    return 0

if __name__ == "__main__": sys.exit(main())
