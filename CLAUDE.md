# Project: Moodle on AWS — Phase 1 Pilot

You are working on a spec-driven Terraform project that deploys a Moodle LMS on AWS for a pilot cohort of 50–100 users. Read this file in full before doing anything else in this repo.

---

## Spec-Driven Workflow

This project follows a strict four-phase workflow. **Do not skip phases.**

```
Requirements  →  Design  →  Tasks  →  Implementation
   (done)       (you)    (you)        (you, one task at a time)
```

| Phase | Artifact | Status |
|---|---|---|
| 1. Requirements | `.specs/phase-1/requirements.md` | ✅ Approved — do not modify |
| 2. Design | `.specs/phase-1/design.md` | ⏳ To be produced |
| 3. Tasks | `.specs/phase-1/tasks.md` | ⏳ To be produced after design |
| 4. Implementation | `terraform/**/*.tf` | ⏳ Only after tasks are approved |

**Hard rule:** Do not write any Terraform (`.tf`) file until both `design.md` and `tasks.md` exist and the user has explicitly said "approved" or "proceed to implementation."

When asked to design, produce `design.md` and stop. When asked to plan tasks, produce `tasks.md` and stop. When asked to implement, do exactly one task from `tasks.md` per session unless the user explicitly says otherwise.

---

## Project Context

- **Workload:** Moodle 4.3+ LMS on a single Ubuntu 22.04 EC2 instance
- **Region:** eu-west-1 (Ireland) — primary
- **Region:** us-east-1 (N. Virginia) — secondary, for the CloudFront ACM certificate ONLY
- **Account model:** Single AWS account, single environment (`pilot`)
- **User scale:** 50–100 concurrent users, no payments, no HA
- **Domain:** `academy.wirfocloud.com` (Route 53 hosted zone for `wirfocloud.com` is assumed to already exist)
- **Cost target:** ~$80/month all-in

---

## Architectural Hard Rules

These are non-negotiable. If a request would violate one of these, push back rather than complying.

1. **No NAT Gateway.** EC2 sits in a public subnet. This is the largest single cost saver in the design and is a deliberate Phase 1 choice.
2. **No Multi-AZ for stateful services.** RDS, ElastiCache, and EFS are all single-AZ. Two AZs are provisioned at the VPC layer for Phase 3 readiness, but only one is used.
3. **No Customer Managed KMS Keys (CMKs).** Use AWS-managed `aws/*` keys (`aws/rds`, `aws/ebs`, `aws/elasticfilesystem`, `aws/secretsmanager`, `aws/logs`). CMKs are deferred to Phase 2.
4. **No Application Load Balancer, no Auto Scaling Group.** TLS terminates at CloudFront. Phase 3 introduces the ALB.
5. **No payment-related anything.** No webhook endpoints, no Flutterwave/Paystack code, no multi-currency logic, no Geo-IP. These are Phase 2.
6. **No SSH.** Admin access is exclusively via AWS Systems Manager Session Manager. Do not create EC2 key pairs. Do not open port 22 anywhere.
7. **Web SG ingress = CloudFront only.** Use the AWS-managed prefix list `com.amazonaws.global.cloudfront.origin-facing`. Never `0.0.0.0/0` on ports 80 or 443.
8. **Internal traffic uses SG-to-SG references**, not CIDR blocks.
9. **Encrypt at rest by default.** Every storage resource (EBS, RDS, EFS, Secrets Manager, CloudWatch Logs, S3) must be encrypted, even when the requirement does not explicitly state it.
10. **HTTPS only.** No plaintext HTTP listeners except a redirect-to-HTTPS rule.

---

## Terraform Conventions

- Terraform `>= 1.7`. AWS provider `>= 5.0, < 6.0`. Pin both in `versions.tf`.
- Two AWS provider configurations: default (`eu-west-1`) and aliased `us_east_1` for the CloudFront ACM certificate.
- Module decomposition is fixed: `network`, `security`, `compute`, `data`, `cache`, `storage`, `dns_cdn`, `observability`. Do not invent new top-level modules without explicit approval.
- Every resource gets these tags: `Project = "moodle-academy"`, `Environment = "pilot"`, `ManagedBy = "terraform"`, `CostCenter = "pilot"`. Use `default_tags` on the provider.
- `lifecycle { prevent_destroy = true }` on RDS, EFS, the Terraform state S3 bucket, and the CloudTrail S3 bucket.
- Variable naming: `snake_case`. Resource names: `snake_case`. No abbreviations unless they are AWS-standard (`vpc`, `sg`, `rds`).
- One file per concern within a module: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`. Add `iam.tf`, `data.tf` only when the file would otherwise exceed ~200 lines.
- Use `for_each` over `count` where order or naming would be affected by changes.
- No hardcoded ARNs, account IDs, or regions inside module bodies. Pass them as variables or read them via `data "aws_caller_identity"` / `data "aws_region"`.

---

## State and Bootstrap

There is a chicken-and-egg problem: Terraform state needs an S3 bucket, but we want Terraform to create the bucket. Resolve it with two configurations:

```
terraform/
├── bootstrap/                # Local state. Run ONCE manually.
│   ├── main.tf               # Creates: state S3 bucket, lock DynamoDB,
│   │                         #          GitHub OIDC provider, deploy IAM role,
│   │                         #          ACM cert in us-east-1
│   └── outputs.tf            # Exports bucket name, role ARN
└── environments/pilot/       # Remote state in the bucket created above.
    └── main.tf               # The actual workload.
```

- Bootstrap config uses **local state**, committed once, almost never re-run.
- Workload config uses **S3 backend** with DynamoDB locking.
- Never put bootstrap resources in the workload config.

---

## Quality Gates

Before suggesting `terraform apply`, you must pass these locally and report results:

```bash
terraform fmt -check -recursive
terraform validate
tflint --recursive
tfsec .
checkov -d . --quiet
```

Any failure → fix before proceeding. If a tool is not installed, say so and stop — do not skip the check silently.

---

## What to do when the user asks you to…

| User says | You do |
|---|---|
| "Start the design" | Read `requirements.md`, produce `design.md`, stop, ask for approval. |
| "Design looks good" / "approved" | Produce `tasks.md`, stop, ask for approval. |
| "Implement task T-00X" | Implement that one task only. Run `fmt` + `validate`. Report. Stop. |
| "Implement everything" | Refuse. Explain that one task per session is the rule. Offer to do task 1. |
| "Add payments" / "Add MFA for the webhook" / "Set up Multi-AZ RDS" | Refuse politely. Explain it is Phase 2 or Phase 3 and out of scope. |
| "Run terraform apply" | Refuse for the first 2–3 applies. Tell the user to run it themselves so they can review the plan. After that, only with explicit per-session permission. |
| "Just write the code, skip the design" | Refuse. Explain the workflow and the cost of skipping it. |

---

## Communication Style

- Be terse. The user is an experienced AWS instructor — explain unfamiliar AWS quirks but don't over-explain basics.
- When making a non-obvious choice, leave a one-line comment in the `.tf` file explaining *why*, not *what*.
- When you're uncertain about a requirement, ask before guessing.
- Use plan mode (Shift+Tab) for design and task phases. Use normal mode for implementation tasks only.

---

## Files you should never touch

- `.specs/phase-1/requirements.md` — already approved, treat as immutable.
- `.git/`, `.terraform/`, `*.tfstate`, `*.tfstate.backup` — Terraform internals.
- Anything under `docs/runbooks/` unless the user explicitly asks.
