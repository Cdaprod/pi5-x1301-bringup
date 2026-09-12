#!/usr/bin/env python3
"""Persistent X1301 appliance primitives; uses no third-party Python packages."""
from __future__ import annotations

import hashlib, json, os, re, socket, subprocess, tempfile, time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable

SCHEMA = 2
DEFAULT_PORTS = {"control_http": 8080, "webrtc_http": 8889, "hls_http": 8888, "rtsp": 8554}
QUALITY = {
    "preview": {"width": 640, "fps": 15, "bitrate": "900k"},
    "balanced": {"width": 1280, "fps": 30, "bitrate": "3500k"},
    "quality": {"width": None, "fps": 60, "bitrate": "8000k"},
}

def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2, sort_keys=True); stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def read_json(path: Path, default: Any) -> Any:
    try:
        with path.open() as stream: return json.load(stream)
    except (OSError, ValueError): return default

def parse_env(path: Path) -> dict[str, str]:
    out = {}
    try: lines = path.read_text().splitlines()
    except OSError: return out
    for line in lines:
        match = re.match(r"X1301_([A-Z0-9_]+)=(?:'([^']*)'|\"([^\"]*)\"|(.*))$", line)
        if match: out[match.group(1).lower()] = next((x for x in match.groups()[1:] if x is not None), "")
    return out

def source_id(identity: dict[str, str]) -> str:
    # Enumeration paths are deliberately excluded. HDMI/ALSA metadata supplements the stable graph identity.
    stable = "|".join(identity.get(k, "") for k in ("driver", "bridge", "media_topology", "source_vendor", "source_product", "alsa_id"))
    return "x1301-" + hashlib.sha256((stable or "tc358743|rp1-cfe").encode()).hexdigest()[:10]

def default_profile(device_id: str) -> dict[str, Any]:
    return {"schema": 1, "device_id": device_id, "alias": device_id,
      "edid": {"profile": "1080p60-safe", "auto_load": True},
      "video": {"pixel_format": "RGB3", "orientation": 0, "preferred_width": None, "preferred_height": None, "preferred_fps": None},
      "audio": {"enabled": True, "sample_rate": 48000, "channels": "auto", "format": "auto"},
      "stream": {"enabled": True, "browser": True, "audio": True, "quality_profile": "balanced", "outputs": []}}

