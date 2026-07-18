SLUG ?=

.PHONY: macos-app macos-app-build-only macos-dmg install-macos-app open-macos-app restart-macos-app new-history new-plan

macos-app:
	./scripts/build-macos-app.sh

macos-app-build-only:
	./scripts/build-macos-app.sh --build-only

macos-dmg:
	./scripts/build-macos-dmg.sh

install-macos-app:
	./scripts/build-macos-app.sh --install-user-app

open-macos-app:
	open ~/Applications/HeySnap.app

restart-macos-app:
	-pkill -x HeySnap
	open ~/Applications/HeySnap.app

new-history:
	@if [ -z "$(SLUG)" ]; then echo "用法: make new-history SLUG=变更名"; exit 1; fi
	./scripts/new-history.sh "$(SLUG)"

new-plan:
	@if [ -z "$(SLUG)" ]; then echo "用法: make new-plan SLUG=计划名"; exit 1; fi
	./scripts/new-exec-plan.sh "$(SLUG)"
