# ADR 0001: Record Architecture Decisions

## Status
Accepted

## Context
1Wallet is an evolving cross-platform personal finance application with strict privacy, security, and ledger consistency requirements. Over time, architectural choices around testing frameworks, third-party SDKs, telemetry, release pipelines, and modularity need to be documented so that future engineers, automated tools, and AI agents understand why specific technologies and trade-offs were chosen.

## Decision
We adopt Architecture Decision Records (ADRs) using the standard MADR/Nygard lightweight format. All ADRs will reside in `docs/adr/` with numbered filenames (`000X-short-description.md`).

Each record covers:
- **Title & Number**: Sequential identifier and clear topic.
- **Status**: Proposed, Accepted, Deprecated, or Superseded.
- **Context**: The background, operational requirements, constraints, and alternatives considered.
- **Decision**: The selected direction and the technical justification.
- **Consequences**: Positive and negative outcomes, trade-offs, and invariants to uphold.
- **Compliance**: How the decision is verified and maintained in CI/CD and developer workflows.

## Consequences
- Major technical choices and contested tool comparisons (e.g., Patrol vs Maestro, Sentry vs Crashlytics, Shorebird y/n) are recorded permanently in source control.
- Changes to architecture must either reference an existing ADR or introduce a new/superseding ADR.
