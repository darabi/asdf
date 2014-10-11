(in-package :asdf-tools)

(deftestcmd %load (lisp) ;; load would be a clash, so use %load instead
  "load asdf into an interactive Lisp for debugging
load from individual source files, to make it easier to quickly locate
compilation errors and to interactively debug ASDF."
  (with-asdf-dir ()
    (run-test-lisp
     (format nil "loading ASDF into an interactive ~(~A~)" lisp)
     `((load "test/script-support.lisp")
       (asdf-test::interactive-test
        ',(system-source-files :asdf/defsystem :monolithic t)))
     :lisp lisp :debugger t :output :interactive)))

(deftestcmd test-load-systems (lisp systems)
  "test loading of your favorite systems
Use your preferred Lisp implementation"
  (with-asdf-dir ()
    (let* ((log (newlogfile "systems" lisp)))
      (log! log "Loading all these systems on ~(~A~):~{~%  ~A~}~%~%" lisp systems)
      (run-test-lisp
       "loading the systems"
       `((load "test/script-support.lisp")
         (asdf-test::with-test () (asdf-test::test-load-systems ,@systems)))
       :lisp lisp :log log))))

(deftestcmd test-clean-load (lisp log)
  "test that asdf load cleanly
Use your preferred lisp implementation and check that asdf is loaded without any output message"
  (nest
   (block ()
     (case lisp ((:gcl :cmucl) (return t)))) ;; These are hopeless
   (with-asdf-dir ())
   (let ((nop (newlogfile "nop" lisp))
         (load (newlogfile "load" lisp)))
     (run-test-lisp
      (format nil "starting ~(~A~), loading the script support, and exiting without doing anything" lisp)
      `((load "test/script-support.lisp" :verbose nil :print nil)
        (asdf-test::exit-lisp 0))
      :lisp lisp :output nop :log log)
     (run-test-lisp
      (format nil "starting ~(~A~), loading the script support, loading ASDF from source, then exiting" lisp)
      `((load "test/script-support.lisp" :verbose nil :print nil)
        (asdf-test::verbose nil)
        (load "build/asdf.lisp" :verbose nil :print nil)
        (uiop/image:quit 0))
      :lisp lisp :output load :log log)
     (if (nth-value 2 (run `(diff ,nop ,load)
                           :output :interactive :error-output :output :input nil))
         (progn
           (log! log "GOOD: Loading ASDF on ~(~A~) produces no message" lisp)
           (return t))
         (progn
           (log! log "BAD: Loading ASDF on ~(~A~) produces messages" lisp)
           (return nil))))))

(deftestcmd test-basic (lisp systems)
  "basic test: doc, clean-load, load-systems"
  (doc)
  (test-clean-load lisp)
  (test-load-systems lisp systems))
