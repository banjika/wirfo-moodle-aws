# Phase 1 Requirements Document — Moodle LMS on AWS (Cost-Optimized Pilot)

**Project:** Moodle Learning Management System
**Domain:** academy.wirfocloud.com
**Region:** eu-west-1 (Ireland)
**Document Status:** Phase 1 — Pilot deployment, no payments
**Target Audience:** 50–100 concurrent users
**Deployment Model:** Single AWS account, single region

---

## 1. Executive Summary

### What Phase 1 Is

Phase 1 is a **production-foundation pilot deployment** of a Moodle LMS on AWS. It is the smallest viable architecture that can host a real cohort of 50–100 learners on a custom domain over HTTPS, with automated backups and basic observability. It is **not** a high-availability system, **not** a payment-processing system, and **not** a multi-region system. Those concerns are deferred to Phases 2 and 3.

> *Analogy:* Phase 1 is like opening a single well-equipped classroom with one teacher, a locked filing cabinet, and a smoke alarm — enough to teach safely. Phase 2 adds a card reader at the door for paid enrolment. Phase 3 turns it into a campus with backup classrooms in case one floods.

### Cost Posture

**Very low — target ~$60–$90 per month** all-in. The architecture aggressively avoids the four classic cost traps in AWS: NAT Gateways, Multi-AZ duplication, idle provisioned capacity, and per-service KMS Customer Managed Keys (CMKs). Where AWS-managed encryption keys (`aws/*`) provide adequate security, Phase 1 uses them and defers CMKs to Phase 2.

### Key Constraints

- Single AWS account, single region (eu-west-1).
- Single Availability Zone for compute, database, cache, and EFS mount target. Two AZs are *configured at the VPC/subnet layer* so Phase 3 HA needs no network refactoring, but only one AZ is *used* in Phase 1.
- No payment processing. Moodle is configured for self-enrolment and manual enrolment only.
- No multi-AZ RDS, no Auto Scaling Group, no Application Load Balancer, no NAT Gateway.
- No regulatory pricing-compliance logic (BNR REG 89/2025 — deferred to Phase 2 alongside payments).
- Best-effort uptime: targeted ~99% monthly availability, no formal SLA.

---

## 2. Scope Definition

### 2.1 Included in Phase 1

**Compute & Application**

- One EC2 instance running Ubuntu 22.04 LTS on a Graviton (`t4g`) processor, hosting Moodle 4.3+, PHP 8.1+, and Apache or Nginx.
- Automated Moodle installation on first boot via user-data, pulling configuration secrets from AWS Secrets Manager.
- Self-enrolment and manual enrolment plugins only. **No payment plugins installed.**

**Networking**

- A dual-stack VPC (IPv4 `10.0.0.0/16` + Amazon-provided IPv6) with two public and two private subnets across two AZs — provisioned but only one AZ actively used for workloads in Phase 1.
- Internet Gateway for IPv4/IPv6 ingress and egress on the public subnet.
- Egress-Only Internet Gateway for IPv6 outbound from private subnets (used by Phase 3, present from day one for forward-compatibility).
- **No NAT Gateway.** The EC2 instance lives in a public subnet and uses its own public IPv4 + IPv6 for outbound traffic, eliminating ~$32/month per AZ.

**Data Layer**

- Amazon RDS for PostgreSQL 15+, single-AZ, `db.t4g.small`, encrypted at rest with the AWS-managed `aws/rds` key. Storage autoscaling enabled up to 200 GB.
- Amazon ElastiCache for Valkey (open-source Redis fork), single-node `cache.t4g.micro`, used for Moodle sessions and the Moodle Universal Cache (MUC).
- Amazon EFS in Bursting throughput mode (cheaper than Elastic at this scale) for `/var/moodledata`, with a single mount target in the same AZ as the EC2 instance.

**Security**

