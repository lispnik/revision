;;;; render-capture.lisp --- shared headless render-capture + golden-snapshot
;;;; helpers for the TUI test scripts.  Load AFTER (asdf:load-system :revision).
;;;;
;;;; The reliable way to test a TUI: draw a laid-out view into a headless SCREEN
;;;; (whose back buffer is just an in-memory cell array) and read it back — no
;;;; terminal, no PTY, no emulator, no timing.  Every per-cell attribute (colour,
;;;; underline, the menu-hotkey highlight) is present and assertable, which a
;;;; pixel/gif recorder cannot give you.  To drive state, build and dispatch CLOS
;;;; events (any keysym + modifier bits, Alt included), redraw, and re-capture.

(in-package #:revision)

(defun capture-view (view w h)
  "Lay VIEW out to WxH, draw it into a fresh headless screen, and return the screen."
  (let ((s (make-screen)))
    (screen-resize s w h)
    (let ((*screen* s) (*context* (make-context :full-redraw t)))
      (layout view (rect 0 0 w h))
      (draw view))
    s))

(defun capture-cell (s x y)
  "The packed cell (character code + 32-bit attribute) at (X,Y) of screen S."
  (aref (screen-back s) (screen-index s x y)))

(defun capture-row (s y)
  "Row Y of screen S as a string. Printable characters render as themselves;
control codes, blanks, and the wide-glyph continuation sentinel (a non-character
code) render as a space — so a double-width glyph shows as itself followed by a
space, keeping columns aligned."
  (coerce (loop for x from 0 below (screen-width s)
                for code = (cell-char-code (capture-cell s x y))
                collect (if (<= 32 code #x10ffff) (code-char code) #\Space))
          'string))

(defun capture-text (s)
  "The whole screen as one newline-joined string, trailing blanks trimmed per row —
a stable text snapshot suitable for golden-file comparison."
  (with-output-to-string (out)
    (dotimes (y (screen-height s))
      (write-string (string-right-trim " " (capture-row s y)) out)
      (terpri out))))

;;; --- golden snapshots -------------------------------------------------------
;;; CHECK-SNAPSHOT compares rendered text against tests/golden/<name>.txt.  Run a
;;; script with --regen-golden (or REVISION_REGEN_GOLDEN=1, i.e. `make
;;; regen-golden') to (re)write the goldens after an intended rendering change —
;;; mirroring the KEYBINDINGS.md regeneration check.

(defparameter *golden-dir* "tests/golden/")

(defun %golden-path (name) (format nil "~a~a.txt" *golden-dir* name))

(defun regen-golden-p ()
  (or (sb-ext:posix-getenv "REVISION_REGEN_GOLDEN")
      (member "--regen-golden" sb-ext:*posix-argv* :test #'string=)))

(defun check-snapshot (name text)
  "True if TEXT matches the golden file for NAME.  With regeneration on, (re)writes
the golden and returns true.  A missing golden fails with a hint."
  (let ((path (%golden-path name)))
    (cond
      ((regen-golden-p)
       (ensure-directories-exist path)
       (with-open-file (o path :direction :output :if-exists :supersede
                               :if-does-not-exist :create :external-format :utf-8)
         (write-string text o))
       (format t "  regen ~a~%" path)
       t)
      ((probe-file path)
       (string= text (with-open-file (in path :external-format :utf-8)
                        (let ((buf (make-string (file-length in))))
                          (subseq buf 0 (read-sequence buf in))))))
      (t
       (format t "  MISSING golden ~a — run `make regen-golden'~%" path)
       nil))))
