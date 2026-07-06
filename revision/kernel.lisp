;;;; kernel.lisp --- the revision kernel: reactive metaclass, views, class events,
;;;; keymaps, commands, and the (view x event) dispatch protocol.

(in-package #:revision)

;;; ---------------------------------------------------------------------------
;;; Reactive metaclass: mutating any slot of a reactive instance invalidates the
;;; screen, so views never call DRAW on themselves -- the loop commits one frame
;;; per iteration.  An :AROUND method on (SETF SLOT-VALUE-USING-CLASS) invalidates
;;; only on a *changed* value (writing a slot back to its current EQL value is a
;;; no-op, so per-frame bookkeeping like WINDOW-ACTIVE doesn't perpetually re-dirty
;;; the screen), and records WHICH view changed so the loop can repaint just the
;;; affected top window (INVALIDATE / *DIRTY-VIEWS*) instead of the whole desktop.
;;; ---------------------------------------------------------------------------

(defclass reactive-class (standard-class) ()
  (:documentation "Metaclass whose instances invalidate the screen when a slot write CHANGES
its value: an :around method on (SETF SLOT-VALUE-USING-CLASS) calls INVALIDATE, so views
never repaint themselves -- mutating reactive state schedules one committed frame on the
next loop, and a no-op write (same EQL value) schedules nothing."))
(defmethod sb-mop:validate-superclass ((c reactive-class) (s standard-class)) t)

(defvar *dirty* nil "Set when reactive state changed since the last frame.")
(defvar *root* nil "The current top-level window (the modal background).")
(defvar *dirty-views* nil
  "Views invalidated since the last committed frame.  When every entry lives inside the
current top window (and nothing structural changed), the loop repaints just that window
instead of the whole desktop -- see the desktop loop's partial-frame path.")
(defvar *full-redraw* t
  "Forces the next commit to repaint the whole tree (reset after each frame).  Set by any
invalidation the partial path can't localize: a non-view change, or a BOUNDS change (which
can vacate cells a partial repaint would leave stale).")

(defun invalidate (&optional object slot)
  "Mark the UI dirty so the event loop commits a fresh frame next iteration.  When OBJECT
is a VIEW whose geometry did not change, record it for a partial repaint (only the affected
top window is redrawn); anything else -- a non-view, or a BOUNDS change that can vacate
cells -- forces a full-screen redraw.  SLOT is the changed slot's name (NIL from explicit
callers, which are treated as a localizable view change)."
  (setf *dirty* t)
  (cond ((not (typep object 'view)) (setf *full-redraw* t))
        ((eq slot 'bounds)          (setf *full-redraw* t))
        (t (pushnew object *dirty-views* :test #'eq))))

(defmethod (setf sb-mop:slot-value-using-class) :around
    (new (class reactive-class) object slot)
  (let* ((bound (sb-mop:slot-boundp-using-class class object slot))
         (old   (and bound (sb-mop:slot-value-using-class class object slot))))
    (prog1 (call-next-method)
      (unless (and bound (eql old new))        ; a no-op write (same value) schedules no frame
        (invalidate object (sb-mop:slot-definition-name slot))))))

;;; ---------------------------------------------------------------------------
;;; Views.  Bounds reuse revision's TRECT; capabilities would be mixins -- here we
;;; only need the base + OUTLINE.
;;; ---------------------------------------------------------------------------

(defclass view ()
  ((bounds :initarg :bounds :initform nil :accessor view-bounds
           :documentation "The view's screen rectangle (a revision TRECT), assigned by LAYOUT.")
   (owner  :initarg :owner  :initform nil :accessor view-owner
           :documentation "The containing view (NIL for a root window); walk it up via VIEW-ROOT.")
   (name   :initarg :name   :initform nil :accessor view-name
           :documentation "Optional symbol identifying the view, used by FIND-VIEW lookups.")
   (keymap :initarg :keymap :initform nil :accessor view-keymap
           :documentation "The view's KEYMAP (or NIL); its chain turns key events into commands."))
  (:metaclass reactive-class)
  (:documentation "Root of the view hierarchy: a rectangular region that draws itself and
handles events.  A reactive instance, so mutating a slot repaints; subclasses add HANDLE-EVENT
and DRAW methods.  CONTAINER extends it with subviews."))

(defgeneric draw (view)
  (:documentation "Render VIEW into the screen back buffer, within its bounds."))

(defgeneric layout (view rect)
  (:documentation "Assign VIEW (and its subtree) bounds within RECT.")
  (:method ((v view) rect) (setf (view-bounds v) rect)))

;;; geometry shorthands over revision's TRECT
(defun rect (x0 y0 x1 y1)
  "Construct a rectangle spanning the half-open range (X0,Y0) inclusive to (X1,Y1) exclusive."
  (revision::make-trect x0 y0 x1 y1))
(defun r-x0 (r) (revision::rect-ax r))   (defun r-y0 (r) (revision::rect-ay r))
(defun r-x1 (r) (revision::rect-bx r))   (defun r-y1 (r) (revision::rect-by r))
(defun r-w  (r) (revision::rect-width r)) (defun r-h (r) (revision::rect-height r))

;;; ---------------------------------------------------------------------------
;;; Events as a class hierarchy -- dispatched on (view x event), no type tags.
;;; ---------------------------------------------------------------------------

(defclass event ()
  ((handled :initform nil :accessor handled-p
            :documentation "Set true once a HANDLE-EVENT method consumes the event, stopping bubbling."))
  (:documentation "Base class for input/system events dispatched to views via HANDLE-EVENT."))
(defclass key-event (event)
  ((keysym    :initarg :keysym    :reader event-keysym
              :documentation "The key: a character, or a keyword for a special key (:up :enter :f1 …).")
   (modifiers :initarg :modifiers :initform 0 :reader event-modifiers
              :documentation "Bitmask of held modifiers (+MD-CTRL+ / +MD-ALT+ / +MD-SHIFT+)."))
  (:documentation "A key-press event; its (KEYSYM . MODIFIERS) form the token matched against keymaps."))
(defclass mouse-event (event)
  ((where   :initarg :where   :reader event-where
            :documentation "Cell position of the pointer (a TPOINT in screen coordinates).")
   (buttons :initarg :buttons :initform 0 :reader event-buttons))
  (:documentation "Base class for mouse events; EVENT-WHERE gives the pointer's cell position."))
(defclass mouse-down (mouse-event) ((double :initarg :double :initform nil :reader event-double))
  (:documentation "A mouse button-press event (EVENT-DOUBLE is true for the 2nd click of a double-click)."))
(defclass mouse-up   (mouse-event) ())
(defclass mouse-move (mouse-event) ())
(defclass wheel-event (mouse-event) ((delta :initarg :delta :reader event-delta
                                            :documentation "Scroll amount/direction (negative = up, positive = down)."))
  (:documentation "A mouse-wheel scroll event; EVENT-DELTA gives the scroll direction and magnitude."))
(defclass command-event (event) ((command :initarg :command :reader event-command)))
(defclass broadcast-event (event)
  ((id :initarg :id :reader event-id) (info :initarg :info :initform nil :reader event-info)))
(defclass idle-event (event) ())

;;; ---------------------------------------------------------------------------
;;; Keymaps: input bindings are *data* (layered, introspectable, rebindable).
;;; A binding maps a keysym -> a command name (symbol).
;;; ---------------------------------------------------------------------------

(defclass keymap ()
  ((parent   :initarg :parent :initform nil :reader keymap-parent
             :documentation "Fallback keymap consulted when a token is unbound here (the inheritance chain).")
   (bindings :initform (make-hash-table :test 'equal) :reader keymap-bindings))
  (:documentation "A layer of input bindings mapping (KEYSYM . MODS) tokens to command names,
with an optional PARENT for inheritance.  Bindings are data -- introspectable and rebindable."))

;;; A binding key normalises to a (KEYSYM . MODS) token.  Terminals deliver a
;;; Ctrl-letter as a control character (code 1-26) that already carries +md-ctrl+
;;; (see PARSE-PLAIN-BYTE), so fold that in; a (KEYSYM . MODS) cons is taken as-is
;;; and a bare keysym has no modifiers.  This is the SAME token the menu
;;; accelerators use (ACCEL-KEY / ACCEL-MODS), so one representation drives both.
(defun %key-mods (spec)
  (cond ((consp spec) (cdr spec))
        ((and (characterp spec) (<= 1 (char-code spec) 26)) +md-ctrl+)
        (t 0)))
(defun key-token (spec)
  "Canonical (KEYSYM . MODS) for a binding spec (a keysym, a control char, or an
already-formed (KEYSYM . MODS) cons)."
  (cons (if (consp spec) (car spec) spec) (%key-mods spec)))

(defun bind-key (km spec command)
  "Bind SPEC (a keysym, a control char, or a (KEYSYM . MODS) cons) to command name COMMAND
in keymap KM, normalising SPEC to its canonical token first."
  (setf (gethash (key-token spec) (keymap-bindings km)) command))

(defun %km-get (km token)
  (and km (or (gethash token (keymap-bindings km)) (%km-get (keymap-parent km) token))))

(defun keymap-lookup (km keysym &optional (mods 0) loose)
  "Command bound to KEYSYM+MODS in KM's chain.  Exact (keysym . mods) match by default.
With LOOSE true, fall back to a modifier-insensitive (keysym . 0) binding when there is
no exact match -- OFF by default, so a plain binding no longer silently swallows its
modified variants (Ctrl-/Shift-<key> only fires a binding made for it)."
  (or (%km-get km (cons keysym mods))
      (and loose (plusp mods) (%km-get km (cons keysym 0)))))

(defun ctrl (ch)
  "A binding spec for Ctrl-CH: the (KEYSYM . MODS) cons (CH . +md-ctrl+).  Ctrl lives
in the modifier bits -- TRANSLATE normalises the control char terminals send to this
form -- so e.g. (ctrl #\\o) matches the same token the driver produces for Ctrl-O."
  (cons (char-downcase ch) revision::+md-ctrl+))

(defmacro defkeymap (name (&optional parent) &body bindings)
  "Define a keymap NAME (optionally inheriting PARENT) from (KEYSYM COMMAND) pairs."
  `(defparameter ,name
     (let ((km (make-instance 'keymap :parent ,parent)))
       ,@(loop for (k c) in bindings collect `(bind-key km ,k ',c))
       km)))

;;; ---------------------------------------------------------------------------
;;; Commands: behaviour is an object (with a reactive ENABLED slot, so disabling
;;; one auto-repaints anything that shows it), not an integer + a central COND.
;;; ---------------------------------------------------------------------------

(defclass command ()
  ((name    :initarg :name    :reader command-name
            :documentation "The symbol naming this command (its key in *COMMANDS* and in keymaps).")
   (action  :initarg :action  :reader command-action)
   (doc     :initarg :doc     :initform nil :reader command-doc)      ; one-line description (see DEFINE-COMMAND)
   (source  :initarg :source  :initform nil :reader command-source)  ; defining file (cross-file collision detection)
   (enabled :initarg :enabled :initform t   :accessor command-enabled))  ; boolean, or a predicate thunk
  (:metaclass reactive-class)
  (:documentation "A named, reactive unit of behaviour: an ACTION closure over (VIEW EVENT) plus
an ENABLED flag.  Reactive, so toggling ENABLED auto-repaints menus/buttons that show it.
Invoked by name through PERFORM; keymaps and menus reference commands by NAME."))

(defun command-enabled-p (command)
  "Is COMMAND enabled right now?  ENABLED is a boolean, or a predicate thunk evaluated
on demand -- the single enablement check used by PERFORM (and available to menus /
buttons), so a guarded command no longer needs a second, hand-rolled check."
  (let ((e (command-enabled command))) (if (functionp e) (funcall e) e)))

(defvar *commands* (make-hash-table) "Name -> COMMAND object.")

(defun register-command (name action &optional doc (enabled t))
  "Register command NAME (ENABLED may be a boolean or a predicate thunk).  Warns if NAME
is redefined from a DIFFERENT source file -- an accidental cross-file collision.  A live
redefinition from the same file, or from the REPL (source NIL), is silent, so redefining
a command interactively still works."
  (let ((src (or *compile-file-truename* *load-truename*))       ; NIL when evaluated at the REPL
        (old (gethash name *commands*)))
    (when (and old src (command-source old) (not (equal src (command-source old))))
      (warn "revision: command ~s redefined in ~a (first defined in ~a)"
            name (file-namestring src) (file-namestring (command-source old))))
    (setf (gethash name *commands*)
          (make-instance 'command :name name :action action :doc doc :source src :enabled enabled))))

(defmacro define-command (name (view event) &body body)
  "Define and register command NAME with an action over (VIEW EVENT).  A leading
string in BODY (with forms following it) becomes the command's :DOC -- a one-line
description surfaced in the generated keybinding reference."
  (let ((doc (when (and (stringp (first body)) (rest body)) (pop body))))
    `(register-command ',name
                       (lambda (,view ,event) (declare (ignorable ,view ,event)) ,@body)
                       ,doc)))

(defgeneric perform (command view event)
  (:documentation "Run COMMAND (a command object or its name) for VIEW/EVENT.")
  (:method ((c command) view event)
    (when (command-enabled-p c) (funcall (command-action c) view event)))
  (:method ((c symbol) view event)
    (let ((cmd (gethash c *commands*)))
      (if cmd (perform cmd view event)
          (error "PERFORM: no command named ~s -- a keymap or menu binding typo?" c)))))

;;; ---------------------------------------------------------------------------
;;; Dispatch: handle-event is a multimethod on (view x event).  The base view
;;; turns a key into a command via its keymap chain; everything else is methods.
;;; ---------------------------------------------------------------------------

(defgeneric handle-event (view event)
  (:documentation "Dispatch EVENT to VIEW: the core (view x event) multimethod protocol.  The base
VIEW turns a key event into a command via its keymap chain; subclasses add methods and set
HANDLED-P once they consume it.  The default method ignores the event.")
  (:method ((v view) (e event)) nil))

(defmethod handle-event ((v view) (e key-event))
  (let ((cmd (keymap-lookup (view-keymap v) (event-keysym e) (event-modifiers e))))
    (when cmd (perform cmd v e) (setf (handled-p e) t))))

;;; ---------------------------------------------------------------------------
;;; Drawing helpers (write packed cells straight to revision's back buffer,
;;; clipped to the view's bounds).
;;; ---------------------------------------------------------------------------

(defun %put-code (x y code attr)
  "Like %PUT-CELL but writes a raw character CODE (e.g. revision::+wide-cont+, the
sentinel marking the second cell of a double-width glyph)."
  (when revision:*screen*
    (revision:screen-cell-set revision:*screen* x y (revision::cell-make-code code attr))))

(defun %put-cell (x y char attr) (%put-code x y (char-code char) attr))

(defun draw-text (view col row string attr)
  "Write STRING at view-local (COL,ROW), clipped to VIEW's width.  Grapheme-aware:
a multi-code-point cluster (skin-tone / ZWJ emoji, combining marks) is interned as
one display unit, and a double-width glyph reserves its second cell with the
+wide-cont+ sentinel (so the flush doesn't overwrite its right half)."
  (let* ((b (view-bounds view))
         (ax (revision::rect-ax b)) (gy (+ (revision::rect-ay b) row))
         (w (revision::rect-width b))
         (n (length string)) (i 0) (x col))
    (loop while (and (< i n) (< x w)) do
      (let* ((j (revision::next-grapheme-col string i))       ; end of the grapheme at I
             (g (subseq string i j))
             (code (if (= (- j i) 1) (char-code (char string i)) (revision::intern-grapheme g)))
             (cw (max 1 (revision::grapheme-width g))))
        (%put-code (+ ax x) gy code attr)
        (when (and (= cw 2) (< (1+ x) w))                     ; wide glyph: reserve the 2nd cell
          (%put-code (+ ax x 1) gy revision::+wide-cont+ attr))
        (setf i j) (incf x cw)))))

(defun %hclip (s hl) (if (< hl (length s)) (subseq s hl) ""))   ; drop HL leading columns (horizontal scroll)

(defun fill-row (view col row width attr)
  (let* ((b (view-bounds view))
         (gx (+ (revision::rect-ax b) col)) (gy (+ (revision::rect-ay b) row)))
    (dotimes (i width) (%put-cell (+ gx i) gy #\Space attr))))

;;; ---------------------------------------------------------------------------
;;; Terminal -> revision event translation.  Reuse revision's escape-sequence decoder;
;;; map its key codes to keysyms (special keys -> keywords, printable -> chars).
;;; ---------------------------------------------------------------------------

(defparameter *special-keys*
  (list (cons +kb-up+ :up)     (cons +kb-down+ :down)
        (cons +kb-left+ :left) (cons +kb-right+ :right)
        (cons +kb-enter+ :enter) (cons +kb-esc+ :esc)
        (cons +kb-home+ :home) (cons +kb-end+ :end)
        (cons +kb-pgup+ :pgup) (cons +kb-pgdn+ :pgdn)
        (cons +kb-tab+ :tab)   (cons +kb-shift-tab+ :shift-tab)
        (cons revision::+kb-back+ :back) (cons revision::+kb-del+ :del)
        (cons revision::+kb-ins+ :ins)
        (cons revision::+kb-f1+ :f1) (cons revision::+kb-f2+ :f2) (cons revision::+kb-f3+ :f3)
        (cons revision::+kb-f4+ :f4) (cons revision::+kb-f5+ :f5) (cons revision::+kb-f6+ :f6)
        (cons revision::+kb-f7+ :f7) (cons revision::+kb-f8+ :f8) (cons revision::+kb-f9+ :f9)
        (cons revision::+kb-f10+ :f10)))

(defun translate (tev)
  "Translate a revision event struct into a revision event object, or NIL to ignore."
  (let ((ty (revision::iev-type tev)))
    (cond
      ((= ty +ev-key-down+)
       (let* ((k (revision::iev-key-code tev)) (c (revision::iev-char-code tev))
              (m (revision::iev-modifiers tev))
              (ks (or (cdr (assoc k *special-keys*)) (and (plusp c) (code-char c)))))
         ;; Normalise a Ctrl-letter: terminals deliver it as a control character
         ;; (code 1-26); present it as the base letter with +md-ctrl+, so Ctrl lives
         ;; only in the modifiers -- one encoding, like Shift+Del or Alt-X.
         (when (and (characterp ks) (<= 1 (char-code ks) 26))
           (setf ks (code-char (+ (char-code ks) 96))
                 m  (logior m revision::+md-ctrl+)))
         (and ks (make-instance 'key-event :keysym ks :modifiers m))))
      ((= ty +ev-mouse-wheel+)
       (make-instance 'wheel-event :delta (revision::iev-wheel tev) :where (%where tev)))
      ((= ty revision::+ev-mouse-down+)
       (make-instance 'mouse-down :where (%where tev) :buttons (revision::iev-mouse-buttons tev)))
      ((= ty revision::+ev-mouse-up+)
       (make-instance 'mouse-up :where (%where tev) :buttons (revision::iev-mouse-buttons tev)))
      ((member ty (list revision::+ev-mouse-move+ revision::+ev-mouse-auto+))
       (make-instance 'mouse-move :where (%where tev) :buttons (revision::iev-mouse-buttons tev)))
      (t nil))))

(defun %where (tev)
  "Mouse position of TEV as a (X . Y) cons in screen coordinates."
  (let ((p (revision::iev-mouse-where tev)))
    (cons (revision::point-x p) (revision::point-y p))))

;;; ---------------------------------------------------------------------------
;;; Theming: colours are named roles resolved through *THEME* (a plist), instead
;;; of byte palettes walked up the owner chain.
;;; ---------------------------------------------------------------------------

;;; The classic Turbo Vision "blue window / grey dialog" palette (VGA 16-colour,
;;; IRGB order: 0 blk 1 blu 2 grn 3 cyn 4 red 5 mag 6 brn 7 lgray …).
(defparameter *theme*
  (list :normal          (revision:make-attr 7 1)     ; light grey on blue (window text)
        :focused         (revision:make-attr 15 3)    ; white on cyan (selected row)
        :frame           (revision:make-attr 15 1)    ; bright white on blue (active window)
        :frame-inactive  (revision:make-attr 7 1)     ; light grey on blue (background window)
        :menu-bar        (revision:make-attr 0 7)     ; black on light-grey (the menu bar)
        :menu            (revision:make-attr 0 7)     ; black on light-grey (dropdown)
        :menu-selected   (revision:make-attr 15 2)    ; white on green (highlighted item)
        :menu-hotkey     (revision:make-attr 4 7)     ; red on light-grey (Alt-hotkey letter)
        :menu-disabled   (revision:make-attr 8 7)     ; dim grey on light-grey
        :status          (revision:make-attr 0 3)     ; black on cyan (status line)
        :button          (revision:make-attr 15 2)    ; white on green (button)
        :button-focused  (revision:make-attr 14 2)    ; yellow on green (focused/default button)
        :label           (revision:make-attr 14 1)    ; yellow on blue
        :input           (revision:make-attr 0 3)     ; black on cyan (input field)
        :input-focused   (revision:make-attr 15 3)    ; white on cyan
        :error           (revision:make-attr 15 4)    ; white on red
        :desktop         (revision:make-attr 8 1)     ; dim ░ pattern on blue (the desktop)
        :scrollbar       (revision:make-attr 0 3)     ; scrollbar track + arrows + corners: black on cyan (classic TV)
        :scrollbar-thumb (revision:make-attr 14 3))   ; the position indicator █: yellow on cyan
  "Role -> packed attribute.")

;;; The classic "grey dialog" palette, bound over *THEME* while a dialog and its
;;; children draw, so dialogs read grey instead of the blue window scheme.
(defparameter *dialog-theme*
  (list :normal          (revision:make-attr 0 7)     ; black on light-grey
        :focused         (revision:make-attr 15 3)    ; white on cyan
        :frame           (revision:make-attr 0 7)     ; black on light-grey (active)
        :frame-inactive  (revision:make-attr 8 7)     ; dim grey on light-grey
        :menu-bar        (revision:make-attr 0 7)
        :menu            (revision:make-attr 0 7)
        :menu-selected   (revision:make-attr 15 2)
        :menu-hotkey     (revision:make-attr 4 7)
        :menu-disabled   (revision:make-attr 8 7)
        :status          (revision:make-attr 0 7)     ; dialog help text on grey
        :button          (revision:make-attr 15 2)    ; green button
        :button-focused  (revision:make-attr 14 2)    ; yellow on green (default)
        :label           (revision:make-attr 0 7)     ; black on light-grey
        :input           (revision:make-attr 0 3)     ; black on cyan (input field)
        :input-focused   (revision:make-attr 15 3)    ; white on cyan
        :error           (revision:make-attr 15 4)    ; white on red
        :desktop         (revision:make-attr 8 1)
        :scrollbar       (revision:make-attr 8 7)
        :scrollbar-thumb (revision:make-attr 0 7))
  "Role -> attribute while a DIALOG draws (the grey-dialog palette).")

(defun role (key)
  "The colour attribute the current *THEME* assigns to the semantic role KEY (e.g. :normal,
:focused, :status, :frame), or a plain grey-on-black default when the role is unset."
  (or (getf *theme* key) (revision:make-attr 7 0)))

;;; ---------------------------------------------------------------------------
;;; Chrome helpers (box, centred text).
;;; ---------------------------------------------------------------------------

(defun %box (x0 y0 x1 y1 attr &optional double)
  "Draw a box; DOUBLE uses the ═║╔╗╚╝ line set (classic active window), else ─│┌┐."
  (multiple-value-bind (tl hz tr vt bl br)
      (if double (values #\╔ #\═ #\╗ #\║ #\╚ #\╝) (values #\┌ #\─ #\┐ #\│ #\└ #\┘))
    (%put-cell x0 y0 tl attr) (%put-cell x1 y0 tr attr)
    (%put-cell x0 y1 bl attr) (%put-cell x1 y1 br attr)
    (loop for x from (1+ x0) below x1 do (%put-cell x y0 hz attr) (%put-cell x y1 hz attr))
    (loop for y from (1+ y0) below y1 do (%put-cell x0 y vt attr) (%put-cell x1 y vt attr))))

(defun %darken-cell (x y)
  "Darken the back-buffer cell at (X,Y), keeping its glyph -- one drop-shadow cell."
  (let ((s revision:*screen*))
    (when (and s (>= x 0) (< x (revision:screen-width s)) (>= y 0) (< y (revision:screen-height s)))
      (let* ((back (revision::screen-back s)) (idx (+ x (* y (revision:screen-width s)))))
        (setf (aref back idx)
              (revision::cell-make-code (revision::cell-char-code (aref back idx)) (revision:make-attr 8 0)))))))

(defun %drop-shadow (x0 y0 x1 y1)
  "Paint a Turbo-Vision drop shadow: two columns down the right edge, one row
along the bottom, offset one cell past the (X0,Y0)-(X1,Y1) box."
  (loop for y from (1+ y0) to (1+ y1) do (%darken-cell (1+ x1) y) (%darken-cell (+ x1 2) y))
  (loop for x from (+ x0 2) to (+ x1 2) do (%darken-cell x (1+ y1))))

(defun %text-at (x y string attr)
  (loop for i below (length string) do (%put-cell (+ x i) y (char string i) attr)))

;;; A scrollable view answers this protocol; a window draws a scrollbar bound to
;;; its SCROLL-TARGET, and the desktop maps clicks/drags on it to SCROLL-TO.
(defgeneric scroll-pos  (v) (:documentation "First visible row (the scroll offset)."))
(defgeneric scroll-max  (v) (:documentation "Maximum scroll offset (>= 0)."))
(defgeneric scroll-page (v) (:documentation "Number of visible rows."))
(defgeneric scroll-to   (v pos) (:documentation "Set the offset (clamped) and repaint."))

;;; The horizontal counterpart; a view with SCROLL-HMAX > 0 gets a bottom
;;; scrollbar too.  Default: no horizontal scrolling.
(defgeneric scroll-hpos  (v) (:method (v) (declare (ignore v)) 0))
(defgeneric scroll-hmax  (v) (:method (v) (declare (ignore v)) 0))
(defgeneric scroll-hpage (v) (:method (v) (declare (ignore v)) 1))
(defgeneric scroll-hto   (v pos) (:method (v pos) (declare (ignore v pos)) nil))

;;; Context-sensitive status-bar chips: a focused view may offer (LABEL . THUNK)
;;; actions the desktop appends to the status line.  Default: none.
(defgeneric status-hints (view)
  (:method (v) (declare (ignore v)) nil)
  (:documentation "The (LABEL . THUNK) action chips the focused VIEW contributes to the desktop status
bar; specialize to offer context actions.  Default: none."))

(defun draw-vscroll (x y0 y1 pos max)
  "Draw a vertical scrollbar in column X with arrows at rows Y0 (▲) and Y1 (▼)
and a thumb positioned by POS/MAX over the track between them."
  (let ((bar (role :scrollbar)) (thumb (role :scrollbar-thumb)))
    (when (> y1 y0)
      (%put-cell x y0 #\▲ bar)                        ; arrows share the track colour (classic TV)
      (%put-cell x y1 #\▼ bar)
      (let ((track (- y1 y0 1)))                       ; inner rows y0+1 .. y1-1
        (loop for r from 1 below (- y1 y0) do (%put-cell x (+ y0 r) #\▒ bar))
        (when (and (plusp max) (plusp track))
          (%put-cell x (+ y0 1 (max 0 (min (1- track) (floor (* pos (1- track)) max)))) #\█ thumb))))))

(defun draw-hscroll (y x0 x1 pos max)
  "Draw a horizontal scrollbar in row Y with arrows at cols X0 (◄) and X1 (►)
and a thumb positioned by POS/MAX over the track between them."
  (let ((bar (role :scrollbar)) (thumb (role :scrollbar-thumb)))
    (when (> x1 x0)
      (%put-cell x0 y #\◄ bar)                        ; arrows share the track colour (classic TV)
      (%put-cell x1 y #\► bar)
      (let ((track (- x1 x0 1)))                       ; inner cols x0+1 .. x1-1
        (loop for c from 1 below (- x1 x0) do (%put-cell (+ x0 c) y #\▒ bar))
        (when (and (plusp max) (plusp track))
          (%put-cell (+ x0 1 (max 0 (min (1- track) (floor (* pos (1- track)) max)))) y #\█ thumb))))))

;;; ---------------------------------------------------------------------------
;;; Focus + containers.  FOCUSABLE-P is a protocol GF (default NIL); a container
;;; routes key events to its focused child, handles Tab/Shift-Tab itself, and
;;; bubbles anything unhandled to its own keymap via CALL-NEXT-METHOD.
;;; ---------------------------------------------------------------------------

(defgeneric focusable-p (view)
  (:documentation "True if VIEW can hold keyboard focus (a focusable leaf).  Default NIL; interactive
widgets override it, and containers use it to enumerate focus stops.")
  (:method ((v view)) nil))

(defclass container (view)
  ((subviews :initform '() :accessor subviews
             :documentation "Child views in paint order (last paints on top); see ADD-SUBVIEW.")
   (focus    :initform nil :accessor container-focus       ; the focused leaf, anywhere below (root only)
             :documentation "On the root window, the focused focusable leaf anywhere in the subtree (else NIL)."))
  (:documentation "A VIEW that holds SUBVIEWS: it draws each child, routes key events to its focused
leaf, handles Tab/Shift-Tab focus movement, and hit-tests mouse events down the tree.  On the
root window CONTAINER-FOCUS names the focused leaf anywhere in the subtree.")
  (:metaclass reactive-class))

(defun add-subview (c v)
  "Add view V as a child of container C (appended last, so it paints on top) and set V's
owner to C.  Returns V."
  (setf (view-owner v) c
        (subviews c) (append (subviews c) (list v)))
  v)

(defun view-root (v)
  "The topmost owner of V (the root window): follow VIEW-OWNER up until it is NIL."
  (if (view-owner v) (view-root (view-owner v)) v))

(defun view-name= (a b)
  "Compare two view-name designators by NAME, not object identity, so a name interned
in a different package still matches -- e.g. an application's 'EDIT and the framework's
'EDIT name the same view.  (EQL on symbols is package-sensitive, which silently made
FIND-VIEW return NIL across packages; comparing SYMBOL-NAMEs removes that footgun.)"
  (cond ((or (null a) (null b)) nil)
        ((and (typep a '(or symbol string character))
              (typep b '(or symbol string character)))
         (string= (string a) (string b)))
        (t (eql a b))))

(defun find-view (root name)
  "Depth-first search for the subview named NAME, or NIL.  Names match by NAME string
\(see VIEW-NAME=), so a lookup works even when NAME is interned in another package."
  (cond ((view-name= (view-name root) name) root)
        ((typep root 'container) (some (lambda (sv) (find-view sv name)) (subviews root)))
        (t nil)))

(defun view-focused-p (v)
  "True when V is the focused widget of its root window."
  (let ((r (view-root v))) (and (typep r 'container) (eq v (container-focus r)))))

;;; Focus is a *window-level* property over every focusable leaf in the subtree,
;;; so nested layout containers don't each need their own focus management.
(defun all-focusables (v)
  "List every focusable leaf in V's subtree, in depth-first paint order -- the window's
Tab order.  Flattens nested layout containers so focus is a window-level property."
  (cond ((focusable-p v) (list v))
        ((typep v 'container) (mapcan #'all-focusables (subviews v)))
        (t nil)))

(defun focus-next (root &optional (dir 1))
  "Move ROOT's focus to the next focusable leaf, cycling; DIR 1 advances (Tab), -1 goes
back (Shift-Tab).  No-op when there are no focusable leaves."
  (let ((fs (all-focusables root)))
    (when fs
      (let ((cur (or (position (container-focus root) fs) 0)))
        (setf (container-focus root) (nth (mod (+ cur dir) (length fs)) fs))))))

(defmethod draw ((c container))
  (dolist (sv (subviews c)) (draw sv)))

(defmethod handle-event ((c container) (e key-event))
  (let ((ks (event-keysym e)))
    (cond
      ((and (logtest (event-modifiers e) revision::+md-alt+) (characterp ks)   ; Alt-<label mnemonic>
            (%dispatch-label-hotkey c ks))
       (setf (handled-p e) t))
      ((eql ks :tab)       (focus-next c 1)  (setf (handled-p e) t))
      ((eql ks :shift-tab) (focus-next c -1) (setf (handled-p e) t))
      (t (let ((f (container-focus c))) (when f (handle-event f e)))   ; -> the focused leaf
         (unless (handled-p e) (call-next-method))))))                 ; -> container's keymap

;;; ---------------------------------------------------------------------------
;;; Mouse: events carry a screen point; dispatch hit-tests the view tree top-down
;;; to the deepest view under the pointer, and a click also focuses it.
;;; ---------------------------------------------------------------------------

(defun point-in-rect-p (x y r)
  (and r (<= (revision::rect-ax r) x) (< x (revision::rect-bx r))
       (<= (revision::rect-ay r) y) (< y (revision::rect-by r))))

(defun view-at (root x y)
  "The deepest view in ROOT's subtree whose bounds contain (X,Y), or NIL.
Children are tested front-to-back (last added paints on top)."
  (when (point-in-rect-p x y (view-bounds root))
    (or (and (typep root 'container)
             (loop for sv in (reverse (subviews root))
                   for hit = (view-at sv x y) when hit return hit))
        root)))

(defun mouse-col (view e) (- (car (event-where e)) (revision::rect-ax (view-bounds view))))
(defun mouse-row (view e) (- (cdr (event-where e)) (revision::rect-ay (view-bounds view))))

(defmethod handle-event ((v view) (e mouse-event)) nil)         ; default: ignore

(defmethod handle-event ((c container) (e mouse-event))
  (let* ((w (event-where e)) (hit (and w (view-at c (car w) (cdr w)))))
    (when (and hit (not (eq hit c)))
      (when (and (typep e 'mouse-down) (focusable-p hit))
        (setf (container-focus (view-root hit)) hit))             ; click focuses
      (handle-event hit e))))
