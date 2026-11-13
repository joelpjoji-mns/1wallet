.PHONY: all help test bdd a11y analyze format format-check scan clean run

help:
	@echo "1Wallet Development Automation"
	@echo "--------------------------------"
	@echo "make test         - Run full Flutter test suite"
	@echo "make bdd          - Run BDD executable specifications suite"
	@echo "make a11y         - Run automated accessibility (a11y) checks"
	@echo "make analyze      - Run Flutter static analysis"
	@echo "make format       - Format all Dart code in the workspace"
	@echo "make format-check - Verify Dart code formatting without modifying"
	@echo "make scan         - Run local security and lint checks"
	@echo "make clean        - Clean build artifacts"

test:
	flutter test

bdd:
	flutter test test/bdd_suite_test.dart

a11y:
	flutter test test/accessibility/

analyze:
	flutter analyze --no-fatal-infos

format:
	dart format .

format-check:
	dart format --output=none --set-exit-if-changed .

scan:
	flutter analyze --no-fatal-infos
	flutter test test/bdd_suite_test.dart
	flutter test test/observability_test.dart

clean:
	flutter clean
	rm -rf build/
