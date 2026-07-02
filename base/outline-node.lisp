;;;; outline-node.lisp --- the collapsible-tree NODE data structure.
;;;;
;;;; Just the data model (a node + lazy-loader/expansion helpers); it carries no
;;;; view dependencies, so both the classic TOUTLINE view and the tv2 outline
;;;; widget build on it.  (The classic view lives in src/outline.lisp.)

(in-package #:tvision)

(defstruct (outline-node (:constructor make-outline-node (text &optional children data setter)))
  (text "" )
  (children '())
  (expanded nil)
  (data nil)
  (color nil)     ; optional foreground colour index for this row (e.g. a git-status tint)
  (loader nil)    ; optional (lambda () -> children) called on first expand (lazy trees)
  (setter nil))   ; optional (lambda (new-value)) writing DATA back to its place

(defun outline-node (text &rest children)
  "Convenience: a node with TEXT and the given child nodes (expanded)."
  (let ((n (make-outline-node text children)))
    (setf (outline-node-expanded n) t)
    n))

(defun outline-node-expandable-p (n)
  "True when N can be expanded -- it has children, or a not-yet-loaded LOADER."
  (or (outline-node-children n) (outline-node-loader n)))

(defun outline-ensure-children (n)
  "Lazily populate N's children from its LOADER the first time they are needed.
A no-op for ordinary (eager) nodes.  Returns N."
  (when (and (outline-node-loader n) (null (outline-node-children n)))
    (setf (outline-node-children n) (funcall (outline-node-loader n))))
  n)
