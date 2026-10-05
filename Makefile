APP := $(CURDIR)/wattever.app

.PHONY: test build run once

test:
	swift test

build: test
	swift build -c release --product wattever
	if [ -d "$(APP)" ]; then trash "$(APP)"; fi
	mkdir -p "$(APP)/Contents/MacOS"
	cp .build/release/wattever "$(APP)/Contents/MacOS/wattever"
	cp Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"

once: build
	"$(APP)/Contents/MacOS/wattever" --once

run: build
	-killall wattever
	while pgrep -x wattever >/dev/null; do sleep 0.1; done
	open "$(APP)"
