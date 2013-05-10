(defvar pyret-mode-hook nil)
(defvar pyret-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "RET" 'newline-and-indent)
    map)
  "Keymap for Pyret major mode")

(defconst pyret-ident-regex "[a-zA-Z_][a-zA-Z0-9$_\\-]*")
(defconst pyret-keywords-regex 
  (regexp-opt
   '("fun" "var" "cond" "when" "import" "provide"
     "data" "end" "do" "try" "except"
     "as" "with" "sharing")))
(defconst pyret-punctuation-regex
  (regexp-opt '(":" "::" "=>" "->" "<" ">" "," "^" "(" ")" "[" "]" "{" "}" "." "\\" ";" "|" "=")))
(defconst pyret-font-lock-keywords-1
  (list
   `(,(concat 
       "\\(^\\|[ \t]\\|" pyret-punctuation-regex "\\)\\("
       pyret-keywords-regex
       "\\)\\($\\|[ \t]\\|" pyret-punctuation-regex "\\)") 
     (1 font-lock-builtin-face) (2 font-lock-keyword-face) (3 font-lock-builtin-face))
   `(,pyret-punctuation-regex . font-lock-builtin-face)
   `(,(concat "\\<" (regexp-opt '("true" "false") t) "\\>") . font-lock-constant-face)
   )
  "Minimal highlighting expressions for Pyret mode")

(defconst pyret-font-lock-keywords-2
  (append
   pyret-font-lock-keywords-1
   (list
    ;; "| else" is a builtin
    '("\\([|]\\)[ \t]+\\(else\\)" (1 font-lock-builtin-face) (2 font-lock-keyword-face))
    ;; "data IDENT"
    `(,(concat "\\(\\<data\\>\\)[ \t]+\\(" pyret-ident-regex "\\)") 
      (1 font-lock-keyword-face) (2 font-lock-type-face))
    ;; "| IDENT(whatever) =>" is a function name
    `(,(concat "\\([|]\\)[ \t]+\\(" pyret-ident-regex "\\)(.*?)[ \t]*=>")
      (1 font-lock-builtin-face) (2 font-lock-function-name-face))
    ;; "| IDENT =>" is a variable name
    `(,(concat "\\([|]\\)[ \t]+\\(" pyret-ident-regex "\\)[ \t]*=>")
      (1 font-lock-builtin-face) (2 font-lock-variable-name-face))
    ;; "| IDENT (", "| IDENT with", "| IDENT" are all considered type names
    `(,(concat "\\([|]\\)[ \t]+\\(" pyret-ident-regex "\\)[ \t]*\\(?:(\\|with\\|$\\)")
      (1 font-lock-builtin-face) (2 font-lock-type-face))
    `(,(concat "\\(" pyret-ident-regex "\\)[ \t]*::[ \t]*\\(" pyret-ident-regex "\\)") 
      (1 font-lock-variable-name-face) (2 font-lock-type-face))
    `(,(concat "\\(->\\)[ \t]*\\(" pyret-ident-regex "\\)")
      (1 font-lock-builtin-face) (2 font-lock-type-face))
    `(,(regexp-opt '("<" ">")) . font-lock-builtin-face)
    `(,(concat "\\(" pyret-ident-regex "\\)[ \t]*\\((\\|:\\)")  (1 font-lock-function-name-face))
    `(,pyret-ident-regex . font-lock-variable-name-face)
    ))
  "Additional highlighting for Pyret mode")

(defconst pyret-font-lock-keywords pyret-font-lock-keywords-2
  "Default highlighting expressions for Pyret mode")


(defconst pyret-mode-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?_ "w" st)
    (modify-syntax-entry ?$ "w" st)
    (modify-syntax-entry ?# "< b" st)
    (modify-syntax-entry ?\n "> b" st)
    (modify-syntax-entry ?: "." st)
    (modify-syntax-entry ?^ "." st)
    (modify-syntax-entry ?= "." st)
    (modify-syntax-entry ?- "." st)
    (modify-syntax-entry ?, "." st)
    (modify-syntax-entry ?' "\"" st)
    (modify-syntax-entry ?{ "(}" st)
    (modify-syntax-entry ?} "){" st)
    (modify-syntax-entry ?. "." st)
    (modify-syntax-entry ?\\ "." st)
    (modify-syntax-entry ?\; "." st)
    (modify-syntax-entry ?| "." st)
    st)
  "Syntax table for pyret-mode")



;; Eight (!) kinds of indentation:
;; bodies of functions
;; bodies of conditions (these indent twice, but lines beginning with a pipe indent once)
;; bodies of data declarations (these also indent twice excepting the lines beginning with a pipe)
;; bodies of sharing declarations
;; additional lines inside unclosed parentheses
;; bodies of objects (and list literals)
;; unterminated variable declarations
;; lines beginning with a period

(defvar nestings (vector))
(defvar nestings-dirty t)

(defun indent (funs conds datas shareds trys excepts parens objects vars fields period)
  (vector funs conds datas shareds trys excepts parens objects vars fields period))

(defun FUN () (looking-at "\\bfun\\b"))
(defun VAR () (looking-at "\\bvar\\b"))
(defun COND () (looking-at "\\bcond\\b"))
(defun WHEN () (looking-at "\\bwhen\\b"))
(defun IMPORT () (looking-at "\\bimport\\b"))
(defun PROVIDE () (looking-at "\\bprovide\\b"))
(defun DATA () (looking-at "\\bdata\\b"))
(defun END () (looking-at "\\bend\\b"))
(defun DO () (looking-at "\\bdo\\b"))
(defun TRY () (looking-at "\\btry\\b"))
(defun EXCEPT () (looking-at "\\bexcept\\b"))
(defun AS () (looking-at "\\bas\\b"))
(defun WITH () (looking-at "\\bwith\\b"))
(defun PIPE () (looking-at "|"))
(defun SHARING () (looking-at "\\bsharing\\b"))
(defun COLON () (looking-at ":"))
(defun COMMA () (looking-at ","))
(defun LBRACK () (looking-at "\\["))
(defun RBRACK () (looking-at "\\]"))
(defun LBRACE () (looking-at "{"))
(defun RBRACE () (looking-at "}"))
(defun LPAREN () (looking-at "("))
(defun RPAREN () (looking-at ")"))
(defun EQUALS () (looking-at "="))
(defun COMMENT () (looking-at "[ \t]*#.*$"))

(defun has-top (stack top)
  (if top
      (and (equal (car-safe stack) (car top))
           (has-top (cdr stack) (cdr top)))
    t))

(defun compute-nestings ()
  (let ((nlen (if nestings (length nestings) 0))
        (doclen (count-lines (point-min) (point-max))))
    (cond 
     ((>= (+ doclen 1) nlen)
      (setq nestings (vconcat nestings (make-vector (+ 1 (- doclen nlen)) (indent 0 0 0 0 0 0 0 0 0 0 0)))))
     (t nil)))
  (let ((n 0)
        (open-fun 0) (cur-opened-fun 0) (cur-closed-fun 0)
        (open-cond 0) (cur-opened-cond 0) (cur-closed-cond 0)
        (open-data 0) (cur-opened-data 0) (cur-closed-data 0)
        (open-shared 0) (cur-opened-shared 0) (cur-closed-shared 0)
        (open-try 0) (cur-opened-try 0) (cur-closed-try 0)
        (open-except 0) (cur-opened-except 0) (cur-closed-except 0)
        (open-parens 0) (cur-opened-parens 0) (cur-closed-parens 0)
        (open-object 0) (cur-opened-object 0) (cur-closed-object 0)
        (open-vars 0) (cur-opened-vars 0) (cur-closed-vars 0)
        (open-fields 0) (cur-opened-fields 0) (cur-closed-fields 0)
        (initial-period 0)
        (opens nil))
    (save-excursion
      (beginning-of-buffer)
      (while (not (eobp))
        (aset nestings n 
              (indent open-fun open-cond open-data open-shared open-try open-except open-parens open-object open-vars open-fields initial-period))
        (setq cur-opened-fun 0) (setq cur-opened-cond 0) 
        (setq cur-opened-data 0) (setq cur-opened-shared 0) (setq cur-opened-try 0) (setq cur-opened-except 0)
        (setq cur-opened-parens 0) (setq cur-opened-object 0)
        (setq cur-opened-vars 0) (setq cur-opened-fields 0)
        (setq cur-closed-fun 0) (setq cur-closed-cond 0)
        (setq cur-closed-data 0) (setq cur-closed-shared 0) (setq cur-closed-try 0) (setq cur-closed-except 0)
        (setq cur-closed-parens 0) (setq cur-closed-object 0)
        (setq cur-closed-vars 0) (setq cur-closed-fields 0)
        (setq initial-period 0)
        ;;(message "At start of line %d, opens is %s" (+ n 1) opens)
        (while (not (eolp))
          (cond
           ((COMMENT)
            (goto-char (match-end 0)))
           ((and (looking-at "[^ \t]") (has-top opens '(needsomething)))
            (pop opens)) ;; don't advance, because we may need to process that text
           ((looking-at "^[ \t]*\\.\\|\\^") 
            (setq initial-period 1)
            (goto-char (match-end 0)))
           ((COLON)
            (cond
             ((or (has-top opens '(wantcolon))
                  (has-top opens '(wantcolonorequal)))
              (pop opens))
             ((or (has-top opens '(object))
                  (has-top opens '(shared)))
                  ;;(has-top opens '(data)))
              ;;(message "Line %d, saw colon in context %s, pushing 'field" (+ 1 n) (car-safe opens))
              (incf open-fields)
              (incf cur-opened-fields)
              (push 'field opens)
              (push 'needsomething opens)))
            (forward-char))
           ((COMMA)
            (cond
             ((has-top opens '(field))
              (pop opens)
              (incf cur-closed-fields)))
            (forward-char))
           ((EQUALS)
            (cond
             ((has-top opens '(wantcolonorequal))
              (pop opens))
             (t 
              (while (has-top opens '(var))
                (pop opens)
                (incf cur-closed-vars))
              (incf open-vars)
              (incf cur-opened-vars)
              (push 'var opens)
              (push 'needsomething opens)))
            (forward-char))
           ((VAR)
            (incf open-vars) (incf cur-opened-vars)
            (push 'var opens)
            (push 'needsomething opens)
            (push 'wantcolonorequal opens)
            (goto-char (match-end 0)))
           ((FUN)
            (incf open-fun) (incf cur-opened-fun)
            (push 'fun opens)
            (push 'wantcolon opens)
            (push 'wantcloseparen opens)
            (push 'wantopenparen opens)
            (goto-char (match-end 0)))
           ((WHEN) ;when indents just like funs
            (incf open-fun) (incf cur-opened-fun)
            (push 'fun opens)
            (push 'wantcolon opens)
            (goto-char (match-end 0)))
           ((looking-at "[ \t]+") (goto-char (match-end 0)))
           ((COND)
            (incf open-cond) (incf cur-opened-cond)
            (push 'cond opens)
            (push 'wantcolon opens)
            (goto-char (match-end 0)))
           ((DATA)
            (incf open-data) (incf cur-opened-data)
            (push 'data opens)
            (push 'wantcolon opens)
            (push 'needsomething opens)
            (goto-char (match-end 0)))
           ((PIPE)
            (cond 
             ((or (has-top opens '(object data))
                  (has-top opens '(field object data)))
              (decf open-object)
              (cond
               ((has-top opens '(field))
                (pop opens)
                (if (> cur-opened-fields 0) ;; if a field was just opened, 
                    (incf cur-closed-fields) ;; say it's closed
                  (decf open-fields)))) ;; otherwise decrement the running count
              (if (has-top opens '(object))
                  (pop opens)))
             ((has-top opens '(data))
              (push 'wantcloseparen opens) (push 'wantopenparen opens) (push 'needsomething opens)
              ))
            (forward-char))
           ((WITH)
            (cond
             ((has-top opens '(wantopenparen wantcloseparen data))
              (pop opens) (pop opens)
              (incf open-object) (incf cur-opened-object)
              (push 'object opens))
             ((has-top opens '(data))
              (incf open-object) (incf cur-opened-object)
              (push 'object opens)))
            (goto-char (match-end 0)))
           ((PROVIDE)
            (push 'provide opens)
            (goto-char (match-end 0)))
           ((SHARING)
            (decf open-data) (incf cur-closed-data)
            (incf open-shared) (incf cur-opened-shared)
            (cond 
             ((has-top opens '(object data))
              (pop opens) (pop opens) (decf open-object)
              (push 'shared opens))
             ((has-top opens '(data))
              (pop opens)
              (push 'shared opens)))
            (goto-char (match-end 0)))
           ((TRY)
            (incf open-try) (incf cur-opened-try)
            (push 'try opens)
            (push 'wantcolon opens)
            (goto-char (match-end 0)))
           ((EXCEPT)
            (decf open-try) (incf cur-closed-try)
            (incf open-except) (incf cur-opened-except)
            (cond
             ((has-top opens '(try))
              (pop opens)
              (push 'except opens)
              (push 'wantcolon opens)
              (push 'wantcloseparen opens)
              (push 'wantopenparen opens)))
            (goto-char (match-end 0)))
           ((LBRACK)
            (incf open-object) (incf cur-opened-object)
            (push 'array opens)
            (forward-char))
           ((RBRACK)
            (decf open-object) (incf cur-closed-object)
            (if (has-top opens '(array))
                (pop opens))
            (while (has-top opens '(var))
              (pop opens)
              (incf cur-closed-vars))
            (forward-char))
           ((LBRACE)
            (incf open-object) (incf cur-opened-object)
            (cond 
             ;; minor hacks to make indentation slightly less deep for object literals
             ;; assigned to variables or to fields of object literals
             ((> cur-opened-vars 0)
              (while (has-top opens '(var))
                (pop opens)
                (incf cur-closed-vars)))
             ((> cur-opened-fields 0)
              (while (has-top opens '(field))
                (pop opens)
                (incf cur-closed-fields))))
            (push 'object opens)
            (forward-char))
           ((RBRACE)
            (decf open-object) (incf cur-closed-object)
            (cond
             ((has-top opens '(field))
              (pop opens)
              (if (> cur-opened-fields 0) ;; if a field was just opened, 
                  (incf cur-closed-fields) ;; say it's closed
                (decf open-fields)))) ;; otherwise decrement the running count
            (if (has-top opens '(object))
                (pop opens))
            (while (has-top opens '(var))
              (pop opens)
              (incf cur-closed-vars))
            (forward-char))
           ((LPAREN)
            (incf open-parens) (incf cur-opened-parens)
            (cond
             ((has-top opens '(wantopenparen))
              (pop opens))
             ((or (has-top opens '(object))
                  (has-top opens '(shared))) ; method in an object or sharing section
              (push 'fun opens)
              (push 'wantcolon opens)
              (push 'wantcloseparen opens)
              (incf open-fun) (incf cur-opened-fun))
             (t
              (push 'wantcloseparen opens)))
            (forward-char))
           ((RPAREN)
            (decf open-parens) (incf cur-closed-parens)
            (if (has-top opens '(wantcloseparen))
                (pop opens))
            (while (has-top opens '(var))
              (pop opens)
              (incf cur-closed-vars))
            (forward-char))
           ((END)
            (cond
             ((has-top opens '(object data))
              (decf open-object) (pop opens)))
            (let ((h (car-safe opens)))
              (cond
               ((equal h 'provide)
                (pop opens))
               ((equal h 'fun) 
                (decf open-fun) (incf cur-closed-fun) 
                (pop opens))
               ((equal h 'cond)
                (decf open-cond) (incf cur-closed-cond)
                (pop opens))
               ((equal h 'data)
                (decf open-data) (incf cur-closed-data)
                (pop opens))
               ((equal h 'shared)
                (decf open-shared) (incf cur-closed-shared)
                (pop opens))
               ((equal h 'try)
                (decf open-try) (incf cur-closed-try)
                (pop opens))
               ((equal h 'except)
                (decf open-except) (incf cur-closed-except)
                (pop opens))
               (t nil)))
            (while (has-top opens '(var))
              (pop opens)
              (incf cur-closed-vars))
            (goto-char (match-end 0)))
           (t (if (not (eobp)) (forward-char)))))
        ;;(message "At end   of line %d, opens is %s" (+ n 1) opens)
        (aset nestings n (indent (- open-fun (max 0 (- cur-opened-fun cur-closed-fun)))
                                 (- open-cond cur-opened-cond)
                                 (- open-data cur-opened-data)
                                 (- open-shared cur-opened-shared)
                                 (- open-try cur-opened-try)
                                 (- open-except cur-opened-except)
                                 (+ open-parens (- cur-closed-parens cur-opened-parens))
                                 (- open-object (max 0 (- cur-opened-object cur-closed-object)))
                                 (- open-vars cur-opened-vars)
                                 (- open-fields cur-opened-fields)
                                 initial-period))
        (let ((h (car-safe opens)))
          (while (equal h 'var)
            (pop opens)
            (incf cur-closed-vars)
            (setq h (car-safe opens))))
        (setq open-vars (- open-vars cur-closed-vars))
        ;;(message "On line %d, there are currently %d open fields, %d opened fields, and %d closed fields"
        ;;         (+ 1 n)
        ;;         open-fields cur-opened-fields cur-closed-fields)
        (setq open-fields (- open-fields cur-closed-fields))
        (incf n)
        (if (not (eobp)) (forward-char))))
    (aset nestings n 
          (indent open-fun open-cond open-data open-shared open-try open-except 
                  open-parens open-object open-vars open-fields initial-period)))
  (setq nestings-dirty nil))


(defun print-nestings ()
  "Displays the nestings information in the Messages buffer"
  (interactive)
  (let ((i 0))
    (while (and (< i (length nestings))
                (< i (line-number-at-pos (point-max))))
      (let* ((indents (aref nestings i))
             (open-fun    (elt indents 0))
             (open-cond   (elt indents 1))
             (open-data   (elt indents 2))
             (open-shared (elt indents 3))
             (open-try    (elt indents 4))
             (open-except (elt indents 5))
             (open-parens (elt indents 6))
             (open-object (elt indents 7))
             (open-vars   (elt indents 8))
             (open-fields (elt indents 9))
             (initial-period (elt indents 10))
             (total-indent (+ open-fun (* 2 open-cond) (* 2 open-data) open-shared open-try open-except open-object open-parens open-vars open-fields initial-period)))
        (message "Line %d: Fun %d, Cond %d, Data %d, Shared %d, Try %d, Except %d, Parens %d, Objects %d, Vars %d, Fields %d, Periods %d"
                 (incf i)
                 open-fun open-cond open-data open-shared open-try open-except open-parens open-object open-vars open-fields initial-period)
        ))))

(defun pyret-indent-line ()
  "Indent current line as Pyret code"
  (interactive)
  (cond
   (nestings-dirty
    (compute-nestings)))
  (let* ((indents (aref nestings (min (- (line-number-at-pos) 1) (length nestings))))
         (open-fun    (elt indents 0))
         (open-cond   (elt indents 1))
         (open-data   (elt indents 2))
         (open-shared (elt indents 3))
         (open-try    (elt indents 4))
         (open-except (elt indents 5))
         (open-parens (elt indents 6))
         (open-object (elt indents 7))
         (open-vars   (elt indents 8))
         (open-fields (elt indents 9))
         (initial-period (elt indents 10))
         (total-indent (+ open-fun (* 2 open-cond) (* 2 open-data) open-shared open-try open-except open-object open-parens open-vars open-fields initial-period)))
    (save-excursion
      (beginning-of-line)
      (if (looking-at "^[ \t]*[|]")
          (if (> total-indent 0)
              (indent-line-to (* tab-width (- total-indent 1)))
            (indent-line-to 0))
        (indent-line-to (max 0 (* tab-width total-indent))))
      (setq nestings-dirty nil))
    (if (< (current-column) (current-indentation))
        (forward-char (- (current-indentation) (current-column))))
    ))


(defun pyret-comment-dwim (arg)
  "Comment or uncomment current line or region in a smart way.
For detail, see `comment-dwim'."
  (interactive "*P")
  (require 'newcomment)
  (let ((comment-start "#") (comment-end ""))
    (comment-dwim arg)))

(defun pyret-mode ()
  "Major mode for editing Pyret files"
  (interactive)
  (kill-all-local-variables)
  (set-syntax-table pyret-mode-syntax-table)
  (use-local-map pyret-mode-map)
  (set (make-local-variable 'font-lock-defaults) '(pyret-font-lock-keywords))
  (set (make-local-variable 'comment-start) "#")
  (set (make-local-variable 'comment-end) "")
  (set (make-local-variable 'indent-line-function) 'pyret-indent-line)  
  (set (make-local-variable 'tab-width) 2)
  (set (make-local-variable 'indent-tabs-mode) nil)
  (setq major-mode 'pyret-mode)
  (setq mode-name "Pyret")
  (set (make-local-variable 'nestings) nil)
  (set (make-local-variable 'nestings-dirty) t)
  (add-hook 'before-change-functions
               (function (lambda (beg end) 
                           (setq nestings-dirty t)))
               nil t)
  (run-hooks 'pyret-mode-hook))



(provide 'pyret-mode)

(add-to-list 'auto-mode-alist '("\\.arr$" . pyret-mode))