- AWS Secrets Manager for the database master password and the Moodle admin password. **Manual rotation in Phase 1** — automatic rotation deferred to Phase 2 because it requires a VPC-attached Lambda and Interface VPC Endpoints that contradict the no-NAT cost stance.
- IAM instance profile with least-privilege permissions for Secrets Manager (read), CloudWatch Logs/Metrics (write), SES (send), and KMS use.
- Security Groups for each tier (web, db, cache, efs) using SG-to-SG references rather than CIDR blocks for internal traffic.
- VPC Flow Logs to CloudWatch Logs (note: there is no such thing as "Security Group flow logs" — the original requirement was reworded).
- HTTPS termination via **Amazon CloudFront in front of the EC2 instance**, using an ACM certificate. This solves the "ACM certs cannot be installed on EC2" problem identified in the requirements review and gives a free WAF attachment point for Phase 2.
- AWS CloudTrail (management events) enabled at the account level, delivered to a versioned, encrypted S3 bucket with object-lock for tamper resistance.
- Admin access exclusively via **AWS Systems Manager Session Manager**. No SSH ports open. No bastion host. No EC2 key pairs in Terraform state.

**Observability**

- CloudWatch Logs for Moodle application logs, web server logs, and system logs (separate log groups, 30-day retention).
- CloudWatch Agent on the EC2 instance for memory, disk, and CPU-credit metrics.
- A small set of **critical** CloudWatch alarms (CPU >80%, CPU credits <20%, disk >85%, RDS storage >85%, RDS connection count >80% of max, ACM cert expiry <30 days, instance status check failed). All alarms publish to a single SNS topic with email subscriptions.
- CloudWatch Synthetics canary hitting `https://academy.wirfocloud.com/login/index.php` every 5 minutes as an external "are we up?" probe.

**DNS & Certificates**

- Route 53 A and AAAA records for `academy.wirfocloud.com` pointing to the CloudFront distribution.
- ACM-issued public TLS certificate in `us-east-1` (required for CloudFront).

**Backup & Recovery**

- RDS automated backups, 7-day retention, point-in-time recovery enabled.
- AWS Backup vault for EFS, daily backups, 7-day retention.
- Quarterly restore-test runbook with a documented "pass/fail" definition.
- **RTO 4 hours, RPO 24 hours** — explicitly best-effort, single-AZ.

**Infrastructure-as-Code**

- Terraform with an S3 backend (versioned, encrypted) and DynamoDB state lock table.
- Module decomposition: `network`, `security`, `compute`, `data`, `cache`, `storage`, `dns_cdn`, `observability`.
- A single `enable_high_availability` boolean for Phase 3 toggle, *plus* independent flags for `rds_multi_az`, `enable_alb`, and `cache_cluster_mode` so each Phase 3 capability can be enabled in isolation rather than as one all-or-nothing switch.

### 2.2 Explicitly Out of Scope

**Out of scope — deferred to Phase 2 (Monetization)**

- Payment gateway integration (Flutterwave, Paystack, or equivalent).
- Webhook endpoint, HMAC signature verification, IP allowlists.
- Multi-currency enrolment instances (RWF / USD / EUR).
- BNR REG 89/2025 regional pricing compliance and Geo-IP filtering.
- MaxMind GeoIP2 integration.
- PCI DSS SAQ-A documentation.
- Invoice generation and 7-year retention.
- Automatic Secrets Manager rotation.
- AWS WAF managed rule sets (the *attachment point* exists in Phase 1 via CloudFront, but rules and their cost are added in Phase 2).
- Customer Managed KMS Keys (Phase 2 introduces them for payment data isolation).

**Out of scope — deferred to Phase 3 (High Availability)**

- Application Load Balancer.
- Auto Scaling Group with multiple EC2 instances.
- Multi-AZ RDS deployment.
- Multi-node ElastiCache cluster with automatic failover.
- Multiple EFS mount targets across AZs.
- Cross-region snapshot copy and DR runbooks.
- Dedicated Moodle cron leader-election strategy.
- Blue/green deployment tooling.

---

## 3. Functional Requirements (Phase 1)

The system shall provide the following user-facing capabilities. EARS-style phrasing is preserved for testability.

