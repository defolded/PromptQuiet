.PHONY: build test docker-test app run clean

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

build:
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift build

test:
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift test

docker-test:
	docker compose run --rm core-test

app:
	./scripts/bundle-app.sh

run: app
	open dist/PromptQuiet.app

clean:
	rm -rf .build dist
