
(defsystem "fare-quasiquote-test"
  #+asdf3 :version #+asdf3 (:read-file-line "version.text")
  :depends-on ("fare-quasiquote-extras" "hu.dwim.stefil")
  :components ((:file "quasiquote-test"))
  :perform (test-op (o c)
             (format! t "~&Testing fare-quasiquote")
             (symbol-call :fare-quasiquote/test :fare-quasiquote-test)))
