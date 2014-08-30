;;; -*- Lisp -*-

(defsystem "fare-quasiquote-optima"
  #+asdf3 :version #+asdf3 (:read-file-line "version.text")
  :depends-on ("fare-quasiquote" (:version "optima" "1.0"))
  :components ((:file "fare-quasiquote-optima")))
