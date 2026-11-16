APP := $(CURDIR)/wattever.app
LIBEXEC := /usr/local/libexec/wattever-powermetrics

.PHONY: test build run once shim enable

test:
	swift test

build: test
	swift build -c release --product wattever
	if [ -d "$(APP)" ]; then trash "$(APP)"; fi
	mkdir -p "$(APP)/Contents/MacOS"
	cp .build/release/wattever "$(APP)/Contents/MacOS/wattever"
	cp Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"

shim:
	mkdir -p .build
	clang -Wall -Wextra -O2 -o .build/wattever-powermetrics shim/wattever-powermetrics.c
	codesign --force --sign - .build/wattever-powermetrics

enable: shim
	sudo install -d -o root -g wheel -m 755 /usr/local/libexec
	sudo install -o root -g wheel -m 4755 .build/wattever-powermetrics "$(LIBEXEC)"
	sudo codesign --force --sign - "$(LIBEXEC)"
	sudo chmod 4755 "$(LIBEXEC)"

once: build
	"$(APP)/Contents/MacOS/wattever" --once

run: build
	@if [ ! -u "$(LIBEXEC)" ]; then echo "wattever: run 'make enable' once for the real chip counters"; fi
	-killall wattever
	while pgrep -x wattever >/dev/null; do sleep 0.1; done
	open "$(APP)"
