# TODO — production-readiness

Tracking the gaps between "works for internal build glue" and "trustworthy for
wide/production use".

## Done

- [x] **CI.** `.github/workflows/test.yml` runs `make -C tests` on push/PR
  (installs make/curl/git/tar/unzip/patch/coreutils/gcc on ubuntu-latest).
- [x] **`curl -fL`.** All three download recipes use `curl -fL --retry 3`, so an
  HTTP error fails the build instead of caching the error page.
- [x] **Atomic cache writes.** Downloads and the git tarball are written to
  `<final>.part.$(GRAFT_RUNID)` and renamed into place, so a crashed or concurrent
  build never leaves a half-written file that looks like a valid cache entry. This
  is the safe-shared-cache fix (corruption is prevented; concurrent jobs may still
  both download, which is wasteful but correct — no lock needed).
- [x] **Namespaced scratch dir.** `NAME_TMP` now defaults to `$b/graft-tmp/<name>`
  instead of a fixed `/tmp/graft_<name>`: per-project, no cross-user/concurrent
  collisions, no predictable-`/tmp` symlink surface, and removed by `make clean`
  (also fixes the leftover-`/tmp` hygiene item).
- [x] **Download integrity check.** Optional `NAME_SHA256` (tar/zip sources and
  `GRAFT_FETCH_FILE`) verifies the download and fails on mismatch. Covered by
  `test_sha256` (correct hash accepted, wrong hash rejected).
- [x] **macOS claim corrected.** README now states graft targets Linux + GNU
  coreutils/findutils and that the overlay feature needs GNU `find`/`ln` (macOS:
  `brew install coreutils findutils`). No longer implies plain-BSD support.
- [x] **`pidwatch.c` audit + hardening.** Reviewed: token-based pidfile ownership,
  session-wide kills, and self-healing on concurrent starts look sound. Fixed one
  real gap — the watchdog now redirects its own std fds to `/dev/null`, so it no
  longer holds the caller's stdout/stderr open (which can hang a pipe or CI step
  waiting for EOF).

## Remaining / deferred

- [ ] **Full BSD/macOS portability of overlays.** `GRAFT_OVERLAY` still uses GNU
  `find -printf` and `ln -r`. Documented as a GNU requirement rather than rewritten,
  to avoid destabilizing a working feature. Revisit if real macOS-native support is
  wanted (compute relative symlinks portably; replace `-printf`).

- [ ] **Hermetic tests.** The suite still depends on live upstreams (github.com,
  raw.githubusercontent, jq releases), so it can break on an outage or an upstream
  change. Consider a local fixture server or vendored fixtures for offline/stable CI.
  (The relocation test is already partly offline.)

- [ ] **`pidwatch.c` residual caveats (inherent).** `stop`/`status` identify the
  process by PID, so a stale pidfile whose PID was reused could mis-target
  `kill(-pid)`. The watchdog self-verifies via its token, but `stop` does not. This
  is the classic pidfile/PID-reuse limitation; fully solving it needs more than a
  pidfile. Documented here rather than fixed.

- [ ] **PID-reuse note for `stop`.** As above — if hardening is wanted, have `do_stop`
  confirm the target really is a pidwatch instance (e.g. re-read and match the token,
  or check the process before signalling the session).

- [ ] **Release/semver discipline.** v1.6.0 shipped a `BREAKING CHANGE` (removed the
  `DL` alias) under a minor bump; per semver that warranted a major. Process item,
  not code — note for future releases if external users are expected.
