# Pi 5 X1301 Bring-up

Conservative, log-first bring-up tooling for a Raspberry Pi 5 with the Geekworm X1301 / TC358743 HDMI-to-CSI-2 stack.

This repo is designed for an already-developed Pi: it inventories existing V4L2/media devices before making assumptions about `/dev/videoN`, `/dev/mediaN`, or `/dev/v4l-subdevN`.

## Quick start

```bash
sudo apt update
sudo apt install -y v4l-utils media-ctl ffmpeg
git clone <your-repo-url>
cd pi5-x1301-bringup

# Phase 1: non-destructive inventory
./tools/x1301/inventory.sh

# Phase 2: install boot overlays if missing.
# Reboot only if the script says it changed config.txt.
sudo ./tools/x1301/install-overlay.sh

# After reboot, configure HDMI capture.
sudo ./tools/x1301/configure.sh

# Test a short raw capture.
sudo ./tools/x1301/capture-test.sh
```

All scripts tee their output into `logs/`.

## Important

The scripts intentionally discover device nodes rather than assuming Geekworm's example node numbers. Existing `/dev/video19` or other prior V4L2 devices are not modified merely because they exist.

`configure.sh` detects a TC358743 subdevice and its associated media graph, loads the supplied 1080p60 EDID, queries DV timings, configures the CSI2 link, and locates a likely capture node.

If automatic discovery is ambiguous, it stops and prints the candidates rather than guessing.

## EVF direction

Once `capture-test.sh` succeeds, use the detected capture node as the source for the [separate ST7735 EVF application](https://github.com/Cdaprod/pi5-st7735-evf.git).
