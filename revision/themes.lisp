;;;; themes.lisp --- the built-in colour palettes and theme switching.
;;;;
;;;; *THEME* (in draw.lisp) is the live role->attribute map; here are the shipped
;;;; palettes (Blue / Dark / Light) and APPLY-THEME / CYCLE-THEME, which rebind
;;;; *THEME* and repaint.  The Settings window and the Options menu drive these.

(in-package #:revision)

;;; --- colour themes ----------------------------------------------------------

(defparameter *theme-classic* (copy-list *theme*))
(defparameter *theme-dark*
  (list :normal          (revision:make-attr 7 0)     :focused         (revision:make-attr 15 4)
        :frame           (revision:make-attr 15 0)    :frame-inactive  (revision:make-attr 8 0)
        :menu-bar        (revision:make-attr 0 7)     :menu            (revision:make-attr 0 7)
        :menu-selected   (revision:make-attr 15 4)    :menu-hotkey     (revision:make-attr 4 7)
        :menu-disabled   (revision:make-attr 8 7)     :status          (revision:make-attr 15 8)
        :button          (revision:make-attr 0 7)     :button-focused  (revision:make-attr 15 4)
        :label           (revision:make-attr 14 0)    :input           (revision:make-attr 15 8)
        :input-focused   (revision:make-attr 15 0)    :error           (revision:make-attr 15 4)
        :desktop         (revision:make-attr 8 0)     :scrollbar       (revision:make-attr 7 8)
        :scrollbar-thumb (revision:make-attr 15 8)))
(defparameter *theme-light*
  (list :normal          (revision:make-attr 0 7)     :focused         (revision:make-attr 15 1)
        :frame           (revision:make-attr 0 7)     :frame-inactive  (revision:make-attr 8 7)
        :menu-bar        (revision:make-attr 0 7)     :menu            (revision:make-attr 0 7)
        :menu-selected   (revision:make-attr 15 1)    :menu-hotkey     (revision:make-attr 4 7)
        :menu-disabled   (revision:make-attr 8 7)     :status          (revision:make-attr 0 3)
        :button          (revision:make-attr 15 1)    :button-focused  (revision:make-attr 14 1)
        :label           (revision:make-attr 1 7)     :input           (revision:make-attr 0 15)
        :input-focused   (revision:make-attr 0 15)    :error           (revision:make-attr 15 4)
        :desktop         (revision:make-attr 8 7)     :scrollbar       (revision:make-attr 0 7)
        :scrollbar-thumb (revision:make-attr 1 7)))
(defparameter *themes* (list (cons "Blue" *theme-classic*) (cons "Dark" *theme-dark*) (cons "Light" *theme-light*)))
(defvar *theme-index* 0)

(defun apply-theme (dt index &key note)
  "Switch to theme INDEX (into *THEMES*) and redraw; optionally announce it."
  (setf *theme-index* (mod index (length *themes*)))
  (destructuring-bind (name . palette) (nth *theme-index* *themes*)
    (setf *theme* palette)
    (invalidate dt)
    (when note (%tool-note (format nil "colour theme: ~a" name)))))

(defun cycle-theme (dt)
  (apply-theme dt (1+ *theme-index*) :note t))
