;;;; table.lisp --- a column/grid list viewer (revision's TListViewer/TTableView).
;;;;
;;;; COLUMNS is a list of (TITLE WIDTH ACCESSOR); ACCESSOR maps a row object to
;;;; its cell value.  Row 0 is a header; the rest are the scrollable, selectable
;;;; data rows.  Implements the scroller protocol so a hosting window draws a
;;;; frame scrollbar, and supports keyboard + mouse selection and the wheel.

(in-package #:revision)

(defclass table-view (view)
  ((columns     :initarg :columns :initform '() :accessor table-columns
                :documentation "Column specs, each a (TITLE WIDTH ACCESSOR) list; ACCESSOR maps a row to its cell value.")
   (rows        :initarg :rows :initform '() :accessor table-rows
                :documentation "List of row objects, one per data row (the header is drawn separately).")
   (selected    :initform 0 :accessor table-selected
                :documentation "Index into ROWS of the currently selected/highlighted data row.")
   (top         :initform 0 :accessor table-top)                           ; first visible data row
   (hleft       :initform 0 :accessor table-hleft)                         ; horizontal scroll offset (cols)
   (on-activate :initarg :on-activate :initform nil :accessor table-on-activate)
   (on-inspect  :initarg :on-inspect  :initform nil :accessor table-on-inspect))   ; (tv ROW) -> open the inspector (Alt-I)
  (:metaclass reactive-class)
  (:documentation "A columnar table/grid viewer: a fixed header over scrollable, selectable data
rows.  COLUMNS defines the (title, width, accessor) of each column; supports
keyboard and mouse selection, the wheel, and the scroller protocol for frame
scrollbars."))

(defmethod focusable-p ((tv table-view)) t)

(defun %pad (val w)
  "VAL as a string padded/truncated to W columns (with a trailing gap)."
  (let* ((s (princ-to-string val)) (n (length s)))
    (cond ((>= n w) (subseq s 0 (max 0 (1- w))))
          (t (concatenate 'string s (make-string (- w n) :initial-element #\Space))))))

(defun table-page (tv) (max 1 (1- (r-h (view-bounds tv)))))    ; visible data rows (header takes one)

(defun table-scroll-fix (tv)
  (let ((h (table-page tv)) (sel (table-selected tv)) (top (table-top tv)))
    (cond ((< sel top) (setf (table-top tv) sel))
          ((>= sel (+ top h)) (setf (table-top tv) (1+ (- sel h)))))))

(defun table-move (tv delta)
  (let ((n (length (table-rows tv))))
    (when (plusp n)
      (setf (table-selected tv) (max 0 (min (1- n) (+ (table-selected tv) delta))))
      (table-scroll-fix tv))))

(defun %table-width (tv) (reduce #'+ (table-columns tv) :key #'second :initial-value 0))
(defun %table-header-string (tv)
  (with-output-to-string (s) (dolist (c (table-columns tv)) (write-string (%pad (first c) (second c)) s))))
(defun %table-row-string (tv rowdata)
  (with-output-to-string (s) (dolist (c (table-columns tv)) (write-string (%pad (funcall (third c) rowdata) (second c)) s))))

(defmethod draw ((tv table-view))
  (let* ((b (view-bounds tv)) (h (r-h b)) (w (r-w b)) (active (view-focused-p tv))
         (rows (table-rows tv)) (top (table-top tv)) (hl (table-hleft tv)))
    (let ((hattr (role :label)))                                ; header (scrolls with the rows)
      (fill-row tv 0 0 w hattr)
      (draw-text tv 0 0 (%hclip (%table-header-string tv) hl) hattr))
    (dotimes (row (1- h))                                       ; data rows
      (let* ((i (+ top row)) (y (1+ row))
             (attr (if (and (= i (table-selected tv)) active) (role :focused) (role :normal))))
        (fill-row tv 0 y w attr)
        (when (< i (length rows))
          (draw-text tv 0 y (%hclip (%table-row-string tv (nth i rows)) hl) attr))))))

(defun table-activate (tv)
  (when (and (table-on-activate tv) (< (table-selected tv) (length (table-rows tv))))
    (funcall (table-on-activate tv) tv (nth (table-selected tv) (table-rows tv)))))

(defmethod handle-event ((tv table-view) (e key-event))
  (let ((ks (event-keysym e)) (n (length (table-rows tv))))
    (cond
      ((eql ks :up)    (table-move tv -1) (setf (handled-p e) t))
      ((eql ks :down)  (table-move tv 1)  (setf (handled-p e) t))
      ((eql ks :pgup)  (table-move tv (- (table-page tv))) (setf (handled-p e) t))
      ((eql ks :pgdn)  (table-move tv (table-page tv)) (setf (handled-p e) t))
      ((eql ks :home)  (setf (table-selected tv) 0) (table-scroll-fix tv) (setf (handled-p e) t))
      ((eql ks :end)   (setf (table-selected tv) (max 0 (1- n))) (table-scroll-fix tv) (setf (handled-p e) t))
      ((eql ks :left)  (scroll-hto tv (- (table-hleft tv) 8)) (setf (handled-p e) t))
      ((eql ks :right) (scroll-hto tv (+ (table-hleft tv) 8)) (setf (handled-p e) t))
      ((eql ks :enter) (table-activate tv) (setf (handled-p e) t))
      ((and (table-on-inspect tv) (characterp ks) (char-equal ks #\i)       ; Alt-I: open the focused row in the inspector
            (logtest (event-modifiers e) revision::+md-alt+))
       (when (< (table-selected tv) n)
         (funcall (table-on-inspect tv) tv (nth (table-selected tv) (table-rows tv))))
       (setf (handled-p e) t))
      (t (call-next-method)))))

(defmethod view-key-hints ((tv table-view))
  '(("Up / Down"    . "move the selected row")
    ("PgUp / PgDn"  . "page the selection")
    ("Home / End"   . "first / last row")
    ("Left / Right" . "scroll columns horizontally")
    ("Enter"        . "activate the selected row")
    ("Alt+I"        . "inspect the selected row (when enabled)")))

(defmethod handle-event ((tv table-view) (e mouse-down))
  (let ((row (+ (table-top tv) (1- (mouse-row tv e)))))         ; row 0 is the header
    (when (and (>= (mouse-row tv e) 1) (< row (length (table-rows tv))))
      (setf (table-selected tv) row) (table-scroll-fix tv)))
  (setf (handled-p e) t))

(defmethod handle-event ((tv table-view) (e wheel-event))
  (table-move tv (* 3 (event-delta e))) (setf (handled-p e) t))

;;; scroller protocol (data rows scroll under the fixed header)
(defmethod scroll-page ((tv table-view)) (table-page tv))
(defmethod scroll-pos  ((tv table-view)) (table-top tv))
(defmethod scroll-max  ((tv table-view)) (max 0 (- (length (table-rows tv)) (table-page tv))))
(defmethod scroll-to   ((tv table-view) pos) (setf (table-top tv) (max 0 (min pos (scroll-max tv)))) (invalidate tv))
(defmethod scroll-hpage ((tv table-view)) (max 1 (if (view-bounds tv) (r-w (view-bounds tv)) 1)))
(defmethod scroll-hpos  ((tv table-view)) (table-hleft tv))
(defmethod scroll-hmax  ((tv table-view)) (max 0 (- (%table-width tv) (scroll-hpage tv))))
(defmethod scroll-hto   ((tv table-view) pos) (setf (table-hleft tv) (max 0 (min pos (scroll-hmax tv)))) (invalidate tv))

;;; A window hosting a TABLE-VIEW; the application (which names the view) provides the
;;; WINDOW-SAVE-STATE / WINDOW-RESTORE-STATE methods so the view name matches its package.
(defclass table-window (window) ()
  (:metaclass reactive-class)
  (:documentation "A window whose scroll target is a TABLE-VIEW; the desktop saves and
restores its scroll offset and selected row via the app's persistence methods."))
