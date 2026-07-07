;;;; desktop.lisp --- the IDE shell: a menu bar, a status bar, and a desktop that
;;;; hosts the ported windows.  This is the classic Turbo Vision chrome that the
;;;; standalone windows lacked.
;;;;
;;;; One screen, one event loop.  The desktop draws a patterned background, the
;;;; active window (laid out *between* the bars), the bottom status bar, and the
;;;; top menu bar (its dropdown overlays everything).  The menu is "live" whenever
;;;; no window is open; opening a window from it hands the window focus, and Esc
;;;; closes the window back to the menu — so no F10/Alt key decoding is needed.

(in-package #:revision)

(defvar *app-done* nil "Set by File→Exit to leave the desktop loop.")
(defvar *desktop* nil "The running desktop instance (for cross-window actions like eval-in-REPL).")
(defvar *sizemove-win* nil
  "When set, the desktop routes arrow keys to move (Shift: resize) this window
until Enter/Esc.  Driven from Window ▸ Size/move.")

;;; The status bar (STATUS-BAR, the *TOOL-MESSAGE* infra, %TOOL-NOTE's note
;;; target) lives in status-bar.lisp; the menu bar in menu-bar.lisp.

(defun %partial-frame-p (dt views full)
  "True when this frame can repaint just the top window instead of the whole desktop:
nothing forced a full redraw, no dropdown is open (a menu overlays windows), and every
invalidated view lives inside the current top window -- so nothing behind or around it
changed and, being topmost in Z-order, nothing overlaps it."
  (and (not full) views
       (null (menu-active (dt-menubar dt)))
       (let ((top (dt-top dt)))
         (and top (every (lambda (v) (and (typep v 'view) (eq (view-root v) top))) views)))))

;;; --- the menu bar (MENU-BAR and its navigation) lives in menu-bar.lisp ---

;;; --- desktop ----------------------------------------------------------------

(defclass desktop (view)
  ((menubar   :accessor dt-menubar)
   (statusbar :accessor dt-statusbar)
   (windows   :initform '() :accessor dt-windows     ; back-to-front Z-order; last = topmost/focused
              :documentation "The hosted windows in back-to-front Z-order; the last is topmost/focused.")
   (drag      :initform nil :accessor dt-drag))       ; (:move WIN OFFX OFFY) | (:resize WIN) while dragging
  (:metaclass reactive-class)
  (:documentation "The IDE shell: a menu bar, a status bar, and a background hosting movable,
resizable, overlapping windows.  Owns the single event loop and window Z-order."))

(defun dt-top (dt)
  "The topmost (focused) window on desktop DT, or NIL when none are open."
  (car (last (dt-windows dt))))
(defun dt-raise (dt w)
  "Move window W to the top of desktop DT's Z-order, making it the focused window."
  (setf (dt-windows dt) (append (remove w (dt-windows dt)) (list w))))
(defun dt-content (dt)
  "The rectangle between the menu bar (row 0) and status bar (last row)."
  (let* ((r (view-bounds dt)) (ax (revision::rect-ax r)) (ay (revision::rect-ay r)) (w (r-w r)) (h (r-h r)))
    (rect ax (1+ ay) (+ ax w) (+ ay (1- h)))))

(defmethod layout ((dt desktop) r)
  (setf (view-bounds dt) r)
  (let ((ax (revision::rect-ax r)) (ay (revision::rect-ay r)) (w (r-w r)) (h (r-h r)))
    (layout (dt-menubar dt)   (rect ax ay (+ ax w) (+ ay 1)))
    (layout (dt-statusbar dt) (rect ax (+ ay (1- h)) (+ ax w) (+ ay h)))))

(defmethod draw ((dt desktop))
  (let* ((b (view-bounds dt)) (w (r-w b)) (h (r-h b))
         (ax (revision::rect-ax b)) (ay (revision::rect-ay b)) (bg (role :desktop)) (top (dt-top dt)))
    (loop for y from (1+ ay) below (+ ay (1- h)) do          ; patterned background
      (loop for x from ax below (+ ax w) do (%put-cell x y #\▒ bg)))
    (loop for win in (dt-windows dt) for i from 1 do        ; windows back-to-front, numbered 1..
      (setf (window-active win) (eq win top) (window-number win) i) (draw win))
    (draw (dt-statusbar dt))
    (draw (dt-menubar dt))))                                 ; menu + dropdown overlay everything

(defun dt-refocus (dt)
  "Keep the menu live only when no window is open."
  (setf (menu-active (dt-menubar dt)) (if (dt-windows dt) nil 0)
        (menu-sel (dt-menubar dt)) 0
        (menu-sub (dt-menubar dt)) nil))

;;; *window-builders* and *extra-menus* (the desktop plugin registry) are defined
;;; early in host.lisp; windows self-register their builders in their own files.

(defun dt-cascade-rect (dt)
  "A cascade-offset rectangle for the Nth window, kept *fully* on the desktop:
the size is capped to the content area, then the offset origin is shifted back
from the edge (rather than clamping the far corner and squashing the window)."
  (let* ((c (dt-content dt)) (n (length (dt-windows dt)))
         (cw (min (r-w c) (max 40 (floor (* (r-w c) 4) 5))))
         (ch (min (r-h c) (max 8  (floor (* (r-h c) 4) 5))))
         (ox (min (+ (revision::rect-ax c) (* (mod n 6) 3)) (- (revision::rect-bx c) cw)))
         (oy (min (+ (revision::rect-ay c) (* (mod n 6) 2)) (- (revision::rect-by c) ch))))
    (rect ox oy (+ ox cw) (+ oy ch))))

(defun dt-add (dt win focus open kind bounds)
  "Host WIN at BOUNDS, recording its KIND (a keyword or NIL) for save/restore."
  (layout win bounds)
  (setf (window-managed win) t (window-kind win) kind
        (container-focus win) (or focus (first (all-focusables win)))
        (window-cleanup win) (and open (funcall open revision:*screen*)))
  (setf (dt-windows dt) (append (dt-windows dt) (list win))))

(defun dt-open (dt kind-or-fn)
  "Open a window: KIND-OR-FN is a builder keyword (looked up in *WINDOW-BUILDERS*
and recorded so the layout can be saved/restored) or a builder function (used
directly, not persisted).  Cascade-positioned, focused on top."
  (let ((bounds (dt-cascade-rect dt)))
    (multiple-value-bind (win focus open)
        (funcall (if (functionp kind-or-fn) kind-or-fn (cdr (assoc kind-or-fn *window-builders*))))
      (when win
        (dt-add dt win focus open (and (keywordp kind-or-fn) kind-or-fn) bounds)
        (dt-refocus dt) (invalidate dt)))))

(defun dt-close-window (dt win)
  "Close WIN on desktop DT: run its cleanup, remove it from the Z-order, and refocus."
  (when (window-cleanup win) (ignoring-errors ("window cleanup") (funcall (window-cleanup win))))
  (setf (dt-windows dt) (remove win (dt-windows dt)))
  (dt-refocus dt) (invalidate dt))

(defun dt-next (dt)                                          ; cycle focus: top goes to the bottom
  (when (dt-windows dt)
    (setf (dt-windows dt) (cons (dt-top dt) (butlast (dt-windows dt))))
    (invalidate dt)))

(defun dt-zoom (dt win)
  "Toggle WIN between its size and filling the desktop content area (classic zoom)."
  (when (window-managed win)
    (if (window-zoomed win)
        (progn (when (window-saved-bounds win) (layout win (window-saved-bounds win)))
               (setf (window-zoomed win) nil))
        (progn (setf (window-saved-bounds win) (view-bounds win) (window-zoomed win) t)
               (layout win (dt-content dt))))
    (dt-raise dt win) (dt-refocus dt) (invalidate dt)))

(defun dt-select-number (dt n)
  "Raise + focus the Nth window (1-based z-order), if it exists."
  (let ((win (nth (1- n) (dt-windows dt))))
    (when win (dt-raise dt win) (dt-refocus dt) (invalidate dt))))

(defun dt-cascade (dt)
  (let ((c (dt-content dt)))
    (loop for win in (dt-windows dt) for i from 0
          for ox = (+ (revision::rect-ax c) (* i 3)) for oy = (+ (revision::rect-ay c) (* i 2))
          for cw = (max 40 (floor (* (r-w c) 4) 5)) for ch = (max 8 (floor (* (r-h c) 4) 5))
          do (layout win (rect ox oy (min (+ ox cw) (revision::rect-bx c)) (min (+ oy ch) (revision::rect-by c)))))
    (invalidate dt)))

(defun dt-tile (dt)
  (let* ((c (dt-content dt)) (n (length (dt-windows dt))))
    (when (plusp n)
      (let* ((cols (ceiling (sqrt n))) (rows (ceiling n cols))
             (cw (floor (r-w c) cols)) (ch (floor (r-h c) rows)))
        (loop for win in (dt-windows dt) for i from 0
              for cx = (mod i cols) for cy = (floor i cols)
              for x0 = (+ (revision::rect-ax c) (* cx cw)) for y0 = (+ (revision::rect-ay c) (* cy ch))
              do (layout win (rect x0 y0 (+ x0 cw) (+ y0 ch))))
        (invalidate dt)))))

(defun dt-help (dt)
  "Open help for the focused window's topic (or the contents page)."
  (let ((topic (if (dt-top dt) (window-help (dt-top dt)) :general)))
    (dt-open dt (lambda () (make-help topic)))))

(defun dt-prev (dt)                                         ; cycle focus backwards
  (when (dt-windows dt)
    (setf (dt-windows dt) (append (cdr (dt-windows dt)) (list (car (dt-windows dt)))))
    (invalidate dt)))

(defun %sizemove-step (dt win ks resize)
  "Move (or, when RESIZE, resize) WIN one cell for arrow key KS, clamped to the
desktop content area."
  (let* ((b (view-bounds win)) (c (dt-content dt))
         (ax (revision::rect-ax b)) (ay (revision::rect-ay b))
         (bx (revision::rect-bx b)) (by (revision::rect-by b))
         (cax (revision::rect-ax c)) (cay (revision::rect-ay c))
         (cbx (revision::rect-bx c)) (cby (revision::rect-by c)))
    (multiple-value-bind (dx dy)
        (case ks (:left (values -1 0)) (:right (values 1 0)) (:up (values 0 -1)) (:down (values 0 1)) (t (values 0 0)))
      (if resize
          (layout win (rect ax ay (max (+ ax 24) (min (+ bx dx) cbx)) (max (+ ay 5) (min (+ by dy) cby))))
          (let* ((ww (r-w b)) (hh (r-h b))
                 (nax (max cax (min (+ ax dx) (- cbx ww))))
                 (nay (max cay (min (+ ay dy) (- cby hh)))))
            (layout win (rect nax nay (+ nax ww) (+ nay hh)))))
      (invalidate dt))))

(defun %dt-window-list (dt)
  "A modal picker over the open windows; Enter raises + focuses the chosen one."
  (let ((wins (reverse (dt-windows dt))))                   ; top-first
    (if (null wins)
        (%tool-note "no windows open")
        (let* ((titles (loop for w in wins for i from 1
                             collect (format nil "~d. ~a" i (string-trim " " (window-title w)))))
               (d (ui (dialog (:title " Windows " :keymap *dialog-keys*
                               :value-fn (lambda (dd) (list-selected (find-view dd 'lst))))
                        (stack
                          (:fill (list-box :name 'lst :items titles))
                          (1 (static-text :role :status :text " ↑↓ choose · Enter: focus · Esc: cancel ")))))))
          (let ((r (exec-view d :width 54 :height (min 20 (+ 4 (length wins))))))
            (when (and (integerp r) (nth r wins))
              (dt-raise dt (nth r wins)) (dt-refocus dt) (invalidate dt)))))))

;;; --- File-menu actions on editors / the REPL --------------------------------

(defun %focused-te (dt)
  "The text-edit of the focused window, when it is an editor."
  (let ((top (dt-top dt))) (and (typep top 'editor-window) (find-view top 'edit))))

(defun %dt-repl (dt)
  "The most-recent REPL window on the desktop, or NIL — found by :kind, so the toolkit
needn't know the repl-window class (which lives in the application)."
  (find :repl (reverse (dt-windows dt)) :key #'window-kind))

(defun %tool-note (msg)
  "Show MSG as a transient status-bar note and log it to the REPL transcript, WITHOUT
raising or refocusing any window (so a tool action never yanks the REPL over the editor
you're working in).  With no REPL open (a bare toolkit desktop) it just shows the note."
  (setf *tool-message* msg *tool-message-time* (get-internal-real-time))
  (when *desktop*
    (ignore-errors (invalidate (dt-statusbar *desktop*)))
    (let ((r (%dt-repl *desktop*)))                          ; log to an existing REPL, in place
      (when r
        (let ((sb (find-view r 'transcript)))
          (when sb (scrollback-append sb (format nil "; ~a~%" msg))))))))

(defun %dt-save-as (dt)
  (let ((te (%focused-te dt)))
    (when te
      (let* ((cur (and (te-filename te) (te-filename te)))
             (p (make-file-dialog :mode :save
                                  :dir (if cur (uiop:pathname-directory-pathname cur) *project-dir*)
                                  :default-name (if cur (file-namestring cur) "untitled.lisp")
                                  :mask "*.lisp")))
        (when p (setf (te-filename te) p) (te-save te)
              (%tool-note (format nil "saved ~a" (file-namestring p))))))))

(defun %dt-save (dt)
  (let ((te (%focused-te dt)))
    (cond ((null te) (%tool-note "no editor focused"))
          ((te-filename te) (te-save te) (%tool-note (format nil "saved ~a" (file-namestring (te-filename te)))))
          (t (%dt-save-as dt)))))                           ; unnamed buffer -> prompt for a name

(defun %dt-save-all (dt)
  (let ((n 0))
    (dolist (w (dt-windows dt))
      (when (typep w 'editor-window)
        (let ((te (find-view w 'edit)))
          (when (and te (te-filename te) (te-modified te)) (te-save te) (incf n)))))
    (%tool-note (format nil "saved ~d modified buffer~:p" n))))

(defun %dt-reload (dt)
  (let ((te (%focused-te dt)))
    (cond ((or (null te) (null (te-filename te))) (%tool-note "no file to reload"))
          (t (te-load te (te-filename te)) (invalidate te) (%tool-note "reloaded from disk")))))

;;; %dt-save-transcript / %dt-save-script / %dt-clear-repl (REPL glue that drives the
;;; moved repl-window's save/clear ops) live in revl — see ide/desktop-ide.lisp.

;;; --- the colour palettes and APPLY-THEME / CYCLE-THEME live in themes.lisp ---


;;; The static global desktop keys as a keymap of named commands -- introspectable
;;; and in the generated reference.  (Alt-<hotkey>, Alt-0, Esc and size/move stay
;;; special in HANDLE-EVENT below: dynamic, context-sensitive, or a mode.)
(define-command select-window (dt e)
  "Raise/focus the Nth desktop window."
  (let ((d (digit-char-p (event-keysym e)))) (when d (dt-select-number dt d))))
(define-command zoom-window (dt e)
  "Zoom / unzoom the top window."
  (let ((top (dt-top dt))) (when top (dt-zoom dt top))))
(define-command help-window (dt e)
  "Contextual help for the focused window."
  (dt-help dt))

(defkeymap *desktop-keys* ()
  ((cons #\1 revision::+md-alt+) select-window) ((cons #\2 revision::+md-alt+) select-window)
  ((cons #\3 revision::+md-alt+) select-window) ((cons #\4 revision::+md-alt+) select-window)
  ((cons #\5 revision::+md-alt+) select-window) ((cons #\6 revision::+md-alt+) select-window)
  ((cons #\7 revision::+md-alt+) select-window) ((cons #\8 revision::+md-alt+) select-window)
  ((cons #\9 revision::+md-alt+) select-window)
  (:f5 zoom-window)
  (:f1 help-window))

;;; --- closing a window, prompting to save an unsaved editor first ------------

(defun %dialog-return (v result)
  "Finish the dialog owning view V with RESULT (used by the Save/Discard buttons)."
  (let ((d (view-root v))) (when (typep d 'dialog) (setf (dialog-result d) result (dialog-done d) t))))
(define-command %choose-save    (v e) (%dialog-return v :save))
(define-command %choose-discard (v e) (%dialog-return v :discard))

(defun %save-discard-cancel (name)
  "Modal Save / Discard / Cancel prompt for NAME's unsaved changes.  Returns :SAVE,
:DISCARD, or :CANCEL (Esc = :CANCEL)."
  (let ((d (ui (dialog (:title " Unsaved changes " :keymap *dialog-keys*)
                 (stack (1 (static-text :role :label
                             :text (format nil " ~a has unsaved changes. " (string-trim " " name))))
                        (:fill (static-text :text ""))
                        (1 (row (:fill (static-text :text ""))
                                (10 (button :label "Save"    :command '%choose-save))
                                (11 (button :label "Discard" :command '%choose-discard))
                                (10 (button :label "Cancel"  :command 'cancel))
                                (:fill (static-text :text "")))))))))
    (let ((r (exec-view d :width 60 :height 8))) (if (member r '(:save :discard)) r :cancel))))

(defun %window-save (dt win)
  "Save WIN's editor in place, or via Save-As for a scratch buffer.  Return T when it is
now saved (so the caller may close), NIL if the user cancelled the save."
  (let ((te (find-view win 'edit)))
    (cond ((null te) t)
          ((te-filename te) (te-save te) t)
          (t (dt-raise dt win) (dt-refocus dt)          ; focus it so %DT-SAVE-AS targets this editor
             (%dt-save-as dt) (not (te-modified te))))))  ; saved iff no longer modified

(defun %dt-request-close (dt win)
  "Close WIN, but when it holds unsaved changes first prompt Save / Discard / Cancel so an
editor is never silently discarded.  Return T when WIN was closed."
  (if (window-dirty-p win)
      (ecase (%save-discard-cancel (window-title win))
        (:save    (when (%window-save dt win) (dt-close-window dt win) t))
        (:discard (dt-close-window dt win) t)
        (:cancel  nil))
      (progn (dt-close-window dt win) t)))

(defmethod handle-event ((dt desktop) (e key-event))
  (let* ((mb (dt-menubar dt)) (top (dt-top dt)) (ks (event-keysym e))
         (mods (event-modifiers e)) (alt (logtest mods revision::+md-alt+))
         (gcmd (%km-get *desktop-keys* (cons ks mods))))       ; exact global-key match (no mod-insensitive fallback)
    (cond
      (*sizemove-win*                                        ; interactive keyboard size/move mode
       (cond ((member ks '(:enter :esc)) (setf *sizemove-win* nil) (%tool-note "size/move done"))
             ((member ks '(:up :down :left :right))
              (%sizemove-step dt *sizemove-win* ks (logtest mods revision::+md-shift+)))))
      ((and alt (eql ks #\0))                                ; Alt-0: window list — caught before the editor eats "0"
       (let ((cmd (menu-accel-command mb #\0 revision::+md-alt+))) (when cmd (perform cmd dt e))))
      ((and alt (characterp ks) (menu-hotkey-index mb ks))   ; Alt-<hotkey> opens that menu (dynamic)
       (setf (menu-active mb) (menu-hotkey-index mb ks) (menu-sel mb) 0) (invalidate mb))
      (gcmd (perform gcmd dt e))                             ; *desktop-keys*: Alt-1..9 select · F5 zoom · F1 help
      (top
       (cond
         ((and (eql ks :esc) (menu-active mb)) (setf (menu-active mb) nil) (invalidate mb))  ; close an open menu
         ((eql ks :esc)                                      ; Esc: dismiss a transient window; an editor is
          (if (window-esc-dismissable-p top)                ; never silently discarded -- prompt only if unsaved
              (dt-close-window dt top)
              (when (window-dirty-p top) (%dt-request-close dt top))))
         ((menu-active mb) (handle-event mb e))              ; a menu is open over the window -> it drives
         (t (setf *running* t) (handle-event top e)          ; otherwise the focused widget gets the key
            (cond ((not *running*) (dt-close-window dt top))
                  ((not (handled-p e))                       ; ignored -> try a global accelerator
                   (let ((cmd (menu-accel-command mb ks mods))) (when cmd (perform cmd dt e))))))))
      (t (let ((cmd (menu-accel-command mb ks mods)))         ; no window: accelerators first, then the menu
           (if cmd (perform cmd dt e) (handle-event mb e)))))))

(defun dt-window-at (dt x y)
  (loop for w in (reverse (dt-windows dt)) when (point-in-rect-p x y (view-bounds w)) return w))

(defun dt-drag-update (dt e)
  (let* ((d (dt-drag dt)) (win (second d)) (w (event-where e)) (mx (car w)) (my (cdr w)) (c (dt-content dt)))
    (cond
      ((typep e 'mouse-up) (setf (dt-drag dt) nil))
      ((typep e 'mouse-move)
       (let* ((b (view-bounds win)) (ax (revision::rect-ax b)) (ay (revision::rect-ay b)))
         (ecase (first d)
           (:move
            (let* ((ww (r-w b)) (hh (r-h b))
                   (nx (max (revision::rect-ax c) (min (- mx (third d)) (- (revision::rect-bx c) ww))))
                   (ny (max (revision::rect-ay c) (min (- my (fourth d)) (- (revision::rect-by c) hh)))))
              (layout win (rect nx ny (+ nx ww) (+ ny hh)))))
           (:resize
            (let ((nx2 (max (+ ax 24) (min (1+ mx) (revision::rect-bx c))))
                  (ny2 (max (+ ay 5)  (min (1+ my) (revision::rect-by c)))))
              (layout win (rect ax ay nx2 ny2))))
           (:scroll
            (multiple-value-bind (sx sy0 sy1) (window-vscroll-bounds win)
              (declare (ignore sx))
              (when sy0 (%scroll-from-click (window-scroll-target win) my sy0 sy1))))
           (:hscroll
            (multiple-value-bind (sy hx0 hx1) (window-hscroll-bounds win)
              (declare (ignore sy))
              (when hx0 (%hscroll-from-click (window-scroll-target win) mx hx0 hx1)))))
         (invalidate dt))))))

(defun dt-window-click (dt win e)
  (dt-raise dt win)
  (let* ((b (view-bounds win)) (lx (mouse-col win e)) (ly (mouse-row win e)) (w (r-w b)) (h (r-h b)))
    (cond
      ((not (typep e 'mouse-down)) (handle-event win e))            ; wheel etc. -> widgets
      ((and (zerop ly) (<= 1 lx 3)) (%dt-request-close dt win))     ; [✕] close box (prompts an unsaved editor)
      ((and (zerop ly) (> w 7) (<= (- w 5) lx (- w 3))) (dt-zoom dt win))  ; [↑] zoom box
      ((and (zerop ly) (event-double e)) (dt-zoom dt win))          ; double-click title -> zoom
      ((and (= lx (1- w)) (= ly (1- h))) (setf (dt-drag dt) (list :resize win)))  ; resize grip
      ((and (= lx (1- w)) (window-scroll-target win) (>= ly 1) (<= ly (- h 2)))   ; right (vertical) scrollbar
       (multiple-value-bind (sx sy0 sy1) (window-vscroll-bounds win)
         (declare (ignore sx))
         (%scroll-from-click (window-scroll-target win) (cdr (event-where e)) sy0 sy1))
       (setf (dt-drag dt) (list :scroll win)))
      ((and (= ly (1- h)) (window-hscroll-bounds win) (<= 1 lx (- w 2)))          ; bottom (horizontal) scrollbar
       (multiple-value-bind (sy hx0 hx1) (window-hscroll-bounds win)
         (declare (ignore sy))
         (%hscroll-from-click (window-scroll-target win) (car (event-where e)) hx0 hx1))
       (setf (dt-drag dt) (list :hscroll win)))
      ((zerop ly) (setf (dt-drag dt) (list :move win lx ly)))       ; title bar -> move
      (t (handle-event win e)))                                     ; interior -> widgets
    (invalidate dt)))

(defmethod handle-event ((dt desktop) (e mouse-event))
  (let* ((w (event-where e)) (x (car w)) (y (cdr w)) (mb (dt-menubar dt)))
    (cond
      ((dt-drag dt) (dt-drag-update dt e))                 ; in a move/resize drag
      ((and (typep e 'mouse-down) (logtest (event-buttons e) revision::+mb-right+))  ; right-click -> context menu
       (let ((win (dt-window-at dt x y)))
         (when win
           (dt-raise dt win) (dt-refocus dt)
           (let ((v (view-at win x y)))                     ; position the cursor/selection, then pop up
             (when v (handle-event v (make-instance 'mouse-down :where (cons x y)
                                                     :buttons revision::+mb-left+)))
             (let ((items (and v (context-menu v))))
               (when items (popup-menu items :x x :y (1+ y))))))
         (invalidate dt)))
      ((menu-hit-p mb x y) (handle-event mb e))
      ((and (typep e 'mouse-down) (= y (revision::rect-ay (view-bounds (dt-statusbar dt)))))
       (handle-event (dt-statusbar dt) e))                 ; status-bar chips
      (t (let ((win (dt-window-at dt x y)))
           (when win (dt-window-click dt win e)))))))

(defun dt-status-items (dt)
  "The status-line chips for the current state: window actions when one is open,
plus the focused widget's own STATUS-HINTS, plus the always-on globals."
  (let* ((mb (dt-menubar dt)) (top (dt-top dt))
         (chips (list (cons "≡ Windows" (lambda () (setf (menu-active mb) 0 (menu-sel mb) 0) (invalidate dt)))
                      (cons "Tile"      (lambda () (dt-tile dt)))
                      (cons "Cascade"   (lambda () (dt-cascade dt)))
                      (cons "Help"      (lambda () (dt-help dt)))
                      (cons "Exit"      (lambda () (setf *app-done* t))))))
    (when top
      (setf chips (append (list (cons "Close" (lambda () (%dt-request-close dt top)))) chips
                          (status-hints top)                       ; the window's own chips (any focus)
                          (status-hints (container-focus top)))))   ; plus the focused widget's
    chips))

;;; --- a dialog demonstrating field validators --------------------------------

(defun %validators-dialog ()
  "Modal dialog showing a range-validated and a picture-validated field."
  (let ((d (ui (dialog (:title " Field validators " :keymap *dialog-keys*
                        :value-fn (lambda (d) (declare (ignore d)) t))
                 (stack
                   (1 (row (20 (static-text :role :label :text " Age (1..120): "))
                           (:fill (input-line :name 'age :validator (range-validator 1 120)))))
                   (1 (row (20 (static-text :role :label :text " Date ##/##/####: "))
                           (:fill (input-line :name 'date :validator (picture-validator "##/##/####")))))
                   (1 (static-text :name 'msg :role :error :text ""))
                   (1 (static-text :role :status :text " letters are rejected in Age; OK validates the fields; Esc cancels "))
                   (1 (row (:fill (static-text :text ""))
                           (8  (button :label "OK"     :command 'accept))
                           (12 (button :label "Cancel" :command 'cancel)))))))))
    (exec-view d :width 52 :height 9)))

;;; --- a window demonstrating the table viewer --------------------------------

;;; make-package-table (the :ptable window) is an IDE tool — it lives in revl
;;; (ide/desktop-ide.lisp), which self-registers it with *window-builders*.

;;; --- a small window demonstrating the cluster controls ----------------------

;;; --- editor feature defaults (wired live from the Settings window) ----------

(defvar *ed-syntax* t)       (defvar *ed-wrap* nil)
(defvar *ed-auto-indent* t)  (defvar *ed-line-numbers* nil)

(defun %set-editor-features (te)
  (setf (te-colorizer te)    (if *ed-syntax* #'lisp-colorize nil)
        (te-wrap te)         *ed-wrap*
        (te-indenter te)     (if *ed-auto-indent* *lisp-indenter* nil)
        (te-line-numbers te) *ed-line-numbers*)
  (when *ed-wrap* (setf (te-left te) 0))
  (te-ensure-visible te) (invalidate te))

(defun %features-value ()
  "Checked-index list (0 syntax · 1 wrap · 2 auto-indent · 3 line-numbers) for the
current defaults."
  (let ((v '()))
    (when *ed-line-numbers* (push 3 v)) (when *ed-auto-indent* (push 2 v))
    (when *ed-wrap* (push 1 v)) (when *ed-syntax* (push 0 v))
    v))

(defun %apply-editor-features (dt cluster)
  "Record the Features cluster as the defaults and apply it to every open editor."
  (let ((v (cluster-value cluster)))
    (setf *ed-syntax*       (and (member 0 v) t) *ed-wrap*        (and (member 1 v) t)
          *ed-auto-indent*  (and (member 2 v) t) *ed-line-numbers* (and (member 3 v) t)))
  (dolist (w (dt-windows dt))
    (when (typep w 'editor-window)
      (let ((te (find-view w 'edit))) (when te (%set-editor-features te)))))
  (%tool-note "editor features applied"))

(defun make-options ()
  "IDE settings — every control applies live: a feature toggle updates all open
editors, the theme radio re-skins the desktop, the timeout field is immediate."
  (let* ((dt *desktop*)
         (win (ui (window (:title " Settings " :keymap *global-keys*)
                    (stack
                      (1 (static-text :role :label :text " Editor features — ↑/↓, Space or click toggles: "))
                      (4 (cluster :name 'features :mode :check
                           :items (list "Syntax highlight" "Word wrap" "Auto-indent" "Line numbers")
                           :value (%features-value)
                           :on-change (lambda (c) (when dt (%apply-editor-features dt c)))))
                      (1 (static-text :role :label :text " Colour theme — radio: "))
                      (3 (cluster :name 'theme :mode :radio
                           :items (mapcar #'car *themes*) :value *theme-index*
                           :on-change (lambda (c) (when dt (apply-theme dt (cluster-value c))))))
                      (1 (row (30 (static-text :role :label :text " Status-note timeout (1–60 s): "))
                              (:fill (input-line :name 'ttl :text (princ-to-string *tool-message-ttl*)
                                       :on-change (lambda (il)
                                                    (let ((n (parse-integer (input-text il) :junk-allowed t)))
                                                      (when (and n (<= 1 n 60)) (setf *tool-message-ttl* n))))))))
                      (:fill (static-text :role :status :text ""))
                      (1 (static-text :role :status :text " Space/click toggles · type to set the timeout · Tab switches · Esc closes ")))))))
    (values win (find-view win 'features))))

;;; --- desktop layout persistence (whole-desktop save / restore) --------------

;;; make-options (the Settings dialog) is a toolkit window; register it.  The IDE
;;; windows (including :ptable) self-register in their own files.
(pushnew (cons :options #'make-options) *window-builders* :key #'car)

(defun %desktop-file () (merge-pathnames ".revision-desktop" (user-homedir-pathname)))

(defun dt-save-layout (dt &optional (path (%desktop-file)))
  "Write the open windows -- kind, bounds, Z-order, and each window's own restorable
state -- to PATH.  A window contributes state through WINDOW-SAVE-STATE: editors save
their filename and any unsaved buffer text, the REPL its package + history, and so on,
so relaunching restores the whole session."
  (let ((layout (loop for w in (dt-windows dt) for k = (window-kind w) when k
                      collect (let ((b (view-bounds w)))
                                (list k (revision::rect-ax b) (revision::rect-ay b)
                                      (revision::rect-bx b) (revision::rect-by b)
                                      ;; serialize per-window so a window whose state has a
                                      ;; container / bad value drops only its own state, not the file
                                      (ignoring-errors ("window-save-state") (serialize (window-save-state w))))))))
    (ignoring-errors ("dt-save-layout write")
     (with-open-file (s path :direction :output :if-exists :supersede :if-does-not-exist :create)
       (let ((*print-readably* t)) (prin1 layout s))))
    layout))

(defun dt-load-layout (dt &optional (path (%desktop-file)))
  "Reopen the windows recorded in PATH at their saved positions.  Each is rebuilt by its
registered builder and then handed its saved state via WINDOW-RESTORE-STATE."
  (dolist (entry (ignoring-errors ("dt-load-layout read")
                   (with-open-file (s path :if-does-not-exist nil) (and s (read s nil nil)))))
    (ignoring-errors ("dt-load-layout entry")
     (destructuring-bind (kind x0 y0 x1 y1 &optional state) entry
       (let ((builder (cdr (assoc kind *window-builders*))))
         (when builder
           (multiple-value-bind (win focus open) (funcall builder)
             (when win
               (ignoring-errors ("window-restore-state") (window-restore-state win (deserialize state)))
               (dt-add dt win focus open kind (rect x0 y0 x1 y1)))))))))
  (dt-refocus dt) (invalidate dt))

;;; --- entry point ------------------------------------------------------------

;;; *extra-menus* is defined in host.lisp (the plugin registry).  A module pushes a
;;; (DT) -> menu-spec function; most-recently-pushed appears last.

(defun %about-dialog ()
  "The classic ≡ system-menu About box."
  (let ((d (ui (dialog (:title " About " :keymap *dialog-keys* :value-fn (constantly t))
                 (stack
                   (1 (static-text :role :label :text "    revl — a Common Lisp IDE"))
                   (1 (static-text :role :label :text "    on the revision CLOS kernel"))
                   (1 (static-text :text ""))
                   (1 (static-text :text "    a Turbo Vision-style TUI, ported to SBCL"))
                   (:fill (static-text :text ""))
                   (1 (row (:fill (static-text :text "")) (8 (button :label "OK" :command 'accept))
                           (:fill (static-text :text "")))))))))
    (exec-view d :width 46 :height 10)))

(defun %desktop-menus (dt)
  (flet ((any-win () (lambda () (dt-top dt))))            ; ENABLED predicate: a window is open
    (%order-menus
     (append
      (list
       (list "≡"
             (list "About…"    (lambda () (%about-dialog))))
       (list "Window"                                     ; window management
             (list "Size/move"       (lambda () (let ((top (dt-top dt)))
                                                  (when top (setf *sizemove-win* top)
                                                        (%tool-note "Size/move: arrows move · Shift+arrows resize · Enter/Esc done"))))
                   (cons :f5 revision::+md-ctrl+) (any-win))                       ; Ctrl-F5
             (list "Zoom"            (lambda () (let ((top (dt-top dt))) (when top (dt-zoom dt top)))) :f5 (any-win))
             (list "Next"            (lambda () (dt-next dt) (dt-refocus dt)) :f6 (any-win))
             (list "Previous"        (lambda () (dt-prev dt) (dt-refocus dt))
                   (cons :f6 revision::+md-shift+) (any-win))                      ; Shift-F6
             (list "Tile"            (lambda () (dt-tile dt) (dt-refocus dt)) nil (any-win))
             (list "C~a~scade"       (lambda () (dt-cascade dt) (dt-refocus dt)) nil (any-win))   ; access key A (C = Close)
             (list "List…"           (lambda () (%dt-window-list dt)) (cons #\0 revision::+md-alt+) (any-win))  ; Alt-0
             (list "Close"           (lambda () (let ((top (dt-top dt))) (when top (%dt-request-close dt top))))
                   (cons :f3 revision::+md-alt+) (any-win))                        ; Alt-F3 (CUA: close window)
             (list "Clos~e~ all"     (lambda () (dolist (w (copy-list (dt-windows dt)))   ; stop if a save is cancelled
                                                  (unless (%dt-request-close dt w) (return)))
                                                (dt-refocus dt) (invalidate dt))
                   nil (any-win)))
       (list "Options"
             (list "Settings…"       (lambda () (dt-open dt :options)))
             (list "Colours…"        (lambda () (make-color-dialog)))
             (list "Colour theme"    (lambda () (cycle-theme dt)))
             (list "Validators…"     (lambda () (%validators-dialog))))
       (list "Help"
             (list "This window"     (lambda () (dt-help dt)) :f1)))
      (remove nil (mapcar (lambda (f) (funcall f dt)) (reverse *extra-menus*)))))))   ; modules' menus (a NIL result = a contributor that opted out)

;;; ensure-repl (open-or-focus the desktop's REPL) is IDE glue — see revl's
;;; ide/desktop-ide.lisp.

(defun run-desktop ()
  "Run the revision IDE: a Turbo-Vision-style desktop with a menu bar, a status bar,
and movable / resizable / overlapping windows (drag the title bar, drag the
bottom-right corner to resize, click [✕] to close; Window menu tiles/cascades).
Returns on File→Exit."
  (revision:with-screen (s)
    (let ((dt (make-instance 'desktop)))
      (setf (dt-menubar dt)   (make-instance 'menu-bar :menus (%desktop-menus dt))
            (dt-statusbar dt)  (make-instance 'status-bar :provider (lambda () (dt-status-items dt))))
      (layout dt (rect 0 0 (revision:screen-width s) (revision:screen-height s)))
      (setf (context-root *context*) dt *desktop* dt *ui-thread* sb-thread:*current-thread* *app-done* nil
            (context-dirty *context*) t (context-full-redraw *context*) t)
      (dt-load-layout dt)                                    ; restore the previous session's windows
      (loop until *app-done* do
        (drain-ui-callbacks)
        (let ((c *context*) (expired (%expire-tool-message)))  ; auto-clear the status-bar note
          (when (or (context-dirty c) expired)
            (revision:hide-cursor s)
            (let ((views (context-dirty-views c)) (full (or (context-full-redraw c) expired)))
              (setf (context-dirty-views c) nil (context-full-redraw c) nil (context-dirty c) nil)
              (if (%partial-frame-p dt views full)             ; hot path: repaint only the focused window
                  (progn (draw (dt-top dt)) (draw (dt-statusbar dt)))
                  (draw dt)))
            (revision:flush-screen s)))
        (revision::pump-input s (%tool-message-timeout (revision::input-timeout s)))
        (loop for tev = (revision::screen-next-event s)   ; drain ALL decoded events before blocking
              while (and tev (not *app-done*))
              do (let ((ev (translate tev))) (when ev (handle-event dt ev)))))
      (dt-save-layout dt)                                    ; persist the desktop for next launch
      (dolist (win (dt-windows dt))                          ; stop any open windows' threads
        (when (window-cleanup win) (ignoring-errors ("window cleanup") (funcall (window-cleanup win))))))))

;;; (The application-facing symbols this file provides — *desktop*, the plugin
;;; registry, dt-* — are exported with the rest of the API in base/package.lisp.)

