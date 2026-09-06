# EVF integration contract

Consumers should read `/usr/local/lib/x1301/runtime-status.sh --json`; it cheaply reads the last atomic `/run/x1301/state.env`. `/usr/local/lib/x1301/hdmi-status.sh --json` performs a direct hardware query. Device nodes are current discoveries, not stable identifiers.

Schema 1 retains `X1301_STATUS_SCHEMA`, `X1301_SIGNAL_STATE`, `X1301_MEDIA`, `X1301_SUBDEV`, `X1301_VIDEO`, `X1301_WIDTH`, `X1301_HEIGHT`, `X1301_FPS`, `X1301_CONFIGURED`, and `X1301_LAST_CHANGE`. It also publishes `X1301_POWER_PRESENT`, `X1301_TIMINGS_LOCKED`, `X1301_AUDIO_PRESENT`, `X1301_AUDIO_SAMPLING_RATE`, `X1301_PIXELCLOCK_HZ`, `X1301_PIXELFORMAT`, `X1301_MODE_ID`, `X1301_MODE_GENERATION`, `X1301_DRIVER`, `X1301_RP1_CFE_DETECTED`, and `X1301_ERROR`. JSON uses the corresponding lower-case names, except the retained top-level `X1301_STATUS_SCHEMA`.

Signal states are `DISCONNECTED`, `PRESENT_NO_SIGNAL`, `MODE_CHANGE`, `LOCKED`, and `ERROR`. `MODE_CHANGE` means a locked timing or graph identity is awaiting configuration; only `LOCKED` plus `configured=true` is capture-ready. `mode_id` includes dimensions, frame rate, pixel clock, and pixel format. `mode_generation` increments for each locked mode/node transition. `last_change` marks an observed transition; `error` carries discovery, parsing, or configuration failure detail.

`power_present`, `timings_locked`, and `configured` can be correlated with board indicators. X1301 onboard HDMI/video LEDs may be hardware-controlled. No GPIO is assigned or driven. Application-semantic POWER/HDMI/ERROR/REC LEDs remain a separate future GPIO feature.

Physical input event names remain `BUTTON_F1`, `BUTTON_F2`, `BUTTON_F3`, `BUTTON_F4`, `BUTTON_MENU`, `ENCODER_LEFT`, `ENCODER_RIGHT`, `ENCODER_PRESS`, and `ENCODER_LONG_PRESS`. Display and input backends must remain capture-independent.
