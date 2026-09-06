# Pi 5 X1301 Bring-up

Device-discovering tools for the Geekworm X1301 / TC358743 on Raspberry Pi 5. Install dependencies with `sudo apt install v4l-utils media-ctl ffmpeg edid-decode`.

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

See [service lifecycle](docs/SERVICE.md), [pipeline architecture](docs/PIPELINE.md), [troubleshooting](docs/TROUBLESHOOTING.md), [EVF integration](docs/EVF_INTEGRATION.md), and [EDID notes](tools/x1301/edid/README.md).
