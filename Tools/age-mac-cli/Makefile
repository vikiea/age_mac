PREFIX ?= $(HOME)/.local
BINARY := age-mac

.PHONY: build test fmt install-local

build:
	cargo build --release

test:
	cargo test

fmt:
	cargo fmt --check

install-local: build
	mkdir -p "$(PREFIX)/bin"
	cp "target/release/$(BINARY)" "$(PREFIX)/bin/$(BINARY)"
	chmod +x "$(PREFIX)/bin/$(BINARY)"
	@echo "Installed $(PREFIX)/bin/$(BINARY)"
