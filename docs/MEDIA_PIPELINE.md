# X1301 media pipeline

## Ownership and data flow

```text
HDMI -> TC358743 -> MIPI CSI-2 -> RP1-CFE -> discovered capture node
  -> one policy-selected FFmpeg encoder -> MediaMTX fanout
       |-> WebRTC browser viewer
       |-> HLS compatibility viewer
       `-> RTSP / optional profile LAN consumers

HDMI audio -> TC358743 audio -> semantically discovered ALSA PCM
  -> the same FFmpeg producer/mux -> MediaMTX fanout
```

`x1301-hdmi-watch` is the sole signal/capture graph authority. It discovers the
media device, TC358743 subdevice, and `rp1-cfe-csi2_ch0` node; queries and sets
live DV timings; resets and links `csi2:4 -> rp1-cfe-csi2_ch0:0`; sets pads 0/4
to `RGB888_1X24/<live size>`; sets the capture node to `RGB3`; and requires a
full frame from STREAMON. The other services only consume its state.

`x1301-appliance` owns identities, generated profiles, ports, capabilities, and
canonical JSON. `x1301-stream` owns exactly one native FFmpeg producer per
active profile. MediaMTX 1.21.0 is pinned and installed once, never at boot.
`x1301-web` owns only static UI and read-only APIs; its iframe persists through
signal and mode transitions.

## Performance policy

The selector prefers verified FFmpeg H.264 V4L2, VAAPI, or NVENC encoders, then
`libx264`, then `libopenh264`. Software mode caps presentation at 1280 pixels
wide and 30 fps without changing capture truth. Preview, balanced, and quality
profiles request progressively greater presentation quality. MediaMTX remuxes
one encoded producer to all clients, so client count does not multiply encoding.
