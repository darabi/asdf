(in-package :asdf-tools)

;;; Upgrade tests

(defun get-upgrade-lisps (&optional (x *upgrade-test-lisps*))
  (if (eq x :default) (get-lisps) x))

(defparameter *default-upgrade-test-tags*
  ;; We return a list of entries in reverse chronological order,
  ;; which should also be more or less the order of decreasing relevance.
  '("REQUIRE" ;; a magic tag meaning whatever your implementation provides, if anything

    ;; The 3.1 series provides the asdf3.1 feature, meaning users can rely on
    ;; all the stabilization work done in 3.0 so far, plus extra developments
    ;; in UIOP, package-inferred-system, and more robustification.
    "3.1.3" ;; (2014-07-24) a bug fix release for 3.1.2
    "3.1.2" ;; (2014-05-06) the first ASDF 3.1 release

    ;; The 3.0 series is a stable release of ASDF 3
    ;; with Robert Goldman taking over maintainership at 3.0.2.
    ;; 3.0.0 was just 2.33.10 promoted, but version-satisfies meant it was suddenly
    ;; not compatible with ASDF2 anymore, so we immediately released 3.0.1
    "3.0.3" ;; (2013-10-22) the last in the ASDF 3.0 series
    "3.0.2" ;; (2013-07-02) the first ASDF 3 in SBCL
    "3.0.1" ;; (2013-05-16) the first stable ASDF 3 release

    ;; 2.27 to 2.33 are Faré's "stable" ASDF 3 pre-releases
    "2.32" ;; (2013-03-05) the first really stable ASDF 3 pre-release
    "2.27" ;; (2013-02-01) the first ASDF 3 pre-release

    ;; The ASDF 2 series
    ;; Note that 2.26.x is where the refactoring that begat ASDF 3 took place.
    ;; 2.26.61 is the last single-file, single-package ASDF.
    "2.26" ;; (2012-10-30) the last stable ASDF 2 release, long used by Quicklisp, SBCL, etc.
    "2.22" ;; (2012-06-12) used by debian wheezy, etc.
    "2.20" ;; (2012-01-18) in CCL 1.8, Ubuntu 12.04 LTS
    "2.019" ;; (2011-11-29) still included in LispWorks in 2014.
    "2.014.6" ;; (2011-04-06) first included in Quicklisp, and for some time.
    "2.011" ;; (2010-12-09) long used by CLISP 2.49, Debian squeeze, Ubuntu 10.04 LTS.
    "2.008" ;; (2010-09-10) somewhat stable checkpoint in the ASDF 2 series.
    "2.000" ;; (2010-05-31) first stable ASDF 2 release.

    ;; The original ASDF 1 series
    "1.369" ;; (2009-10-27) the last release by Gary King
    "1.85" ;; (2004-05-16) the last release by Daniel Barlow (not 1.37, which is the README revision!)
    "1.97")) ;; (2006-05-14) the last release before Gary King takes over

(defun get-upgrade-tags (&optional (x *upgrade-test-tags*))
  (if (eq x :default) *default-upgrade-test-tags* x))

