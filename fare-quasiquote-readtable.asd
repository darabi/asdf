;;; -*- Lisp -*-

(defsystem "fare-quasiquote-readtable"
  #+asdf3 :version #+asdf3 (:read-file-line "version.text")
  :depends-on ("named-readtables" "fare-quasiquote")
  :components ((:file "quasiquote-readtable")))
