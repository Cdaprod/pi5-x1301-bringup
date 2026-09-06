# EVF integration contract

Consumers should run `tools/x1301/hdmi-status.sh --json` (schema `X1301_STATUS_SCHEMA=1`) rather than parse logs. `logs/last-mode.env` is a configuration snapshot fallback. JSON fields include `signal_state`, `width`, `height`, `fps`, `video`, `media`, and `subdev` (the node equivalents of `video_node`, `media_node`, and `subdev_node`).

Events are `DISCONNECTED`, `PRESENT_NO_SIGNAL`, `LOCKED`, `MODE_CHANGE`, and `ERROR`. Only a successful live `--query-dv-timings` is locked. These events can drive the ST7735 UI, DSI UI, LEDs, buttons, encoder, service, or watchdog.

Semantic LEDs: POWER means service alive; HDMI is off for `DISCONNECTED`, blinking for `PRESENT_NO_SIGNAL`, and solid for `LOCKED`; ERROR means discovery/configuration failure; REC is reserved for recording. No GPIO numbers are assigned.

Physical input event names are `BUTTON_F1`, `BUTTON_F2`, `BUTTON_F3`, `BUTTON_F4`, `BUTTON_MENU`, `ENCODER_LEFT`, `ENCODER_RIGHT`, `ENCODER_PRESS`, and `ENCODER_LONG_PRESS`. GPIO assignment waits for HDMI-audio conflict validation.

Display backends may be an ST7735 SPI 128x128 prototype, ST7789 SPI, DSI panel, or Pi HDMI display. Capture and status must remain display-independent.