**FR-1: Public Access via Custom Domain**
THE Moodle_Platform SHALL be accessible at `https://academy.wirfocloud.com` over HTTPS only, with HTTP requests automatically redirected to HTTPS.

**FR-2: User Authentication & Self-Service**
THE Moodle_Platform SHALL allow users to register accounts, verify email addresses, log in, log out, and reset forgotten passwords using Moodle's built-in authentication.

**FR-3: Course Lifecycle**
THE Moodle_Platform SHALL allow administrators and teachers to create courses, upload content (documents, video links, images), build quizzes, and grade submissions.

**FR-4: Free Enrolment Only**
THE Moodle_Platform SHALL support **self-enrolment** (with optional enrolment key) and **manual enrolment** by administrators. THE Moodle_Platform SHALL NOT have any payment plugin installed or enabled.

**FR-5: Persistent Course Files**
THE Moodle_Platform SHALL store user-uploaded files on the EFS-backed `/var/moodledata` such that files persist across EC2 instance replacement.

**FR-6: Session Persistence Across Requests**
THE Moodle_Platform SHALL store user sessions in the Valkey cache so that login state survives PHP-FPM worker restarts.

**FR-7: Outbound Email**
THE Moodle_Platform SHALL send transactional email (registration verification, password reset, course notifications) via Amazon SES using the verified sender domain `wirfocloud.com` with SPF, DKIM, and DMARC records configured.

**FR-8: Administrative Console Access**
Administrators SHALL access Moodle administrative functions through the standard Moodle web UI. Operating-system-level admin access to the EC2 instance SHALL be available exclusively via AWS Systems Manager Session Manager.

---

## 4. Non-Functional Requirements

### 4.1 Load & Capacity

- Target **50–100 concurrent users** during typical class hours, with bursts to ~150 during quiz windows.
- Database sized for ~10,000 total registered users and ~500 active courses.
- File storage initial allocation 50 GB with autoscaling headroom.

### 4.2 Performance

- Page response time under nominal load (50 users): **< 2 seconds** for authenticated dashboard pages.
- Quiz attempt save latency: **< 1 second**.
- Acknowledged limitation: users in Rwanda accessing eu-west-1 incur ~130–160 ms baseline network RTT. CloudFront edge caching of Moodle's static assets (theme, JS, CSS, images) is used to mitigate this for non-dynamic content.

### 4.3 Availability

- **Best-effort ~99% monthly availability.** No formal SLA.
- Single-AZ design means an AZ outage causes downtime. This is an explicit, documented trade-off for Phase 1.
- Planned maintenance windows: Sunday 02:00–04:00 UTC, communicated to users in advance.

### 4.4 Recovery Objectives

- **RTO: 4 hours** (manual recovery from snapshot).
- **RPO: 24 hours** (daily automated backups, point-in-time recovery within the 7-day RDS retention window).

### 4.5 Security Baseline

- All data encrypted at rest using AWS-managed keys (`aws/rds`, `aws/ebs`, `aws/elasticfilesystem`, `aws/secretsmanager`).
- All data in transit encrypted via TLS 1.2+ (CloudFront → users, EC2 → RDS, EC2 → ElastiCache, EC2 → EFS).
- IAM least-privilege; no `*:*` policies; no long-lived IAM access keys; admin access via AWS SSO / IAM Identity Center where available.
- CloudTrail enabled for management-event audit.
- VPC Flow Logs enabled.
- Amazon GuardDuty enabled (~$5–10/month for this workload size; cheap insurance against compromised EC2 and anomalous API behaviour).

### 4.6 Compliance

- **No formal compliance framework** in Phase 1. GDPR considerations apply because data is hosted in eu-west-1 (Ireland); a Privacy Policy and Data Processing notice are the responsibility of the platform owner, not of this infrastructure.

---

## 5. AWS Architecture Overview (Phase 1 Only)

### 5.1 Logical Topology

