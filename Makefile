# Command-line build for KeyGrid. No Xcode required.
#   make           build the release binary
#   make test      run unit tests
#   make run       quit any running copy, assemble dist/KeyGrid.app, and open it
#   make install   copy the bundle to /Applications
#   SIGN_IDENTITY="My Cert" make install   sign with a stable identity
#                                           so Accessibility stays granted across rebuilds

APP           = KeyGrid
CONFIG       ?= release
BIN           = .build/$(CONFIG)/$(APP)
BUNDLE        = dist/$(APP).app
SIGN_IDENTITY ?= -

# Tests use Swift Testing. With Command Line Tools alone (no Xcode), SwiftPM
# does not find the Testing framework on its own, so point it there. When
# Xcode is selected these paths do not exist and the flags stay empty.
DEVDIR     := $(shell xcode-select -p)
TESTING_FW := $(DEVDIR)/Library/Developer/Frameworks
TESTING_LIB:= $(DEVDIR)/Library/Developer/usr/lib
ifneq ($(wildcard $(TESTING_FW)/Testing.framework),)
TEST_FLAGS  = --disable-xctest --enable-swift-testing \
              -Xswiftc -F -Xswiftc $(TESTING_FW) \
              -Xlinker -F -Xlinker $(TESTING_FW) \
              -Xlinker -rpath -Xlinker $(TESTING_FW) \
              -Xlinker -rpath -Xlinker $(TESTING_LIB)
endif

build:
	swift build -c $(CONFIG)

test:
	swift test $(TEST_FLAGS)

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp Resources/KeyGrid.icns Resources/MenuBarIcon*.png $(BUNDLE)/Contents/Resources/
	codesign --force --sign "$(SIGN_IDENTITY)" $(BUNDLE)

run: bundle
	# `open` only brings a running copy forward; quit it, and wait until it
	# has gone, so the new build runs.
	-pkill -x $(APP)
	while pgrep -x $(APP) >/dev/null; do sleep 0.1; done
	open $(BUNDLE)

install: bundle
	rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/

clean:
	rm -rf .build dist

.PHONY: build test bundle run install clean
