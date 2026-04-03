.PHONY: build install verify

build:
	xcodebuild -project SSHTunnelManager.xcodeproj -scheme SSHTunnelManager -configuration Release build CODE_SIGNING_ALLOWED=NO

install: build
	rm -rf /Applications/SSHTunnelManager.app
	cp -R "$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -path '*SSHTunnelManager*/Build/Products/Release/SSHTunnelManager.app' -print | tail -n 1)" /Applications/SSHTunnelManager.app

verify:
	./scripts/verify-ssh-regression.sh
