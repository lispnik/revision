;;;; emoji.lisp --- a read-only, filterable emoji palette.
;;;;
;;;; A scrollable list of emoji, each labelled with its Unicode name (straight
;;;; from SBCL's CHAR-NAME).  Type to filter by name; Enter or a click copies the
;;;; glyph to the revision clipboard (paste into any editor/REPL with Ctrl-V) and, via
;;;; OSC 52, to the terminal's system clipboard (paste elsewhere with ⌘V/Ctrl-V).

(in-package #:revision)

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
    (when revision:*screen*
      (let ((b64 (%base64 (sb-ext:string-to-octets s :external-format :utf-8))))
        (revision::%emit revision:*screen* (format nil "~c]52;c;~a~c\\" #\Escape b64 #\Escape))
        (revision::%flush-out revision:*screen*)))))

;;; --- the emoji set (single-codepoint, named glyphs from SBCL) ---------------

(defparameter *emoji-ranges*
  '((#x1F300 . #x1F5FF) (#x1F600 . #x1F64F) (#x1F680 . #x1F6FF)   ; pictographs, emoticons, transport
    (#x1F900 . #x1F9FF) (#x1FA70 . #x1FAFF)                        ; supplemental + extended-A
    (#x2600 . #x26FF)   (#x2700 . #x27BF))                         ; misc symbols, dingbats
  "Codepoint ranges scanned for emoji.")

(defparameter *skin-tones*
  '((#x1F3FB . "light skin tone")       (#x1F3FC . "medium-light skin tone")
    (#x1F3FD . "medium skin tone")      (#x1F3FE . "medium-dark skin tone")
    (#x1F3FF . "dark skin tone"))
  "The five Fitzpatrick emoji-modifier codepoints + their names.")

(defparameter *modifier-base*
  '(#x261D #x26F9 (#x270A . #x270D) #x1F385 (#x1F3C2 . #x1F3C4) #x1F3C7 (#x1F3CA . #x1F3CC)
    (#x1F442 . #x1F443) (#x1F446 . #x1F450) (#x1F466 . #x1F478) #x1F47C (#x1F481 . #x1F483)
    (#x1F485 . #x1F487) #x1F48F #x1F491 #x1F4AA (#x1F574 . #x1F575) #x1F57A #x1F590
    (#x1F595 . #x1F596) (#x1F645 . #x1F647) (#x1F64B . #x1F64F) #x1F6A3 (#x1F6B4 . #x1F6B6)
    #x1F6C0 #x1F6CC #x1F90C #x1F90F (#x1F918 . #x1F91F) #x1F926 (#x1F930 . #x1F939)
    (#x1F93D . #x1F93E) #x1F977 (#x1F9B5 . #x1F9B6) (#x1F9B8 . #x1F9B9) #x1F9BB
    (#x1F9CD . #x1F9CF) (#x1F9D1 . #x1F9DD) (#x1FAC3 . #x1FAC5) (#x1FAF0 . #x1FAF8))
  "Unicode Emoji_Modifier_Base codepoints/ranges (emoji that accept a skin tone).")

(defun %modifier-base-p (cp)
  "T if the codepoint CP accepts a skin-tone modifier (a UAX-#29 grapheme test is
useless here — the modifier is an Extend char that joins any base)."
  (some (lambda (e) (if (consp e) (<= (car e) cp (cdr e)) (= e cp))) *modifier-base*))

(defun %emoji-chars ()
  "List of (EMOJI-STRING . NAME): every named codepoint in *EMOJI-RANGES*, plus
skin-tone variants for modifier bases and man/woman variants for \"PERSON …\"
emoji (via ZWJ + gender sign)."
  (let ((out '()))
    (flet ((emit (str name) (push (cons str name) out)))
      (dolist (r *emoji-ranges*)
        (loop for cp from (car r) to (cdr r)
              for ch = (ignore-errors (code-char cp))
              for name = (and ch (char-name ch) (substitute #\Space #\_ (char-name ch)))   ; spaces read/filter cleanly
              when name do
                (emit (string ch) name)                            ; the base glyph
                (when (%modifier-base-p cp)                        ; + skin tones
                  (dolist (st *skin-tones*)
                    (emit (coerce (list ch (code-char (car st))) 'string)
                          (format nil "~a: ~a" name (cdr st)))))
                (when (search "PERSON" name)                       ; + gender (ZWJ ♂/♀ VS16)
                  (dolist (g '((#x2642 . "man") (#x2640 . "woman")))
                    (emit (coerce (list ch (code-char #x200D) (code-char (car g)) (code-char #xFE0F)) 'string)
                          (format nil "~a: ~a" name (cdr g))))))))
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
      (setf *clipboard* e)                                 ; revision clipboard: paste with Ctrl-V
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
