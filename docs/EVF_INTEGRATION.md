# EVF integration contract

Two schema-versioned APIs are available. `tools/x1301/hdmi-status.sh --json` performs a live direct hardware query. `tools/x1301/runtime-status.sh --json` cheaply reads the watcher's last atomic state and should normally be used when the service is active. `logs/last-mode.env` is only a configuration snapshot fallback. Fields include `signal_state`, `width`, `height`, `fps`, `video`, `media`, and `subdev`.

Events are `DISCONNECTED`, `PRESENT_NO_SIGNAL`, `LOCKED`, `MODE_CHANGE`, and `ERROR`. Only a successful live `--query-dv-timings` is locked. These events can drive the ST7735 UI, DSI UI, LEDs, buttons, encoder, service, or watchdog.

Semantic LEDs: POWER means service alive; HDMI is off for `DISCONNECTED`, blinking for `PRESENT_NO_SIGNAL`, and solid for `LOCKED`; ERROR means discovery/configuration failure; REC is reserved for recording. No GPIO numbers are assigned.

Physical input event names are `BUTTON_F1`, `BUTTON_F2`, `BUTTON_F3`, `BUTTON_F4`, `BUTTON_MENU`, `ENCODER_LEFT`, `ENCODER_RIGHT`, `ENCODER_PRESS`, and `ENCODER_LONG_PRESS`. GPIO assignment waits for HDMI-audio conflict validation.

Display backends may be an ST7735 SPI 128x128 prototype, ST7789 SPI, DSI panel, or Pi HDMI display. Capture and status must remain display-independent.
