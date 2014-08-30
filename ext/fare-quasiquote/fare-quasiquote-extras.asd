
(defsystem "fare-quasiquote-extras"
  #+asdf3 :version #+asdf3 (:read-file-line "version.text")
  :description "fare-quasiquote plus extras"
  ;; not including deprecated fare-matcher anymore
  :depends-on ("fare-quasiquote-optima" "fare-quasiquote-readtable"))
