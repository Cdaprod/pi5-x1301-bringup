# Pi 5 X1301 Media Appliance

An offline, persistent Geekworm X1301 / TC358743 appliance for Raspberry Pi 5.
It retains the proven dynamic RP1-CFE bring-up sequence and adds remembered
sources, HDMI audio, one-producer browser/LAN streaming, a status API, and a CLI.

## Install or update

```bash
sudo apt install v4l-utils media-ctl ffmpeg edid-decode alsa-utils curl
sudo ./tools/x1301/install-mediamtx.sh       # pinned 1.21.0 arm64 binary
sudo ./tools/x1301/install-service.sh --enable --start
x1301ctl status
```

Installation is idempotent. It preserves `/etc/x1301/config.json`, generated
profiles, aliases, device history, and port assignments. Uninstall units and
application code with `sudo ./tools/x1301/install-service.sh --uninstall`;
persistent configuration/state is intentionally retained.

The default generated ports are control HTTP `8080`, HLS `8888`, WebRTC HTTP
`8889`, and RTSP `8554`. The registry checks first assignment for conflicts,
records replacements, and reuses the result on reboot. Run `x1301ctl url` for
the actual viewer URL; `/api/v1/status`, `/devices`, `/profiles`, `/ports`,
`/capabilities`, and `/stream` are read-only LAN APIs under `/api/v1/`.

## Services and storage

* `x1301-edid`: loads the installed safe EDID using bounded device polling.
* `x1301-hdmi-watch`: sole root-owned signal/graph authority and STREAMON test.
* `x1301-appliance`: source identity, profiles, ALSA/capability probes, ports,
  derived MediaMTX configuration, and atomic runtime state.
* `x1301-appliance-init`: validates persisted ports and materializes capabilities
  and generated configuration before dependent services start. It is the sole
  systemd `StateDirectory=x1301` lifecycle owner; the root HDMI watcher no
  longer races it by applying root ownership to the same persistent directory.
* `x1301-mediamtx`: WebRTC/HLS/RTSP fanout for the single encoded producer.
* `x1301-stream`: native FFmpeg capture/audio mux and one encoder process.
* `x1301-web`: persistent self-hosted viewer and read-only API; it starts even
  when HDMI is disconnected.

Administrator defaults and overrides live in `/etc/x1301/`; generated durable
state lives in `/var/lib/x1301/` (`devices.json`, `profiles.d`, `ports.json`,
`capabilities.json`, `last-runtime.json`); ephemeral state lives in
`/run/x1301/` (`state.env`, `stream.json`, `capture.json`, `runtime.json`,
`generated/mediamtx.yml`). JSON is
written by fsync and atomic rename. The schema-1 shell environment remains for
EVF compatibility; canonical JSON uses schema 2 and labels source, capture, and
stream FPS separately.

## Operation

```bash
x1301ctl status --json
x1301ctl devices; x1301ctl profiles; x1301ctl ports
x1301ctl capabilities; x1301ctl stream status
sudo x1301ctl capabilities --rescan  # explicitly repeat encoder init probes
x1301ctl audio status; x1301ctl audio test
x1301ctl diagnose
xdg-open "$(x1301ctl url)"                 # from the Pi desktop
```

`x1301ctl` always reads canonical `/run/x1301` and `/var/lib/x1301` paths; it
does not accept ambient `X1301_RUN` overrides. Tests and recovery tooling may
use explicit `--runtime-dir` and `--state-dir` options. Missing, unreadable, or
invalid runtime state is reported as an error with exit status 2 rather than an
empty status display.

## Storage permission verification

The installer creates administrator configuration as `root:root` and mutable
state/runtime directories as `x1301:x1301`, preserves existing JSON and
profiles, then performs a create → rename → delete test as the actual `x1301`
account. Installation stops before service startup if effective access fails.
This tests UID resolution, ACLs, mount/namespace policy, and mode bits rather
than trusting `stat` alone. Run the same diagnostic later with:

```bash
sudo x1301ctl permissions
stat -c '%a %U:%G %n' \
  /var/lib/x1301 \
  /var/lib/x1301/profiles.d \
  /var/lib/x1301/generated \
  /run/x1301

sudo -u x1301 sh -c '
  set -e
  p=/var/lib/x1301/profiles.d/.x1301-write-test-$$
  printf test > "$p"
  mv "$p" "$p.moved"
  rm "$p.moved"
'

systemctl cat x1301-appliance-init.service
systemctl cat x1301-appliance.service
x1301ctl status --json
x1301ctl url
```

Use the displayed URL from a phone/computer on the same trusted LAN. The API
has no authentication or mutation endpoints and should not be exposed directly
to the Internet. OBS can open the generated RTSP URL shown by `x1301ctl status`.
Profiles may retain additional enabled RTSP/UDP destinations in `stream.outputs`;
no destination address is invented by the appliance.

On unplug, the producer exits/retries while the web surface remains available.
The watcher records `DISCONNECTED` or `PRESENT_NO_SIGNAL`. A timing lock or mode
change increments generation, safely rebuilds the graph, validates a real RGB
frame, and lets the single producer reconnect under the same remembered source.

