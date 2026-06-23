.PHONY: help install uninstall check test doctor doctor-fix

help:
	@echo "Developer/install helpers (make is optional):"
	@echo "  make install     - Install and verify the vassist command"
	@echo "  make uninstall   - Remove installer-owned vassist files"
	@echo "  make doctor      - Run diagnostics for the current directory"
	@echo "  make doctor-fix  - Apply confirmed doctor preference fixes"
	@echo "  make check       - Run safe syntax/static checks"
	@echo "  make test        - Run isolated integration tests under /tmp"

install:
	./install.sh

uninstall:
	./install.sh --uninstall

# Run diagnostics for the current directory.
doctor:
	vassist doctor

# Apply confirmed doctor preference fixes for the current directory.
doctor-fix:
	vassist doctor --fix

check:
	bash -n install.sh scripts/vscode-mode.sh tests/integration.sh tests/dependency-checks.sh tests/release-checks.sh
	python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("scripts/settings-patch.py").read_text(encoding="utf-8"))'
	bash tests/release-checks.sh

test: check
	bash tests/dependency-checks.sh
	bash tests/integration.sh
