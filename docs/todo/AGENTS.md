# X1301 task ledger

- [x] Distinguish live `--query-dv-timings` lock from remembered `dv.current` timings and report the graph-owned capture node.
- [x] Prefer `rp1-cfe-csi2_ch0` for capture and use generic probing only when that entity has no device node.
- [x] Centralize media-entity discovery, HDMI controls, and DV timing parsing.
- [x] Separate explicit EDID loading, status inspection, transition watching, and active-mode configuration.
- [x] Preserve the legacy EDID path while naming the multi-mode compatible EDID clearly.
- [x] Add isolated shell coverage and document the CAM0 overlay and detection stages.
- [ ] Validate EDID loading, hot-plug states, advertised source modes, mode changes, and captures on Raspberry Pi 5/X1301 hardware.
- [ ] Confirm audio controls and capture after installing `tc358743-audio` on hardware.
