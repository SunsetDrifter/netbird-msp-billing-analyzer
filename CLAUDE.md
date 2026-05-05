# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A two-script Bash project — there is no build system, package manager, or test framework. All logic lives in two files:

- `analyzer.sh` — the analyzer that calls the NetBird MSP/billing API and writes reports.
- `install.sh` — the user-facing installer that downloads a tagged release of the analyzer from GitHub and places it on `PATH` as `netbird-msp-analyzer`.

The repo is published at `SunsetDrifter/netbird-msp-billing-analyzer`. Releases are git tags (e.g. `v0.9.2`); `install.sh` pulls the script from `raw.githubusercontent.com/.../<tag>/analyzer.sh`. **Bumping behavior that depends on a release requires a new tag** — editing `main` alone does not change what `curl | bash` users get. Tags before the rename (`v0.9.0`–`v0.9.2`) reference the old filename `netbird-msp-comprehensive.sh` and continue to work because that path exists at those frozen revisions.

**Versioning convention**: tags and the `VERSION` constant in `analyzer.sh` use the `vX.Y.Z` format. When cutting a new tag, bump `VERSION` in `analyzer.sh` to match (e.g. `v0.10.1`). GitHub release titles should be the tag string only — no extra title text. `./analyzer.sh --version` prints just the version string (no script-name prefix).

## Running and testing locally

```bash
# Syntax-check (the installer also does this on the downloaded copy)
bash -n analyzer.sh
bash -n install.sh

# Run the analyzer directly (loads ./.env automatically if present)
NETBIRD_API_TOKEN=... ./analyzer.sh

# Useful flags
./analyzer.sh --help                       # full usage
./analyzer.sh --output-dir /tmp/reports    # write reports elsewhere
./analyzer.sh --tenant <id>                # single-tenant debug run
./analyzer.sh --json-only                  # skip .txt
./analyzer.sh --csv                        # also write a CSV summary
./analyzer.sh --quiet                      # suppress progress messages

# Install from local checkout (pulls the latest release from GitHub, not the local copy)
./install.sh --user           # installs latest tagged release to ~/.local/bin
./install.sh --version v0.9.2 # pin a specific tag
./install.sh --uninstall      # remove from /usr/local/bin and ~/.local/bin
```

There are no automated tests. Verification is manual: run the analyzer against a real MSP token and check that `netbird_comprehensive_<timestamp>.txt` and `.json` are produced and that `executive_summary` totals match the per-tenant numbers.

## Architecture

### Analyzer flow (`analyzer.sh`)

1. `parse_args` runs first; flags are documented in `--help`. Conflicting `--json-only` + `--text-only` errors out.
2. Loads `.env` if present, then requires `NETBIRD_API_TOKEN`.
3. `make_api_call` is the single HTTP wrapper — every request goes through it. It captures HTTP status, returns the body on 200, prints a diagnostic to stderr otherwise. Add new endpoints by calling this function, not by hand-rolling `curl`.
4. Fetches `integrations/msp/tenants`, optionally filters to a single ID with `--tenant`, then for each tenant calls:
   - `integrations/billing/subscription?account=<id>` → plan tier (via `detect_billing_plan`)
   - `users?service_user=false&account=<id>` → registered users (filtered to `status=="active" && is_blocked==false`)
   - `integrations/billing/usage?account=<id>` → billable user/peer counts
5. The `output` helper writes to console and (unless `--json-only`) appends to the text report. `log_progress` prints status lines that respect `--quiet`. Per-tenant JSON is built with `jq -n --arg`/`--argjson` and accumulated in the `all_tenant_details` array; the final report is assembled with `jq -s` + `jq -n`. The final JSON is `jq empty`-validated; failure logs a warning but does not fail the run.

### Installer flow (`install.sh`)

`set -euo pipefail` is on, so unset variables and pipe failures abort. Key decisions:

- Install dir: `/usr/local/bin` if writable or running as root, otherwise `~/.local/bin` (also forced by `--user`). When falling back to user dir, the installer appends `export PATH="$HOME/.local/bin:$PATH"` to the shell rc file (`.zshrc`, `.bashrc`/`.bash_profile`, or fish config).
- Dependencies: auto-installs `curl` and `jq` via Homebrew (macOS) or apt/yum/dnf/zypper (Linux). On unknown package managers it errors out rather than continuing.
- Version resolution: `--version <tag>` pins; otherwise queries `api.github.com/repos/.../releases/latest` and uses `.tag_name`.
- The downloaded script is `bash -n`-validated before being copied into place.

## Conventions specific to this repo

- The analyzer is self-contained — do not split it into sourced helper files. The installer downloads exactly one script (`SCRIPT_NAME` constant in `install.sh`), and adding `source ./lib/foo.sh` will break installed copies.
- Source filename is `analyzer.sh`; the installed binary is named `netbird-msp-analyzer`. Don't conflate the two when editing `install.sh`.
- Output files use the pattern `netbird_comprehensive_*` and are gitignored; do not rename without updating `.gitignore`.
- All shell-to-JSON construction must go through `jq -n --arg`/`--argjson`. Don't reintroduce heredoc string interpolation — it silently corrupts output when tenant fields contain quotes or backslashes.
- **NetBird's `/users` and `/peers` endpoints don't paginate** — they ignore `limit`, `page`, `page_size`, and `offset` and always return the full array, with no `Link` header. Verified against the live API on 2026-05-05. If that ever changes, the script will silently undercount; revisit if NetBird publishes a paginated response shape.
- Tenants in the report are sorted by name (case-insensitive). Don't reorder mid-pipeline — downstream consumers (CSV, JSON `tenant_details`) inherit this order.
- The first API call (`integrations/msp/tenants`) doubles as the auth check and runs *before* the report banner is printed, so a bad token doesn't leave a half-rendered header.
- `set -uo pipefail` is on but `-e` is intentionally off: per-tenant failures fall through with sentinel values (`"Unknown"`, `0`, defaulted billing usage) so one bad tenant doesn't abort the whole run. Keep using explicit `if [ $? -ne 0 ]` checks rather than relying on `-e`.
- Errors that should halt the run go to stderr and `exit 1` (or `exit 2` for usage errors). Errors that should be reported but allow the run to continue print to the report via `output`.
