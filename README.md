# verifying-production-readiness

English | [한국어](README.ko.md)

A Claude Code skill that turns a go/no-go release decision into an auditable record. Passing tests are not, on their own, a reason to ship. The skill makes you base a verdict on what you observed. A lint script then checks the defect ledger, so the verdict cannot claim more than the evidence shows.

- Version: **0.17.2** (2026-11-05)
- License: MIT · Author: Wook Jang

The full reference, including the change history, is in Korean in [README.ko.md](README.ko.md).

## What is inside

All paths below are inside `skills/verifying-production-readiness/`.

| File | Role |
|---|---|
| `SKILL.md` | Seven Iron Rules, three evidence grades, four verdict words, the workflow, and a light mode |
| `axes.md` | The eleven audit axes: what to check, how, the pass line, and common mistakes. Also maps each axis to delegate tools and a model tier |
| `report-template.md` | Report outline, ledger format, and how a later session picks up an earlier report |
| `measurement-hygiene.md` | Things that make a measurement invalid |
| `media-adapters.md` | How the axes apply to targets that are not web apps (native, CLI, library, pipeline, daemon) |
| `bin/vpr` | Single entry point: `new`, `lint`, `render`, `package`, `test`, `rules` |
| `bin/ledger-lint.sh` | Machine checks R1–R13 on the ledger |
| `bin/new-report.sh` | Creates a report skeleton. `--axes` picks the axes to audit |
| `bin/report-html.py` | Renders a report to one self-contained HTML file. It runs lint first |
| `bin/ensure-tools.sh` | Checks for delegate skills and CLIs, and installs them with `--install` |
| `test/run-tests.sh` | Regression tests for every rule, determinism, the scaffolder, packaging and the entry point (**202 passed**) |

CI (`.github/workflows/ci.yml` at the repository root) runs the tests and the packaging check on ubuntu and macOS for every push to `main` and every pull request.

## Install

As a plugin:

```bash
claude plugin marketplace add wook8170/verifying-production-readiness
claude plugin install verifying-production-readiness@verifying-production-readiness
```

The same plugin is also listed in the [wook8170-plugins](https://github.com/wook8170/claude-plugins) marketplace together with king-wjang-harness and wb.

As a plain skill: put `skills/verifying-production-readiness/` at `~/.claude/skills/verifying-production-readiness/`. Claude Code finds it on its own.

It needs `bash` and `python3` (standard library only). `git` is optional. When present, citations resolve from the repository root.

```bash
bin/vpr test        # install check: expect "202 passed, 0 failed"
```

## Five-minute start

```bash
bin/vpr new ~/myproject                # 1. create readiness.md and evidence/
bin/vpr new ~/myproject --axes 3,5,7   #    or pick the axes up front
```

The core axes ④ usability/E2E, ⑥ security, ⑧ logic and ⑨ determinism are always included. Axes you leave out are recorded as excluded.

2. Fill in the gate table with numeric targets before you measure. If you change a target after seeing the result, that is approval after the fact, not a verdict.
3. Audit. Keep command output in `evidence/`, and write each finding as one ledger row right away:

```markdown
| SUP-01 | BLOCKER | ⑦ | 3 high findings reach production | open | measured | `evidence/audit.log:3` | — |
```

```bash
bin/vpr lint ~/myproject     # 4. the verdict counts only if this passes
bin/vpr render ~/myproject   # 5. HTML for publishing
```

There are four verdicts: **ship**, **ship with conditions**, **do not ship**, and **cannot judge**. If nothing was measured, lint refuses "ship" (R8). In that case give a conditional verdict with its conditions written out, or "cannot judge".

## Rules in short

| Rule | Check |
|---|---|
| R1 | A `measured` row must cite a file that exists. A `file:line` cite must point inside the file |
| R2 | A `verified` row must cite the evidence that closed it |
| R3 | IDs are unique |
| R4 | Severity, status and evidence grade use fixed words |
| R5 | `rejected` and `deferred` rows need a reason |
| R6 | The open-BLOCKER count in the header matches the ledger, and "ship" with an open BLOCKER fails |
| R7 | Cited evidence must not be empty or point at a blank line |
| R8 | "Ship" needs at least one measured citation |
| R9 | Each measured cell in the gate table holds a number or a valid citation, or says it was not measured |
| R10 | A passing verdict needs a gate table |
| R11 | "Ship with conditions" must list its conditions |
| R12 | A verdict in a sibling report file must match the ledger |
| R13 | Core axes cannot be excluded, and an excluded axis needs a reason under a passing verdict |

Exit codes: `0` pass, `1` rule violation (do not publish), `2` lint could not run (also do not publish). Wrap publishing so that only exit `0` passes.

## What it runs, sends, and fetches

The plugin contains one skill and nothing else. It has no hooks, no MCP servers, no agents, and no commands, so nothing runs on its own when a session starts or a tool is used.

### What it runs

The scripts in `skills/verifying-production-readiness/bin/` run only when you run them, or when Claude runs them while following the skill. They need `bash` and `python3` (standard library only).

| Script | What it does on your machine |
|---|---|
| `vpr` | Passes each subcommand to one of the scripts below |
| `new-report.sh` | Creates `readiness.md` and `evidence/` (or, with `--full`, `docs/release-readiness/<date>/`) in the target folder. It never overwrites an existing report |
| `ledger-lint.sh` | Reads the report and ledger and prints findings. It calls `git rev-parse` to find the repository root, and deletes only its own temporary files |
| `report-html.py` | Runs the lint, then writes one self-contained HTML file next to the report (`report.html` by default) |
| `package.sh` | Copies the skill into a new folder in plugin layout. It refuses to write into a folder that already exists |
| `ensure-tools.sh` | Checks whether the delegate skills and the `gitleaks` CLI are present. With `--install` it runs the installs listed under "What it fetches" |
| `test/run-tests.sh` | Runs the self-tests in temporary folders |

### What it sends

Nothing. No script opens a network connection, and the plugin collects no data. Reports stay as local files in the project you audit. The skill asks Claude to publish the rendered HTML report as a claude.ai Artifact so remote readers can see it. That step uses Claude's own Artifact tool in your session, and you see it like any other tool call.

### What it fetches

Only `ensure-tools.sh --install` downloads anything, and only when you or Claude run it with that flag:

- `brew install gitleaks` through Homebrew, when `gitleaks` is missing and Homebrew is installed.
- `claude plugin install <skill>` for a missing delegate skill (`qa`, `qa-only`, `browse`, `benchmark`, `cso`, `design-review`, `codex`, `canary`). It installs only from marketplaces you have already added, and never adds a marketplace.

Without `--install`, the script only reports what is missing.

## Field records

`docs/` holds a record of the skill in use:

- `2026-08-22-skill-benchmark.html`: a comparison with other verification tools, based on four rounds of real use.

## License

MIT. See [LICENSE](LICENSE).