```
                     Internet (Users)
                           │
                           ▼
              ┌──────────────────────┐
              │  Route 53 (A/AAAA)   │
              │ academy.wirfocloud   │
              └──────────┬───────────┘
                         ▼
              ┌──────────────────────┐
              │  CloudFront (HTTPS)  │  ← ACM cert in us-east-1
              │  (TLS termination,   │  ← WAF attachment point (P2)
              │   static caching)    │
              └──────────┬───────────┘
                         ▼
       ─── VPC 10.0.0.0/16 (eu-west-1, dual-stack) ───────────────
       │
       │   Public Subnet (AZ-a)         Public Subnet (AZ-b) [unused P1]
       │   ┌────────────────────┐
       │   │  EC2 t4g.small     │       Private Subnet (AZ-a, AZ-b)
       │   │  Moodle + PHP-FPM  │       ┌────────────────────────┐
       │   │  (public IPv4+IPv6)│ ────► │ RDS db.t4g.small       │
       │   │  CloudWatch Agent  │       │ (single-AZ, encrypted) │
       │   │  SSM Agent         │ ────► │ ElastiCache Valkey     │
       │   │                    │       │ (cache.t4g.micro)      │
       │   │  EFS mount /var/   │ ────► │ EFS mount target (a)   │
       │   │  moodledata        │       └────────────────────────┘
       │   └────────────────────┘
       │
       │   IGW (in/out IPv4+IPv6)    EIGW (out-only IPv6, used in P3)
       └──────────────────────────────────────────────────────────
```

### 5.2 Why This Shape

- **EC2 in a public subnet** is an unusual choice in "best-practice" AWS, but it is the *correct* choice here: it eliminates the NAT Gateway cost and is acceptable when (a) the SG allows only ports 80/443 from the CloudFront prefix list, (b) admin access is via SSM not SSH, and (c) automatic security updates are enabled. Phase 3 moves the instance behind an ALB into private subnets.
- **CloudFront in front of EC2** solves three problems at once: TLS via ACM (which cannot be installed on EC2), DDoS absorption, and latency mitigation for Rwandan users via static caching at edge locations.
- **Single CMK strategy = no CMKs.** Each AWS-managed `aws/*` key is free. A per-service CMK strategy adds ~$1/month per key plus API costs and offers little incremental security at pilot scale. Phase 2 introduces CMKs for payment-related data isolation only.

---

## 6. Recommended AWS Services

| Concern | Service | Sizing / Tier | Phase 1 Monthly Estimate (eu-west-1) |
|---|---|---|---|
| Compute | EC2 `t4g.small` (Graviton) | 2 vCPU, 2 GiB | ~$13 |
| Block storage | EBS `gp3` 30 GB | baseline | ~$2.40 |
| Database | RDS PostgreSQL `db.t4g.small`, single-AZ, 20 GB gp3 | encrypted | ~$30 |
| Cache | ElastiCache Valkey `cache.t4g.micro`, single node | encrypted in transit | ~$11 |
| File storage | EFS, Bursting throughput, ~20 GB stored | encrypted | ~$6 |
| CDN / TLS | CloudFront | low traffic | ~$1–5 |
| TLS cert | ACM | — | $0 |
| DNS | Route 53 hosted zone (assumed existing) + records | — | ~$0.50 |
| Email | Amazon SES | < 10k emails/month | <$1 |
| Secrets | Secrets Manager (2 secrets) | — | ~$0.80 |
| Logs | CloudWatch Logs (30-day retention, ~5 GB) | — | ~$3 |
| Monitoring | CloudWatch alarms + Synthetics canary | 1 canary, ~10 alarms | ~$2 |
| Threat detection | GuardDuty | small workload | ~$5 |
| Audit | CloudTrail (mgmt events) + S3 bucket | — | <$1 |
| Backups | AWS Backup for EFS + RDS automated | 7-day retention | ~$3 |
| **Total** | | | **~$80/month** |

**Explicitly avoided in Phase 1 to keep cost down:** NAT Gateway, ALB, Multi-AZ RDS, ElastiCache replicas, VPC Interface Endpoints, KMS CMKs, AWS WAF rules, AWS Config rules, Security Hub, multiple environments.

---

## 7. Security Baseline

