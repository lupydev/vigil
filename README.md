# Vigil

A macOS menu bar watchdog for **work that outlived its purpose** — processes
still consuming a core long after the job that started them ended.

It reads the kernel's own CPU accounting instead of sampling, so it can identify
a wedged process from a single reading. It never acts on your machine, and it
writes nothing to your disk.

---

## The problem

Software that spawns background work does not always clean it up. A parent
crashes, a run is cancelled, a socket drops, a watcher loses its file
descriptor — and the child keeps going, spinning on a loop nobody is waiting on.

Common sources:

- **Build and test daemons** that survive a cancelled run — Gradle, Jest and
  Vitest watchers, `tsc --watch`, webpack, pytest workers
- **Language servers and IDE helpers** that wedge after an index or a crash
- **Container and VM runtimes** left running with nothing to run
- **Sync, indexing and backup agents** stuck retrying something unreachable
- **Media, render and export jobs** that hang without failing
- Anything started by a tool that died before reaping it

These are not crashes. Nothing errors, nothing alerts, no dialog appears. The
machine keeps working — just warmer, louder, and slower — and the symptoms are
easy to attribute to the machine simply getting old.

### Why it compounds

A pinned core is the visible cost. The expensive one is second-order: sustained
load and the memory these processes hold push the system into swap, and **macOS
does not reclaim swap while running**. Once pages are written, only a restart
frees them.

So the machine begins paging against the SSD continuously — more heat, more
wear, worse latency — and that condition persists even after the original CPU
spike would have been noticed. The longer the uptime, the deeper it gets.

### Why it goes unnoticed for so long

The tools to find this are already installed on every Mac. That is what makes it
frustrating rather than difficult.

**`ps` reports CPU as a decaying average over roughly the last minute.** From
the man page:

> `%cpu` — The CPU utilization of the process; this is a decaying average over
> up to a minute of previous (real) time.

That column cannot separate a compile that started thirty seconds ago from a
daemon wedged since Tuesday. Both read ~100%. Any monitor built on "CPU is high"
fires on every build, test run and export — and gets muted within a week.

**Activity Monitor** shows it immediately, to anyone who opens Activity Monitor.
Nobody opens Activity Monitor on a machine that is merely warm.

**Cleaner utilities** answer a different question. Free disk space is usually
not the issue, and reclaiming it does nothing for a process burning a core.

The gap is not capability. It is that the two facts which together identify
abandoned work — **how hard** it is working and **how long** it has been doing
it — are not presented in the same place.

## How Vigil detects it

### The kernel is already keeping the history

`proc_pidinfo(pid, PROC_PIDTASKALLINFO, …)` returns, per process:

```c
info.pbsd.pbi_start_tvsec      // process start time, epoch seconds
info.ptinfo.pti_total_user     // cumulative CPU consumed, mach ticks
info.ptinfo.pti_total_system   // cumulative CPU consumed, mach ticks
info.ptinfo.pti_resident_size  // resident memory
```

`pti_total_user + pti_total_system` is a **running total of every nanosecond the
process has spent on a core**, maintained continuously since it was created.
Divided by the process's age:

```
lifetime CPU % = cumulative CPU time / (now − start time) × 100
```

Available from **one reading**. No database, no warm-up, no sampling window —
and strictly more accurate than a sampler could reconstruct, because the kernel
counted continuously while a sampler only sees the moments it looked.

### Two signals, cross-referenced

A lifetime average alone is not enough: a process can carry a heavy past and be
idle now. Every finding requires independent facts to agree.

| Signal | Source | Answers |
|---|---|---|
| Lifetime average | kernel counters, one reading | has it burned since it started? |
| Current CPU | delta of the counter between two readings | is it burning *right now*? |
| Age | `pbi_start_tvsec` | has it existed long enough to be a mistake? |

Current CPU is a delta of the cumulative counter across two known instants — an
honest percentage over a known interval, rather than a platform average with
hidden decay.

### The shape a lifetime average cannot see

