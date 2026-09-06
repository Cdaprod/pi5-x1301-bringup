# X1301 pipeline

```text
HDMI source -> X1301 HDMI RX -> TC358743 -> CSI-2 -> RP1 CFE -> /dev/video* -> future EVF app
```

Media entity discovery determines every device node; numbering may change after reboot. X1301 HDMI OUT is clean hardware pass-through. Pi-generated UI overlays are a separate software display path for a future ST7735, DSI, or Pi HDMI display. They are not inserted into X1301 HDMI OUT.
