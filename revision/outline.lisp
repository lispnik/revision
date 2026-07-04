;;;; outline.lisp --- the outline widget ported onto the revision kernel.
;;;;
;;;; Compare with src/outline.lisp (the classic TOutline): there is no integer
;;;; command, no event-type COND, and no manual DRAW-VIEW calls.  Navigation
;;;; keys are data (a keymap), each maps to a named command, mutating a reactive
;;;; slot (FOCUSED/TOP) repaints automatically, and colours come from theme
;;;; roles.  The lazy outline-node data structure is reused from revision intact.

(in-package #:revision)

(defvar *running* nil)

(defclass outline (view)
  ((roots   :initarg :roots :initform '() :accessor outline-roots
            :documentation "List of top-level OUTLINE-NODE structures forming the tree.")
   (focused :initform 0 :accessor outline-focused
            :documentation "Row index (into the flattened visible nodes) of the focused node.")
   (top     :initform 0 :accessor outline-top
            :documentation "Index of the first visible row (the vertical scroll offset).")
   (hleft   :initform 0 :accessor outline-hleft))          ; horizontal scroll offset (cols)
  (:metaclass reactive-class)
  (:documentation "A collapsible tree view over OUTLINE-NODE trees, with lazy child loading.
FOCUSED/TOP are reactive so mutating them auto-repaints."))

(defmethod focusable-p ((ol outline)) t)

(defun ov-visible (roots)
  "List of (NODE . DEPTH) for every visible node, loading lazy children en route."
  (let ((out '()))
    (labels ((walk (nodes depth)
               (dolist (n nodes)
                 (push (cons n depth) out)
                 (when (revision:outline-node-expanded n)
                   (revision:outline-ensure-children n)               ; lazy load
                   (walk (revision:outline-node-children n) (1+ depth))))))
      (walk roots 0))
    (nreverse out)))

(defmethod draw ((ol outline))
  (let* ((b (view-bounds ol)) (h (revision::rect-height b)) (w (revision::rect-width b))
         (vis (ov-visible (outline-roots ol))) (top (outline-top ol))
         (active (or (null (view-owner ol)) (view-focused-p ol))))
    (dotimes (row h)
      (let* ((i (+ top row))
             (nd (and (< i (length vis)) (nth i vis)))
             (sel (and (= i (outline-focused ol)) active))
             (color (and nd (revision:outline-node-color (car nd))))
             (attr (cond (sel (role :focused))
                         (color (revision:make-attr color 1))
                         (t (role :normal)))))
        (fill-row ol 0 row w attr)
        (when nd
          (destructuring-bind (n . depth) nd
            (let ((s (%outline-row-string n depth)) (hl (outline-hleft ol)))
              (draw-text ol 0 row (if (< hl (length s)) (subseq s hl) "") attr))))))))

(defun %outline-row-string (n depth)
  (concatenate 'string
               (make-string (* 2 depth) :initial-element #\Space)
               (cond ((not (revision:outline-node-expandable-p n)) "  ")
                     ((revision:outline-node-expanded n) "- ")
                     (t "+ "))
               (revision:outline-node-text n)))

(defun %outline-maxwidth (ol)
  "Widest visible row (chars), for the horizontal scrollbar extent (0 when empty)."
  (let ((m 0))
    (dolist (nd (ov-visible (outline-roots ol)) m)
      (setf m (max m (length (%outline-row-string (car nd) (cdr nd))))))))

;;; --- navigation helpers (mutate reactive slots -> auto repaint) -------------

(defun ov-current (ol)
  "The OUTLINE-NODE currently focused, or NIL when the tree is empty."
  (let ((vis (ov-visible (outline-roots ol))))
    (and (< (outline-focused ol) (length vis)) (car (nth (outline-focused ol) vis)))))

(defun ov-scroll-to-focus (ol)
  (let ((h (revision::rect-height (view-bounds ol))) (f (outline-focused ol)) (top (outline-top ol)))
    (cond ((< f top) (setf (outline-top ol) f))
          ((>= f (+ top h)) (setf (outline-top ol) (1+ (- f h)))))))

(defun ov-move (ol delta)
  (let ((n (length (ov-visible (outline-roots ol)))))
    (when (plusp n)
      (setf (outline-focused ol) (min (max 0 (+ (outline-focused ol) delta)) (1- n)))
      (ov-scroll-to-focus ol))))

(defmethod handle-event ((ol outline) (e mouse-down))
  (let ((row (+ (outline-top ol) (mouse-row ol e))))
    (when (and (>= row 0) (< row (length (ov-visible (outline-roots ol)))))
      (setf (outline-focused ol) row) (ov-scroll-to-focus ol) (invalidate ol)))
  (setf (handled-p e) t))

(defmethod handle-event ((ol outline) (e wheel-event))
  (ov-move ol (* 3 (event-delta e))) (setf (handled-p e) t))

;;; --- commands + keymap ------------------------------------------------------

(define-command quit (v e) "Leave the current view / close the window." (setf *running* nil))
(define-command cursor-up   (v e) "Move the selection up."   (ov-move v -1))
(define-command cursor-down (v e) "Move the selection down." (ov-move v 1))

(define-command activate (v e)
  "Expand or collapse the focused node."
  (let ((n (ov-current v)))
    (when (and n (revision:outline-node-expandable-p n))
      (setf (revision:outline-node-expanded n) (not (revision:outline-node-expanded n)))
      (when (revision:outline-node-expanded n) (revision:outline-ensure-children n))
      (invalidate v))))                ; the node is a struct (not reactive) -> repaint by hand

(define-command collapse (v e)
  "Collapse the focused node, or move to its parent."
  (let ((n (ov-current v)))
    (if (and n (revision:outline-node-expandable-p n) (revision:outline-node-expanded n))
        (progn (setf (revision:outline-node-expanded n) nil) (invalidate v))
        (ov-move v -1))))

(defkeymap *global-keys* ()
  (#\q quit)
  (:esc quit))   ; an escape hatch that works even while a text field is focused

(defkeymap *outline-keys* (*global-keys*)
  (:up    cursor-up)
  (:down  cursor-down)
  (:enter activate)
  (:right activate)
  (:left  collapse))

;;; --- sample data ------------------------------------------------------------

(defun demo-roots ()
  "A small hand-built tree, including a lazily-loaded directory and a tinted node."
  (flet ((file (name &optional color)
           (let ((n (revision:make-outline-node name nil :file)))
             (when color (setf (revision:outline-node-color n) color))
             n)))
    (let* ((utils (revision:make-outline-node "utils/" (list (file "strings.lisp")
                                                            (file "math.lisp"))))
           (lazy  (revision:make-outline-node "vendor/  (lazy)")))
      (setf (revision:outline-node-loader lazy)
            (lambda () (list (file "big-lib.lisp") (file "more.lisp"))))
      (let* ((src  (revision:make-outline-node "src/" (list utils lazy (file "main.lisp" 14))))
             (root (revision:make-outline-node "my-project"
                                              (list src (file "README.md") (file ".gitignore")))))
        (setf (revision:outline-node-expanded utils) t
              (revision:outline-node-expanded src) t
              (revision:outline-node-expanded root) t)
        (list root)))))
