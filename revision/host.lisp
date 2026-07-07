;;;; host.lisp --- the shared event loop + a full-screen runner.
;;;;
;;;; Every window used to copy the same loop (drain bridge callbacks, repaint on
;;;; *DIRTY*, pump + dispatch input).  EVENT-LOOP is that loop, once; RUN-VIEW is
;;;; the standalone full-screen host.  Windows are now built by make-* builders
;;;; that return (values WINDOW FOCUS OPEN) — OPEN is an optional thunk run after
;;;; layout (to start background threads) that returns a cleanup thunk — so the
;;;; same window can be hosted full-screen (RUN-VIEW) or inside the DESKTOP.

(in-package #:revision)

;;; --- the desktop plugin registry -------------------------------------------
;;; Defined here (early, before any window file) so a window can self-register its
;;; builder and a module can contribute a menu regardless of load order.  These are
;;; the seam an application (e.g. revl) uses to add its windows + menus to the shell.

(defvar *window-builders* nil
  "Alist of KIND (keyword) -> 0-arg builder returning (values WINDOW FOCUS OPEN).  Managed
through REGISTER-WINDOW; DT-OPEN and layout save/restore look a builder up by keyword.")

(defvar *extra-menus* nil
  "Alist of NAME (keyword) -> a (DESKTOP) -> menu-spec function.  Managed through
REGISTER-MENU; the desktop merges each contribution into its menu bar (see %DESKTOP-MENUS).")

;;; The desktop plugin API: windows and menus register by KIND/NAME through these
;;; functions rather than by hand-splicing the alists, so a contributor never depends
;;; on the representation -- and re-registration is idempotent (replace by key), which
;;; a plain PUSHNEW/PUSH got wrong: PUSHNEW kept the STALE builder on a file reload, and
;;; PUSH duplicated a menu.  Registration by key fixes both.

(defun register-window (kind builder)
  "Register BUILDER -- a 0-arg function returning (values WINDOW FOCUS OPEN) -- under KIND
(a keyword), so the desktop can open it by keyword (from a menu, or when restoring a saved
layout).  Idempotent: re-registering KIND REPLACES its builder, so reloading the window's
file updates it cleanly.  Returns KIND."
  (check-type kind keyword)
  (setf *window-builders* (acons kind builder (remove kind *window-builders* :key #'car)))
  kind)

(defun unregister-window (kind)
  "Remove KIND's window builder from the registry; returns T when one was registered."
  (prog1 (and (assoc kind *window-builders*) t)
    (setf *window-builders* (remove kind *window-builders* :key #'car))))

(defun window-kinds ()
  "The registered window-builder keywords (e.g. for a picker or introspection)."
  (mapcar #'car *window-builders*))

(defun register-menu (name contributor)
  "Register CONTRIBUTOR -- a function of the desktop returning a menu spec (LABEL item...),
or NIL to contribute nothing -- under NAME (a keyword), as a desktop menu-bar contribution.
A contribution whose title matches a built-in menu merges into it; otherwise it adds a new
top-level menu, positioned by *MENU-ORDER*.  Idempotent: re-registering NAME replaces it, so
a file reload doesn't duplicate the menu.  Returns NAME."
  (check-type name keyword)
  (setf *extra-menus* (acons name contributor (remove name *extra-menus* :key #'car)))
  name)

(defun event-loop (s root)
  "Drive ROOT until *RUNNING* becomes NIL.  The cursor is hidden every frame and
re-shown by whichever focused widget owns it (input-line / text-edit), so it
never lingers when focus moves to a non-text widget."
  (let ((c *context*))
    (loop while *running* do
      (drain-ui-callbacks)
      (when (context-dirty c)
        (revision:hide-cursor s)
        (setf (context-dirty-views c) nil (context-full-redraw c) nil (context-dirty c) nil)  ; one full-screen view: always a full draw
        (draw root) (revision:flush-screen s))
      (revision::pump-input s (revision::input-timeout s))
      (loop for tev = (revision::screen-next-event s)      ; drain ALL decoded events before blocking
            while (and tev *running*)
            do (let ((ev (translate tev))) (when ev (handle-event root ev)))))))

(defun run-view (win &key focus open)
  "Run WIN full-screen in its own screen session until it quits.  FOCUS is the
initial focused widget; OPEN (a thunk of the screen) may start background work
and return a cleanup thunk."
  (revision:with-screen (s)
    (layout win (rect 0 0 (revision:screen-width s) (revision:screen-height s)))
    (setf (context-root *context*) win
          (container-focus win) (or focus (first (all-focusables win)))
          *ui-thread* sb-thread:*current-thread* *running* t
          (context-dirty *context*) t (context-full-redraw *context*) t)
    (let ((cleanup (and open (funcall open s))))
      (unwind-protect (event-loop s win)
        (when cleanup (ignoring-errors ("run-view cleanup") (funcall cleanup)))))))
