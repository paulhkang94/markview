.PHONY: build test run clean verify playwright playwright-fixtures playwright-install playwright-headed install

build:
	swift build

# Build + install MarkView.app locally (auto-invoked by `make playwright` after tests pass)
install:
	bash scripts/bundle.sh --install

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

playwright-install:
	cd Tests/playwright && npm ci && npx playwright install chromium

playwright-fixtures:
	bash scripts/gen-playwright-fixtures.sh

playwright: playwright-fixtures
	cd Tests/playwright && npx playwright test && date +%s > ../../.last-render-verify-at && cd ../.. && bash scripts/bundle.sh --install

playwright-headed: playwright-fixtures
	cd Tests/playwright && npx playwright test --headed

playwright-update-snapshots: playwright-fixtures
	cd Tests/playwright && npx playwright test --update-snapshots
