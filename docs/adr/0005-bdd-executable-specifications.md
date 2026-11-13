# ADR 0005: Behavior-Driven Development (BDD) and Executable Specifications

## Status
Accepted

## Context
1Wallet's financial and offline capabilities involve subtle business rules:
- Expenses decrease account balances in exact integer minor units.
- Transfers atomically debit the source account and credit the target account.
- In offline mode, the app persists records locally and enforces that zero cloud sync writes occur.
- Write guards prevent accidental overwrite of remote revisions when switching between offline and online states.

Traditional unit and widget tests verify implementation mechanics, but do not provide a clear, business-readable specification of end-to-end user workflows.

## Decision
We adopt **BDD Executable Specifications using Gherkin syntax (`.feature` files)**:

1. **Business-Language Feature Files**: Feature scenarios reside in `test/bdd/features/` and specify user expectations in standard Given/When/Then syntax.
2. **Deterministic Step Definitions**: Step definitions (`test/bdd/step_definitions/`) are wired directly to `test/test_harness.dart` and `test/offline_mode_fakes.dart`. This ensures that steps manipulate the real Riverpod ledger state and verify real database invariants rather than superficial UI mocks.
3. **Dedicated CI Runner & Reporting**: A dedicated BDD test suite runner executes the specifications, measures pass/fail status, and generates structured execution reports published as CI artifacts.
4. **Behavior Acceptance Scope**: BDD tests do not replace granular unit tests; they represent high-level acceptance criteria for money-critical and offline workflows.

## Consequences
- Business rules are readable by financial auditors, product managers, and developers.
- Proves mathematically that offline transactions remain strictly local and never emit network requests to Firestore.
- Step definitions are reusable across multiple scenarios, reducing boilerplate.
