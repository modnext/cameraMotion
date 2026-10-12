## Config
MOD_NAME = FS25_cameraMotion

## Package contents
FILES  = modDesc.xml icon_cameraMotion.dds
DIRS   = scripts l10n gui
PKG    = $(FILES) $(DIRS)

## Paths
SOURCE_DIR = $(CURDIR)
DEST_DIR   = $(patsubst %/,%,$(dir $(CURDIR)))
DIST_DIR   = $(SOURCE_DIR)/dist

## Artifacts
DEV_ZIP = $(MOD_NAME)_dev.zip
REL_ZIP = $(MOD_NAME).zip

## Tools
PS  = powershell -NoProfile -ExecutionPolicy Bypass -Command
ZIP = tar -a -c -f

.PHONY: all dev build clean

all: build

## Build dev zip and copy to game Mods folder
dev:
	cd "$(SOURCE_DIR)" && $(ZIP) "$(DEV_ZIP)" $(PKG)
	$(PS) "Move-Item -Path \"$(SOURCE_DIR)/$(DEV_ZIP)\" -Destination \"$(DEST_DIR)\" -Force"

## Build release zip and move to dist folder
build:
	$(PS) "New-Item -ItemType Directory -Path '$(DIST_DIR)' -Force | Out-Null"
	cd "$(SOURCE_DIR)" && $(ZIP) "$(DIST_DIR)/$(REL_ZIP)" $(PKG)

## Remove dev and release artifacts
clean:
	$(PS) 'if (Test-Path "$(DEST_DIR)/$(DEV_ZIP)") { Remove-Item -Path "$(DEST_DIR)/$(DEV_ZIP)" -Force }'
	$(PS) 'if (Test-Path "$(DIST_DIR)/$(REL_ZIP)") { Remove-Item -LiteralPath "$(DIST_DIR)/$(REL_ZIP)" -Force }'
