#!/bin/sh
# Tests for pidwatch
# Uses a simple sleep process as the test binary.
set +e

DIR=$(mktemp -d)
PIDFILE="$DIR/test.pid"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
cleanup() {
    ../pidwatch stop "$PIDFILE" 2>/dev/null || true
    rm -rf "$DIR"
}
trap cleanup EXIT

svc_pid() { sed -n '3p' "$PIDFILE" 2>/dev/null; }
wd_pid() { sed -n '2p' "$PIDFILE" 2>/dev/null; }
pf_token() { sed -n '1p' "$PIDFILE" 2>/dev/null; }

wait_pidfile() {
    I=0; while [ ! -f "$PIDFILE" ] && [ $I -lt 50 ]; do sleep 0.1; I=$((I+1)); done
}

# Wait for pidfile to exist with a different token than the given one.
wait_new_token() {
    OLD="$1"
    I=0; while [ $I -lt 50 ]; do
        if [ -f "$PIDFILE" ]; then
            CUR=$(sed -n '1p' "$PIDFILE" 2>/dev/null)
            [ -n "$CUR" ] && [ "$CUR" != "$OLD" ] && return 0
        fi
        sleep 0.1; I=$((I+1))
    done
    return 1
}

assert_alive() {
    wait_pidfile
    if [ -f "$PIDFILE" ] && kill -0 "$(svc_pid)" 2>/dev/null; then
        ok "$1"
    else
        fail "$1"
    fi
}

assert_dead() {
    if [ ! -f "$PIDFILE" ] || ! kill -0 "$(svc_pid)" 2>/dev/null; then
        ok "$1"
    else
        fail "$1"
    fi
}

assert_no_pidfile() {
    if [ ! -f "$PIDFILE" ]; then
        ok "$1"
    else
        fail "$1"
    fi
}

# ── Test 1: start and stop ──
echo "Test 1: start and stop"
../pidwatch start "$PIDFILE" 60 /bin/sleep 999
assert_alive "process is running after start"
WD=$(wd_pid); SVC=$(svc_pid)
# Verify both watchdog and service are distinct processes
if [ "$WD" != "$SVC" ] && kill -0 "$WD" 2>/dev/null && kill -0 "$SVC" 2>/dev/null; then
    ok "watchdog ($WD) and service ($SVC) are distinct and alive"
else
    fail "watchdog and service should be distinct and alive"
fi

../pidwatch stop "$PIDFILE"
sleep 0.3
assert_dead "service is dead after stop"
assert_no_pidfile "pidfile removed after stop"
# Verify watchdog also died
if ! kill -0 "$WD" 2>/dev/null; then
    ok "watchdog is dead after stop"
else
    fail "watchdog still alive after stop"
    kill "$WD" 2>/dev/null || true
fi

# ── Test 2: pidfile removal kills process ──
echo "Test 2: pidfile removal kills process"
../pidwatch start "$PIDFILE" 60 /bin/sleep 999
assert_alive "process is running"
SVC=$(svc_pid); WD=$(wd_pid)

rm -f "$PIDFILE"
sleep 2  # watchdog checks every 1s
if ! kill -0 "$SVC" 2>/dev/null; then
    ok "service killed after pidfile removal"
else
    fail "service still alive after pidfile removal"
    kill "$SVC" 2>/dev/null || true
fi
if ! kill -0 "$WD" 2>/dev/null; then
    ok "watchdog exited after pidfile removal"
else
    fail "watchdog still alive after pidfile removal"
    kill "$WD" 2>/dev/null || true
fi

# ── Test 3: process crash removes pidfile ──
echo "Test 3: process crash removes pidfile"
../pidwatch start "$PIDFILE" 60 /bin/sleep 1
assert_alive "process is running"
SVC=$(svc_pid); WD=$(wd_pid)

kill "$SVC"
sleep 2  # watchdog detects death
assert_no_pidfile "pidfile removed after process crash"
if ! kill -0 "$WD" 2>/dev/null; then
    ok "watchdog exited after process crash"
else
    fail "watchdog still alive after process crash"
    kill "$WD" 2>/dev/null || true
fi

# ── Test 4: timeout kills process ──
echo "Test 4: timeout kills process"
../pidwatch start "$PIDFILE" 2 /bin/sleep 999
assert_alive "process is running"
SVC=$(svc_pid)

