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

def stable_id(prefix: str, values: list[str]) -> str:
    return prefix + "-" + hashlib.sha256("|".join(values).encode()).hexdigest()[:10]

def adapter_id(identity: dict[str, str]) -> str:
    """Identify the capture adapter without using Linux enumeration paths."""
    return stable_id("x1301", [identity.get(k, "") for k in ("driver", "bridge", "media_topology", "udev_path")])

def source_id(adapter: str, fingerprint: str | None = None, fallback_slot: str = "default") -> str:
    """Identify an HDMI source, falling back to a persistent adapter source slot."""
    return stable_id("source", [adapter, "fingerprint", fingerprint]) if fingerprint else stable_id("source", [adapter, "slot", fallback_slot])

def default_profile(device_id: str) -> dict[str, Any]:
    return {"schema": 1, "device_id": device_id, "alias": device_id,
      "edid": {"profile": "1080p60-safe", "auto_load": True},
      "video": {"pixel_format": "RGB3", "orientation": 0, "preferred_width": None, "preferred_height": None, "preferred_fps": None},
      "audio": {"enabled": True, "sample_rate": 48000, "channels": "auto", "format": "auto"},
      "stream": {"enabled": True, "browser": True, "audio": True, "quality_profile": "balanced", "outputs": []}}

class Registry:
    def __init__(self, etc: Path, var: Path): self.etc, self.var = etc, var
    def recognize(self, identity: dict[str, str], runtime: dict[str, Any], fingerprint: str | None = None) -> tuple[str, str, dict[str, Any]]:
        aid = adapter_id(identity)
        registry = read_json(self.var / "devices.json", {"schema": 2, "adapters": {}, "sources": {}})
        # Migrate the original flat registry without discarding it.
        registry.setdefault("legacy_devices", registry.pop("devices", {})); registry["schema"] = 2
        adapters = registry.setdefault("adapters", {}); sources = registry.setdefault("sources", {})
        adapter = adapters.setdefault(aid, {"id": aid, "first_seen": now(), "fallback_slot": "default"})
        adapter.update({"last_seen": now(), "runtime": runtime})
        did = source_id(aid, fingerprint, adapter["fallback_slot"])
        record = sources.setdefault(did, {"id": did, "adapter_id": aid, "fingerprint": fingerprint, "first_seen": now(), "alias": did})
        record.update({"last_seen": now(), "runtime": runtime})
        profile_path = self.var / "profiles.d" / f"{did}.json"
        profile = read_json(self.etc / "profiles.d" / f"{did}.json", None) or read_json(profile_path, None)
        if profile is None: profile = default_profile(did); atomic_json(profile_path, profile)
        atomic_json(self.var / "devices.json", registry)
        return aid, did, profile

def now() -> str: return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def parse_arecord_cards(text: str) -> list[dict[str, Any]]:
    result = []
    for card, cid, name, device, pcm in re.findall(r"card (\d+): ([^ ]+) \[([^]]+)\], device (\d+): ([^\[]+)", text, re.I):
        score = sum(term in (cid+name+pcm).lower() for term in ("tc358743", "hdmi", "x1301"))
        result.append({"card": int(card), "device": int(device), "id": cid, "name": name, "pcm_name": pcm.strip(), "pcm": f"hw:{card},{device}", "score": score})
    return sorted(result, key=lambda x: (-x["score"], x["card"], x["device"]))

def parse_cec_source(text: str) -> dict[str, str]:
    """Extract source-stable CEC metadata while excluding logical/node addresses."""
    fields = {}
    aliases = {"vendor id": "vendor_id", "osd name": "osd_name", "device type": "device_type", "language": "language"}
    for label, key in aliases.items():
        match = re.search(rf"^\s*{re.escape(label)}\s*:\s*(.+?)\s*$", text, re.I | re.M)
        if match and match.group(1).lower() not in ("unknown", "n/a"): fields[key] = match.group(1).strip()
    return fields

