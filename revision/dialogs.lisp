;;;; dialogs.lisp --- the standard dialogs: file picker, change-dir, colours.
;;;;
;;;; Each composes EXEC-VIEW with the existing controls (input-line, list-box,
;;;; cluster, button) and returns a value, mirroring revision's TFileDialog /
;;;; TChDirDialog / TColorDialog.

(in-package #:revision)

;;; --- file / directory picker ------------------------------------------------

(defun %glob-match (pat str)
  "Case-insensitive glob match: * = any run, ? = any char."
  (let ((p (string-downcase pat)) (s (string-downcase str)))
    (labels ((m (i j)
               (cond ((= i (length p)) (= j (length s)))
                     ((char= (char p i) #\*) (or (m (1+ i) j) (and (< j (length s)) (m i (1+ j)))))
                     ((= j (length s)) nil)
                     ((or (char= (char p i) #\?) (char= (char p i) (char s j))) (m (1+ i) (1+ j)))
                     (t nil))))
      (m 0 0))))

(defun %pattern-is-glob (p) (and p (or (find #\* p) (find #\? p))))

(defun %file-matches-p (name pattern)
  "Does NAME pass filter PATTERN?  Empty/\"*\" = all; glob if it has */?; otherwise a
case-insensitive substring (type-ahead)."
  (cond ((or (null pattern) (zerop (length pattern)) (string= pattern "*")) t)
        ((%pattern-is-glob pattern) (%glob-match pattern name))
        (t (and (search (string-downcase pattern) (string-downcase name)) t))))

(defun %hidden-name-p (n) (and (plusp (length n)) (char= (char n 0) #\.)))
(defun %typeahead-match (name ta)                       ; live substring from the Filter field
  (or (null ta) (zerop (length ta)) (and (search (string-downcase ta) (string-downcase name)) t)))

(defun %dir-entries (dir dirs-only mask typeahead show-hidden)
  "\"../\", then subdirectories (trailing /), then files.  MASK (a glob like
\"*.lisp\") filters files; TYPEAHEAD (a substring) filters both dirs and files."
  (flet ((keep-dir (n) (and (or show-hidden (not (%hidden-name-p n))) (%typeahead-match n typeahead)))
         (keep-file (n) (and (or show-hidden (not (%hidden-name-p n)))
                             (%file-matches-p n mask) (%typeahead-match n typeahead))))
    (let ((subs (sort (loop for p in (ignore-errors (uiop:subdirectories dir))
                            for n = (format nil "~a/" (car (last (pathname-directory p))))
                            when (keep-dir n) collect n) #'string<))
          (files (unless dirs-only
                   (sort (loop for p in (ignore-errors (uiop:directory-files dir))
                               for n = (file-namestring p) when (keep-file n) collect n) #'string<))))
      (append (list "../") subs files))))

(defun %expand-user (s)
  "Expand a leading ~ to the user's home directory."
  (if (and (plusp (length s)) (char= (char s 0) #\~))
      (namestring (merge-pathnames (subseq s (if (and (> (length s) 1) (char= (char s 1) #\/)) 2 1))
                                   (user-homedir-pathname)))
      s))

;;; File-dialog state shared with the global toggle-hidden / new-folder commands,
;;; bound dynamically around EXEC-VIEW (so a button can reach the live dialog).
(defstruct fd cur mode mask dirs-only show-hidden dialog)
(defvar *fd* nil)

(defun %fd-breadcrumb (dir)
  (let ((s (namestring dir))) (if (> (length s) 62) (concatenate 'string "…" (subseq s (- (length s) 61))) s)))
(defun %fd-refill (fd)
  (let* ((d (fd-dialog fd)) (lb (find-view d 'files))
         (ta (if (eq (fd-mode fd) :save) "" (input-text (find-view d 'pat)))))   ; :save field is a name, not a filter
    (setf (list-items lb) (%dir-entries (fd-cur fd) (fd-dirs-only fd) (fd-mask fd) ta (fd-show-hidden fd))
          ;; while filtering, pre-select the first real entry (skip "../") so Enter
          ;; opens/enters the match instead of navigating up
          (list-selected lb) (if (and (plusp (length ta)) (> (length (list-items lb)) 1)) 1 0)
          (list-top lb) 0 (list-hleft lb) 0
          ;; show the active mask as a hint while the Filter field is empty
          (static-text-text (find-view d 'dir))
          (let ((bc (%fd-breadcrumb (fd-cur fd))))
            (if (and (fd-mask fd) (not (string= (fd-mask fd) "*")) (zerop (length ta)))
                (format nil "~a   (~a)" bc (fd-mask fd))
                bc)))
    (invalidate d)))
(defun %fd-goto (fd dir)
  (setf (fd-cur fd) (uiop:ensure-directory-pathname dir))
  (let ((d (fd-dialog fd)) (pat (find-view (fd-dialog fd) 'pat)))
    (when (eq (fd-mode fd) :open)                        ; entering a directory resets the type-ahead filter
      (setf (input-text pat) "" (input-caret pat) 0 (container-focus d) pat))
    (%fd-refill fd) (invalidate d)))

(define-command fd-hidden (v e)
  (when *fd* (setf (fd-show-hidden *fd*) (not (fd-show-hidden *fd*))) (%fd-refill *fd*)))
(define-command fd-mkdir (v e)
  (when *fd*
    (let ((name (prompt-string " New folder " "Name:")))
      (when (and name (plusp (length (string-trim " " name))))
        (ignore-errors (ensure-directories-exist
                        (uiop:ensure-directory-pathname (merge-pathnames (string-trim " " name) (fd-cur *fd*)))))
        (%fd-refill *fd*)))))

(defun %dir-item-p (item)
  (or (string= item "../") (and (plusp (length item)) (char= (char item (1- (length item))) #\/))))

(defun make-file-dialog (&key (dir (uiop:getcwd)) dirs-only (mode :open) (mask "*") default-name
                              (title (case mode (:save " Save file ")
                                       (t (if dirs-only " Choose directory " " Open file ")))))
  "Modal file picker.  MODE :open returns an existing file (or the current directory
when DIRS-ONLY); MODE :save returns a name to write, confirming an overwrite.  MASK
filters the file list (a glob like \"*.lisp\"); the Filter/Name field also does
type-ahead.  Returns a pathname, or NIL on cancel."
  (let* ((fd (make-fd :cur (uiop:ensure-directory-pathname dir) :mode mode :mask mask
                      :dirs-only dirs-only :show-hidden nil))
         (savep (eq mode :save)))
    (labels
        ((field (d) (string-trim " " (input-text (find-view d 'pat))))
         (target (d)                                    ; the pathname the user is choosing
           (cond (dirs-only (fd-cur fd))                ; Change-dir: the current directory
                 (savep (let ((f (field d))) (and (plusp (length f)) (merge-pathnames (%expand-user f) (fd-cur fd)))))
                 (t (let* ((lb (find-view d 'files)) (sel (nth (list-selected lb) (list-items lb))))
                      (and sel (not (%dir-item-p sel)) (merge-pathnames sel (fd-cur fd)))))))
         (fd-type (lb ch)                               ; forward a keystroke from the list to the Filter field
           (let* ((d (view-root lb)) (inp (find-view d 'pat)) (txt (input-text inp)))
             (setf (input-text inp) (if (eq ch :back)
                                        (if (plusp (length txt)) (subseq txt 0 (1- (length txt))) txt)
                                        (concatenate 'string txt (string ch)))
                   (input-caret inp) (length (input-text inp)))
             (%fd-refill fd)))
         (activate (lb item)
           (let ((d (view-root lb)))
             (cond ((string= item "../") (%fd-goto fd (uiop:pathname-parent-directory-pathname (fd-cur fd))))
                   ((%dir-item-p item) (%fd-goto fd (merge-pathnames (subseq item 0 (1- (length item))) (fd-cur fd))))
                   (savep (setf (input-text (find-view d 'pat)) item) (perform 'accept lb nil))  ; click-to-overwrite
                   (t (perform 'accept lb nil)))))
         (validate (d)
           (let ((tp (target d)))
             (cond
               ((and savep (zerop (length (field d)))) (fail-validation " Enter a file name. "))
               ((null tp) (fail-validation " Select a file. "))
               ((uiop:directory-exists-p (uiop:ensure-directory-pathname tp))   ; a directory -> navigate into it
                (unless dirs-only (%fd-goto fd tp)
                        (setf (input-text (find-view d 'pat)) (if savep (or default-name "") "")) (fail-validation "")))
               ((and savep (not (uiop:directory-exists-p (uiop:pathname-directory-pathname tp))))
                (fail-validation " No such directory. "))
               ((and savep (probe-file tp)
                     (not (%confirm (format nil " ~a exists.  Overwrite it? " (file-namestring tp)))))
                (fail-validation ""))
               ((and (not savep) (not dirs-only) (not (probe-file tp))) (fail-validation " No such file. "))))))
      (let ((d (ui (dialog (:title title :keymap *dialog-keys* :validator #'validate
                            :value-fn (lambda (d) (let ((tp (target d))) (and tp (namestring tp)))))
                     (stack
                       (1 (static-text :name 'dir :role :label :text ""))
                       (1 (row (9 (static-text :role :label :text (if savep " Name:   " " Filter: ")))
                               (:fill (input-line :name 'pat :history-id :file
                                        :text (if savep (or default-name "") "")     ; Filter is pure type-ahead
                                        :on-change (lambda (il) (declare (ignore il))
                                                     (unless savep (%fd-refill fd)))))))
                       (:fill (list-box :name 'files :on-activate #'activate
                                        :on-type (unless savep #'fd-type)))    ; type-ahead from the list
                       (1 (static-text :name 'msg :role :error :text ""))
                       (1 (row (:fill (static-text :text ""))
                               (11 (button :label "Hidden" :command 'fd-hidden))
                               (11 (button :label "Folder" :command 'fd-mkdir))
                               (10 (button :label (cond (savep "Save") (dirs-only "Choose") (t "Open")) :command 'accept))
                               (10 (button :label "Cancel" :command 'cancel)))))))))
        (setf (fd-dialog fd) d)
        (%fd-refill fd)
        (let* ((*fd* fd) (r (exec-view d :width 72 :height 22)))
          (if (eq r :cancel) nil (ignore-errors (pathname r))))))))

;;; --- colour customiser (visual swatches + live preview of *THEME*) ----------

(defparameter *color-roles*
  '(:normal :focused :frame :menu-bar :menu-selected :status :label :desktop :button))

;;; A row of colour swatches (0..COUNT-1): ←/→ or click selects; a ▲ marks the
;;; choice.  BG-P shows them as background blocks, else foreground blocks.
(defclass color-swatches (view)
  ((count :initarg :count :initform 16 :accessor sw-count)
   (value :initarg :value :initform 0 :accessor sw-value)
   (bg-p  :initarg :bg-p  :initform nil :accessor sw-bg-p)
   (on-change :initarg :on-change :initform nil :accessor sw-on-change))
  (:metaclass reactive-class))

(defmethod focusable-p ((v color-swatches)) t)
(defun sw-notify (v) (when (sw-on-change v) (funcall (sw-on-change v) v)))

(defmethod draw ((v color-swatches))
  (let* ((b (view-bounds v)) (ax (revision::rect-ax b)) (ay (revision::rect-ay b)) (w (r-w b))
         (foc (view-focused-p v)))
    (fill-row v 0 0 w (role :label)) (fill-row v 0 1 w (role :label))
    (dotimes (i (sw-count v))
      (let ((cx (* i 3)))
        (when (<= (+ cx 2) w)
          (let ((cattr (if (sw-bg-p v) (revision:make-attr 0 i) (revision:make-attr i 0)))
                (ch    (if (sw-bg-p v) #\Space #\█)))
            (%put-cell (+ ax cx) ay ch cattr) (%put-cell (+ ax cx 1) ay ch cattr))
          (when (= i (sw-value v))                    ; marker under the chosen swatch
            (let ((m (if foc #\▲ #\·)))
              (%put-cell (+ ax cx) (1+ ay) m (role :label)) (%put-cell (+ ax cx 1) (1+ ay) m (role :label)))))))))

(defmethod handle-event ((v color-swatches) (e key-event))
  (case (event-keysym e)
    (:left  (setf (sw-value v) (mod (1- (sw-value v)) (sw-count v))) (sw-notify v) (setf (handled-p e) t))
    (:right (setf (sw-value v) (mod (1+ (sw-value v)) (sw-count v))) (sw-notify v) (setf (handled-p e) t))
    (t (call-next-method))))

(defmethod handle-event ((v color-swatches) (e mouse-down))
  (let ((i (floor (mouse-col v e) 3)))
    (when (< i (sw-count v)) (setf (sw-value v) i) (sw-notify v)))
  (setf (handled-p e) t))

;;; A swatch showing sample text in the currently-chosen fg/bg attribute.
(defclass color-preview (view)
  ((attr :initform (revision:make-attr 7 1) :accessor cp-attr))
  (:metaclass reactive-class))
(defmethod draw ((v color-preview))
  (fill-row v 0 0 (r-w (view-bounds v)) (cp-attr v))
  (draw-text v 1 0 " Sample — the quick brown fox  AaBbCc 0123 " (cp-attr v)))

(defun %color-refresh-preview (d)
  (let ((pv (find-view d 'preview)))
    (when pv (setf (cp-attr pv) (revision:make-attr (sw-value (find-view d 'fg)) (sw-value (find-view d 'bg))))
          (invalidate pv))))

(define-command color-apply (v e)
  "Set the chosen role's attribute from the fg/bg swatches and repaint live."
  (let* ((d (view-root v))
         (role (nth (cluster-value (find-view d 'role)) *color-roles*))
         (fg (sw-value (find-view d 'fg))) (bg (sw-value (find-view d 'bg))))
    (setf (getf *theme* role) (revision:make-attr fg bg))
    (let ((bg-view (context-root *context*))) (when bg-view (invalidate bg-view)))))

(defun make-color-dialog ()
  "Visual colour customiser: pick a role, then a foreground and background from
the swatch strips (with a live sample); Apply previews it on *THEME*."
  (let ((d (ui (dialog (:title " Colours " :keymap *dialog-keys* :value-fn (lambda (d) (declare (ignore d)) t))
                 (stack
                   (1 (label :role :label :link 'role :text " ~R~ole:"))
                   (9 (cluster :name 'role :mode :radio
                        :items (mapcar (lambda (r) (string-downcase (symbol-name r))) *color-roles*) :value 0))
                   (1 (label :role :label :link 'fg :text " ~F~oreground  (←/→):"))
                   (2 (color-swatches :name 'fg :count 16 :value 7
                        :on-change (lambda (v) (%color-refresh-preview (view-root v)))))
                   (1 (label :role :label :link 'bg :text " ~B~ackground  (←/→):"))
                   (2 (color-swatches :name 'bg :count 8 :bg-p t :value 1
                        :on-change (lambda (v) (%color-refresh-preview (view-root v)))))
                   (1 (color-preview :name 'preview))
                   (:fill (static-text :text ""))
                   (1 (row (:fill (static-text :text ""))
                           (9  (button :label "Apply" :command 'color-apply))
                           (10 (button :label "Done"  :command 'accept)))))))))
    (%color-refresh-preview d)
    (exec-view d :width 54 :height 20)))

;;; --- general dialog helpers (relocated from the now-revl project window) -----
;;; A default directory for file dialogs (the IDE's Change-dir sets it), a modal
;;; one-line prompt, and a Yes/No confirm — all toolkit-level, used across the
;;; framework, so they belong with the other dialogs rather than in an app window.

(defvar *project-dir* "/Users/mkennedy/Projects/common-lisp/revision/"
  "Default root for file dialogs / new project-manager windows; set by Change-dir.")

(defun prompt-string (title label)
  "Modal one-line prompt; return the entered string, or NIL on cancel."
  (let ((d (ui (dialog (:title title :keymap *dialog-keys*
                        :value-fn (lambda (d) (input-text (find-view d 'q))))
                 (stack
                   (1 (row ((+ 2 (length label)) (static-text :role :label :text label))
                           (:fill (input-line :name 'q))))
                   (1 (static-text :role :status :text " Enter: search · Esc: cancel ")))))))
    (let ((r (exec-view d :width 60 :height 6))) (if (eq r :cancel) nil r))))

(defun %confirm (message)
  "A modal Yes/No dialog; return T on Yes."
  (let ((d (ui (dialog (:title " Confirm " :keymap *dialog-keys* :value-fn (constantly t))
                 (stack (1 (static-text :role :label :text message))
                        (:fill (static-text :text ""))
                        (1 (row (:fill (static-text :text ""))
                                (9  (button :label "Yes" :command 'accept))
                                (9  (button :label "No"  :command 'cancel)))))))))
    (not (eq (exec-view d :width 54 :height 7) :cancel))))
