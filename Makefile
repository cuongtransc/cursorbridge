APP := build/CursorBridge.app
INSTALL_DIR := $(HOME)/Applications

.PHONY: app test run install clean

app:
	scripts/build-app.sh

test:
	scripts/test.sh

run: app
	-pkill -x CursorBridge
	open $(APP)

install: app
	-pkill -x CursorBridge
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/CursorBridge.app
	cp -R $(APP) $(INSTALL_DIR)/
	open $(INSTALL_DIR)/CursorBridge.app

clean:
	rm -rf .build build
