# X1301 EDID profile

`x1301-compatible.txt` describes the video modes the HDMI sink accepts; one EDID can advertise multiple modes. EDID is not the live source mode: `--query-dv-timings` reports what the source is actually sending.

Programming EDID may trigger HDMI renegotiation. Load it explicitly with `load-edid.sh`; do not rewrite it continuously or from the watcher. Validate without hardware using `validate-edid.sh`.
