;;;; tv2.asd --- An experimental CLOS-native re-architecture kernel for tvision.
;;;;
;;;; tv2 is a clean-break redesign of the framework's *dispatch and construction*
;;;; layers: state is reactive (a metaclass invalidates the screen on mutation),
;;;; events are CLOS classes dispatched by multimethods, input resolves to named
;;;; commands through layered keymaps, and behaviour lives in command objects --
;;;; not 138 integer constants and a central dispatch COND.
;;;;
;;;; It reuses tvision's terminal driver, screen/cell buffer, geometry and the
;;;; outline-node data structure unchanged; only the plumbing is new.

(asdf:defsystem "tv2"
  :description "Experimental CLOS-native kernel for the tvision TUI framework."
  :depends-on ()
  :serial t
  :components ((:module "base"                     ; the foundation tv2 owns (was tvision's lower half):
                :serial t                           ; terminal driver, cell/colour model, geometry, events,
                :components ((:file "package")       ; the Unicode/grapheme engine, and the outline-node struct.
                             (:file "geometry")
                             (:file "colors")
                             (:file "draw-buffer")
                             (:file "events")
                             (:file "screen")
                             (:file "outline-node")))
               (:module "tv2"
                :serial t
                :components ((:file "package")
                             (:file "kernel")
                             (:file "fuzzy")
                             (:file "runtime")
                             (:file "outline")
                             (:file "widgets")
                             (:file "cluster")
                             (:file "validator")
                             (:file "scrollback")
                             (:file "layout")
                             (:file "host")
                             (:file "modal")
                             (:file "threadmon")
                             (:file "browser")
                             (:file "project")
                             (:file "debugger")
                             (:file "repl")
                             (:file "syntax")
                             (:file "regex")
                             (:file "editor")
                             (:file "html")
                             (:file "scrollbar")
                             (:file "table")
                             (:file "dialogs")
                             (:file "help")
                             (:file "desktop")
                             (:file "inspect")
                             (:file "tools")
                             (:file "paredit")
                             (:file "nav")
                             (:file "compile")
                             (:file "editing")
                             (:file "emoji")
                             (:file "sbcl")
                             (:file "docs")
                             (:file "app")))))
