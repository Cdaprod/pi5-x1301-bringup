#!/usr/bin/env python3
"""Reconcile watcher state into persistent identity/profile/stream state.

Example: x1301-appliance.py --once
"""
import argparse, json, os, shutil, signal, socket, subprocess, sys, time
from pathlib import Path
from x1301lib import *
STARTED = time.monotonic()

def paths():
    return tuple(Path(os.environ.get(k, d)) for k, d in (("X1301_ETC", "/etc/x1301"), ("X1301_VAR", "/var/lib/x1301"), ("X1301_RUN", "/run/x1301")))

def run_text(args):
    try: return subprocess.run(args, capture_output=True, text=True, timeout=8).stdout
    except (OSError, subprocess.SubprocessError): return ""

def audio_state(env, previous=None):
    present = env.get("audio_present") == "1"
    cards = parse_arecord_cards(run_text(["arecord", "-l"])) if present else []
    card = cards[0] if cards and cards[0]["score"] else None
    params = parse_hw_params(run_text(["arecord", "-D", card["pcm"], "--dump-hw-params", "-d", "0", "/dev/null"])) if card else {}
    validated = bool(previous and card and previous.get("pcm") == card["pcm"] and previous.get("validated"))
    if card and not validated:
        try:
            validated = subprocess.run(["arecord", "-q", "-D", card["pcm"], "-d", "1", "-f", params.get("format") or "S32_LE", "/dev/null"], timeout=3).returncode == 0
        except (OSError, subprocess.SubprocessError): validated = False
    return {"present": present, "validated": validated, "device": card["name"] if card else None, "pcm": card["pcm"] if card else None,
            "stable_id": card["id"] if card else None, "sample_rate": int(env.get("audio_sampling_rate") or 0) or params.get("sample_rate"),
            "channels": params.get("channels"), "format": params.get("format")}

def reconcile(etc, var, run):
    for directory in (etc / "profiles.d", var / "profiles.d", var / "generated", run / "generated"): directory.mkdir(parents=True, exist_ok=True)
    config = read_json(etc / "config.json", {}); env = parse_env(run / "state.env")
    ports_record = allocate_ports(var / "ports.json", config.get("ports")); ports = ports_record["ports"]
    caps = probe_capabilities(); atomic_json(var / "capabilities.json", caps)
    previous = read_json(run / "runtime.json", {}); previous_audio = previous.get("source", {}).get("audio", {})
    audio = audio_state(env, previous_audio); device_id = None; profile = default_profile("x1301-unknown")
    if env.get("rp1_cfe_detected") == "1":
        ident = {"driver": env.get("driver", "rp1-cfe"), "bridge": "tc358743", "media_topology": "tc358743>csi2:4>rp1-cfe-csi2_ch0:0", "alsa_id": audio.get("stable_id") or ""}
        runtime_nodes = {"media_device": env.get("media"), "subdev": env.get("subdev"), "video_device": env.get("video"), "alsa_pcm": audio.get("pcm")}
        device_id, profile = Registry(etc, var).recognize(ident, runtime_nodes)
    width, height, fps = int(env.get("width") or 0), int(env.get("height") or 0), float(env.get("fps") or 0)
    pipeline = select_pipeline(caps, profile["stream"]["quality_profile"], width, fps)
    host = socket.gethostname(); viewer = urls(host, ports, device_id or "x1301")
    generate_mediamtx(run / "generated" / "mediamtx.yml", ports, device_id or "x1301")
    configured = env.get("configured") == "1"
    source = Source(identity={"device_id": device_id, "alias": profile.get("alias") if device_id else None},
      signal={"state": "LIVE" if configured else env.get("signal_state", "DISCONNECTED"), "power_present": env.get("power_present") == "1", "timings_locked": env.get("timings_locked") == "1", "generation": int(env.get("mode_generation") or 0)},
      video={"device": env.get("video"), "media_device": env.get("media"), "subdev": env.get("subdev"), "pixel_format": env.get("pixelformat", "RGB3"), "width": width or None, "height": height or None, "source_fps": fps or None, "capture_fps": None, "orientation": profile["video"]["orientation"]},
      audio=audio, profile={"active": device_id, "settings": profile})
    state = {"schema": SCHEMA, "timestamp": now(), "uptime_seconds": round(time.monotonic() - STARTED, 1), "service_state": "ready", "source": source.json(), "configured": configured,
      "stream": {**pipeline, "ready": False, "stream_fps": None, "frame_counter": None, "outputs": profile["stream"].get("outputs", [])},
      "ports": ports, "port_conflicts": ports_record["conflicts"], "urls": viewer, "mode_id": env.get("mode_id"), "mode_generation": int(env.get("mode_generation") or 0),
      "driver": env.get("driver"), "last_transition": env.get("last_change"), "last_success": now() if configured else None, "last_error": env.get("error") or None}
    atomic_json(run / "runtime.json", state); atomic_json(var / "last-runtime.json", state)
    return state

def main():
    parser=argparse.ArgumentParser(); parser.add_argument("--once", action="store_true"); parser.add_argument("--interval", type=float, default=2); args=parser.parse_args()
    etc,var,run=paths(); running=True
    def stop(*_):
        nonlocal running; running=False
    signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
    while running:
        try: reconcile(etc,var,run)
        except Exception as exc:
            atomic_json(run / "runtime.json", {"schema": SCHEMA, "timestamp": now(), "service_state":"error", "last_error":str(exc)})
            if args.once: raise
        if args.once: break
        time.sleep(args.interval)
    return 0
if __name__ == "__main__": sys.exit(main())
