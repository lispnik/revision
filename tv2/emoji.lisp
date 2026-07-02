;;;; emoji.lisp --- a read-only, filterable emoji palette.
;;;;
;;;; A scrollable list of emoji, each labelled with its Unicode name (straight
;;;; from SBCL's CHAR-NAME).  Type to filter by name; Enter or a click copies the
;;;; glyph to the tv2 clipboard (paste into any editor/REPL with Ctrl-V) and, via
;;;; OSC 52, to the terminal's system clipboard (paste elsewhere with ⌘V/Ctrl-V).

(in-package #:tv2)

;;; --- OSC 52: put text on the terminal's system clipboard --------------------

(defun %base64 (bytes)
  (let ((tbl "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        (out (make-string-output-stream)) (n (length bytes)))
    (loop for i from 0 below n by 3
          for b0 = (aref bytes i)
          for b1 = (if (< (+ i 1) n) (aref bytes (+ i 1)) 0)
          for b2 = (if (< (+ i 2) n) (aref bytes (+ i 2)) 0)
          do (write-char (char tbl (ash b0 -2)) out)
             (write-char (char tbl (logior (ash (logand b0 3) 4) (ash b1 -4))) out)
             (write-char (if (< (+ i 1) n) (char tbl (logior (ash (logand b1 15) 2) (ash b2 -6))) #\=) out)
             (write-char (if (< (+ i 2) n) (char tbl (logand b2 63)) #\=) out))
    (get-output-stream-string out)))

(defun %osc52-copy (s)
  "Best-effort: set the terminal's clipboard to S via OSC 52 (ignored by terminals
that don't support it)."
  (ignore-errors
    (when tvision:*screen*
      (let ((b64 (%base64 (sb-ext:string-to-octets s :external-format :utf-8))))
        (tvision::%emit tvision:*screen* (format nil "~c]52;c;~a~c\\" #\Escape b64 #\Escape))
        (tvision::%flush-out tvision:*screen*)))))

;;; --- the emoji set (single-codepoint, named glyphs from SBCL) ---------------

(defparameter *emoji-ranges*
  '((#x1F300 . #x1F5FF) (#x1F600 . #x1F64F) (#x1F680 . #x1F6FF)   ; pictographs, emoticons, transport
    (#x1F900 . #x1F9FF) (#x1FA70 . #x1FAFF)                        ; supplemental + extended-A
    (#x2600 . #x26FF)   (#x2700 . #x27BF))                         ; misc symbols, dingbats
  "Codepoint ranges scanned for emoji.")

(defun %emoji-chars ()
  "List of (CHAR . NAME) for every assigned, named codepoint in *EMOJI-RANGES*."
  (let ((out '()))
    (dolist (r *emoji-ranges*)
      (loop for cp from (car r) to (cdr r)
            for ch = (ignore-errors (code-char cp))
            for name = (and ch (char-name ch))
            when name do (push (cons ch name) out)))
    (nreverse out)))

;;; --- the window -------------------------------------------------------------

(defclass emoji-window (window) () (:metaclass reactive-class))

(defun %emoji-refill (win all)
  "Rebuild the list from ALL, filtered by the Filter field (a name substring)."
  (let* ((lb (find-view win 'list)) (q (string-downcase (input-text (find-view win 'flt))))
         (matches (if (zerop (length q)) all
                      (remove-if-not (lambda (p) (search q (string-downcase (cdr p)))) all))))
    (setf (list-items lb)
          (mapcar (lambda (p) (format nil "~a  ~a" (car p) (substitute #\Space #\_ (cdr p)))) matches)
          (list-selected lb) 0 (list-top lb) 0 (list-hleft lb) 0)
    (invalidate win)))

(defun %emoji-copy (item)
  (when (and item (plusp (length item)))
    (let ((e (subseq item 0 (%next-col item 0))))          ; the leading grapheme is the emoji
      (setf *clipboard* e)                                 ; tv2 clipboard: paste with Ctrl-V
      (%osc52-copy e)                                       ; system clipboard: paste elsewhere
      (%tool-note (format nil "copied ~a to the clipboard" e)))))

(defun make-emoji ()
  "A read-only, scrollable emoji palette with a name Filter; Enter or a click
copies the emoji."
  (let* ((all (%emoji-chars))
         (win (make-instance 'emoji-window :title " Emoji palette " :keymap *global-keys*))
         (body (ui (stack
                     (1 (row (9 (static-text :role :label :text " Filter: "))
                             (:fill (input-line :name 'flt
                                      :on-change (lambda (il) (declare (ignore il)) (%emoji-refill win all))))))
                     (:fill (list-box :name 'list
                              :on-type (lambda (lb ch)                 ; type from the list -> the Filter field
                                         (declare (ignore lb))
                                         (let* ((flt (find-view win 'flt)) (txt (input-text flt)))
                                           (setf (input-text flt) (if (eq ch :back)
                                                                      (if (plusp (length txt)) (subseq txt 0 (1- (length txt))) txt)
                                                                      (concatenate 'string txt (string ch)))
                                                 (input-caret flt) (length (input-text flt)))
                                           (%emoji-refill win all)))
                              :on-activate (lambda (lb item) (declare (ignore lb)) (%emoji-copy item))))
                     (1 (static-text :role :status
                          :text " type to filter by name · Enter / click copies the emoji · Esc closes "))))))
    (add-subview win body)
    (%emoji-refill win all)
    (setf (window-scroll-target win) (find-view win 'list) (window-help win) :emoji)
    (values win (find-view win 'list))))

(pushnew (cons :emoji #'make-emoji) *window-builders* :key #'car)   ; register for Tools menu + layout restore
