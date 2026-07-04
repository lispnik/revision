;;;; outline-node.lisp --- the collapsible-tree NODE data structure.
;;;;
;;;; Just the data model (a node + lazy-loader/expansion helpers); it carries no
;;;; view dependencies, so both the classic TOUTLINE view and the revision outline
;;;; widget build on it.  (The classic view lives in src/outline.lisp.)

(in-package #:revision)

(defstruct (outline-node (:constructor make-outline-node (text &optional children data setter)))
  "One node of a collapsible outline/tree: its display TEXT, child nodes, current
expansion state, an arbitrary DATA payload, and optional per-row COLOR, lazy
LOADER, and DATA SETTER hooks."
  (text "" )
  (children '())
  (expanded nil)
  (data nil)
  (color nil)     ; optional foreground colour index for this row (e.g. a git-status tint)
  (loader nil)    ; optional (lambda () -> children) called on first expand (lazy trees)
  (setter nil))   ; optional (lambda (new-value)) writing DATA back to its place

(setf (documentation 'make-outline-node 'function)
      "Construct an OUTLINE-NODE with display TEXT and optional CHILDREN, DATA
payload, and DATA SETTER function.")
(setf (documentation 'outline-node-text 'function)
      "The display text of outline node N.")
(setf (documentation 'outline-node-children 'function)
      "The list of child OUTLINE-NODEs of node N.")
(setf (documentation 'outline-node-expanded 'function)
      "True when outline node N is currently expanded (its children shown).")
(setf (documentation 'outline-node-data 'function)
      "The arbitrary application payload attached to outline node N.")
(setf (documentation 'outline-node-color 'function)
      "Optional foreground colour index for node N's row (e.g. a git-status tint), or NIL.")
(setf (documentation 'outline-node-loader 'function)
      "Optional thunk (lambda () -> children) called on N's first expand to lazily
populate its children, or NIL for an eager node.")
(setf (documentation 'outline-node-setter 'function)
      "Optional function (lambda (new-value)) that writes node N's edited DATA back
to its source, or NIL.")

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
