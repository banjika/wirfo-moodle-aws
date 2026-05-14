# Moodle on AWS - Phase 1 Pilot

Terraform infrastructure for a single-instance Moodle LMS deployment in AWS, sized for 50-100 concurrent users on a pilot cohort. Built spec-driven with Claude Code.

> **Phase 1 only.** No payments, no high availability, no multi-region. Phase 2 and Phase 3 are documented as roadmap, not implemented here.

---

## Status

**Phase 1 deployed and validated.** Live at `https://academy.wirfoncloud.com`.

| Milestone | Status | Date |
|---|---|---|
| Bootstrap (state backend, OIDC, ACM, CloudTrail) | Complete | 2026-05-10 |
| Workload first apply (T-029) | Complete | 2026-05-10 |
| Rebuild-safe user-data (T-029.5) | Complete | 2026-05-11 |
| Smoke test (T-030) | PASS | 2026-05-11 |
| First restore drill (T-031) | PASS | 2026-05-14 |
| RTO measured | 57 min (target: < 4h) | 2026-05-14 |
| RPO measured | ~9h (target: <= 24h) | 2026-05-14 |

Ongoing work tracked in [`.specs/phase-1/tasks.md`](.specs/phase-1/tasks.md).

---

## Quick links

| Document | Purpose |
|---|---|
| [`.specs/phase-1/requirements.md`](.specs/phase-1/requirements.md) | What we're building and why. Approved. |
| [`.specs/phase-1/design.md`](.specs/phase-1/design.md) | How we're building it. Approved. |
| [`.specs/phase-1/tasks.md`](.specs/phase-1/tasks.md) | Atomic implementation steps. Approved. |
| [`CLAUDE.md`](CLAUDE.md) | House rules for Claude Code sessions. |

---

## Runbooks

Operational procedures, one short page each:

| Runbook | When to use |
|---|---|
| [`docs/runbooks/bootstrap.md`](docs/runbooks/bootstrap.md) | Re-running bootstrap (rare; account migration) |
| [`docs/runbooks/first-deploy.md`](docs/runbooks/first-deploy.md) | First workload apply, end-to-end |
| [`docs/runbooks/ses.md`](docs/runbooks/ses.md) | Requesting SES production access; verifying pilot recipient addresses |
| [`docs/runbooks/restore-drill.md`](docs/runbooks/restore-drill.md) | Quarterly RDS + EFS restore drill with pass/fail criteria |

---

## Repository layout

```
.
|-- CLAUDE.md                       # Auto-loaded by Claude Code at session start
|-- README.md                       # This file
|-- .gitignore
|-- .specs/
|   `-- phase-1/
|       |-- requirements.md
|       |-- design.md
|       `-- tasks.md
|-- terraform/
|   |-- bootstrap/                  # State bucket, OIDC, ACM cert, CloudTrail. Local state. Run once.
|   |-- environments/
|   |   `-- pilot/                  # The workload. Remote state in S3.
|   `-- modules/                    # network, security, compute, data, cache, storage, dns_cdn, observability
|-- docs/
|   `-- runbooks/                   # Operational procedures
`-- .github/
    `-- workflows/                  # Terraform CI/CD via GitHub Actions OIDC
```

---

## Deploying a change

Open PR -> CI plan runs on the PR -> review -> merge to `main` -> approve the `production` GitHub Environment gate -> CI applies.

Both `Terraform Plan` (on PRs touching IaC paths) and `Terraform Apply` (on push to main) workflows live in `.github/workflows/`. Authentication is OIDC into the deploy role provisioned by bootstrap; no long-lived AWS credentials exist anywhere in the repo or in GitHub secrets.

---

## How this project was built (the workflow)

This is a **spec-driven** project. The order was fixed:

```
Requirements  ->  Design  ->  Tasks  ->  Implementation
   (done)        (done)     (done)       (ongoing, near-complete)
```

> *Analogy:* Requirements is the client brief, design is the architectural blueprint, tasks is the build schedule, implementation is the actual construction. You don't pour concrete before the blueprint is approved.

The three spec documents are immutable once approved. Implementation work happens one task per Claude Code session, with each task scoped to ~30 min and ~3-4 files. See `CLAUDE.md` for the working agreement that guides Claude Code sessions on this repo.

---

## Local quality gates

Install once:

```bash
brew install terraform tflint tfsec
pip install checkov
```

Run before every commit to a Terraform file:

```bash
cd terraform/environments/pilot
terraform fmt -check -recursive
terraform validate
tflint --recursive
tfsec .
checkov -d . --quiet
```

All five must pass. CI runs the same gates on every PR; local pre-flight just makes the CI cycle short.

---

## First-time AWS setup

Before the workload config can run, the **bootstrap config** must be applied once. Detailed procedure: [`docs/runbooks/bootstrap.md`](docs/runbooks/bootstrap.md). Summary:

```bash
# 1. Get AWS credentials (prefer SSO / IAM Identity Center over long-lived keys)
aws sso login --profile moodle-pilot

# 2. Apply bootstrap (creates state bucket, lock table, OIDC provider, ACM cert in us-east-1, CloudTrail)
cd terraform/bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 3. Capture outputs - you need them to configure GitHub repo variables
terraform output

# 4. Now the workload can use the remote backend
cd ../environments/pilot
terraform init   # Will prompt to migrate state into S3 the first time
```

The bootstrap config uses **local state** (the chicken-and-egg problem: Terraform cannot store its state in a bucket it has not created yet). The workload config uses **remote state** in the S3 bucket the bootstrap created, with DynamoDB locking.

---

## Cost expectations

| Phase | Approximate monthly cost (eu-west-1) |
|---|---|
| Phase 1 (this) | **~$80** |
| Phase 2 (+ payments, WAF, CMKs) | ~$110 |
| Phase 3 (+ HA: NAT, ALB, Multi-AZ RDS, ASG) | ~$190+ |

See `.specs/phase-1/requirements.md` section 6 and section 10.3 for the breakdown.

---

## Out of scope (intentionally)

These are **not** in Phase 1. Do not ask Claude Code to add them - it has been instructed to refuse.

- Payment gateway integration (Flutterwave, Paystack)
- Multi-currency enrolment, BNR REG 89/2025 compliance, Geo-IP filtering
- Application Load Balancer, Auto Scaling Group
- Multi-AZ RDS, ElastiCache replicas, multiple EFS mount targets
- Cross-region disaster recovery
- Customer Managed KMS Keys
- AWS WAF rule sets (the *attachment point* exists via CloudFront; rules are Phase 2)
- AWS Config, Security Hub, multi-account AWS Organizations setup

---

## License

Internal project. Not licensed for external distribution.