# Makefile --- the tv2 CLOS-native text-mode UI framework (a library).
#
# A library with no external dependencies; there is no binary to dump.  The
# example application, `tvlisp', ships as a sibling project at ../tvlisp.
#
# Usage:
#   make            # compile/load the framework (build check)
#   make test       # headless test suite
#   make clean      # remove this project's fasl cache

SBCL ?= sbcl

# Load SYSTEM, adding this directory to the source registry explicitly so it
# works even without a global ocicl/ASDF config.
define asdf-load
$(SBCL) --non-interactive \
	--eval '(require :asdf)' \
	--eval '(asdf:initialize-source-registry (list :source-registry (list :tree (uiop:getcwd)) :inherit-configuration))' \
	--eval '(handler-bind ((warning (function muffle-warning))) $(1))' \
	--eval '(uiop:quit 0)'
endef

FRAMEWORK := tv2.asd $(wildcard base/*.lisp) $(wildcard tv2/*.lisp)

.DEFAULT_GOAL := all
.PHONY: all clean test test-tv2 help

# Build check: compile and load the framework (base + tv2 kernel).
all: $(FRAMEWORK)
	$(call asdf-load,(asdf:load-system :tv2))

test: test-tv2

# Headless tests: SBCL-specific IDE features and the editor's display-width
# (wide CJK / emoji) + widget layout.
test-tv2: $(FRAMEWORK) tests/tv2-sbcl-tests.lisp tests/tv2-editor-tests.lisp
	$(SBCL) --script tests/tv2-sbcl-tests.lisp
	$(SBCL) --script tests/tv2-editor-tests.lisp

clean:
	rm -rf $(HOME)/.cache/common-lisp/*tvision* $(HOME)/.cache/common-lisp/*tv2* 2>/dev/null || true

help:
	@echo "Targets: all (default), test, test-tv2, clean"