def cec_fingerprint(metadata: dict[str, str]) -> str | None:
    return stable_id("hdmi", [metadata[k] for k in sorted(metadata)]) if metadata else None

def _alsa_values(text: str, key: str) -> list[str]:
    match = re.search(rf"^{key}:\s*(.+)$", text, re.M)
    if not match: return []
    return re.findall(r"[A-Z][A-Z0-9_]+|\d+", match.group(1))

def parse_hw_params(text: str, reported_rate: int | None = None) -> dict[str, Any]:
    formats = [x for x in _alsa_values(text, "FORMAT") if not x.isdigit()]
    channel_values = [int(x) for x in _alsa_values(text, "CHANNELS") if x.isdigit()]
    rate_values = [int(x) for x in _alsa_values(text, "RATE") if x.isdigit()]
    chosen_format = next((x for x in ("S32_LE", "S24_LE", "S16_LE") if x in formats), formats[0] if formats else None)
    channels = 2 if 2 in channel_values or (len(channel_values) == 2 and channel_values[0] <= 2 <= channel_values[1]) else (min(channel_values) if channel_values else None)
    if reported_rate and (reported_rate in rate_values or len(rate_values) == 2 and rate_values[0] <= reported_rate <= rate_values[1]): rate = reported_rate
    elif 48000 in rate_values or len(rate_values) == 2 and rate_values[0] <= 48000 <= rate_values[1]: rate = 48000
    else: rate = min(rate_values) if rate_values else reported_rate
    return {"formats": formats, "channel_values": channel_values, "rate_values": rate_values,
            "format": chosen_format, "channels": channels, "sample_rate": rate}

def probe_capabilities(run: Callable[..., subprocess.CompletedProcess] = subprocess.run, device_nodes: list[str] | None = None) -> dict[str, Any]:
    def cmd(args):
        try: return run(args, text=True, capture_output=True, timeout=8).stdout
        except (OSError, subprocess.SubprocessError): return ""
    enc = cmd(["ffmpeg", "-hide_banner", "-encoders"]); hw = cmd(["ffmpeg", "-hide_banner", "-hwaccels"])
    gst = cmd(["gst-inspect-1.0"]); devices = cmd(["v4l2-ctl", "--list-devices"])
    names = ("h264_v4l2m2m", "h264_vaapi", "h264_nvenc", "libx264", "libopenh264", "aac", "libopus")
    advertised = {n: bool(re.search(rf"\b{re.escape(n)}\b", enc)) for n in names}
    codec_nodes = []
    for node in device_nodes or sorted(str(x) for x in Path("/dev").glob("video*")):
        details = cmd(["v4l2-ctl", "-d", node, "-D"])
        if re.search(r"Video Memory-to-Memory|M2M|Encoder", details, re.I): codec_nodes.append({"node": node, "capabilities": details})
    usable = {}
    for name in names:
        if not advertised[name]: usable[name] = False; continue
        if name in ("aac", "libopus"): usable[name] = advertised[name]; continue
        if name == "h264_v4l2m2m" and not codec_nodes: usable[name] = False; continue
        try:
            result = run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=size=64x64:rate=1", "-frames:v", "1", "-c:v", name, "-f", "null", "-"], text=True, capture_output=True, timeout=12)
            usable[name] = result.returncode == 0
        except (OSError, subprocess.SubprocessError): usable[name] = False
    return {"schema": 2, "timestamp": now(), "signature": capability_signature(run), "advertised_encoders": advertised, "encoders": usable, "codec_nodes": codec_nodes,
            "hwaccels": [x.strip() for x in hw.splitlines() if x.strip() and "acceleration" not in x.lower()],
            "gstreamer": {"installed": bool(gst), "v4l2h264enc": "v4l2h264enc" in gst}, "v4l2_devices": devices}

