# Moodle on AWS — Phase 1 Pilot

Terraform infrastructure for a single-instance Moodle LMS deployment in AWS, sized for 50–100 concurrent users on a pilot cohort. Built spec-driven with Claude Code.

> **Phase 1 only.** No payments, no high availability, no multi-region. Phase 2 and Phase 3 are documented as roadmap, not implemented here.

---

## Quick links

| Document | Purpose |
|---|---|
| [`.specs/phase-1/requirements.md`](.specs/phase-1/requirements.md) | What we're building and why. **Approved.** |
| [`.specs/phase-1/design.md`](.specs/phase-1/design.md) | How we're building it. *(produced in design phase)* |
| [`.specs/phase-1/tasks.md`](.specs/phase-1/tasks.md) | Atomic implementation steps. *(produced in tasks phase)* |
| [`CLAUDE.md`](CLAUDE.md) | House rules for Claude Code sessions. |

---

## Repository layout

```
.
├── CLAUDE.md                       # Auto-loaded by Claude Code at session start
├── README.md                       # This file
├── .gitignore
├── .specs/
│   └── phase-1/
│       ├── requirements.md         # Approved
│       ├── design.md               # Produced in Step 2
│       └── tasks.md                # Produced in Step 3
├── terraform/
│   ├── bootstrap/                  # State bucket, OIDC, ACM cert. Local state. Run once.
│   └── environments/
│       └── pilot/                  # The workload. Remote state.
├── docs/
│   └── runbooks/                   # Operational procedures
└── .github/
    └── workflows/                  # Terraform CI/CD via GitHub Actions OIDC
```

---

## How this project is built (the workflow)

This is a **spec-driven** project. The order is fixed:

```
Requirements  →  Design  →  Tasks  →  Implementation
   (done)         (1)        (2)          (3)
```

> *Analogy:* Requirements is the client brief, design is the architectural blueprint, tasks is the build schedule, implementation is the actual construction. You don't pour concrete before the blueprint is approved.

### Step 1 — Design (one Claude Code session)

```bash
claude
```

Then in the session:

> Read `.specs/phase-1/requirements.md`. Produce `.specs/phase-1/design.md` per the workflow in `CLAUDE.md`. Use plan mode. Stop when done and ask for approval.

Iterate on the design until it's right. Commit when approved.

### Step 2 — Tasks (one Claude Code session)

```bash
claude
```

> Produce `.specs/phase-1/tasks.md` from the approved design. Stop when done and ask for approval.

Commit when approved.

### Step 3 — Implementation (one Claude Code session per task)

```bash
claude
```

> Implement task T-001 from `.specs/phase-1/tasks.md`. Do not implement any other tasks.

Run quality gates locally between tasks (see below). Commit each green task separately.

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

All five must pass.

---

## First-time AWS setup

Before `terraform apply` of the workload config can run, the **bootstrap config** must be applied once:

```bash
# 1. Get AWS credentials (prefer SSO / Identity Center over long-lived keys)
aws sso login --profile moodle-pilot

# 2. Apply bootstrap (creates state bucket, lock table, OIDC, ACM cert)
cd terraform/bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 3. Note the outputs — you'll need them for the workload backend config
terraform output

# 4. Now the workload can use the remote backend
cd ../environments/pilot
terraform init   # Will prompt to migrate state into S3
```

The bootstrap config uses **local state** that is committed to the repo (encrypted via the bucket it creates is bootstrap-only — no sensitive data). The workload config uses **remote state** in the S3 bucket the bootstrap created.

---

## Cost expectations

| Phase | Approximate monthly cost (eu-west-1) |
|---|---|
| Phase 1 (this) | **~$80** |
| Phase 2 (+ payments, WAF, CMKs) | ~$110 |
| Phase 3 (+ HA: NAT, ALB, Multi-AZ RDS, ASG) | ~$190+ |

See `requirements.md` §6 and §10.3 for the breakdown.

---

## Out of scope (intentionally)

These are **not** in Phase 1. Do not ask Claude Code to add them — it has been instructed to refuse.

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
