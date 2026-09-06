.PHONY: help inventory status status-json runtime-status runtime-status-json edid-info edid-validate load-edid configure preflight frame capture watch test clean-logs overlay service-install service-enable service-start service-stop service-status service-logs service-uninstall

help:
	@printf '%s\n' 'READ-ONLY: inventory status status-json edid-info edid-validate preflight' \
	  'MODIFIES HARDWARE STATE: load-edid configure frame capture' \
	  'WATCH: make watch is read-only; run hdmi-watch.sh --configure explicitly to modify state' \
	  'ADMINISTRATIVE: overlay, service-install/enable/start/stop/status/logs/uninstall'
inventory:
	./tools/x1301/inventory.sh
status:
	./tools/x1301/hdmi-status.sh
status-json:
	./tools/x1301/hdmi-status.sh --json
runtime-status:
	./tools/x1301/runtime-status.sh
runtime-status-json:
	./tools/x1301/runtime-status.sh --json
edid-info:
	./tools/x1301/inspect-edid.sh
edid-validate:
	./tools/x1301/validate-edid.sh
load-edid:
	sudo ./tools/x1301/load-edid.sh
configure:
	sudo ./tools/x1301/configure.sh
preflight:
	./tools/x1301/capture-preflight.sh
frame:
	sudo ./tools/x1301/capture-frame.sh
capture:
	sudo ./tools/x1301/capture-test.sh
watch:
	./tools/x1301/hdmi-watch.sh
test:
	./tests/test-common.sh
	./tests/test-status-parser.sh
	./tests/test-watcher-service.sh
	./tests/x1301-shell-tests.sh
clean-logs:
	./tools/x1301/cleanup-logs.sh
overlay:
	sudo ./tools/x1301/install-overlay.sh
service-install:
	sudo ./tools/x1301/install-service.sh
service-enable:
	sudo ./tools/x1301/install-service.sh --enable
service-start:
	sudo systemctl start x1301-hdmi-watch.service
service-stop:
	sudo systemctl stop x1301-hdmi-watch.service
service-status:
	systemctl status x1301-hdmi-watch.service
service-logs:
	journalctl -u x1301-hdmi-watch.service -f
service-uninstall:
	sudo ./tools/x1301/install-service.sh --uninstall