def capability_signature(run: Callable[..., subprocess.CompletedProcess] = subprocess.run) -> str:
    values = []
    for args in (["uname", "-r"], ["ffmpeg", "-version"], ["v4l2-ctl", "--list-devices"]):
        try: values.append(run(args, text=True, capture_output=True, timeout=8).stdout.splitlines()[0])
        except (OSError, subprocess.SubprocessError, IndexError): values.append("")
    return hashlib.sha256("|".join(values).encode()).hexdigest()

def cached_capabilities(path: Path, force: bool = False, run: Callable[..., subprocess.CompletedProcess] = subprocess.run) -> dict[str, Any]:
    cached = read_json(path, {})
    if not force and cached.get("schema") == 2 and cached.get("signature") == capability_signature(run): return cached
    result = probe_capabilities(run); atomic_json(path, result); return result

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

def allocate_ports(path: Path, configured: dict[str, int] | None = None, in_use: Callable[[int], Any] | None = None, validate_persisted: bool = False) -> dict[str, Any]:
    old = read_json(path, {"schema": 1, "ports": {}, "conflicts": []})
    # Once assigned, a bound socket is normally one of our own services. Preserve
    # the registry unless an administrator explicitly changes a requested port.
    desired = {**DEFAULT_PORTS, **(configured or {})}
    unchanged = old.get("ports") and (not configured or old.get("requested", DEFAULT_PORTS) == desired)
    if unchanged and not validate_persisted:
        return old
    preferred = old.get("ports", {}) if unchanged else desired
    in_use = in_use or port_owner; assigned, conflicts = {}, []
    reserved = set()
    for service, wanted in preferred.items():
        port = int(wanted); owner = in_use(port); conflict = owner not in (False, None, "x1301") or port in reserved
        if conflict:
            replacement = next(p for p in range(port + 1, port + 1000) if not in_use(p) and p not in reserved)
            conflicts.append({"service": service, "requested": port, "conflict": str(owner or "reserved"), "replacement": replacement}); port = replacement
        assigned[service] = port; reserved.add(port)
    result = {"schema": 1, "requested": desired, "ports": assigned, "conflicts": conflicts}; atomic_json(path, result); return result

def _port_in_use(port: int) -> bool:
    with socket.socket() as s:
        try: s.bind(("0.0.0.0", port)); return False
        except OSError as exc: return exc

def port_owner(port: int) -> str | bool:
    """Return false, x1301, or a description of the process owning a TCP port."""
    try:
        output = subprocess.run(["ss", "-H", "-ltnp", f"sport = :{port}"], text=True, capture_output=True, timeout=3).stdout.strip()
    except (OSError, subprocess.SubprocessError): return _port_in_use(port)
    if not output: return False
    return "x1301" if re.search(r"x1301|mediamtx", output, re.I) else output[:240]

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

def generate_mediamtx(path: Path, ports: dict[str, int]) -> bool:
    """Atomically update deterministic MediaMTX config only when it changes."""
    functional = f"rtspAddress: :{ports['rtsp']}\nhlsAddress: :{ports['hls_http']}\nwebrtcAddress: :{ports['webrtc_http']}\npaths:\n  x1301:\n    source: publisher\n"
    try:
        if "\n".join(path.read_text().splitlines()[2:]) + "\n" == functional: return False
    except OSError: pass
    content = f"# GENERATED by x1301; schema=2\n# generated_at={now()}\n{functional}"
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    with os.fdopen(fd, "w") as stream: stream.write(content); stream.flush(); os.fsync(stream.fileno())
    os.replace(tmp, path); return True

@dataclass
class Source:
    identity: dict[str, Any] = field(default_factory=dict); signal: dict[str, Any] = field(default_factory=dict)
    video: dict[str, Any] = field(default_factory=dict); audio: dict[str, Any] = field(default_factory=dict); profile: dict[str, Any] = field(default_factory=dict)
    def json(self) -> dict[str, Any]: return asdict(self)
