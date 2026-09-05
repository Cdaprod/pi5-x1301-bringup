.PHONY: inventory overlay configure capture status edid-info load-edid watch test

inventory:
	./tools/x1301/inventory.sh
overlay:
	sudo ./tools/x1301/install-overlay.sh
configure:
	sudo ./tools/x1301/configure.sh
capture:
	sudo ./tools/x1301/capture-test.sh
status:
	./tools/x1301/hdmi-status.sh
edid-info:
	./tools/x1301/inspect-edid.sh
load-edid:
	sudo ./tools/x1301/load-edid.sh
watch:
	./tools/x1301/hdmi-watch.sh
test:
	./tests/x1301-shell-tests.sh
