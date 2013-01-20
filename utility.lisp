;;;; -------------------------------------------------------------------------
;;;; General Purpose Utilities for ASDF

(asdf/package:define-package :asdf/utility
  (:recycle :asdf/utility :asdf)
  (:use :common-lisp :asdf/package :asdf/compatibility)
  #+gcl<2.7 (:shadowing-import-from :asdf/compatibility #:with-standard-io-syntax)
  (:export
   ;; magic helper to define debugging functions:
   #:asdf-debug #:load-asdf-debug-utility #:*asdf-debug-utility*
   #:undefine-function #:undefine-functions #:defun* #:defgeneric* ;; (un)defining functions
   #:if-let ;; basic flow control
   #:while-collecting #:appendf #:length=n-p #:remove-plist-keys #:remove-plist-key ;; lists and plists
   #:emptyp ;; sequences
   #:first-char #:last-char #:split-string ;; strings
   #:string-prefix-p #:string-enclosed-p #:string-suffix-p
   #:find-class* ;; CLOS
   #:stamp< #:stamps< #:stamp*< #:stamp<= ;; stamps
   #:earlier-stamp #:stamps-earliest #:earliest-stamp
   #:later-stamp #:stamps-latest #:latest-stamp #:latest-stamp-f
   #:list-to-hash-set ;; hash-table
   #:ensure-function #:sub-object ;; functions
   #:call-function #:call-functions #:register-hook-function
   #:match-condition-p #:match-any-condition-p ;; conditions
   #:call-with-muffled-conditions #:with-muffled-conditions
   #:load-string #:load-stream
   #:parse-version #:unparse-version #:version-compatible-p)) ;; version
(in-package :asdf/utility)

;;;; Defining functions in a way compatible with hot-upgrade:
;; DEFUN* and DEFGENERIC* use FMAKUNBOUND to delete any previous fdefinition,
;; thus replacing the function without warning or error
;; even if the signature and/or generic-ness of the function has changed.
;; For a generic function, this invalidates any previous DEFMETHOD.
(eval-when (:load-toplevel :compile-toplevel :execute)
  (defun undefine-function (function-spec)
    (cond
      ((symbolp function-spec)
       #+(and clisp (or))
       (let ((f (and (fboundp function-spec) (fdefinition function-spec))))
         (when (typep f 'clos:standard-generic-function)
           (loop :for m :in (clos:generic-function-methods f)
                 :do (remove-method f m))))
       (fmakunbound function-spec))
      ((and (consp function-spec) (eq (car function-spec) 'setf)
            (consp (cdr function-spec)) (null (cddr function-spec)))
       #-(or gcl<2.7) (fmakunbound function-spec))
      (t (error "bad function spec ~S" function-spec))))
  (defun undefine-functions (function-spec-list)
    (map () 'undefine-function function-spec-list)))

(macrolet
    ((defdef (def* def)
       `(defmacro ,def* (name formals &rest rest)
          (destructuring-bind (name &key (supersede t))
              (if (or (atom name) (eq (car name) 'setf))
                  (list name :supersede nil)
                  name)
            (declare (ignorable supersede))
            `(progn
             ;; undefining the previous function is the portable way
             ;; of overriding any incompatible previous gf,
             ;; but we usually try to do it only for the functions that need it,
             ;; which happens in asdf/upgrade - however, for ECL, we need this hammer,
             ;; (which causes issues in clisp)
               #-ecl ;XXX
               ,@(when (or supersede #+(or (and gcl (not gcl-pre2.7))) t)
                   `((undefine-function ',name)))
               #-gcl ; gcl 2.7.0 notinline functions lose secondary return values :-(
               ,@(when (and #+ecl (symbolp name)) ; fails for setf functions on ecl
                   `((declaim (notinline ,name))))
               (,',def ,name ,formals ,@rest))))))
  (defdef defgeneric* defgeneric)
  (defdef defun* defun))


;;; Magic debugging help. See contrib/debug.lisp
(defvar *asdf-debug-utility*
  '(ignore-errors (merge-pathnames "cl/asdf/contrib/debug.lisp" (user-homedir-pathname)))
  "form that evaluates to the pathname to your favorite debugging utilities")

(defmacro asdf-debug (&rest keys)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (load-asdf-debug-utility ,@keys)))

(defun* load-asdf-debug-utility (&key package utility-file)
  (let* ((*package* (if package (find-package package) *package*))
         (keyword (read-from-string
                   (format nil ":DBG-~:@(~A~)" (package-name *package*)))))
    (unless (member keyword *features*)
      (let* ((utility-file (or utility-file *asdf-debug-utility*))
             (file (ignore-errors (probe-file (eval utility-file)))))
        (if file (load file)
            (error "Failed to locate debug utility file: ~S" utility-file))))))


;;; Flow control
(defmacro if-let (bindings &body (then-form &optional else-form)) ;; from alexandria
  ;; bindings can be (var form) or ((var1 form1) ...)
  (let* ((binding-list (if (and (consp bindings) (symbolp (car bindings)))
                           (list bindings)
                           bindings))
         (variables (mapcar #'car binding-list)))
    `(let ,binding-list
       (if (and ,@variables)
           ,then-form
           ,else-form))))

;;; List manipulation
(defmacro while-collecting ((&rest collectors) &body body)
  "COLLECTORS should be a list of names for collections.  A collector
defines a function that, when applied to an argument inside BODY, will
add its argument to the corresponding collection.  Returns multiple values,
a list for each collection, in order.
   E.g.,
\(while-collecting \(foo bar\)
           \(dolist \(x '\(\(a 1\) \(b 2\) \(c 3\)\)\)
             \(foo \(first x\)\)
             \(bar \(second x\)\)\)\)
Returns two values: \(A B C\) and \(1 2 3\)."
  (let ((vars (mapcar #'(lambda (x) (gensym (symbol-name x))) collectors))
        (initial-values (mapcar (constantly nil) collectors)))
    `(let ,(mapcar #'list vars initial-values)
       (flet ,(mapcar #'(lambda (c v) `(,c (x) (push x ,v) (values))) collectors vars)
         ,@body
         (values ,@(mapcar #'(lambda (v) `(reverse ,v)) vars))))))

(define-modify-macro appendf (&rest args)
  append "Append onto list") ;; only to be used on short lists.

(defun* length=n-p (x n) ;is it that (= (length x) n) ?
  (check-type n (integer 0 *))
  (loop
    :for l = x :then (cdr l)
    :for i :downfrom n :do
    (cond
      ((zerop i) (return (null l)))
      ((not (consp l)) (return nil)))))

;;; remove a key from a plist, i.e. for keyword argument cleanup
(defun* remove-plist-key (key plist)
  "Remove a single key from a plist"
  (loop :for (k v) :on plist :by #'cddr
    :unless (eq k key)
    :append (list k v)))

(defun* remove-plist-keys (keys plist)
  "Remove a list of keys from a plist"
  (loop :for (k v) :on plist :by #'cddr
    :unless (member k keys)
    :append (list k v)))


;;; Sequences
(defun* emptyp (x)
  "Predicate that is true for an empty sequence"
  (or (null x) (and (vectorp x) (zerop (length x)))))


;;; Strings

(defun* first-char (s)
  (and (stringp s) (plusp (length s)) (char s 0)))

(defun* last-char (s)
  (and (stringp s) (plusp (length s)) (char s (1- (length s)))))

(defun* split-string (string &key max (separator '(#\Space #\Tab)))
  "Split STRING into a list of components separated by
any of the characters in the sequence SEPARATOR.
If MAX is specified, then no more than max(1,MAX) components will be returned,
starting the separation from the end, e.g. when called with arguments
 \"a.b.c.d.e\" :max 3 :separator \".\" it will return (\"a.b.c\" \"d\" \"e\")."
  (block ()
    (let ((list nil) (words 0) (end (length string)))
      (flet ((separatorp (char) (find char separator))
             (done () (return (cons (subseq string 0 end) list))))
        (loop
          :for start = (if (and max (>= words (1- max)))
                           (done)
                           (position-if #'separatorp string :end end :from-end t)) :do
          (when (null start)
            (done))
          (push (subseq string (1+ start) end) list)
          (incf words)
          (setf end start))))))

(defun* string-prefix-p (prefix string)
  "Does STRING begin with PREFIX?"
  (let* ((x (string prefix))
         (y (string string))
         (lx (length x))
         (ly (length y)))
    (and (<= lx ly) (string= x y :end2 lx))))

(defun* string-suffix-p (string suffix)
  "Does STRING end with SUFFIX?"
  (let* ((x (string string))
         (y (string suffix))
         (lx (length x))
         (ly (length y)))
    (and (<= ly lx) (string= x y :start1 (- lx ly)))))

(defun* string-enclosed-p (prefix string suffix)
  "Does STRING begin with PREFIX and end with SUFFIX?"
  (and (string-prefix-p prefix string)
       (string-suffix-p string suffix)))


;;; CLOS
(defun* find-class* (x &optional (errorp t) environment)
  (etypecase x
    ((or standard-class built-in-class) x)
    #+gcl<2.7 (keyword nil)
    (symbol (find-class x errorp environment))))


;;; stamps: a REAL or boolean where NIL=-infinity, T=+infinity
(deftype stamp () '(or real boolean))
(defun* stamp< (x y)
  (etypecase x
    (null (and y t))
    ((eql t) nil)
    (real (etypecase y
            (null nil)
            ((eql t) t)
            (real (< x y))))))
(defun* stamps< (list) (loop :for y :in list :for x = nil :then y :always (stamp< x y)))
(defun* stamp*< (&rest list) (stamps< list))
(defun* stamp<= (x y) (not (stamp< y x)))
(defun* earlier-stamp (x y) (if (stamp< x y) x y))
(defun* stamps-earliest (list) (reduce 'earlier-stamp list :initial-value t))
(defun* earliest-stamp (&rest list) (stamps-earliest list))
(defun* later-stamp (x y) (if (stamp< x y) y x))
(defun* stamps-latest (list) (reduce 'later-stamp list :initial-value nil))
(defun* latest-stamp (&rest list) (stamps-latest list))
(define-modify-macro latest-stamp-f (&rest stamps) latest-stamp)


;;; Hash-tables
(defun* list-to-hash-set (list &aux (h (make-hash-table :test 'equal)))
  (dolist (x list h) (setf (gethash x h) t)))


;;; Function designators
(defun* ensure-function (fun &key (package :cl))
  "Coerce the object FUN into a function.

If FUN is a FUNCTION, return it.
If the FUN is a non-sequence literal constant, return constantly that,
i.e. for a boolean keyword character number or pathname.
Otherwise if FUN is a non-literally constant symbol, return its FDEFINITION.
If FUN is a CONS, return the function that applies its CAR
to the appended list of the rest of its CDR and the arguments.
If FUN is a string, READ a form from it in the specified PACKAGE (default: CL)
and EVAL that in a (FUNCTION ...) context."
  (etypecase fun
    (function fun)
    ((or boolean keyword character number pathname) (constantly fun))
    ((or function symbol) fun)
    (cons #'(lambda (&rest args) (apply (car fun) (append (cdr fun) args))))
    (string (eval `(function ,(with-standard-io-syntax
                                (let ((*package* (find-package package)))
                                  (read-from-string fun))))))))

(defun* sub-object (object path)
  "Given an OBJECT and a PATH, list of successive accessors,
call each accessor on the result of the previous calls.
An accessor may be an integer, meaning a call to ELT,
a function or symbol, meaning itself,
or a list of a function and arguments, interpreted as per ENSURE-FUNCTION.
As a degenerate case, the PATH may be an atom of a single such accessor
instead of a list."
  (flet ((access (object accessor)
           (etypecase accessor
             (integer (elt object accessor))
             ((or function symbol) (funcall accessor object))
             (cons (funcall (ensure-function accessor) object)))))
    (if (listp path)
        (dolist (accessor path object)
          (setf object (access object accessor)))
        (access object path))))

(defun* call-function (function-spec &rest arguments)
  (apply (ensure-function function-spec) arguments))

(defun* call-functions (function-specs)
  (map () 'call-function function-specs))

(defun* register-hook-function (variable hook &optional (call-now-p t))
  (pushnew hook (symbol-value variable))
  (when call-now-p (call-function hook)))


;;; Version handling
(defun* unparse-version (version-list)
  (format nil "~{~D~^.~}" version-list))

(defun* parse-version (version-string &optional on-error)
  "Parse a VERSION-STRING as a series of natural integers separated by dots.
Return a (non-null) list of integers if the string is valid;
otherwise return NIL.

When invalid, ON-ERROR is called as per CALL-FUNCTION before to return NIL,
with format arguments explaining why the version is invalid.
ON-ERROR is also called if the version is not canonical
in that it doesn't print back to itself, but the list is returned anyway."
  (block nil
   (unless (stringp version-string)
     (call-function on-error "~S: ~S is not a string" 'parse-version version-string)
     (return))
   (unless (loop :for prev = nil :then c :for c :across version-string
                 :always (or (digit-char-p c)
                             (and (eql c #\.) prev (not (eql prev #\.))))
                 :finally (return (and c (digit-char-p c))))
     (call-function on-error "~S: ~S doesn't follow asdf version numbering convention"
                    'parse-version version-string)
     (return))
   (let* ((version-list
            (mapcar #'parse-integer (split-string version-string :separator ".")))
          (normalized-version (unparse-version version-list)))
     (unless (equal version-string normalized-version)
       (call-function on-error "~S: ~S contains leading zeros" 'parse-version version-string))
     version-list)))


(defun* version-compatible-p (provided-version required-version)
  "Is the provided version a compatible substitution for the required-version?
If major versions differ, it's not compatible.
If they are equal, then any later version is compatible,
with later being determined by a lexicographical comparison of minor numbers."
  (let ((x (parse-version provided-version 'warn))
        (y (parse-version required-version 'warn)))
    (labels ((bigger (x y)
               (cond ((not y) t)
                     ((not x) nil)
                     ((> (car x) (car y)) t)
                     ((= (car x) (car y))
                      (bigger (cdr x) (cdr y))))))
      (and x y (= (car x) (car y))
           (or (not (cdr y)) (bigger (cdr x) (cdr y)))))))


;;; Condition control

(defvar *uninteresting-conditions* nil
  "Uninteresting conditions, as per MATCH-CONDITION-P")

(defparameter +simple-condition-format-control-slot+
  #+abcl 'system::format-control
  #+allegro 'excl::format-control
  #+clisp 'system::$format-control
  #+clozure 'ccl::format-control
  #+ecl 'si::format-control
  #+(or cmu scl) 'conditions::format-control
  #+(or gcl lispworks) 'conditions::format-string
  #+sbcl 'sb-kernel:format-control
  #-(or abcl allegro clisp clozure cmu ecl gcl lispworks sbcl scl) nil
  "Name of the slot for FORMAT-CONTROL in simple-condition")

(defun* match-condition-p (x condition)
  "Compare received CONDITION to some pattern X:
a symbol naming a condition class,
a simple vector of length 2, arguments to find-symbol* with result as above,
or a string describing the format-control of a simple-condition."
  (etypecase x
    (symbol (typep condition x))
    ((simple-vector 2) (typep condition (find-symbol* (svref x 0) (svref x 1) nil)))
    (function (funcall x condition))
    (string (and (typep condition 'simple-condition)
                 ;; On SBCL, it's always set and the check triggers a warning
                 #+(or allegro clozure cmu lispworks scl)
		 (slot-boundp condition +simple-condition-format-control-slot+)
                 (ignore-errors (equal (simple-condition-format-control condition) x))))))

(defun* match-any-condition-p (condition conditions)
  "match CONDITION against any of the patterns of CONDITIONS supplied"
  (loop :for x :in conditions :thereis (match-condition-p x condition)))

(defun* call-with-muffled-conditions (thunk conditions)
  (handler-bind ((t #'(lambda (c) (when (match-any-condition-p c conditions)
                                    (muffle-warning c)))))
    (funcall thunk)))

(defmacro with-muffled-uninteresting-conditions ((conditions) &body body)
  `(call-with-muffled-uninteresting-conditions #'(lambda () ,@body) ,conditions))

