b := build_test_pidwatch
DL := .cache_test_pidwatch

include ../graft.mk

DIRS := $b $(DL)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

# Use sleep as a test service
SVC_CMD         := /bin/sleep 999
SVC_PIDFILE     := $b/svc.pid
SVC_TIMEOUT     := 10
SVC_READY_CMD   := sleep 0.2
SVC_READY_TRIES := 20
$(eval $(call GRAFT_DAEMON,SVC))

.PHONY: test
test: | $b
	@# ── Start service ──
	@$(MAKE) -f test_pidwatch.mk $(SVC_PIDFILE)
	@test -f $(SVC_PIDFILE) || (echo "ERROR: pidfile not created" && exit 1)
	@SVC_PID=$$(sed -n '3p' $(SVC_PIDFILE)); \
	kill -0 $$SVC_PID 2>/dev/null || (echo "ERROR: service not running" && exit 1)
	@echo "  start: OK"

	@# ── Pidfile has the 7-line extended format ──
	@#    (token, watchdog PID, service PID, cmd=, stdout=, stderr=, started=)
	@LINES=$$(wc -l < $(SVC_PIDFILE)); \
	test "$$LINES" -eq 7 || (echo "ERROR: pidfile should have 7 lines, has $$LINES" && exit 1)
	@grep -q '^cmd=' $(SVC_PIDFILE)     || (echo "ERROR: pidfile missing cmd= line"     && exit 1)
	@grep -q '^stdout=' $(SVC_PIDFILE)  || (echo "ERROR: pidfile missing stdout= line"  && exit 1)
	@grep -q '^stderr=' $(SVC_PIDFILE)  || (echo "ERROR: pidfile missing stderr= line"  && exit 1)
	@grep -q '^started=' $(SVC_PIDFILE) || (echo "ERROR: pidfile missing started= line" && exit 1)
	@echo "  pidfile format: OK"

	@# ── Stop service ──
	@$(MAKE) -f test_pidwatch.mk svc_stop
	@test ! -f $(SVC_PIDFILE) || (echo "ERROR: pidfile still exists after stop" && exit 1)
	@echo "  stop: OK"

	@# ── Start again, then kill process — watchdog should clean pidfile ──
	@$(MAKE) -f test_pidwatch.mk $(SVC_PIDFILE)
	@SVC_PID=$$(sed -n '3p' $(SVC_PIDFILE)); \
	kill $$SVC_PID; \
	sleep 2; \
	test ! -f $(SVC_PIDFILE) || (echo "ERROR: pidfile not cleaned after process death" && exit 1)
	@echo "  watchdog cleanup: OK"

	@# ── Start again, remove pidfile — watchdog should kill process ──
	@$(MAKE) -f test_pidwatch.mk $(SVC_PIDFILE)
	@SVC_PID=$$(sed -n '3p' $(SVC_PIDFILE)); \
	rm -f $(SVC_PIDFILE); \
	sleep 2; \
	! kill -0 $$SVC_PID 2>/dev/null || (echo "ERROR: process still alive after pidfile removal" && exit 1)
	@echo "  pidfile removal: OK"

	@echo "Service test: OK"
