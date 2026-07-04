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

;;; --- the IDE's desktop menus -----------------------------------------------
;;; The generic revision shell provides only ≡ / Window / Options(toolkit) / Help(this
;;; window).  The IDE contributes File and Tools, and adds its own Options + Help items
;;; (which %ORDER-MENUS merges into the shell's), by pushing to *EXTRA-MENUS*.

(push (lambda (dt)
        (flet ((any-win () (lambda () (dt-top dt))))
          (list "File"
                (list "New"            (lambda () (dt-open dt :editor)) (ctrl #\n))
                (list "Open file…"     (lambda () (let ((p (make-file-dialog :dir *project-dir* :title " Open file ")))
                                                    (when p (dt-open dt (lambda () (make-editor p)))))) :f3)
                (list "Change dir…"    (lambda () (let ((p (make-file-dialog :dir *project-dir* :dirs-only t :title " Change dir ")))
                                                    (when p (setf *project-dir* (uiop:ensure-directory-pathname p))))))
                :--
                (list "Save"           (lambda () (%dt-save dt)) :f2 (any-win))
                (list "Save as…"       (lambda () (%dt-save-as dt)) nil (any-win))
                (list "Save all"       (lambda () (%dt-save-all dt)) nil (any-win))
                (list "Reload file"    (lambda () (%dt-reload dt)) nil (any-win))
                :--
                (list "Save transcript…"  (lambda () (%dt-save-transcript dt)))
                (list "Save Lisp script…" (lambda () (%dt-save-script dt)))
                (list "Clear REPL"        (lambda () (%dt-clear-repl dt)))
                :--
                (list "Save layout"    (lambda () (dt-save-layout dt)))
                (list "Restore layout" (lambda () (mapc (lambda (w) (dt-close-window dt w)) (copy-list (dt-windows dt)))
                                         (dt-load-layout dt)) nil (lambda () t))
                :--
                (list "Exit"           (lambda () (setf *app-done* t)) (cons #\x revision::+md-alt+)))))
      *extra-menus*)

(push (lambda (dt)
        (list "Tools"
              (list "Lisp REPL"       (lambda () (dt-open dt :repl))
                    (cons :f2 revision::+md-alt+))                            ; Alt-F2 = new REPL
              (list "Project manager" (lambda () (dt-open dt :project)))
              (list "Package browser" (lambda () (dt-open dt :packages)))
              (list "ASDF systems"    (lambda () (dt-open dt :systems)))
              (list "Thread monitor"  (lambda () (dt-open dt :threads)))
              (list "HTML browser"    (lambda () (dt-open dt :html)))
              (list "Package table"   (lambda () (dt-open dt :ptable)))
              (list "Emoji palette"   (lambda () (dt-open dt :emoji)))))
      *extra-menus*)

(push (lambda (dt)
        (declare (ignore dt))
        (list "Options"
              (list "Eval timing"     (lambda () (setf *repl-time* (not *repl-time*))
                                        (%tool-note (if *repl-time* "eval timing ON" "eval timing OFF"))))))
      *extra-menus*)

(push (lambda (dt)
        (list "Help"
              (list "Contents"        (lambda () (dt-open dt (lambda () (make-help :general)))))
              (list "Keybindings"     (lambda () (dt-open dt (lambda () (make-help :keys)))))
              (list "Topics" :submenu
                    (list "Lisp REPL"       (lambda () (dt-open dt (lambda () (make-help :repl)))))
                    (list "Text editor"     (lambda () (dt-open dt (lambda () (make-help :editor)))))
                    (list "Project manager" (lambda () (dt-open dt (lambda () (make-help :project)))))
                    (list "Browsers"        (lambda () (dt-open dt (lambda () (make-help :browser)))))
                    (list "HTML browser"    (lambda () (dt-open dt (lambda () (make-help :html)))))
                    (list "Thread monitor"  (lambda () (dt-open dt (lambda () (make-help :threads))))))
              :--
              (list "About…"          (lambda () (%about-dialog)))))
      *extra-menus*)