1. **Identity & Access**
   - One IAM role for the EC2 instance with five narrow policies (Secrets Manager read on named secrets, CloudWatch Logs write on named log groups, CloudWatch Metrics PutMetricData, SES SendEmail/SendRawEmail, SSM Session Manager).
   - Human access via AWS IAM Identity Center (AWS SSO) where possible; otherwise IAM users with MFA mandatory.
   - **No long-lived access keys.** GitHub Actions deploys via OIDC federation, not via stored keys.

2. **Network**
   - Web SG: ingress 80/443 from `com.amazonaws.global.cloudfront.origin-facing` AWS-managed prefix list only; no `0.0.0.0/0`.
   - DB SG, Cache SG, EFS SG: ingress only from Web SG (SG-to-SG reference).
   - All egress restricted: HTTPS to AWS API endpoints, PostgreSQL to DB SG, Valkey to Cache SG, NFS to EFS SG, SMTP/SES on 587/465.
   - VPC Flow Logs to CloudWatch Logs, 14-day retention.

3. **Data Protection**
   - At rest: RDS encrypted with `aws/rds`; EBS encrypted with `aws/ebs`; EFS encrypted with `aws/elasticfilesystem`; Secrets Manager encrypted with `aws/secretsmanager`; CloudWatch Logs encrypted with `aws/logs`; S3 backup buckets with SSE-S3.
   - In transit: TLS 1.2+ everywhere — CloudFront viewer policy redirects HTTP→HTTPS; RDS `rds.force_ssl=1`; ElastiCache `transit_encryption_enabled=true`; EFS mounted with `tls`.
   - Moodle `$CFG->wwwroot` set to `https://academy.wirfocloud.com` and `$CFG->cookiesecure=true`.

4. **Audit**
   - CloudTrail management-events trail, log-file validation enabled, S3 bucket versioned + object-locked.
   - GuardDuty enabled across the account.

5. **Patching & Hardening**
   - Ubuntu unattended-upgrades for security patches.
   - SSM Patch Manager baseline applied weekly (Sunday maintenance window).
   - `fail2ban` configured for the Moodle login URL.

---

## 8. Operational & DevOps Approach

### 8.1 Infrastructure-as-Code

- **Terraform** with provider versions pinned in `versions.tf`.
- Remote state in an S3 bucket (versioning + SSE + replication blocked from public access) with DynamoDB locking.
- Module structure:

```
terraform/
├── modules/
│   ├── network/        (VPC, subnets, IGW, EIGW, route tables, flow logs)
│   ├── security/       (SGs, IAM roles, KMS aliases, Secrets Manager)
│   ├── compute/        (EC2, EIP, instance profile, user-data template)
│   ├── data/           (RDS, parameter group, subnet group)
│   ├── cache/          (ElastiCache Valkey)
│   ├── storage/        (EFS, mount targets, AWS Backup plan)
│   ├── dns_cdn/        (Route 53 records, CloudFront, ACM in us-east-1)
│   └── observability/  (CloudWatch Logs/agent config, alarms, SNS, canary)
└── environments/
    └── pilot/          (single environment for Phase 1)
```

- `terraform validate`, `tflint`, `tfsec`, and `checkov` run in CI on every PR.
- `lifecycle { prevent_destroy = true }` on RDS, EFS, the S3 state bucket, and the S3 CloudTrail bucket. Documented break-glass override procedure.

### 8.2 CI/CD

- **GitHub Actions** with OIDC trust into a dedicated Terraform deployment IAM role.
- Pipeline stages: `fmt → validate → tflint → tfsec → plan (PR comment) → manual approval → apply (main branch)`.
- Moodle application code, plugin updates, and DB migrations are *not* in the Terraform repo. They are deployed via SSM RunCommand from a small companion repo, also using GitHub Actions OIDC.
- A baked **AMI built with Packer** carries the Moodle install, PHP, web server, CloudWatch Agent, and SSM Agent. User-data only fetches secrets and writes the Moodle `config.php`. This reduces first-boot from ~10 minutes (vanilla user-data approach) to ~90 seconds.

### 8.3 Observability