Adapter and HDMI-source identities are separate. An explicitly discovered or
administrator-supplied `source_fingerprint` selects a source-specific profile;
when the receiver exposes no source metadata, a persistent fallback source slot
is used for that adapter. ALSA availability and card numbers never affect either
identity. Encoder wrappers are selected only after a real one-frame FFmpeg
initialization succeeds, and the result is cached until kernel/FFmpeg/topology
changes or an explicit rescan. FFmpeg progress is published independently and
merged by the sole canonical runtime-state writer.

## Overlay (independent, one-time stage)

Run `sudo make overlay`, then reboot only when requested. The supported CAM/DISP0 configuration is:

```ini
dtoverlay=tc358743,cam0
dtoverlay=tc358743-audio
```

The installer removes incompatible TC358743 CAM1/`4lane=1` lines. No other Make target invokes `overlay` transitively.

## Detection and operation stages

Each stage is separate: `make inventory` enumerates kernel devices; `make status` discovers the RP1 CFE graph, resolves the TC358743 node from its owning media entity, reads HDMI power, and checks timing lock; `make edid-info` decodes the bundled EDID without touching hardware; `sudo make load-edid` explicitly programs it; and `sudo make configure` applies the **already active** timing to the CFE route. Normal configuration never rewrites EDID.

The file `tools/x1301/edid/x1301-compatible.txt` is one EDID that advertises multiple source modes (including 1080p and lower modes); its name does not imply one fixed timing. The old `tools/x1301/1080P60EDID.txt` path remains as a compatibility symlink.

```bash
make inventory
make status
make edid-info
sudo make load-edid       # only when EDID programming is intended
sudo make configure       # or: configure.sh --load-edid
sudo make capture
make watch                # transitions only
sudo ./tools/x1301/hdmi-watch.sh --configure
make test
```

`power_present=1` establishes cable/source presence, not timing lock. Status reports `PRESENT_NO_SIGNAL` until valid DV timings exist. Configuration writes `logs/last-mode.env` and `logs/last-video-node.txt`; capture consumes the node and active dimensions from the environment file.

`make status` reports `SIGNAL=PRESENT_NO_SIGNAL` and `DV_TIMINGS=NO_LINK` when power is present but the live timing ioctl fails; it never treats the driver's remembered `dv.current` mode as a lock. The `VIDEO` field is resolved from the `rp1-cfe-csi2_ch0` entity in the same media graph.

## Signal state model and exit codes

Only a successful `--query-dv-timings` establishes `LOCKED`; remembered `dv.current` never does. Power 0 is `DISCONNECTED`; power 1 plus a failed query is `PRESENT_NO_SIGNAL`; a changed locked resolution emits `MODE_CHANGE`; discovery failures are `ERROR`. Configure exits 2 for discovery, 3 for disconnected, 4 for present/no-signal, and 5 for graph configuration failure. HDMI audio remains optional.

`hdmi-status.sh` exits successfully for all three observable states (`DISCONNECTED`, `PRESENT_NO_SIGNAL`, and `LOCKED`). Its nonzero exits are reserved for dependency, discovery, or malformed driver-output errors. `capture-preflight.sh` remains a readiness gate and returns nonzero with `CAPTURE_READY=0` when capture cannot proceed.

## Known-good hardware observation

The current confirmed example is Debian GNU/Linux 12 (bookworm), kernel `6.12.96+rpt-rpi-2712`, with `dtoverlay=tc358743,cam0` and `dtoverlay=tc358743-audio`. The latest inventory observed RP1 CFE `/dev/media3`, TC358743 `/dev/v4l-subdev2`, and primary capture `/dev/video0`; these are examples, never hardcoded assumptions. It observed `power_present=1`, `dv.query=no-link`, and remembered `dv.current=640x480p59`: the source was electrically present without a valid live timing lock.

## Production hot-plug service

Install and activate the ordered EDID/watcher lifecycle with:

```bash
sudo tools/x1301/install-service.sh --enable --start
```

At boot, `x1301-edid.service` validates and loads the canonical EDID once after bounded device discovery. The watcher starts afterward and does not rewrite EDID. It handles disconnected boot, late connection, source replacement, full timing changes (including frame rate/pixel clock), node renumbering, and configuration retry without operator commands. Both services run normally with no source connected. Installed live and cached status APIs are `/usr/local/lib/x1301/hdmi-status.sh` and `/usr/local/lib/x1301/runtime-status.sh`.

The atomic `/run/x1301/state.env` contract exposes power, timing lock, audio, full mode identity/generation, discovered graph nodes/driver, configuration readiness, and errors. No undocumented onboard LED GPIO is driven; onboard HDMI/video LEDs may be hardware-controlled.

See [media appliance architecture](docs/MEDIA_PIPELINE.md), [service lifecycle](docs/SERVICE.md), [pipeline architecture](docs/PIPELINE.md), [troubleshooting](docs/TROUBLESHOOTING.md), [EVF integration](docs/EVF_INTEGRATION.md), and [EDID notes](tools/x1301/edid/README.md).
