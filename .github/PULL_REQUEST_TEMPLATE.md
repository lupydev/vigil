## What this changes

<!-- One paragraph. What is different after this merges, and why. -->

## What you measured

<!--
Every serious bug in this project passed the test suite, because they all lived
at the boundary with the operating system. Tell us what you observed on a real
machine — the process you ran, the numbers before and after, the file that did
or did not appear.

If this is a docs-only change, write "docs only" and move on.
-->

## Invariants

- [ ] This does **not** give Vigil the ability to act on the machine (kill, delete, configure, execute).
- [ ] This does **not** write anything to the user's disk.
- [ ] `VigilCore` still imports nothing platform-specific.

<!--
If you are deliberately changing one of these, do not tick the box — say so
here and explain. They are architectural decisions, not paperwork, and they are
discussable. Silently breaking one is the only unacceptable option.
-->

## Thresholds

<!--
Only if you added or changed one. What number, and what measurement justifies
it? "Seems about right" is not a justification. If you added a rule that can
overlap an existing one, explain how they are kept mutually exclusive.

Delete this section if it does not apply.
-->

## Checks

- [ ] `swift run coretests` passes
- [ ] `swift run vigil --scan` runs clean on my machine
- [ ] New behaviour has tests for when it fires **and** for when it stays silent

## Environment

<!-- e.g. M4, macOS 26.6, Swift 6.2.3 -->
