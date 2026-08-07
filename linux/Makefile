ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

BINARY_NAME       := affection_vpn
APPLICATION_ID    := dev.affection.affection_vpn
DESKTOP_FILE      := $(APPLICATION_ID).desktop
ICON_FILE         := affection-vpn.png

PREFIX            ?= /opt/affection-vpn
BINDIR            ?= /usr/bin
DESKTOP_DIR       ?= /usr/share/applications
ICON_DIR          ?= /usr/share/icons/hicolor/192x192/apps

BUILD_BUNDLE      := $(ROOT)/build/linux/x64/release/bundle
DEB_BUILD_DIR     := $(ROOT)/build/linux/x64/release/deb-pkg

VERSION := $(shell grep '^version:' $(ROOT)/pubspec.yaml | sed 's/version: *//; s/+.*//' 2>/dev/null || echo "0.0.0")
ARCH    := amd64

.PHONY: all build install uninstall deb clean

all: build

build:
	cd "$(ROOT)" && flutter build linux --release --build-name="$(VERSION)"
	# Stage the pinned xray core + geo databases into the bundle so every
	# artifact (deb / tar.gz / install) is self-contained. Non-fatal so local
	# offline builds still work — the app falls back to a system xray.
	"$(ROOT)/scripts/fetch_xray_linux.sh" || echo "warning: could not stage xray core (offline build?)"

install: build
	install -d "$(DESTDIR)$(PREFIX)"
	cp -r "$(BUILD_BUNDLE)"/data "$(BUILD_BUNDLE)"/lib "$(DESTDIR)$(PREFIX)/"
	install -Dm755 "$(BUILD_BUNDLE)/$(BINARY_NAME)" "$(DESTDIR)$(PREFIX)/$(BINARY_NAME)"
	@if [ -f "$(BUILD_BUNDLE)/xray" ]; then \
		echo "installing bundled xray core + geo databases"; \
		install -Dm755 "$(BUILD_BUNDLE)/xray" "$(DESTDIR)$(PREFIX)/xray"; \
		install -Dm644 "$(BUILD_BUNDLE)/geoip.dat" "$(BUILD_BUNDLE)/geosite.dat" "$(BUILD_BUNDLE)/LICENSE" "$(DESTDIR)$(PREFIX)/"; \
	fi
	install -d "$(DESTDIR)$(BINDIR)"
	ln -sf "$(PREFIX)/$(BINARY_NAME)" "$(DESTDIR)$(BINDIR)/affection-vpn"
	ln -sf "$(PREFIX)/$(BINARY_NAME)" "$(DESTDIR)$(BINDIR)/$(BINARY_NAME)"
	install -Dm644 "$(ROOT)/linux/$(DESKTOP_FILE)" "$(DESTDIR)$(DESKTOP_DIR)/$(DESKTOP_FILE)"
	install -Dm644 "$(ROOT)/linux/$(ICON_FILE)" "$(DESTDIR)$(ICON_DIR)/$(ICON_FILE)"
	@echo ""
	@echo "Installed to $(PREFIX). You can launch the app from your application menu"
	@echo "or run '$(BINARY_NAME)' from the terminal."

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/affection-vpn"
	rm -f "$(DESTDIR)$(BINDIR)/$(BINARY_NAME)"
	rm -rf "$(DESTDIR)$(PREFIX)"
	rm -f "$(DESTDIR)$(DESKTOP_DIR)/$(DESKTOP_FILE)"
	rm -f "$(DESTDIR)$(ICON_DIR)/$(ICON_FILE)"
	@echo "uninstalled."

deb: build
	rm -rf "$(DEB_BUILD_DIR)"
	mkdir -p "$(DEB_BUILD_DIR)/DEBIAN"
	mkdir -p "$(DEB_BUILD_DIR)/$(PREFIX)"
	mkdir -p "$(DEB_BUILD_DIR)$(BINDIR)"
	mkdir -p "$(DEB_BUILD_DIR)$(DESKTOP_DIR)"
	mkdir -p "$(DEB_BUILD_DIR)$(ICON_DIR)"
	cp -r "$(BUILD_BUNDLE)"/data "$(BUILD_BUNDLE)"/lib "$(DEB_BUILD_DIR)$(PREFIX)/"
	install -Dm755 "$(BUILD_BUNDLE)/$(BINARY_NAME)" "$(DEB_BUILD_DIR)$(PREFIX)/$(BINARY_NAME)"
	@if [ -f "$(BUILD_BUNDLE)/xray" ]; then \
		echo "packaging bundled xray core + geo databases"; \
		install -Dm755 "$(BUILD_BUNDLE)/xray" "$(DEB_BUILD_DIR)$(PREFIX)/xray"; \
		install -Dm644 "$(BUILD_BUNDLE)/geoip.dat" "$(BUILD_BUNDLE)/geosite.dat" "$(BUILD_BUNDLE)/LICENSE" "$(DEB_BUILD_DIR)$(PREFIX)/"; \
	fi
	ln -sf "$(PREFIX)/$(BINARY_NAME)" "$(DEB_BUILD_DIR)$(BINDIR)/affection-vpn"
	ln -sf "$(PREFIX)/$(BINARY_NAME)" "$(DEB_BUILD_DIR)$(BINDIR)/$(BINARY_NAME)"
	install -Dm644 "$(ROOT)/linux/$(DESKTOP_FILE)" "$(DEB_BUILD_DIR)$(DESKTOP_DIR)/$(DESKTOP_FILE)"
	install -Dm644 "$(ROOT)/linux/$(ICON_FILE)" "$(DEB_BUILD_DIR)$(ICON_DIR)/$(ICON_FILE)"
	INSTALLED_SIZE=$$(du -sk "$(DEB_BUILD_DIR)" | cut -f1); \
	sed "s/@VERSION@/$(VERSION)/; s/@ARCH@/$(ARCH)/; s/@SIZE@/$$INSTALLED_SIZE/" \
		"$(ROOT)/linux/control.tmpl" > "$(DEB_BUILD_DIR)/DEBIAN/control"
	dpkg-deb --build -Zxz "$(DEB_BUILD_DIR)" "$(ROOT)/build/linux/x64/release/affection-vpn_$(VERSION)_$(ARCH).deb"
	@echo ""
	@echo "deb package: build/linux/x64/release/affection-vpn_$(VERSION)_$(ARCH).deb"
	@echo "install with: sudo dpkg -i build/linux/x64/release/affection-vpn_$(VERSION)_$(ARCH).deb"

clean:
	cd "$(ROOT)" && rm -rf build/linux/
