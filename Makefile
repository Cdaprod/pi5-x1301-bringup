.PHONY: inventory overlay configure capture

inventory:
	./tools/x1301/inventory.sh

overlay:
	sudo ./tools/x1301/install-overlay.sh

configure:
	sudo ./tools/x1301/configure.sh

capture:
	sudo ./tools/x1301/capture-test.sh
