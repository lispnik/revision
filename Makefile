# Makefile --- the revision CLOS-native text-mode UI framework (a library).
#
# A library with no external dependencies; there is no binary to dump.  The
# example application, `revl', ships as a sibling project at ../revl.
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

FRAMEWORK := revision.asd $(wildcard base/*.lisp) $(wildcard revision/*.lisp)

.DEFAULT_GOAL := all
.PHONY: all clean test test-revision keybindings api help

# Build check: compile and load the framework (base + revision kernel).
all: $(FRAMEWORK)
	$(call asdf-load,(asdf:load-system :revision))

test: test-revision

# Headless tests: the editor's display-width (wide CJK / emoji) + widget layout, the
# desktop shell + plugin registry, the public-API contract, and the keybinding-
# reference drift check.  (The SBCL/IDE-feature tests moved to revl.)
test-revision: $(FRAMEWORK) tests/revision-editor-tests.lisp tests/revision-desktop-tests.lisp tests/revision-api-tests.lisp
	$(SBCL) --script tests/revision-editor-tests.lisp
	$(SBCL) --script tests/revision-desktop-tests.lisp
	$(SBCL) --script tests/revision-api-tests.lisp

# Regenerate the keybinding reference (KEYBINDINGS.md) from the keymaps.
keybindings: $(FRAMEWORK)
	$(call asdf-load,(progn (asdf:load-system :revision) (with-open-file (o "KEYBINDINGS.md" :direction :output :if-exists :supersede) (write-string (uiop:symbol-call :revision :keybinding-markdown) o))))
	@echo "regenerated KEYBINDINGS.md"

# Regenerate the public API reference (API.md) from the exported symbols' docstrings.
api: $(FRAMEWORK)
	$(call asdf-load,(progn (asdf:load-system :revision) (with-open-file (o "API.md" :direction :output :if-exists :supersede) (write-string (uiop:symbol-call :revision :api-markdown) o))))
	@echo "regenerated API.md"

clean:
	rm -rf $(HOME)/.cache/common-lisp/*tvision* $(HOME)/.cache/common-lisp/*revision* 2>/dev/null || true

help:
	@echo "Targets: all (default), test, test-revision, clean"