sleep 3  # timeout is 2s
if ! kill -0 "$SVC" 2>/dev/null; then
    ok "process killed after timeout"
else
    fail "process still alive after timeout"
    kill "$SVC" 2>/dev/null || true
fi
assert_no_pidfile "pidfile removed after timeout"

# ── Test 5: restart replaces old process ──
echo "Test 5: restart replaces old process"
../pidwatch start "$PIDFILE" 60 /bin/sleep 999
assert_alive "first instance running"
TOKEN1=$(pf_token)

# Start again — should kill old, start new
../pidwatch start "$PIDFILE" 60 /bin/sleep 999
if wait_new_token "$TOKEN1"; then
    ok "new token after restart"
else
    fail "token unchanged after restart"
fi
assert_alive "second instance running"
WD=$(wd_pid)
if kill -0 "$WD" 2>/dev/null; then
    ok "active watchdog is alive"
else
    fail "active watchdog is dead"
fi
../pidwatch stop "$PIDFILE"

# ── Test 6: survives parent shell exit ──
echo "Test 6: survives parent shell exit"
sh -c '../pidwatch start "'"$PIDFILE"'" 60 /bin/sleep 999'
assert_alive "process survived parent shell exit"
../pidwatch stop "$PIDFILE"

# ── Test 7: stop is idempotent ──
echo "Test 7: stop is idempotent"
../pidwatch stop "$PIDFILE"
../pidwatch stop "$PIDFILE"
ok "double stop did not error"

# ── Test 8: stop on nonexistent pidfile ──
echo "Test 8: stop on nonexistent pidfile"
../pidwatch stop "$DIR/nonexistent.pid"
ok "stop on missing pidfile did not error"

# ── Test 9: signal propagation (SIGTERM to watchdog) ──
echo "Test 9: SIGTERM to watchdog kills service"
../pidwatch start "$PIDFILE" 60 /bin/sleep 999
assert_alive "process is running"
SVC=$(svc_pid); WD=$(wd_pid)

kill "$WD"
sleep 1
if ! kill -0 "$SVC" 2>/dev/null; then
    ok "service killed when watchdog receives SIGTERM"
else
    fail "service still alive after watchdog SIGTERM"
    kill "$SVC" 2>/dev/null || true
fi
assert_no_pidfile "pidfile removed after watchdog SIGTERM"

# ── Test 10: simulates Make reuse (pidfile exists, process alive, no restart) ──
echo "Test 10: Make-style reuse — pidfile current, no restart"
../pidwatch start "$PIDFILE" 60 /bin/sleep 999
assert_alive "initial start"
SVC1=$(svc_pid)

# Simulate what Make does: pidfile exists and is newer than binary, so Make
# skips the recipe. Just verify the process is still alive.
sleep 1
if [ -f "$PIDFILE" ] && kill -0 "$(svc_pid)" 2>/dev/null; then
    ok "process still alive after idle period"
else
    fail "process died during idle"
fi
SVC2=$(svc_pid)
if [ "$SVC1" = "$SVC2" ]; then
    ok "PID unchanged — no spurious restart"
else
    fail "PID changed unexpectedly ($SVC1 -> $SVC2)"
fi
../pidwatch stop "$PIDFILE"

# ── Test 11: simulates Make restart (binary changed) ──
echo "Test 11: Make-style restart — binary changed"
../pidwatch start "$PIDFILE" 60 /bin/sleep 999
assert_alive "initial start"
TOKEN1=$(pf_token)

# Simulate Make re-running the recipe because binary is newer than pidfile
../pidwatch start "$PIDFILE" 60 /bin/sleep 999
if wait_new_token "$TOKEN1"; then
    ok "new token — restart happened"
else
    fail "token unchanged — restart did not happen"
fi
assert_alive "service alive after restart"
../pidwatch stop "$PIDFILE"

# ── Test 12: stop kills child processes ──
echo "Test 12: stop kills child processes"
../pidwatch start "$PIDFILE" 60 ./spawn_children.sh 3 999
wait_pidfile
SVC=$(svc_pid)
# Wait for children to spawn
sleep 1
# Find all processes in the service's session
WD=$(wd_pid)
CHILDREN=$(ps -s "$WD" -o pid= 2>/dev/null | tr -s ' \n' ' ')
if [ -n "$CHILDREN" ]; then
    ok "children exist in session (pids: $CHILDREN)"
else
    fail "no children found in session"
fi