class Registry:
    def __init__(self, etc: Path, var: Path): self.etc, self.var = etc, var
    def recognize(self, identity: dict[str, str], runtime: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        did = source_id(identity); devices = read_json(self.var / "devices.json", {"schema": 1, "devices": {}})
        record = devices["devices"].setdefault(did, {"id": did, "first_seen": now(), "alias": did})
        record.update({"last_seen": now(), "runtime": runtime}); atomic_json(self.var / "devices.json", devices)
        profile_path = self.var / "profiles.d" / f"{did}.json"
        profile = read_json(self.etc / "profiles.d" / f"{did}.json", None) or read_json(profile_path, None)
        if profile is None: profile = default_profile(did); atomic_json(profile_path, profile)
        return did, profile

def now() -> str: return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def parse_arecord_cards(text: str) -> list[dict[str, Any]]:
    result = []
    for card, cid, name, device, pcm in re.findall(r"card (\d+): ([^ ]+) \[([^]]+)\], device (\d+): ([^\[]+)", text, re.I):
        score = sum(term in (cid+name+pcm).lower() for term in ("tc358743", "hdmi", "x1301"))
        result.append({"card": int(card), "device": int(device), "id": cid, "name": name, "pcm_name": pcm.strip(), "pcm": f"hw:{card},{device}", "score": score})
    return sorted(result, key=lambda x: (-x["score"], x["card"], x["device"]))

def parse_hw_params(text: str) -> dict[str, Any]:
    def val(pattern: str, default=None):
        m = re.search(pattern, text, re.M); return m.group(1) if m else default
    channels = val(r"^CHANNELS:\s*(?:\[\s*)?(\d+)")
    return {"channels": int(channels) if channels else None, "format": val(r"^FORMAT:\s*([^\s]+)"), "sample_rate": int(val(r"^RATE:\s*(?:\[\s*)?(\d+)", "0")) or None}

def probe_capabilities(run: Callable[..., subprocess.CompletedProcess] = subprocess.run) -> dict[str, Any]:
    def cmd(args):
        try: return run(args, text=True, capture_output=True, timeout=8).stdout
        except (OSError, subprocess.SubprocessError): return ""
    enc = cmd(["ffmpeg", "-hide_banner", "-encoders"]); hw = cmd(["ffmpeg", "-hide_banner", "-hwaccels"])
    gst = cmd(["gst-inspect-1.0"]); devices = cmd(["v4l2-ctl", "--list-devices"])
    names = ("h264_v4l2m2m", "h264_vaapi", "h264_nvenc", "libx264", "libopenh264", "aac", "libopus")
    return {"schema": 1, "timestamp": now(), "encoders": {n: bool(re.search(rf"\b{re.escape(n)}\b", enc)) for n in names},
            "hwaccels": [x.strip() for x in hw.splitlines() if x.strip() and "acceleration" not in x.lower()],
            "gstreamer": {"installed": bool(gst), "v4l2h264enc": "v4l2h264enc" in gst}, "v4l2_devices": devices}

def select_pipeline(caps: dict[str, Any], profile: str, width: int, fps: float) -> dict[str, Any]:
    enc = caps.get("encoders", {}); policy = dict(QUALITY.get(profile, QUALITY["balanced"])); backend = "software"; name = ""
    for candidate in ("h264_v4l2m2m", "h264_vaapi", "h264_nvenc"):
        if enc.get(candidate): name, backend = candidate, "hardware"; break
    if not name:
        name = "libx264" if enc.get("libx264") else "libopenh264" if enc.get("libopenh264") else ""
    degraded = not name or (backend == "software" and (width > 1280 or fps > 30))
    if backend == "software": policy["width"] = min(policy["width"] or width, 1280); policy["fps"] = min(policy["fps"], 30)
    return {"encoder": name, "encoder_backend": backend if name else "unavailable", "transport": "WebRTC", "quality_profile": profile,
            "target_width": policy["width"] or width, "target_fps": min(policy["fps"], fps or policy["fps"]), "bitrate": policy["bitrate"],
            "degraded": degraded, "degrade_reason": "software capacity guardrail" if degraded and name else "no H.264 encoder" if not name else ""}

def allocate_ports(path: Path, configured: dict[str, int] | None = None, in_use: Callable[[int], Any] | None = None) -> dict[str, Any]:
    old = read_json(path, {"schema": 1, "ports": {}, "conflicts": []})
    # Once assigned, a bound socket is normally one of our own services. Preserve
    # the registry unless an administrator explicitly changes a requested port.
    desired = {**DEFAULT_PORTS, **(configured or {})}
    if old.get("ports") and (not configured or old.get("requested", DEFAULT_PORTS) == desired):
        return old
    requested = desired
    in_use = in_use or (lambda p: _port_in_use(p)); assigned, conflicts = {}, []
    reserved = set()
    for service, wanted in requested.items():
        port = int(wanted); conflict = in_use(port) or port in reserved
        if conflict:
            replacement = next(p for p in range(port + 1, port + 1000) if not in_use(p) and p not in reserved)
            conflicts.append({"service": service, "requested": port, "conflict": str(conflict), "replacement": replacement}); port = replacement
        assigned[service] = port; reserved.add(port)
    result = {"schema": 1, "requested": desired, "ports": assigned, "conflicts": conflicts}; atomic_json(path, result); return result

def _port_in_use(port: int) -> bool:
    with socket.socket() as s:
        try: s.bind(("0.0.0.0", port)); return False
        except OSError as exc: return exc

def resolve_edid(profile: str, roots: list[Path]) -> Path:
    names = {"1080p60-safe": "x1301-compatible.txt", "x1301-compatible": "x1301-compatible.txt"}
    if profile not in names: raise ValueError(f"unknown EDID profile: {profile}")
    for root in roots:
        candidate = root / names[profile]
        if candidate.is_file(): return candidate.resolve()
    raise FileNotFoundError(f"EDID profile {profile} ({names[profile]}) not found in: {', '.join(map(str, roots))}")

def urls(host: str, ports: dict[str, int], stream: str) -> dict[str, str]:
    lan = host if "." in host else host + ".local"
    return {"web": f"http://{lan}:{ports['control_http']}/", "webrtc": f"http://{lan}:{ports['webrtc_http']}/{stream}/",
            "hls": f"http://{lan}:{ports['hls_http']}/{stream}/index.m3u8", "rtsp": f"rtsp://{lan}:{ports['rtsp']}/{stream}"}

def generate_mediamtx(path: Path, ports: dict[str, int], stream: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"# GENERATED by x1301; schema=1 timestamp={now()}\nrtspAddress: :{ports['rtsp']}\nhlsAddress: :{ports['hls_http']}\nwebrtcAddress: :{ports['webrtc_http']}\npaths:\n  {stream}:\n    source: publisher\n")

@dataclass
class Source:
    identity: dict[str, Any] = field(default_factory=dict); signal: dict[str, Any] = field(default_factory=dict)
    video: dict[str, Any] = field(default_factory=dict); audio: dict[str, Any] = field(default_factory=dict); profile: dict[str, Any] = field(default_factory=dict)
    def json(self) -> dict[str, Any]: return asdict(self)
