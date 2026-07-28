# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`revision` is a CLOS-native, text-mode (TUI) UI framework for Common Lisp (SBCL only),
a clean-break re-architecture of a Turbo-Vision-style toolkit. It is a **reusable
library, not an application** — there is no binary to dump. The flagship application
that exercises it (`revl`, a SLIME-class IDE) and other consumers (`revision-term`,
`revision-sixel`) live in **separate sibling repositories**, not here.

Read `revision/README.md` for the architecture in depth and `README.md` (repo root)
for the feature tour.

## Commands

```sh
make            # build check: compile + load the framework (default goal)
make test       # headless suites — editor display-width, widgets, desktop shell, API contract
make api        # regenerate API.md from exported symbols' docstrings
make keybindings # regenerate KEYBINDINGS.md from the keymaps
make clean      # remove this project's fasl cache
```

Run a **single** test suite directly (each is a standalone `--script`, exits non-zero on failure):

```sh
sbcl --script tests/revision-editor-tests.lisp    # editor column math (wide CJK / emoji)
sbcl --script tests/revision-desktop-tests.lisp   # desktop shell + plugin registry
sbcl --script tests/revision-api-tests.lisp        # public-API contract (see boundary below)
```

Interactive load in a REPL: `(asdf:load-system :revision)` — the repo dir is on the
ASDF source registry (via `~/.sbclrc` / ocicl), so it just works.

**No external Lisp dependencies.** The framework depends only on SBCL itself
(`sb-thread`, `sb-mop`, `sb-unicode`, etc.). `systems/` holds vendored deps for CI /
sibling apps, not for building this library — `revision.asd` has an empty `:depends-on`.

## Load order matters

The system is `:serial t`: `base/` loads first (foundation), then `revision/` (the
CLOS kernel), file by file in the order listed in `revision.asd`. A symbol must be
defined before the file that uses it. When adding a `.lisp` file, register it in the
appropriate `:components` list at the right position, or the build breaks.

## The single-package public-API boundary (enforced)

The **entire framework lives in one `revision` package** — `base/package.lisp` holds
the sole `defpackage`. `base/` populates the foundation symbols and `revision/` adds
the kernel; everything shares one namespace.

That `:export` list is the **single source of truth for the public API** — a
deliberate, grouped contract. The boundary is enforced, not conventional:

- Exported symbols are the contract; `API.md` is generated from their docstrings.
- Everything else is internal. A **`%`-prefixed name is a private helper** — reaching
  one as `revision::%foo` from outside is a smell.
- `tests/revision-api-tests.lisp` fails the build if any export lacks a real
  definition (API rot) or if any `%`-private symbol appears in the export list.

Consequences when you change code: **exporting a new symbol requires a docstring** and
a run of `make api`; touching keymaps requires `make keybindings`. Both generated files
(`API.md`, `KEYBINDINGS.md`) are committed and CI-relevant — regenerate them in the
same change rather than letting them drift.

## Architecture — the core idea

Where a classic Turbo Vision port hand-computes bounds, dispatches on integer command
constants, and calls `draw-view` after every mutation, revision replaces the *dispatch
and construction* layers with CLOS:

- **Reactive metaclass** (`reactive-class`, `reactive.lisp`): a *changed* slot write
  triggers `invalidate`, recording which view changed for a partial repaint. You do
  **not** call a repaint function after mutating view state.
- **Events are CLOS classes** (`events.lisp`) dispatched by `(view × event)`
  multimethods (`handle-event`), not integer type tags + a `cond`.
- **Commands are named objects** (`commands.lisp`) resolved through layered **keymaps**
  → `perform`. Define behaviour with `define-command`; bind keys with `defkeymap`.
- **Layout is a box-model DSL** (`layout.lisp`): the `ui` macro builds a view tree from
  a nested spec, checked at macroexpansion. `stack` splits vertically, `row`
  horizontally; cells are `:fill` or an integer size (rows in a `stack`, columns in a
  `row`).
- **Colours are named roles** resolved through `*theme*` (a 24-bit RGB theme matched to
  the terminal: true-colour → xterm-256 → 16-colour). A view can also paint arbitrary
  per-cell RGB.
- **Persistence is MOP-based** (`persistent-class` + `:transient` slots in
  `runtime.lisp`): `serialize`/`deserialize` recurse into readable atoms and containers,
  signal on cycles / unserializable values (fail loud, no silent corruption).
- **Worker→UI bridge** (`runtime.lisp`): only the UI thread touches the screen.
  Background work posts via `run-on-ui` / `run-async`; `drain-ui-callbacks` wakes the
  idle event loop instantly (a self-pipe breaks its `select`).

### Layout of the tree

- `base/` — the foundation: `geometry`, `colors` (attribute byte ↔ ANSI SGR, RGB
  themes), `draw-buffer` (cell model + Unicode/grapheme/display-width engine), `events`,
  `screen` (raw mode, alternate screen, diff-based ANSI render, input decode),
  `outline-node`.
- `revision/` — the CLOS kernel and widget set: reactive metaclass, event dispatch,
  keymaps/commands, the `ui` DSL, theming, persistence, the worker→UI bridge, and the
  widgets (editor, outline tree, table, scrollback, HTML view) + the **desktop shell**
  with its `*window-builders*` / `*extra-menus*` **plugin registry** an application
  extends.

### Runnable entry points

`(revision:run-desktop)` — the bare shell (menu bar + status bar + hosted windows).
`(revision:run)` — kitchen-sink demo. Also `run-editor`, `run-html`, and `run-view`
(host any single view full-screen). See `examples/hello-world.lisp`.

## Unicode

Cells carry a full 21-bit code point. Double-width glyphs (CJK / most emoji) claim two
cells; grapheme clusters (combining marks, ZWJ / skin-tone emoji) intern into one cell
so cursor/selection/wrap treat them as one unit. The editor stores the cursor as a
**code-point index** but lays out text in **display columns** — keep that distinction
in mind when touching editor/draw-buffer column math (the editor tests exercise it).

## Change workflow

This repo uses **OpenSpec** for spec-driven changes (`openspec/`, with `opsx:*` skills
and `.claude/commands/opsx/`). For substantial features, prefer proposing a change
through that workflow. Commit messages follow a `type: subject` convention (`feat:`,
`refactor:`, `docs:`, plus a leading area tag for larger areas, e.g. `desktop:`).