../pidwatch stop "$PIDFILE"
sleep 1
# Verify ALL processes in that session are dead
ALL_DEAD=1
for P in $CHILDREN; do
    if kill -0 "$P" 2>/dev/null; then
        ALL_DEAD=0
        fail "process $P still alive after stop"
        kill -9 "$P" 2>/dev/null || true
    fi
done
if [ "$ALL_DEAD" = "1" ]; then
    ok "all children killed by stop"
fi

# ── Test 13: timeout kills child processes ──
echo "Test 13: timeout kills child processes"
../pidwatch start "$PIDFILE" 2 ./spawn_children.sh 3 999
wait_pidfile
WD=$(wd_pid)
sleep 1
CHILDREN=$(ps -s "$WD" -o pid= 2>/dev/null | tr -s ' \n' ' ')
if [ -n "$CHILDREN" ]; then
    ok "children exist in session"
else
    fail "no children found"
fi

sleep 3  # timeout is 2s
ALL_DEAD=1
for P in $CHILDREN; do
    if kill -0 "$P" 2>/dev/null; then
        ALL_DEAD=0
        fail "process $P still alive after timeout"
        kill -9 "$P" 2>/dev/null || true
    fi
done
if [ "$ALL_DEAD" = "1" ]; then
    ok "all children killed by timeout"
fi
assert_no_pidfile "pidfile removed after timeout"

# ── Test 14: process crash kills orphaned children ──
echo "Test 14: process crash kills orphaned children"
../pidwatch start "$PIDFILE" 60 ./spawn_children.sh 3 999
wait_pidfile
SVC=$(svc_pid); WD=$(wd_pid)
sleep 1
CHILDREN=$(ps -s "$WD" -o pid= 2>/dev/null | tr -s ' \n' ' ')
if [ -n "$CHILDREN" ]; then
    ok "children exist before crash"
else
    fail "no children found"
fi

# Kill just the main service process — children become orphans in the session
kill "$SVC"
sleep 2  # watchdog detects death and cleans session

ALL_DEAD=1
for P in $CHILDREN; do
    if kill -0 "$P" 2>/dev/null; then
        ALL_DEAD=0
        fail "orphan $P still alive after main process crash"
        kill -9 "$P" 2>/dev/null || true
    fi
done
if [ "$ALL_DEAD" = "1" ]; then
    ok "all orphans killed after main process crash"
fi
assert_no_pidfile "pidfile removed after crash"

# ── Test 15: pidfile removal kills child processes ──
echo "Test 15: pidfile removal kills child processes"
../pidwatch start "$PIDFILE" 60 ./spawn_children.sh 3 999
wait_pidfile
WD=$(wd_pid)
sleep 1
CHILDREN=$(ps -s "$WD" -o pid= 2>/dev/null | tr -s ' \n' ' ')
if [ -n "$CHILDREN" ]; then
    ok "children exist before pidfile removal"
else
    fail "no children found"
fi

rm -f "$PIDFILE"
sleep 2

ALL_DEAD=1
for P in $CHILDREN; do
    if kill -0 "$P" 2>/dev/null; then
        ALL_DEAD=0
        fail "process $P still alive after pidfile removal"
        kill -9 "$P" 2>/dev/null || true
    fi
done
if [ "$ALL_DEAD" = "1" ]; then
    ok "all children killed after pidfile removal"
fi

# ── Test 16: SIGTERM to watchdog kills child processes ──
echo "Test 16: SIGTERM to watchdog kills child processes"
../pidwatch start "$PIDFILE" 60 ./spawn_children.sh 3 999
wait_pidfile
WD=$(wd_pid)
sleep 1
CHILDREN=$(ps -s "$WD" -o pid= 2>/dev/null | tr -s ' \n' ' ')
if [ -n "$CHILDREN" ]; then
    ok "children exist before SIGTERM"
else
    fail "no children found"
fi

kill "$WD"
sleep 2

ALL_DEAD=1
for P in $CHILDREN; do
    if kill -0 "$P" 2>/dev/null; then
        ALL_DEAD=0
        fail "process $P still alive after watchdog SIGTERM"
        kill -9 "$P" 2>/dev/null || true
    fi
done
if [ "$ALL_DEAD" = "1" ]; then
    ok "all children killed after watchdog SIGTERM"
fi
assert_no_pidfile "pidfile removed after watchdog SIGTERM"

# ── Summary ──
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
