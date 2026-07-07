;;;; revision.asd --- a CLOS-native text-mode UI framework (re-vision of tvision).
;;;;
;;;; revision is a clean-break redesign of a Turbo-Vision-style framework's
;;;; *dispatch and construction* layers: state is reactive (a metaclass
;;;; invalidates the screen on mutation), events are CLOS classes dispatched by
;;;; multimethods, input resolves to named commands through layered keymaps, and
;;;; behaviour lives in command objects -- not 138 integer constants and a
;;;; central dispatch COND.
;;;;
;;;; It owns the foundation (`base/': terminal driver, screen/cell buffer,
;;;; geometry, the Unicode/grapheme engine, the outline-node data structure) and
;;;; layers the new plumbing on top.

(asdf:defsystem "revision"
  :description "A CLOS-native text-mode UI framework for Common Lisp."
  :depends-on ()
  :serial t
  :components ((:module "base"                     ; the foundation: terminal driver, cell/colour
                :serial t                           ; model, geometry, events, the Unicode/grapheme
                :components ((:file "package")       ; engine, and the outline-node struct.
                             (:file "geometry")
                             (:file "colors")
                             (:file "draw-buffer")
                             (:file "events")
                             (:file "screen")
                             (:file "outline-node")))
               (:module "revision"
                :serial t
                :components ((:file "package")
                             (:file "reactive")   ; the reactive metaclass + screen invalidation
                             (:file "events")     ; events as a class hierarchy + terminal translation
                             (:file "commands")   ; keymaps + commands (input bindings and behaviour as data)
                             (:file "view")       ; the view hierarchy, containers, focus, (view x event) dispatch
                             (:file "draw")       ; theming, drawing primitives, chrome, the scroll protocol
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
                             (:file "syntax")
                             (:file "regex")
                             (:file "editor")
                             (:file "html")
                             (:file "scrollbar")
                             (:file "table")
                             (:file "dialogs")
                             (:file "help")
                             (:file "status-bar") ; the desktop's bottom bar + tool notes
                             (:file "menu-bar")   ; the desktop's pull-down menu bar
                             (:file "themes")     ; the built-in colour palettes + switching
                             (:file "desktop")    ; the IDE shell: windows, Z-order, the event loop
                             (:file "emoji")
                             (:file "reference")
                             (:file "reflection")))))
