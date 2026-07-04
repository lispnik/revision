;;;; geometry.lisp --- TPoint and TRect, the geometric primitives of Turbo Vision.

(in-package #:revision)

;;; ---------------------------------------------------------------------------
;;; TPoint
;;; ---------------------------------------------------------------------------

(defstruct (tpoint (:constructor make-tpoint (&optional (x 0) (y 0)))
                   (:conc-name point-))
  "A 2-D screen coordinate: integer column X and row Y, 0-based with the origin
at the top-left of the screen."
  (x 0 :type fixnum)
  (y 0 :type fixnum))

(setf (documentation 'make-tpoint 'function)
      "Construct a TPOINT at column X and row Y (both default to 0).")
(setf (documentation 'point-x 'function)
      "The column (X) coordinate of point P.")
(setf (documentation 'point-y 'function)
      "The row (Y) coordinate of point P.")

(declaim (inline point-equal-p copy-point))
(defun point-equal-p (a b)
  "True when points A and B have the same X and Y coordinates."
  (and (= (point-x a) (point-x b))
       (= (point-y a) (point-y b))))

(defun copy-point (p)
  "Return a fresh TPOINT with the same coordinates as P."
  (make-tpoint (point-x p) (point-y p)))

;;; ---------------------------------------------------------------------------
;;; TRect
;;;
;;; A rectangle is defined by two corner points: A (top-left, inclusive) and
;;; B (bottom-right, exclusive), exactly as in Turbo Vision.
;;; ---------------------------------------------------------------------------

(defstruct (trect (:constructor %make-trect)
                  (:conc-name rect-))
  "An axis-aligned rectangle given by two corner points: A (AX,AY) is the
top-left corner, inclusive, and B (BX,BY) is the bottom-right corner, exclusive."
  (ax 0 :type fixnum)
  (ay 0 :type fixnum)
  (bx 0 :type fixnum)
  (by 0 :type fixnum))

(setf (documentation 'rect-ax 'function)
      "The left edge (X of corner A) of rectangle R, inclusive.")
(setf (documentation 'rect-ay 'function)
      "The top edge (Y of corner A) of rectangle R, inclusive.")
(setf (documentation 'rect-bx 'function)
      "The right edge (X of corner B) of rectangle R, exclusive.")
(setf (documentation 'rect-by 'function)
      "The bottom edge (Y of corner B) of rectangle R, exclusive.")

(defun make-trect (ax ay bx by)
  "Construct a TRECT from top-left corner (AX,AY) and bottom-right corner (BX,BY)."
  (%make-trect :ax ax :ay ay :bx bx :by by))

(declaim (inline rect-width rect-height))
(defun rect-width (r) "The width of rectangle R (BX - AX)." (- (rect-bx r) (rect-ax r)))
(defun rect-height (r) "The height of rectangle R (BY - AY)." (- (rect-by r) (rect-ay r)))

(defun rect-empty-p (r)
  "True when rectangle R has no area (its A corner meets or crosses its B corner)."
  (or (>= (rect-ax r) (rect-bx r))
      (>= (rect-ay r) (rect-by r))))

(defun rect-equal-p (a b)
  "True when rectangles A and B have identical corner coordinates."
  (and (= (rect-ax a) (rect-ax b)) (= (rect-ay a) (rect-ay b))
       (= (rect-bx a) (rect-bx b)) (= (rect-by a) (rect-by b))))

(defun copy-rect (r)
  "Return a fresh TRECT with the same corners as R."
  (make-trect (rect-ax r) (rect-ay r) (rect-bx r) (rect-by r)))

(defun rect-assign (r ax ay bx by)
  "Destructively set rectangle R's corners to (AX,AY)-(BX,BY); return R."
  (setf (rect-ax r) ax (rect-ay r) ay (rect-bx r) bx (rect-by r) by)
  r)

(defun rect-contains-p (r x y)
  "True when point (X,Y) lies within rectangle R (A inclusive, B exclusive)."
  (and (>= x (rect-ax r)) (< x (rect-bx r))
       (>= y (rect-ay r)) (< y (rect-by r))))

(defun rect-move (r dx dy)
  "Destructively translate rectangle R by DX columns and DY rows; return R."
  (incf (rect-ax r) dx) (incf (rect-bx r) dx)
  (incf (rect-ay r) dy) (incf (rect-by r) dy)
  r)

(defun rect-grow (r dx dy)
  "Destructively grow rectangle R by DX columns on each side and DY rows on the
top and bottom (negative values shrink it); return R."
  (decf (rect-ax r) dx) (incf (rect-bx r) dx)
  (decf (rect-ay r) dy) (incf (rect-by r) dy)
  r)

(defun rect-intersect (r o)
  "Destructively set R to the intersection of R and O."
  (setf (rect-ax r) (max (rect-ax r) (rect-ax o))
        (rect-ay r) (max (rect-ay r) (rect-ay o))
        (rect-bx r) (min (rect-bx r) (rect-bx o))
        (rect-by r) (min (rect-by r) (rect-by o)))
  ;; normalise empty rectangles
  (when (< (rect-bx r) (rect-ax r)) (setf (rect-bx r) (rect-ax r)))
  (when (< (rect-by r) (rect-ay r)) (setf (rect-by r) (rect-ay r)))
  r)

(defun rect-union (r o)
  "Destructively set R to the bounding union of R and O."
  (setf (rect-ax r) (min (rect-ax r) (rect-ax o))
        (rect-ay r) (min (rect-ay r) (rect-ay o))
        (rect-bx r) (max (rect-bx r) (rect-bx o))
        (rect-by r) (max (rect-by r) (rect-by o)))
  r)
