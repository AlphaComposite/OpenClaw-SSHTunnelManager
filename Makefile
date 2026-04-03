.PHONY: build install verify

build:
	xcodebuild -project SSHTunnelManager.xcodeproj -scheme SSHTunnelManager -configuration Release build CODE_SIGNING_ALLOWED=NO

install: build
	rm -rf /Applications/SSHTunnelManager.app
	cp -R "$$(xcodebuild -project SSHTunnelManager.xcodeproj -scheme SSHTunnelManager -configuration Release -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | sed 's/.*= *//')/SSHTunnelManager.app" /Applications/SSHTunnelManager.app

verify:
	./scripts/verify-ssh-regression.sh