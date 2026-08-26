# verifying-production-readiness

A Claude Code skill for **judging whether a system can ship to production** — go / no-go
sign-off driven by *observation, not green checkmarks*.

> Green tests, a passing type-check, "it worked on staging" — none of these are grounds for
> shipping. They say a *known* thing didn't break; they say nothing about the *unknown*.

## What it does

- **Pins numeric gates before the audit** — the threshold and how it's counted, fixed up front,
  so a verdict can't be back-fit to the result.
- **Grades every finding by evidence** — `claimed` (someone said so) · `code` (read to confirm) ·
  `measured` (actually run and observed). **A GO verdict is impossible without `measured`.**
- **Drives the real product end-to-end** — a static audit misses the ship-blocker that only an
  actual run reveals.
- **Keeps a defect ledger that survives across sessions** — stable IDs, status, evidence grade, and
  the proof each item was closed. The next session resumes from the open rows.
- **Ships tooling** — a machine `ledger-lint` (rules R1–R13) that refuses a verdict built on
  fabricated evidence, plus an HTML report renderer for remote review.

Verdicts are one of four: **GO · CONDITIONAL GO · NO-GO · UNVERIFIABLE**.

## Install (as a Claude Code plugin)

```bash
claude plugin marketplace add wook8170/verifying-production-readiness
claude plugin install verifying-production-readiness@verifying-production-readiness
```

Then invoke it in a session with `/verifying-production-readiness`, or just ask Claude to judge
whether something is ready to ship.

## Language

The skill's instructions are currently written in **Korean**. An English edition is planned for
international users — see [issues](https://github.com/wook8170/verifying-production-readiness/issues).
The verdict vocabulary (GO / CONDITIONAL GO / NO-GO / UNVERIFIABLE) and the `ledger-lint` rules are
language-independent.

## Layout

```
skills/verifying-production-readiness/
  SKILL.md              the entry point Claude reads
  axes.md               the 11 audit axes (what to look at, how, where the line is)
  report-template.md    ledger format + re-entry procedure
  measurement-hygiene.md  what invalidates a measurement
  media-adapters.md     translation table for non-web targets
  bin/vpr               single entry point: new · lint · render · package · test · rules
```

## License

MIT — see [LICENSE](LICENSE). Authored by **장욱 (Wook Jang)**.
