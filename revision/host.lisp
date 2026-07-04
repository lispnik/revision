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
  "Alist of KEYWORD -> 0-arg builder returning (values WINDOW FOCUS OPEN).  Windows
self-register here; DT-OPEN and layout-restore look a builder up by keyword.")

(defvar *extra-menus* nil
  "List of (DESKTOP) -> menu-spec functions; a module pushes here to contribute a
top-level menu to the desktop menu bar.")

(defun event-loop (s root)
  "Drive ROOT until *RUNNING* becomes NIL.  The cursor is hidden every frame and
re-shown by whichever focused widget owns it (input-line / text-edit), so it
never lingers when focus moves to a non-text widget."
  (loop while *running* do
    (drain-ui-callbacks)
    (when *dirty*
      (revision:hide-cursor s)
      (draw root) (revision:flush-screen s) (setf *dirty* nil))
    (revision::pump-input s 0.05)
    (let ((tev (revision::screen-next-event s)))
      (when tev (let ((ev (translate tev))) (when ev (handle-event root ev)))))))

(defun run-view (win &key focus open)
  "Run WIN full-screen in its own screen session until it quits.  FOCUS is the
initial focused widget; OPEN (a thunk of the screen) may start background work
and return a cleanup thunk."
  (revision:with-screen (s)
    (layout win (rect 0 0 (revision:screen-width s) (revision:screen-height s)))
    (setf *root* win
          (container-focus win) (or focus (first (all-focusables win)))
          *ui-thread* sb-thread:*current-thread* *running* t *dirty* t)
    (let ((cleanup (and open (funcall open s))))
      (unwind-protect (event-loop s win)
        (when cleanup (ignore-errors (funcall cleanup)))))))