- **Logs:** Three CloudWatch Log Groups — `/moodle/app`, `/moodle/web`, `/moodle/system` — 30-day retention.
- **Metrics:** CPU, memory, disk, CPU credits, RDS connections, RDS storage, ElastiCache CPU, ElastiCache evictions, EFS BurstCreditBalance.
- **Alarms (all → single SNS topic with email subscription):**
  - EC2 CPU > 80% for 5 min
  - EC2 CPU credits < 20% of max
  - EC2 status check failed (1 min)
  - Disk > 85%
  - RDS connections > 80% of max
  - RDS storage > 85%
  - RDS CPU > 80% for 10 min
  - ElastiCache evictions > 0
  - Synthetics canary failed
  - ACM cert expiry < 30 days
- **No X-Ray, no OpenTelemetry, no Container Insights, no Application Insights** in Phase 1.

### 8.4 Runbooks (must exist on day 1)

- Restore RDS from snapshot.
- Restore EFS from AWS Backup.
- Replace failed EC2 instance (Auto Recovery handles most cases; manual rebuild documented for the rest).
- Rotate database password manually.
- Renew/re-issue ACM certificate (mostly automatic; documented for edge cases).
- Quarterly restore drill with documented pass criteria.

---

## 9. Cost Optimization Strategy

1. **Graviton everywhere.** `t4g.*` for EC2, RDS, ElastiCache — ~20% cheaper than `t3.*` equivalents at equal or better performance for this workload.
2. **No NAT Gateway.** EC2 in a public subnet uses its own public IP. Saves ~$32/month per AZ + data charges. The Phase 3 NAT Gateway cost is documented in §10 so it isn't a surprise.
3. **Valkey instead of Redis.** Same protocol, ~10–15% lower price than ElastiCache Redis OSS, no per-vCPU licence implications.
4. **gp3 not gp2.** Independent IOPS/throughput pricing, ~20% cheaper at baseline.
5. **EFS Bursting, not Elastic.** Elastic throughput is metered per GB-transferred and is materially more expensive at low traffic. Bursting gives free baseline throughput proportional to stored data.
6. **AWS-managed KMS keys, not CMKs.** Defer per-service CMKs to Phase 2 where payment data justifies the spend.
7. **CloudFront for static caching.** Reduces origin bandwidth and improves UX for Rwandan users — and is free for the first 1 TB/month under AWS Free Tier-adjacent allowances.
8. **30-day log retention.** Anything longer wasn't required by Phase 1 functional needs.
9. **Single-AZ for all stateful services.** The largest single cost saver in the design.
10. **Single environment.** No dev/staging in Phase 1; a future `dev` environment is a Terraform workspace away.

> *Analogy:* Each of these is like choosing the lights, fridge, and oven for a small café. You don't buy the commercial-grade triple-door fridge until you're actually serving 500 covers a night. You buy the right size *now* and leave a wide enough kitchen *footprint* to upgrade later.

---

## 10. Future Expansion Considerations

These are decisions made *now* in Phase 1 to ensure Phase 2 and Phase 3 can be added without rework.

### 10.1 What's pre-wired for Phase 2 (Payments)

- **CloudFront is the front door.** Phase 2 attaches AWS WAF to the existing distribution — no DNS change, no certificate change. Managed rule sets (`AWSManagedRulesCommonRuleSet`, `AWSManagedRulesKnownBadInputsRuleSet`, rate-based rules on `/payment/webhook`) plug straight in.
- **Secrets Manager structure already separates concerns.** Adding `payments/flutterwave/api_key` and `payments/paystack/api_key` is purely additive; the IAM role grants are scoped by secret-name prefix to make it trivial.
- **Outbound SG egress rules** are written as named lists so adding payment-provider FQDN allowances is a localised change.
- **CMK introduction in Phase 2** isolates payment-related encryption from Moodle's general data — this is why Phase 1 deliberately avoids CMKs (so the Phase 2 CMK *means* something).
- **Database schema flexibility.** Moodle's enrolment tables already support multiple enrolment instances per course, which is the hook Phase 2 needs for multi-currency without schema migration.
- **Geo-IP / BNR compliance** is a Phase 2 application-layer concern delivered as a Moodle plugin + MaxMind GeoIP2 download cron. No infrastructure precondition is required other than outbound HTTPS.

