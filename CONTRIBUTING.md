# Contributing to Vigil

Thanks for wanting to help. This document is short, and most of it is about two
invariants that are not up for negotiation, because they are the whole point of
the project.

## The two invariants

**1. Vigil never acts on the machine.**

No pull request may give the app the ability to kill a process, change a
setting, delete a file, or run a command. Findings carry the command that would
fix them, as text the user can copy. The user runs it.

This is enforced by architecture, not by discipline: `MonitorEngine` holds no
port capable of changing anything. Please keep it that way. If you want an
automated remedy, open an issue and let's talk about it first — it is a real
conversation, but it is not a drive-by PR.

**2. Vigil writes nothing to the user's disk.**

No caches, no databases, no logs, no `~/Library/Application Support` directory.
An earlier version persisted samples and it worked out to 1.26 GB a week, which
is an absurd thing for a resource watchdog to do. The kernel already keeps the
history that matters; read [How it works](README.md#how-it-works) for why that
turned out to be better *and* cheaper.

If you think you need to persist something, you probably need to ask the kernel
a better question.

## Architecture

```
VigilCore     pure domain — no Foundation-beyond-basics, no system imports
VigilSystem   adapters — libproc, sysctl, Mach, notifications
VigilApp      menu bar shell and the --scan entry point
CoreTests     domain tests
```

`VigilCore` must not import `Darwin`, `AppKit`, or anything platform-specific.
If a rule needs a new fact about a process, add it to `ProcessSnapshot` and let
the adapter fill it in. This is what makes the rules testable without a machine
in a particular state.

## Running things

```bash
swift build
swift run coretests                   # must pass, exits non-zero on failure
swift run vigil --scan                # see the pipeline against your real machine
./scripts/bundle.sh && open build/Vigil.app
```

Tests use a small hand-rolled harness instead of XCTest, because XCTest and
swift-testing both require full Xcode and this was built against the Command
Line Tools. Adding a suite means adding a `Suite` and registering it in
`Sources/CoreTests/main.swift`.

## Adding a rule

1. Conform to `AnomalyRule` in `Sources/VigilCore/Rules/`.
2. Prefer facts the kernel already knows over facts you would have to accumulate.
   A stateless rule is worth more than a stateful one with the same accuracy.
3. Register it in `Diagnostician.standard`.
4. Write tests for when it fires **and** for when it must stay silent. The
   silent cases are the valuable ones — a rule that fires on every build is
   worse than no rule.
5. Make thresholds constructor parameters, with the default measured rather than
   guessed. Say in a comment what you measured and on what.

If your rule can overlap with an existing one, make them mutually exclusive by
construction the way `LifetimeCpuRule` and `SustainedCpuRule` are — one rule's
floor is the other's ceiling. Reporting one problem twice is worse than
reporting it once badly.

## Thresholds are claims about reality

Every number in this codebase should be defensible with a measurement. The 70%
lifetime threshold exists because a real healthy machine topped out at 35.8%.
The 50% storage floor exists because it sits clear below the lowest rule.

"Seems about right" is not a reason. If you change a threshold, say what you
measured.

## Verify against the machine, not only against the tests

Every serious bug this project has had passed the test suite:

- CPU was underreported **42x** because `pti_total_user` returns mach ticks, not
  nanoseconds, on Apple Silicon. Found by running `yes` and noticing 2% where
  100% belonged.
- The monitor only ran while the menu was open, because `MenuBarExtra` builds its
  content lazily. Found because a file that should have appeared did not.
- The menu bar icon was invisible on a notched Mac. Found by asking the app to
  print its own status item frame.

The domain tests are good and they caught none of these, because all three lived
at the boundary with the operating system. Before you open a PR, run it against
your actual machine and say what you saw.

## Commits and PRs

- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.
- One logical change per PR. A rule plus its tests is one change; a rule plus an
  unrelated refactor is two.
- `swift run coretests` must pass.
- Say what you measured. See the PR template.

## Reporting things

Three issue templates, and the distinction matters:

- **Bug** — something crashed, failed to build, or behaved incorrectly.
- **False finding** — a rule fired when it should not have, or stayed quiet when
  it should have spoken. These are the most useful reports this project can get,
  because they are evidence about thresholds.
- **New rule** — a kind of anomaly Vigil should learn to see.
