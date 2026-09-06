# Troubleshooting decision tree

Always use discovered nodes. Never infer a live lock from `dv.current`.

| Case | Likely layer | Exact command | Good output | Do not assume |
|---|---|---|---|---|
| A. TC358743 absent | Overlay/I2C | `make inventory` | `X1301_FOUND=1` | `/dev/media0` is CFE |
| B. I2C `-121`/wrong CAM port | Wiring/overlay | `dmesg \| grep -iE 'tc358743\|-121'` | TC358743 probes without errors | CAM1/four lanes are compatible |
| C. `power_present=0` | Cable/source power | `make status` | `SIGNAL=LOCKED` after connection | Stored timings mean connected |
| D. Power 1, query fails | HDMI negotiation | `./tools/x1301/source-debug.sh` | Live timing query text | `dv.current` is live |
| E. Timings lock, graph fails | Media routing | `sudo ./tools/x1301/configure.sh --dry-run` | Intended commands and dimensions | EDID must be reloaded |
| F. Graph succeeds, stream fails | Capture node/format | `make preflight` | `CAPTURE_READY=1` | Any Video Capture node is correct |
| G. Wrong colors | Pixel order | `sudo ./tools/x1301/capture-test.sh --frames 1 --png /tmp/test.png` | Correct RGB image | RGB3 and BGR are interchangeable |
| H. Resolution changes | Source mode | `./tools/x1301/hdmi-watch.sh --once` | `LOCKED WIDTHxHEIGHT` | Previous configuration still matches |
| I. Unplug/replug | Hot-plug | `./tools/x1301/hdmi-watch.sh` | Disconnect then lock transitions | Reconfiguration repeats continuously |
| J. Nodes changed | Enumeration | `make status` | Current MEDIA/SUBDEV/VIDEO | Node numbers persist across reboot |


## Managed lifecycle checks

Use `systemctl status x1301-edid.service x1301-hdmi-watch.service` to verify one-time EDID initialization precedes the watcher. Use `/usr/local/lib/x1301/runtime-status.sh --json` to distinguish source power, timing lock, configuration progress, and the last error. `MODE_CHANGE` with `configured=false` is expected during setup or retry backoff; `LOCKED` with `configured=true` is ready. If discovery times out, inspect the overlay/I2C probe and restart both ordered stages with `sudo tools/x1301/install-service.sh --restart`. Mocked tests validate logic only and do not establish physical HDMI, audio, or capture operation.
