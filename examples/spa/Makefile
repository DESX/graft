b := build
DL := .cache
PORT := 8080

include ../../graft.mk

# ── Dependency: devd (live-reload static server) ──
DEVD_DIR     := $b/devd
DEVD_TGT     := $(DEVD_DIR)/devd
DEVD_TAR     := $(DL)/devd-0.9-linux64.tgz
DEVD_TAR_URL := https://github.com/cortesi/devd/releases/download/v0.9/devd-0.9-linux64.tgz
$(eval $(call FETCH,DEVD))

DIRS := $b $(DL) $(DEVD_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call MK_DIR,$V)))

# ── Server: devd watches build/site for changes and live-reloads the browser ──
SRV_CMD         := $(abspath $(DEVD_TGT)) -l -p $(PORT) $(abspath $b/site)
SRV_DEP         := $(DEVD_TGT)
SRV_PIDFILE     := $b/server.pid
SRV_TIMEOUT     := 86400
SRV_READY_CMD   := curl -sf http://localhost:$(PORT)/ > /dev/null
SRV_READY_TRIES := 20
$(eval $(call DAEMON,SRV))

# ── Browser: pidwatch on native Linux, launch-and-forget on WSL ──
WSL := $(shell test -f /proc/sys/fs/binfmt_misc/WSLInterop && echo 1)

ifdef WSL
OPEN := wslview
else
OPEN := xdg-open

BROWSER_CMD         := chromium --app=http://localhost:$(PORT)
BROWSER_PIDFILE     := $b/browser.pid
BROWSER_TIMEOUT     := 86400
BROWSER_READY_CMD   := sleep 0.5
BROWSER_READY_TRIES := 20
$(eval $(call DAEMON,BROWSER))
endif

# ── Source ──
SRC := $(wildcard src/*)

$b/site: | $b
	@mkdir -p $@

$b/site/.built: $(SRC) | $b/site
	@cp src/* $b/site/
	@touch $@

.PHONY: dev open stop clean

ifdef WSL
dev: $b/site/.built $(SRV_PIDFILE)
	@$(OPEN) http://localhost:$(PORT) 2>/dev/null || true

stop: srv_stop
else
dev: $b/site/.built $(SRV_PIDFILE) $(BROWSER_PIDFILE)

stop: srv_stop browser_stop
endif

open:
	@$(OPEN) http://localhost:$(PORT) 2>/dev/null || true

clean: stop
	rm -rf $b $(DL)