A process alive for weeks that jammed an hour ago has a lifetime average near
zero; an hour of burn does not move a long denominator. The dilution is real and
measurable — on one test machine `WindowServer` read 35.8% lifetime at 69
minutes of uptime and 8.8% at four hours, same process, same behaviour.

A second rule covers that shape and only that shape, using a short window held
in memory: sustained above 80% across consecutive readings *while* the lifetime
average stays below 70%. The two rules are mutually exclusive by construction —
one rule's ceiling is the other's floor — so a stuck process is never reported
twice.

### Ask who already knows

The same principle applies beyond CPU. Swap fullness looks like a pressure
signal and is not one: macOS grows the swap file under pressure and **never
shrinks it while running**, so it records where a machine has been, not where it
is. Keyed on that alone, a rule stays lit for hours against a system that
recovered — which is how alerts get ignored.

Rather than approximate current pressure from a paging rate and invent a
threshold for it, `SwapPressureRule` reads
`kern.memorystatus_vm_pressure_level`: the kernel's own live verdict, the same
one behind Activity Monitor's pressure graph and macOS's decisions about
terminating applications. It weighs compression ratio, clean page availability
and file-backed pressure, none of which is visible from here.

Fullness decides *whether* to speak. The kernel decides *how loudly*. Every
threshold not invented here is one that never needs calibrating.

### Two platform details that will bite you

**`pti_total_user` is not nanoseconds on Apple Silicon**, despite the header
comment. It returns mach absolute-time ticks, 125/3 ns each. Read as
nanoseconds, CPU is underreported ~42x: a process pinned at a full core measures
2%.

```swift
mach_timebase_info(&info)                  // numer=125, denom=3 on arm64
nanoseconds = ticks / denom * numer
```

**A pid is not an identity.** macOS reuses pids, so a window keyed on pid alone
will stitch a dead process's history onto a live one and invent load that never
happened. Identity is `pid + start time`.

## Rules

| Rule | Fires when | Needs history |
|---|---|---|
| `LifetimeCpuRule` | lifetime ≥ 70%, current ≥ 50%, age ≥ 2h | no |
| `SustainedCpuRule` | ≥ 80% every reading for 10+ min, lifetime < 70%, age ≥ 2h | yes, in memory |
| `SwapPressureRule` | swap ≥ 70% used; severity from the kernel's pressure level | no |
| `DiskPressureRule` | ≤ 10% free (5% critical) | no |

Every threshold is a constructor parameter.

### Calibration, and its limits

The current defaults come from measurements on **a small number of machines**.
On one idle-to-moderate developer machine, lifetime averages looked like this:

```
 35.8%  WindowServer          2.0%  container runtime
  9.9%  editor/agent          1.5%  metadata indexer
  7.5%  virtualization        1.1%  wifi driver extension
  6.5%  terminal              1.0%  browser
```

Nothing exceeded 36%; almost everything sat under 10%. A process pinned since
birth approaches 100%, so 70% was chosen to sit clear of observed normal with
room to spare.

**This is the weakest part of the project, and the easiest to help with.** A
render farm, a CI runner, a machine that transcodes video all day, or one that
mostly sits idle will have a different notion of normal, and thresholds tuned on
someone else's workload may be wrong on yours. If Vigil flags something
legitimate — or stays quiet while something is clearly stuck — that is a
[false finding](../../issues/new?template=false_finding.yml), and it is the most
valuable report this project can receive.

## What Vigil costs

Measured on an Apple Silicon laptop at a 60-second interval:

| | |
|---|---|
| CPU per sweep | ~17 ms to read ~500 processes |
| Duty cycle | ~0.03% |
| Resident memory | 35 MB |
| Disk | **0 bytes** |

The in-memory window is bounded on both axes: at most 120 readings of at most 20
hot processes, discarded on quit. Losing it on restart costs almost nothing,
because `LifetimeCpuRule` works from the first reading with no warm-up.

## Two invariants

**Vigil never acts.** No port in `MonitorEngine` can change the machine. This is
architectural, not a matter of discipline — granting it that power would take a
deliberate change, not an accidental one. Findings carry the command that would
fix them, with a copy button. You decide, and you run it.

