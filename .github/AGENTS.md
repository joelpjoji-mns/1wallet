# `.github/` — GitHub Project Metadata & CI/CD Root

## 🎯 Role & Overview
Houses GitHub repository templates, issue/PR automation, Dependabot configurations, and CI/CD workflow pipelines for 1Wallet.

---

## 🗂️ Sub-modules

- **`workflows/`**: GitHub Actions workflow YAML files automating pull request validation, beta builds, production Android/iOS signing and releases, and Dependabot auto-merges.

---

## 🛡️ Critical Invariants & Architecture

1. **Strict Secrets Separation**:
   - Production signing keystores, Google Play credentials, Apple certificates, and Firebase service keys must remain stored in GitHub Encrypted Secrets, never committed to git.
2. **Release Quality Gates**:
   - Every release pipeline requires automated testing (`flutter test`) and lint checks to succeed before artifacts are uploaded or deployed.
