---
type: policy
title: Code structure
description: New code defaults to one type (or tight family) per file, organized by the repo's own existing domain vocabulary; a repo that already has blob files remediates them as a scoped, dedicated initiative rather than folding the cleanup into routine issues.
tags: [policy, structure, refactor, duplication]
timestamp: 2026-08-04
---

# Code structure

**Default for new code: one type, or one tight family of types, per file.** Group files by the
repo's own existing domain vocabulary rather than inventing a new one — if the repo already has a
per-domain test-target layout (e.g. `OCCT<Domain>Tests`), a new `<Type>+<Domain>.swift` or
`<Domain>/<Type>.swift` file uses those same domain names, so the taxonomy stays single-sourced
instead of drifting between how code is organized and how it's tested. When extending a type that
already lives in a large file, prefer adding a `<Type>+<Domain>.swift` split over appending to the
existing file further. This applies everywhere, all the time, independent of whether a repo
currently has a blob problem — most satellite repos in this org don't (their largest files run
300-900 lines) and this rule is what keeps it that way.

**A repo that already has blob files remediates them as a scoped, dedicated initiative** — tracked
per the [issue-tracking](issue-tracking.md) policy (its own project board, not folded into routine
issues) — not by drive-by cleanup. Follow the method OCCTSwift's segmented duplication audit
([#377](https://github.com/SecondMouseAU/OCCTSwift/issues/377), passes tracked under
`refactor/377-segmented-audit` / `refactor/381-pass1b`) and OCCTReconstruct's analysis/build split
([#450](https://github.com/SecondMouseAU/OCCTReconstruct/issues/450),
[#555](https://github.com/SecondMouseAU/OCCTReconstruct/issues/555)) converged on independently:

1. **Segment before auditing.** Don't run one duplication/size lens over structurally different
   code in the same pass — hand-written wrapper boilerplate and hand-written app logic accumulate
   size and duplication for different reasons and need different judgment. Segment by internal
   dependency layer or structural kind first, then audit each segment on its own terms.
2. **Tell a mechanical split from a design-decision split before starting, and do the mechanical
   ones first.** A mechanical split is a pure lookup — "which file already defines this
   declaration" — with no judgment call in it; a design-decision split requires deciding where
   something *should* live. Do the mechanical split with a one-shot, throwaway migration script
   that reproduces the original content byte-for-byte (verify this mechanically — a sorted-symbol
   diff or equivalent — and put the result in the PR body), never by hand. Land it as one atomic
   PR: when an umbrella file and its new siblings must compile together, splitting that work across
   several agents or PRs by sub-domain leaves the tree non-compiling until the last one lands. Only
   take on the judgment-call splits once the mechanical pattern is proven.
3. **For a bloated file named after one type: evict before you split.** First move out whatever
   doesn't actually belong to that type — standalone types, extensions on other types — to the file
   that actually owns them, one file per type or tight family. Only split what's left, and only if
   it's still too big. A file that turns out to already be a legitimate single concern after
   eviction stays one file; that's a legitimate outcome, not a failure to split further.
4. **Zero behavior change.** Bodies move verbatim: identical public API (signatures, doc comments,
   availability, access level), full test suite green, history that survives a `git mv`-style
   rename. This is what makes a large mechanical PR reviewable at all. If a split seems to need an
   actual behavior or API break, that's a sign something's being rewritten, not moved — pull it out
   as its own separately-reviewed change instead of hiding it inside a structural PR.
5. **Measure fresh, not from the plan.** File sizes and occurrence counts quoted in an issue or a
   plan go stale as unrelated work lands elsewhere — measure again at the start of each pass rather
   than trusting the number already written down. Where the same family gets counted or measured
   more than once, build that count as a committed, executable script that enumerates and measures
   against the real code, not a grep repeated by hand or a number typed into an issue body — a
   repeated hand-recount is exactly where a stale or simply wrong count survives unnoticed.

Why: OCCTSwift's `Sources/OCCTSwift` reached ~56,000 lines across 71 files before #377, dominated
by two Swift files and one bridge header that together ran to roughly 55,000 lines on their own —
about 2.6x OCCTMCP's entire codebase in three files. Both the size and the ecosystem's accumulated
duplication (see [search-before-building](search-before-building.md)) trace back to the same root
cause: nothing forced new code toward small, well-scoped files, so it kept landing in whichever
huge file already existed for that type. OCCTReconstruct's `#450` found the same pathology in a
different shape — not one file grown huge, but the same logic (edge-key packing, the shoelace
formula, union-find, median/percentile) independently reimplemented across dozens of files —
confirming this isn't an OCCTSwift-specific problem, just one that shows up differently depending
on how a repo grew.

Ecosystem standard: see
[OKF-STANDARD.md](https://github.com/SecondMouseAU/ecosystem/blob/main/OKF-STANDARD.md).
