.PHONY: build test run clean verify

build:
	swift build

test:
	swift run MarkViewTestRunner

run: build
	swift run MarkView

clean:
	swift package clean

verify:
	bash verify.sh

verify-build:
	bash verify.sh 0

resolve:
	swift package resolve