(defun extract-tagged-asdf (tag)
  "extract an asdf version from git
Use at a given tag, put it under build/asdf-${tag}.lisp"
  (with-asdf-dir ()
    (ensure-directories-exist (pn "build/"))
    (unless (string-equal tag "REQUIRE")
      (let ((file (pn (strcat "build/asdf-" tag ".lisp"))))
        (unless (probe-file file)
          (cond
            ((version<= tag "2.26.61")
             (git `(show (,tag ":asdf.lisp") (> ,file))))
            (t
             (ensure-directories-exist (pn "build/old/build/"))
             (run `(pipe (git archive ,tag) (tar "xfC" - ,(pn "build/old/"))))
             (run `(make) :directory (pn "build/old/"))
             (rename-file-overwriting-target (pn "build/old/build/asdf.lisp") file))))))))

(deftestcmd extract-all-tagged-asdf (upgrade-tags)
  "extract all asdf tags used for upgrade"
  (map () 'extract-tagged-asdf upgrade-tags))

(defalias extract extract-all-tagged-asdf)

(defparameter *upgrade-test-methods* :default)

(defparameter *all-upgrade-test-methods*
  '((:load-asdf-lisp :load-asdf-lisp-clean)
    (:load-asdf-lisp :load-asdf-system)
    (:load-asdf-lisp :compile-load-asdf-upgrade)
    (:load-asdf-lisp :load-asdf-fasl)
    (() :load-asdf-fasl)
    (:load-asdf-lisp-and-test-uiop :load-asdf-fasl)))

(defun get-upgrade-methods (&optional (x *upgrade-test-methods*))
  (if (eq x :default) *all-upgrade-test-methods* x))

(defun valid-upgrade-test-p (lisp tag method)
  (declare (ignore method))
  (or
   (string-equal tag "REQUIRE") ;; we are hopefully always able to upgrade from REQUIRE
   (ecase lisp
     ;; ABCL makes it damn slow. Also, for some reason, we punt on anything earlier than 2.25,
     ;; and only need to test it once, below for 2.24.
     ((:abcl) (version<= "2.24" tag))

     ;; CCL fasl numbering broke loading of old asdf 2.0
     ((:ccl) (or (version< tag "2.0") (version<= "2.20" tag)))

     ;; My old Ubuntu 10.04LTS clisp 2.44.1 came wired in
     ;; with an antique ASDF 1.374 from CLC that can't be removed.
     ;; More recent CLISPs work.
     ;; 2.00[0-7] use UID, which fails on some old CLISPs.
     ;; Note that for the longest time, CLISP has included 2.011 in its distribution.
     ;; However, the was we punt or don't punt, these should all work.
     ((:clisp) t)

     ;; CMUCL has problems with 2.32 and earlier because of
     ;; the redefinition of system's superclass component.
     ((:cmucl) (version<= "2.33" tag))

     ;; Skip many ECL tests, for various ASDF issues
     ((:ecl) (version<= "2.21" tag))

     ;; GCL 2.7.0 from late November 2013 is required, with ASDF 3.1.2
     ((:gcl) (version<= "3.1.2" tag))

     ;; MKCL is only supported starting with specific versions 2.24, 2.26.x, 3.0.3.0.x, so skip.
     ((:mkcl) (version<= "3.1.2" tag))

     ;; XCL support starts with ASDF 2.014.2
     ;; — It also dies during upgrade trying to show the backtrace.
     ;; We recommend you replace XCL's asdf using:
     ;;     ./tools/asdf-tools install-asdf xcl
     ((:xcl) (version<= "2.15" tag))

     ;; all clear on these implementations
     ((:allegro :lispworks :sbcl :scl) t))))

(deftestcmd test-upgrade (lisp upgrade-tags upgrade-methods)
  "run upgrade tests
Use the preferred lisp implementation"
  (nest
   (with-asdf-dir ())
   (let ((log (newlogfile "upgrade" lisp)))
     ;; Remove stale FASLs from ASDF 1.x,
     ;; especially since different implementations may have the same fasl type
     (dolist (pattern '("build/*.*f*" "uiop/*.*f*" "test/*.*f*"))
       (map () 'delete-file (directory* pattern))))
   (loop :for tag :in upgrade-tags :do
     (loop :for method :in upgrade-methods
           :when (valid-upgrade-test-p lisp tag method) :do
             (extract-tagged-asdf tag)
             (run-test-lisp
              (format nil "Testing ASDF upgrade on ~(~A~) from ~A to ~A using method ~(~{~A~^:~}~)"
                      lisp tag *version* method)
              `((load "test/script-support.lisp")
                (asdf-test::test-upgrade ,@method ,tag))
              :lisp lisp :log log))
    :finally (log! log "Upgrade test succeeded for ~(~A~)" lisp))))

(defalias u test-upgrade)

