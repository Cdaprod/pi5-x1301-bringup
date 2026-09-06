# HDMI watcher service

The watcher continuously rediscovers the RP1 CFE/TC358743 graph, uses live DV timing queries for lock, configures once on lock or mode change, and atomically publishes `/run/x1301/state.env`. It never loads EDID.

Validate foreground behavior before enabling boot startup:

```bash
./tools/x1301/hdmi-watch.sh
sudo ./tools/x1301/hdmi-watch.sh --configure
```

Install without enabling or starting:

```bash
sudo ./tools/x1301/install-service.sh
```

After hardware validation, enable and start explicitly:

```bash
sudo ./tools/x1301/install-service.sh --enable --start
systemctl status x1301-hdmi-watch
journalctl -u x1301-hdmi-watch -f
./tools/x1301/runtime-status.sh --json
```

Use `--start` without `--enable` for the current boot. Uninstall only the installed unit and `/usr/local/lib/x1301` runtime copy with `sudo ./tools/x1301/install-service.sh --uninstall`; repository EDID sources and logs remain untouched.