**Vigil writes nothing to disk.** No caches, no database, no logs, no
`Application Support` directory. An earlier version persisted samples and it
worked out to 1.26 GB a week — an absurd thing for a resource watchdog to do.
When something seems to need persisting, the better move is usually to ask the
kernel a sharper question.

## Install

Requires macOS 14+ and a Swift 6 toolchain. Command Line Tools are enough — full
Xcode is not needed.

```bash
git clone https://github.com/lupydev/vigil.git
cd vigil
./scripts/bundle.sh && open build/Vigil.app
```

The app lives only in the menu bar — no Dock icon, no window. Click the
stethoscope to open it.

### Terminal

```bash
swift run vigil --scan       # one-off check against this machine
swift run coretests          # domain tests, non-zero exit on failure
```

`--scan` takes several readings, because current-CPU deltas need consecutive
samples. `--min-age <seconds>` shortens the two-hour age requirement for a single
scan, which is the fastest way to try a threshold or reproduce a finding:

```bash
$ swift run vigil --scan --samples 3 --interval 3 --min-age 30

FINDINGS

  [CRITICAL] yes has burned 99% CPU for its entire 48s life
      · pid 15763
      · lifetime average 99%
      · current 100%
      · cpu time 47s over 48s
      · /usr/bin/yes
      → Confirm the work is genuinely abandoned, then stop the process.
        kill -9 15763
```

## Architecture

```
VigilCore     pure domain — models, rules, ports, in-memory store
              no Darwin, no AppKit, no I/O. Fully testable.
VigilSystem   adapters — libproc, sysctl, Mach, notifications
VigilApp      menu bar shell (MenuBarExtra) and the --scan entry point
CoreTests     domain tests
```

Rules depend on `ProcessSnapshot` and `ResourceSnapshot`, never on the syscalls
that fill them. Adding a fact means adding a field and letting an adapter
populate it, which keeps rules testable without putting a real machine into a
particular state.

## Known limitations

- **Only processes you own are measured.** `proc_pidinfo` denies task info for
  other users' processes, so root and system daemons — `WindowServer` among them
  — are skipped silently. Fine for the target case, since build daemons,
  containers and editors run as you, but it is not a complete picture of the
  machine. Covering system processes needs elevated privileges, which is a much
  larger decision than it looks.
- **The menu bar item can hide behind the notch.** On a crowded menu bar macOS
  pushes items left, and on a notched Mac they can land underneath it — present,
  functional, invisible. Free up menu bar space if the stethoscope never appears.
- **Disk free space counts purgeable storage.** Vigil reports
  `volumeAvailableCapacityForImportantUsage`, the figure Finder shows, which
  includes reclaimable caches, and it can differ substantially from `df`.
  Neither is wrong; they answer different questions.
- **The first reading of any process reports 0% current CPU.** There is no prior
  reading to delta against. Costs one interval at startup and nothing after —
  `LifetimeCpuRule` does not depend on it.

## Notes for whoever tunes this next

Every serious bug in this project passed the test suite, because all of them
lived at the boundary with the operating system:

- The **42x mach-ticks error** above. Found by running `yes` and seeing 2% where
  100% belonged.
- The monitor **only ran while the menu was open**, because `MenuBarExtra` builds
  its content lazily and the engine started from the view's `.task`. It now
  starts from `applicationDidFinishLaunching`.
- The menu bar icon was **invisible behind the notch**. Found by having the app
  print its own status item frame and comparing it against
  `NSScreen.auxiliaryTopLeftArea`.

The domain tests are good and caught none of these. Run changes against a real
machine and say what you saw.

Tests use a small hand-rolled harness rather than XCTest, because XCTest and
swift-testing both ship with full Xcode and this was built against the Command
Line Tools alone. Installing Xcode makes `swift test` available and the harness
can be retired.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

The most useful contribution is not code — it is **evidence from a machine we
have never measured**. Thresholds here are claims about what normal looks like,
and they were calibrated on very few workloads. Report a false finding, propose
a rule for a failure mode you have actually hit, or just tell us what lifetime
averages look like on your machine under load.

## License

MIT. See [LICENSE](LICENSE).
