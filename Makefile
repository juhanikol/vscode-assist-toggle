.PHONY: help install uninstall check test

help:
	@echo "Developer/install helpers (make is optional):"
	@echo "  make install     - Install and verify the vassist command"
	@echo "  make uninstall   - Remove installer-owned vassist files"
	@echo "  make check       - Run safe syntax/static checks"
	@echo "  make test        - Run isolated integration tests under /tmp"

install:
	./install.sh

uninstall:
	./install.sh --uninstall

check:
	bash -n install.sh scripts/vscode-mode.sh tests/integration.sh tests/dependency-checks.sh
	python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("scripts/settings-patch.py").read_text(encoding="utf-8"))'

test: check
	bash tests/dependency-checks.sh
	bash tests/integration.sh
