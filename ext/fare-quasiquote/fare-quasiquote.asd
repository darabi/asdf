;;; -*- Lisp -*-

(defsystem "fare-quasiquote"
  :description "Portable, matchable implementation of quasiquote"
  :long-description "fare-quasiquote implements
  a portable quasiquote that you can control."
  :license "MIT"
  #+asdf3 :version #+asdf3 (:read-file-line "version.text")
  :depends-on ((:version "fare-utils" "1.0.0"))
  :components
  ((:file "packages")
   (:file "quasiquote" :depends-on ("packages"))
   (:file "pp-quasiquote" :depends-on ("quasiquote")))
  :in-order-to ((test-op (test-op "fare-quasiquote-test")))) ;; Don't try that with ASDF2!
