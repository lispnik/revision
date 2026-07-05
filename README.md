# revision — a CLOS-native text-mode UI framework for Common Lisp

A Turbo-Vision-inspired character-mode UI framework for Common Lisp (SBCL),
rebuilt around CLOS.  It gives you overlapping movable windows, dialogs,
controls, a mouse-aware event system and a DOS-style colour/palette model — all
rendered with ANSI escape sequences in any modern terminal.  Views draw through
named **theme roles** resolved to a **24-bit RGB theme** and matched to the
terminal automatically (true-colour → xterm-256 → 16-colour), so colours are
exact and themeable — and a view can also paint **arbitrary per-cell true
colour** (`make-rgb`) when it wants a gradient or image.

Where a classic Turbo Vision port hand-computes `TRect` bounds, dispatches on 138
integer command constants and calls `draw-view` after every mutation, revision uses a
**reactive metaclass** (slot writes invalidate the screen), **CLOS event classes**
dispatched by multimethods, named **commands** resolved through layered
**keymaps**, and a **box-model layout DSL**.  See [`revision/README.md`](revision/README.md)
for the architecture in depth.

![revl, the SLIME-class IDE built on revision (a separate application) — the full menu bar, paredit + line numbers, source navigation, and a live HyperSpec lookup](media/tv2-ide.gif)

![True-colour rendering: exact VGA palette and live theme switching](media/truecolor.gif)

![Arbitrary per-cell 24-bit colour: a hue × brightness gradient](media/truecolor-gradient.gif)

## Requirements

* [SBCL](http://www.sbcl.org/)
* A POSIX terminal with `stty` (macOS/Linux)
* **No external Lisp libraries to build, run, or test** — the framework depends
  only on SBCL itself.  The threaded REPL/debugger tooling in the example app
  use SBCL's own facilities (`sb-thread`, `sb-mop`, `sb-di`, and the
  `sb-introspect` contrib, all bundled with SBCL).

The project loads through [ocicl](https://github.com/ocicl/ocicl) (the current
directory is on the ASDF source registry via `~/.sbclrc`), so
`(asdf:load-system :revision)` just works.  Because there are no third-party
dependencies there is nothing to `ocicl install`.

## Hello, world

The smallest standalone revision program — one window with a greeting and an OK
button (`examples/hello-world.lisp`, run it with `sbcl --script`):

```lisp
(asdf:load-system "revision")
(in-package #:revision)

(defun hello-world ()
  (let ((win (ui (window (:title " revision " :keymap *global-keys*)
                   (stack
                     (:fill (static-text :text ""))
                     (1 (row (:fill (static-text :text ""))
                             (13 (static-text :role :label :text "Hello, World!"))
                             (:fill (static-text :text ""))))
                     (1 (row (:fill (static-text :text ""))
                             (8  (button :label "OK" :command 'quit))
                             (:fill (static-text :text ""))))
                     (:fill (static-text :text ""))
                     (1 (static-text :role :status :text " Press Esc, q, or OK to quit ")))))))
    (run-view win)))     ; runs full-screen until QUIT

(hello-world)
```

Structure is a box model: `stack` splits vertically, `row` horizontally, cells
are `:fill` (take the rest) or an integer height/width.  Keys map to named
commands; commands are methods on the command name; views react to slot changes
automatically.  See [`revision/README.md`](revision/README.md) for the `ui` macro,
keymaps, commands, theming, and the reactive metaclass.

## Structure

| Module | Responsibility |
|--------|----------------|
| `base/` | the foundation: `geometry` (points/rects), `colors` (attribute byte ↔ ANSI SGR, RGB themes), `draw-buffer` (the cell model + the Unicode/grapheme/display-width engine), `events` (event records + key/mouse/command codes), `screen` (raw mode, alternate screen, diff-based ANSI rendering, input decoding), and the `outline-node` tree data structure |
| `revision/`  | the CLOS-native toolkit: the reactive metaclass, CLOS event dispatch, keymaps → commands, the `ui` layout DSL, theming, MOP persistence, the worker→UI bridge, and the widget/window/dialog/menu set — the text editor, outline tree, table, scrollback transcript, HTML view, and the **desktop shell** with its window+menu **plugin registry**.  (The Lisp-IDE windows — REPL, debugger, inspector, project tree, browsers — live in the `revl` application, not here.) |

