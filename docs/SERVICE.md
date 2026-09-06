# HDMI production services

The production lifecycle has two ordered units. `x1301-edid.service` validates the canonical bundled EDID and loads it once, retrying device discovery for at most 30 seconds by default. `x1301-hdmi-watch.service` starts afterward, continuously rediscovers the live RP1 CFE/TC358743 graph, and configures every newly locked timing. A disconnected boot is normal: EDID programming does not require an active HDMI source, and the watcher remains healthy while publishing `DISCONNECTED`.

```bash
sudo ./tools/x1301/install-service.sh --enable --start
systemctl status x1301-edid.service x1301-hdmi-watch.service
journalctl -u x1301-edid.service -u x1301-hdmi-watch.service -f
/usr/local/lib/x1301/hdmi-status.sh --json
/usr/local/lib/x1301/runtime-status.sh --json
```

The installer copies scripts and EDID under `/usr/local/lib/x1301`, installs both units, and preserves `1080P60EDID.txt` as a symlink to `edid/x1301-compatible.txt`. Repeating install, `--enable`, `--start`, or `--restart` is safe. `--uninstall` stops/disables both units and removes only installed runtime files; repeating it is also safe.

```bash
sudo ./tools/x1301/install-service.sh --restart
sudo ./tools/x1301/install-service.sh --uninstall
```

`X1301_EDID_RETRIES` and `X1301_EDID_RETRY_INTERVAL` tune bounded boot discovery. `X1301_CONFIGURE_BACKOFF` controls retries after graph configuration errors. The watcher never writes EDID.