### 10.2 What's pre-wired for Phase 3 (HA)

- **VPC has 2 public + 2 private subnets across 2 AZs from day one.** Adding HA does not touch the VPC.
- **EFS file system exists in both AZs' subnet group**; a second mount target is one Terraform resource away.
- **`enable_high_availability` boolean *plus* independent capability flags** (`rds_multi_az`, `enable_alb`, `cache_cluster_mode`) so Phase 3 can be rolled out incrementally — for example, Multi-AZ RDS first (a paid-users-justified upgrade), ALB+ASG second.
- **Moodle is configured to read sessions from Valkey**, which is the form Phase 3 needs for sticky-session-free load balancing.
- **`$CFG->wwwroot` already points at the CloudFront/Route 53 endpoint**, not at a server-specific hostname. Phase 3 swaps the origin from EC2 to ALB without any Moodle config change.

### 10.3 Phase 3 cost preview (so it isn't a surprise)

Adding HA changes the monthly bill substantially. Stakeholders should plan for it now:

| Phase 3 addition | Approx monthly delta |
|---|---|
| NAT Gateway (1 AZ) | +$32 + data |
| Application Load Balancer | +$22 + LCU |
| Second EC2 instance | +$13 |
| RDS Multi-AZ (doubles instance + storage) | +$30 |
| ElastiCache replica | +$11 |
| Second EFS mount target | $0 (just data ops) |
| **Phase 3 incremental** | **+$110/month minimum** |

### 10.4 Decisions deliberately deferred

- **PCI DSS SAQ-A documentation:** Phase 2, alongside the payment integration that triggers it.
- **Cross-region DR:** Phase 3, after multi-AZ HA is proven inside eu-west-1.
- **Multi-account AWS Organizations strategy:** out of scope until Phase 2 introduces a financial blast radius worth isolating. When introduced, the existing single-account workload will move into a `Workloads` OU under a new management account.
- **Dedicated Moodle cron node:** unnecessary at one EC2 instance; revisit when ASG count > 1 in Phase 3.
- **Container or serverless migration (ECS Fargate, App Runner, Lambda):** explicitly *not* pursued in Phase 1 because Moodle is a stateful PHP monolith with EFS dependencies; the migration cost outweighs the benefit at 50–100 users.

---

## Appendix A — Document Reconciliation Notes

The previous `requirements.md` contained three structural defects that this document resolves:

1. **Requirements 23 (Payments) and 24 (BNR Compliance)** were listed both as active requirements *and* in the deferred appendix. They are now unambiguously **out of scope for Phase 1** and live only in the Phase 2 roadmap.
2. **Requirement 19 was duplicated** with two different acceptance-criteria lists. The longer (15-criterion) version is canonical; the shorter version is dropped.
3. **"Security Group flow logs"** (Req 9.6) was a non-existent AWS feature. Replaced throughout by **VPC Flow Logs** delivered to CloudWatch Logs.

Three substantive technical changes from the original document:

1. **TLS termination moved from EC2 to CloudFront.** Original Req 22.3 was technically impossible (ACM certificates cannot be exported to EC2). CloudFront is the simplest fix and brings the Phase 2 WAF attachment point with it.
2. **Automatic Secrets Manager rotation deferred to Phase 2.** It requires either a NAT Gateway or a Secrets Manager Interface VPC Endpoint, both of which contradict Phase 1's cost stance.
3. **EFS throughput mode changed to Bursting.** Elastic mode was specified but is more expensive than Bursting at this scale; benchmarking-based switch documented as a Phase 3 decision if quiz throughput requires it.

---

**Next step:** With this Phase 1 scope confirmed, the detailed technical design (module-by-module Terraform variable tables, Security Group matrix, Moodle `config.php` template, user-data script, runbooks) is the natural follow-up before Terraform code is written.
