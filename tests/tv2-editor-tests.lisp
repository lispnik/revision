;;;; tv2-editor-tests.lisp --- editor display-width (wide CJK / emoji) tests.
;;;;
;;;; The tv2 editor stores the cursor as a code-point index but lays out text in
;;;; DISPLAY columns, so wide East-Asian glyphs and emoji occupy two cells and
;;;; the rest of the line stays aligned (mirrors src/draw-buffer.lisp).  These
;;;; exercise that column math directly -- no UI needed.
;;;;
;;;; Run from the repo root:  sbcl --script tests/tv2-editor-tests.lisp

(require :asdf)
;; register this dir tree so tv2.asd, tvision.asd and the vendored systems/ deps
;; all resolve without a global ocicl/ASDF config (works on bare CI too).
(asdf:initialize-source-registry
 (list :source-registry (list :tree (uiop:getcwd)) :inherit-configuration))
(handler-bind ((warning #'muffle-warning)) (asdf:load-system :tv2))
(in-package #:tv2)

(defvar *pass* 0) (defvar *fail* 0)
(defmacro check (desc form)
  `(handler-case (if ,form (progn (incf *pass*) (format t "  ok   ~a~%" ,desc))
                     (progn (incf *fail*) (format t "  FAIL ~a~%" ,desc)))
     (error (e) (incf *fail*) (format t "  ERR  ~a -- ~a~%" ,desc e))))

(defparameter +cjk+ (code-char #x65e5))   ; 日  (East-Asian Wide)
(defparameter +emoji+ (code-char #x1F389)) ; 🎉

;;; ===========================================================================
(format t "~&## char / string display width~%")
(check "ASCII is one column"      (= (%cw #\a) 1))
(check "CJK is two columns"       (= (%cw +cjk+) 2))
(check "emoji is two columns"     (= (%cw +emoji+) 2))
(check "combining/narrow stays 1" (= (%cw (code-char #x3bb)) 1))          ; λ
(let ((s (coerce (list #\a +cjk+ #\b) 'string)))                           ; "a日b"
  (check "string-width mixed = 4" (= (%vwidth s) 4))
  (check "string-width pure CJK"  (= (%vwidth (coerce (list +cjk+ +cjk+ +cjk+) 'string)) 6)))

;;; ===========================================================================
(format t "~%## code-point index <-> display column~%")
(let ((s (coerce (list #\a +cjk+ #\b) 'string)))    ; a(1) 日(2) b(1)
  (check "col->vc @0 = 0" (= (%col->vc s 0) 0))
  (check "col->vc @1 = 1" (= (%col->vc s 1) 1))     ; just after 'a'
  (check "col->vc @2 = 3" (= (%col->vc s 2) 3))     ; just after 日 (1+2)
  (check "col->vc @3 = 4" (= (%col->vc s 3) 4))
  (check "vc->col 0 = 0" (= (%vc->col s 0) 0))
  (check "vc->col 1 = 1" (= (%vc->col s 1) 1))       ; start of 日
  (check "vc->col 2 = 1 (mid wide glyph)" (= (%vc->col s 2) 1))
  (check "vc->col 3 = 2" (= (%vc->col s 3) 2))       ; after 日
  (check "vc->col past end clamps" (= (%vc->col s 99) 3)))
(let ((s (coerce (list #\a +cjk+ +cjk+ #\b) 'string)))     ; a日日b
  (check "index<->column round-trips at boundaries"
         (every (lambda (i) (= (%vc->col s (%col->vc s i)) i)) '(0 1 2 3 4))))

;;; ===========================================================================
(format t "~%## soft-wrap segmentation by display width~%")
(let ((cjk5 (coerce (loop repeat 5 collect +cjk+) 'string)))   ; 5 CJK = 10 cells -> rows of 3 + 2
  (check "wraps 10-cell line at 6 cols -> rows start (0 3)" (equal (%segs-of cjk5 6) '(0 3)))
  (check "two visual rows" (= (%nsegs cjk5 6) 2)))
(check "fits in one row -> single segment"
       (equal (%segs-of (coerce (list +cjk+ +cjk+) 'string) 6) '(0)))
(let ((cjk6 (coerce (loop repeat 6 collect +cjk+) 'string)))   ; 6 CJK = exactly two full rows
  (check "an exactly-full line adds a trailing cursor row" (equal (%segs-of cjk6 6) '(0 3 6))))
(let ((segs (%segs-of (coerce (loop repeat 5 collect +cjk+) 'string) 6)))  ; (0 3)
  (check "seg-of col 0 -> row 0" (= (%seg-of segs 0) 0))
  (check "seg-of col 2 -> row 0" (= (%seg-of segs 2) 0))
  (check "seg-of col 3 -> row 1" (= (%seg-of segs 3) 1))
  (check "seg-of col 5 -> row 1" (= (%seg-of segs 5) 1)))

;;; ===========================================================================
(format t "~%## cursor + vertical motion across wide glyphs~%")
(let ((te (make-instance 'text-edit)))
  (setf (view-bounds te) (rect 0 0 20 6))               ; 20 display columns
  (te-set-text te (format nil "abcdef~%~a~a~agh~%xyz"    ; line1: 日日日gh
                          +cjk+ +cjk+ +cjk+))
  (setf (te-wrap te) t (te-cy te) 0 (te-cx te) 4)       ; display col 4 on "abcdef"
  (te-vmove te 1)
  (check "down moves to line 1" (= (te-cy te) 1))
  (check "down keeps ~display col 4 (lands after 日日 = col 4)"
         (<= (abs (- (%col->vc (te-cur te) (te-cx te)) 4)) 1))
  (te-vmove te -1)
  (check "up returns to line 0" (= (te-cy te) 0))
  (check "up keeps ~display col 4" (<= (abs (- (%col->vc (te-cur te) (te-cx te)) 4)) 1)))

(let ((te (make-instance 'text-edit)))                  ; cursor display column past wide glyphs
  (te-set-text te (coerce (list #\a +cjk+ #\b +cjk+ #\c) 'string))   ; a日b日c
  (check "cursor after 'a日b' sits at display col 4" (= (%col->vc (te-cur te) 3) 4))
  (check "end-of-line display col = full width 7" (= (%col->vc (te-cur te) 5) 7)))

;;; ===========================================================================
(format t "~%## horizontal scroll tracks display columns (flat mode)~%")
(let ((te (make-instance 'text-edit)))
  (setf (view-bounds te) (rect 0 0 6 3))                ; 6 columns wide, no gutter
  (te-set-text te (coerce (loop repeat 10 collect +cjk+) 'string))  ; 10 CJK = 20 cells
  (setf (te-wrap te) nil (te-cy te) 0 (te-cx te) 9)     ; near the end (display col 18)
  (te-ensure-visible te)
  (check "scrolls right so the cursor's display column is visible"
         (<= (te-left te) (%col->vc (te-cur te) (te-cx te)) (+ (te-left te) 6))))

;;; ===========================================================================
(format t "~%## grapheme clusters (combining marks, skin-tone / ZWJ emoji)~%")
(let ((acc (coerce (list #\e (code-char #x301)) 'string)))          ; "é" = e + combining acute
  (check "combining pair is one grapheme"    (= (%next-col acc 0) 2))
  (check "combining cluster is one column"   (= (%vwidth acc) 1))
  (check "display column past the cluster=1" (= (%col->vc acc 2) 1))
  (check "prev-col steps over the cluster"   (= (%prev-col acc 2) 0)))
(let ((skin (coerce (list (code-char #x1F44D) (code-char #x1F3FD)) 'string)))  ; 👍🏽 base+skin-tone
  (check "skin-tone emoji is one grapheme"   (= (%next-col skin 0) 2))
  (check "skin-tone cluster is two columns"  (= (%vwidth skin) 2))
  (check "vc->col mid wide cluster -> start" (= (%vc->col skin 1) 0)))
(let ((fam (coerce (list (code-char #x1F468) (code-char #x200D) (code-char #x1F469)
                         (code-char #x200D) (code-char #x1F467)) 'string)))    ; 👨‍👩‍👧 ZWJ sequence
  (check "ZWJ family is a single grapheme"   (= (%next-col fam 0) (length fam)))
  (check "ZWJ family is two columns"         (= (%vwidth fam) 2)))
(let ((te (make-instance 'text-edit)))        ; backspace removes a whole cluster, not one code point
  (te-set-text te (coerce (list #\a #\e (code-char #x301) #\b) 'string))       ; a é b
  (setf (te-cy te) 0 (te-cx te) 3)            ; cursor after the é cluster (a=0, é=1..3)
  (te-backspace te)
  (check "backspace deletes the whole é grapheme" (string= (te-cur te) "ab"))
  (check "cursor sits at the cluster start"       (= (te-cx te) 1)))

;;; ===========================================================================
(format t "~%## horizontal scrolling (scrollback / table-view / outline)~%")
(let ((sb (make-instance 'scrollback)))
  (setf (view-bounds sb) (rect 0 0 20 5))
  (scrollback-append sb (format nil "~a~%" (make-string 100 :initial-element #\x)))
  (check "scrollback hmax > 0 for a wide line" (> (scroll-hmax sb) 0))
  (scroll-hto sb 999) (check "scrollback hpos clamps to hmax" (= (scroll-hpos sb) (scroll-hmax sb)))
  (scrollback-clear sb) (check "scrollback-clear resets hleft + maxw" (and (= (sb-hleft sb) 0) (= (scroll-hmax sb) 0))))
(let ((tv (make-instance 'table-view :columns (list (list "A" 50 #'identity) (list "B" 50 #'identity))
                                     :rows (list "r1" "r2"))))
  (setf (view-bounds tv) (rect 0 0 30 5))
  (check "table hmax > 0 when columns exceed the width" (> (scroll-hmax tv) 0))    ; 100 cols - 30
  (scroll-hto tv 999) (check "table hpos clamps to hmax" (= (scroll-hpos tv) (scroll-hmax tv))))
(let ((ol (make-instance 'outline :roots (list (%tv2-object->outline (make-string 90 :initial-element #\Q) "v")))))
  (setf (view-bounds ol) (rect 0 0 30 5))
  (check "outline hmax > 0 for a wide node" (> (scroll-hmax ol) 0))
  (scroll-hto ol 999) (check "outline hpos clamps to hmax" (= (scroll-hpos ol) (scroll-hmax ol))))
(let ((e (make-instance 'outline)))                                    ; empty must not error
  (setf (view-bounds e) (rect 0 0 30 5))
  (check "empty outline hmax = 0 (no error)" (= 0 (scroll-hmax e))))
(let* ((got '()) (lb (make-instance 'list-box :items '("a" "b")
                                    :on-type (lambda (lb ch) (declare (ignore lb)) (push ch got)))))
  (setf (view-bounds lb) (rect 0 0 10 5))
  (handle-event lb (make-instance 'key-event :keysym #\x :modifiers 0))
  (handle-event lb (make-instance 'key-event :keysym :back :modifiers 0))
  (check "list-box on-type forwards a printable key + Backspace" (equal got '(:back #\x))))
;;; Ctrl-Space mark mode (terminal-portable selection)
(let ((te (make-instance 'text-edit)))
  (te-set-text te "abcdef")
  (setf (te-mark-mode te) t (te-anchor te) (cons 0 0))
  (te-mark te (make-instance 'key-event :keysym :right :modifiers 0))
  (check "mark mode keeps the anchor on a plain move" (equal (te-anchor te) '(0 . 0)))
  (setf (te-mark-mode te) nil)
  (te-mark te (make-instance 'key-event :keysym :right :modifiers 0))
  (check "without mark mode a plain move collapses the selection" (null (te-anchor te))))
;;; emoji palette
(let ((emoji (%emoji-chars)))
  (check "emoji palette has named glyphs (from SBCL char-name)" (> (length emoji) 500))
  (check "an emoji pair is (EMOJI-STRING . NAME)"
         (let ((p (find "🎉" emoji :key #'car :test #'string=))) (and p (search "PARTY" (cdr p)))))
  (check "includes a skin-tone variant" (find-if (lambda (p) (search "medium skin tone" (cdr p))) emoji))
  (check "skin-tone variant is one grapheme"
         (let ((p (find-if (lambda (p) (search ": medium skin tone" (cdr p))) emoji)))
           (and p (= (%next-col (car p) 0) (length (car p))))))
  (check "includes a gender (man/woman) variant" (find-if (lambda (p) (search ": woman" (cdr p))) emoji)))
(check "base64 encodes correctly (OSC 52)" (string= (%base64 (sb-ext:string-to-octets "A")) "QQ=="))
(let ((lb (make-instance 'list-box :items (list (make-string 80 :initial-element #\z) "short"))))
  (setf (view-bounds lb) (rect 0 0 30 5))
  (check "list-box hmax > 0 for a wide item" (> (scroll-hmax lb) 0))
  (scroll-hto lb 999) (check "list-box hpos clamps to hmax" (= (scroll-hpos lb) (scroll-hmax lb)))
  (check "empty list-box hmax = 0"
         (let ((el (make-instance 'list-box))) (setf (view-bounds el) (rect 0 0 30 5)) (= 0 (scroll-hmax el)))))

;;; ===========================================================================
(format t "~%~d passed, ~d failed~%" *pass* *fail*)
(sb-ext:exit :code (if (zerop *fail*) 0 1))
