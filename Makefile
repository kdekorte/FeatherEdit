# FeatherEdit — build, run and package without leaving the terminal.
# (You can also open Package.swift in Xcode; everything works there too.)

CONFIG  := debug
APP_DIR := build/FeatherEdit.app

.PHONY: build release run app install clean xcode

build:
	@scripts/build.sh

release-build:
	@scripts/build.sh --release

release:
	@scripts/release.sh

run:
	@scripts/run.sh

app:
	@scripts/package.sh

install:
	@scripts/package.sh --install

clean:
	swift package clean
	rm -rf build
	@echo "Cleaned."

xcode:
	open Package.swift
