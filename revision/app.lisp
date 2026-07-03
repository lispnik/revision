;;;; app.lisp --- a launcher that composes the ported windows into one IDE.
;;;;
;;;; Each ported window (run-repl, run-editor, …) owns its own WITH-SCREEN
;;;; session.  Rather than nest screens (REVISION's screen isn't reentrant), the
;;;; launcher runs the menu and the chosen window as *sequential* sessions: pick
;;;; a window, it takes over the screen, and closing it returns to the menu.
;;;; This is the "revl on revision" entry point that the revl project drives.

(in-package #:revision)

(defparameter *app-windows*
  (list (cons "Lisp REPL"             #'run-repl)
        (cons "Text editor"           #'run-editor)
        (cons "Project manager"       #'run-project)
        (cons "Package browser"       #'run-packages)
        (cons "ASDF system browser"   #'run-systems)
        (cons "Thread monitor"        #'run-threadmon)
        (cons "HTML browser"          #'run-html)
        (cons "Kitchen-sink demo"     #'run))
  "Launcher entries: (LABEL . THUNK).")

(defun run-menu ()
  "Show the launcher menu in its own screen session; return the chosen THUNK, or
NIL when the user quits."
  (let ((choice nil))
    (revision:with-screen (s)
      (let ((win (ui (window (:title " revl on revision — launcher " :keymap *global-keys*)
                       (stack
                         (1 (static-text :role :label
                              :text " Choose a window — ↑/↓ then Enter; Esc or q to quit: "))
                         (:fill (list-box :name 'menu :items (mapcar #'car *app-windows*)
                                  :on-activate (lambda (lb item) (declare (ignore item))
                                                 (setf choice (nth (list-selected lb) *app-windows*)
                                                       *running* nil))))
                         (1 (static-text :role :status
                              :text " every window runs on the revision kernel; close it (q/Esc) to return here ")))))))
        (layout win (rect 0 0 (revision:screen-width s) (revision:screen-height s)))
        (setf *root* win
              (container-focus win) (find-view win 'menu)
              *ui-thread* sb-thread:*current-thread* *running* t *dirty* t)
        (loop while *running* do
          (when *dirty*
            (revision:hide-cursor s)
            (draw win) (revision:flush-screen s) (setf *dirty* nil))
          (revision::pump-input s 0.05)
          (let ((tev (revision::screen-next-event s)))
            (when tev (let ((ev (translate tev))) (when ev (handle-event win ev))))))))
    (cdr choice)))

(defun run-app ()
  "Run the revision-based revl IDE.  This is now the full Turbo-Vision-style desktop
shell (menu bar + status bar + hosted windows); see RUN-DESKTOP."
  (run-desktop))