The whole framework lives in a **single `revision` package** (one `defpackage`
in `base/package.lisp`): `base/` populates it with the foundation symbols and
`revision/` adds the kernel, so `revision:make-attr`, `revision:run-desktop`, and
everything else share one namespace.  That `:export` is the **single source of
truth for the public API** — a grouped, deliberate contract; every exported symbol
is documented, and [`API.md`](API.md) is a generated reference (`make api`).

## Unicode

Each cell carries a full 21-bit code point, so any Unicode character can be typed
and rendered.  **Double-width** glyphs (CJK and most emoji) claim two cells (via
`sb-unicode`'s `east-asian-width`), and **grapheme clusters** (combining marks,
ZWJ / skin-tone emoji) are interned into a single cell, so they render as one
glyph and arrow-keys / backspace / mouse / selection treat them as one unit.
Word-wrap reflows wide glyphs whole rather than splitting them at the boundary.

![Editing Greek, Cyrillic, accents and math symbols](media/unicode.gif)

![Word-wrap with emoji: wide glyphs stay whole at the wrap boundary](media/wrap-emoji.gif)

## Example applications

The framework's flagship example, **`revl`** — a SLIME-class Lisp REPL / IDE
that exercises the whole framework (overlapping windows, menus, dialogs, the
syntax-highlighting editor, the object inspector, an HTML browser, a threaded
`sldb`-style debugger, and code-intelligence tools: completion, paredit, source
navigation, tracing/profiling, a HyperSpec lookup) — lives in its own repository:

> **[github.com/lispnik/revl](https://github.com/lispnik/revl)**

Clone it next to this checkout and build:

```sh
git clone git@github.com:lispnik/revl.git   # alongside this revision checkout
cd revl && make && ./revl
```

It reaches this framework through a `systems/revision` symlink to the sibling
checkout, so the two build together with no global configuration.  Its
framework-agnostic Lisp logic lives in a shared `revl-logic` system, so the IDE
reuses it directly on revision.  See that project's README for the full feature tour.

### revision-term — a terminal-emulator widget

**`revision-term`** is a **reusable terminal window** for the framework: it runs
a real child process (your shell, `vi`, `top`, …) on a pseudo-terminal, emulates
it with **libvterm** (via CFFI), and renders the emulated screen into a
`revision` view — so a live terminal becomes a first-class window that any
`revision` app can embed, alongside the REPL, editor, and the rest.  It shows off
the framework's 24-bit colour and text-style attributes with full fidelity
(true-colour, bold/italic/underline, wide CJK/emoji, combining marks).

> **[github.com/lispnik/revision-term](https://github.com/lispnik/revision-term)**

![revision-term: terminal windows in a revision desktop, tiled beside a native Lisp REPL](https://raw.githubusercontent.com/lispnik/revision-term/master/media/demo.gif)

## Testing

```sh
make            # build check: compile + load the framework
make test       # headless suites (editor display-width + widgets, and the desktop shell)
make api        # regenerate API.md — the public-API reference — from the docstrings
make keybindings # regenerate KEYBINDINGS.md from the keymaps
```

The headless suites cover the editor's display-width (wide CJK / emoji) + widget
layout, the **desktop shell + window/menu plugin registry** (opening/closing windows
through `*window-builders*`, `*extra-menus*` merging), and a keybinding-reference
drift check; they exit non-zero on any failure (CI-ready) and need nothing but SBCL.
The example app's own tests — the REPL backend, the debugger, the inspector, and an
end-to-end pty smoke test — live with it in [github.com/lispnik/revl](https://github.com/lispnik/revl).

## License

MIT.
