# Phase 1 Tasks Document — Moodle LMS on AWS

**Project:** Moodle Learning Management System
**Source-of-truth design:** [`.specs/phase-1/design.md`](./design.md) — approved
**Source-of-truth requirements:** [`.specs/phase-1/requirements.md`](./requirements.md) — approved, immutable
**Workflow rule:** one task per session unless explicitly overridden (`CLAUDE.md`).

This document decomposes the approved design into atomic tasks. Each task is sized for ~30 minutes of focused work and ≤ ~3–4 files of code change. Stages run in numerical order; later stages may not begin until all blocking tasks in earlier stages are merged. Within a stage, tasks may run in parallel only when their `Depends on` lists permit.

Universal acceptance criteria — every code-bearing task **must pass these locally before the PR opens**:

```bash
terraform fmt -check -recursive
terraform -chdir=<config-dir> validate
tflint --recursive
tfsec .
checkov -d . --quiet
```

Per-task acceptance criteria below add specific resource-presence and rule-compliance checks on top of these five gates.

---

## Stage 0 — Bootstrap

Stage goal: produce a runnable `terraform/bootstrap/` config that, when applied once by the operator, creates the state backend, OIDC trust, ACM cert, CloudTrail, and the deploy IAM role for Stages 1+.

### T-001 — Repo skeleton

- **Stage / module:** 0 / cross-cutting
- **Deliverable:** the directory layout described in `README.md` exists with empty placeholder files. Specifically: `terraform/bootstrap/.keep`, `terraform/environments/pilot/.keep`, `terraform/modules/{network,security,compute,data,cache,storage,dns_cdn,observability}/.keep`, `.github/workflows/.keep`, `docs/runbooks/.keep`. Add `.tflint.hcl` at repo root with the AWS plugin enabled. Append Terraform-specific patterns to `.gitignore` (`*.tfstate`, `*.tfstate.backup`, `.terraform/`, `.terraform.lock.hcl` is *kept*, `*.tfvars` excluded except `*.tfvars.example`, `tfplan*`).
- **Acceptance criteria:**
  - All directory placeholders committed; `git ls-tree -r HEAD --name-only` shows the layout.
  - `tflint --version` succeeds against the new `.tflint.hcl` (config parses).
  - `.gitignore` lines verified by attempting to add a dummy `pilot.tfvars` — git refuses.
- **Depends on:** none
- **Touch points:** `.gitignore`, `.tflint.hcl`, ~10 `.keep` files

### T-002 — Workload root scaffold

- **Stage / module:** 0 / `terraform/environments/pilot/`
- **Deliverable:** workload root files with no resources yet but a complete provider/backend/variable surface matching `design.md` §3, §6.2.
  - `terraform/environments/pilot/versions.tf` — `required_version = ">= 1.7"`, `hashicorp/aws >= 5.0, < 6.0`, `random >= 3.6, < 4.0`, default provider in `eu-west-1`, aliased provider `us_east_1`. `default_tags` on **both** providers (`Project = "moodle-academy"`, `Environment = "pilot"`, `ManagedBy = "terraform"`, `CostCenter = var.cost_center`, merged with `var.extra_tags`).
  - `terraform/environments/pilot/backend.tf` — `backend "s3"` with hardcoded `bucket = "wirfo-moodle-tfstate-<account-id>"` (literal placeholder; operator substitutes after T-008), `key = "pilot/terraform.tfstate"`, `region = "eu-west-1"`, `dynamodb_table = "wirfo-moodle-tflock"`, `encrypt = true`.
  - `terraform/environments/pilot/variables.tf` — all 35 rows from design.md §3.
  - `terraform/environments/pilot/main.tf` — empty (module calls added per stage).
  - `terraform/environments/pilot/outputs.tf` — empty.
  - `terraform/environments/pilot/terraform.tfvars.example` — populated with placeholder values for `alarm_email`, `moodle_admin_email`.
- **Acceptance criteria:**
  - `terraform -chdir=terraform/environments/pilot init -backend=false` succeeds.
  - `terraform -chdir=terraform/environments/pilot validate` succeeds.
  - `terraform-linters/tflint --recursive` reports zero warnings on the workload directory.
  - `tfsec terraform/environments/pilot` reports zero high/critical findings (low/medium acceptable; document any explicit ignores).
  - All four mandatory tags present in `default_tags` of both providers.
- **Depends on:** T-001
- **Touch points:** 5 files in `terraform/environments/pilot/`

### T-003 — Bootstrap skeleton

- **Stage / module:** 0 / `terraform/bootstrap/`
- **Deliverable:**
  - `terraform/bootstrap/versions.tf` — `required_version = ">= 1.7"`, `hashicorp/aws >= 5.0, < 6.0`, default provider `eu-west-1`, aliased `us_east_1`. `default_tags` mirroring T-002.
  - `terraform/bootstrap/variables.tf` — the 7 bootstrap variables from design.md §6.1 (with their defaults).
  - `terraform/bootstrap/outputs.tf` — declared but empty `output {}` blocks for `state_bucket_name`, `lock_table_name`, `cloudtrail_bucket_name`, `cloudtrail_arn`, `deploy_role_arn`, `acm_certificate_arn` (filled by later tasks).
  - `terraform/bootstrap/main.tf` — empty (resources added per task).
  - `terraform/bootstrap/data.tf` — `data "aws_caller_identity" "current"`, `data "aws_region" "current"`, `data "aws_route53_zone" "main" { name = "wirfoncloud.com." }`.
- **Acceptance criteria:**
  - `terraform -chdir=terraform/bootstrap init` succeeds (local backend, no remote state yet).
  - `terraform -chdir=terraform/bootstrap validate` succeeds.
  - `tflint`, `tfsec`, `checkov` clean.
- **Depends on:** T-001
- **Touch points:** 5 files in `terraform/bootstrap/`

### T-004 — Bootstrap state bucket + DynamoDB lock

- **Stage / module:** 0 / `terraform/bootstrap/`
- **Deliverable:**
  - `terraform/bootstrap/state.tf` containing:
    - `aws_s3_bucket "tfstate"` named `"wirfo-moodle-tfstate-${data.aws_caller_identity.current.account_id}"`, `lifecycle { prevent_destroy = true }`.
    - `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration` (SSE-S3 / `aws/s3` — **not** a CMK), `aws_s3_bucket_public_access_block` (all four = `true`), `aws_s3_bucket_ownership_controls` (`BucketOwnerEnforced`), `aws_s3_bucket_lifecycle_configuration` (90-day noncurrent expiration).
    - `aws_dynamodb_table "tflock"` (`name = "wirfo-moodle-tflock"`, PK `LockID` string, `billing_mode = "PAY_PER_REQUEST"`, `point_in_time_recovery { enabled = true }`).
  - Wire `state_bucket_name` and `lock_table_name` outputs in `outputs.tf`.
  - `terraform/bootstrap/.checkov.yaml`: config-level skip list for five Phase 1 design decisions (inline #checkov:skip not honoured by checkov 3.2.x on Windows; inline annotations retained as intent documentation).
- **Acceptance criteria:**
  - `terraform -chdir=terraform/bootstrap plan` shows exactly: 1 S3 bucket + its 5 sub-resources, 1 DynamoDB table.
  - `tfsec` rules `aws-s3-enable-versioning`, `aws-s3-enable-bucket-encryption`, `aws-s3-block-public-acls`, `aws-s3-block-public-policy` all pass.
  - `checkov` rules `CKV_AWS_18` (logging), `CKV_AWS_21` (versioning), `CKV_AWS_144` (cross-region replication) reviewed; replication intentionally skipped with documented `# checkov:skip=CKV_AWS_144` comment (Phase 1 cost stance).
- **Depends on:** T-003
- **Touch points:** 2 files (`state.tf`, `outputs.tf`)

### T-005 — Bootstrap GitHub OIDC provider + deploy role

- **Stage / module:** 0 / `terraform/bootstrap/`
- **Deliverable:**
  - `terraform/bootstrap/github_oidc.tf`: `aws_iam_openid_connect_provider "github"` with thumbprint(s) and `client_id_list = ["sts.amazonaws.com"]`.
  - `terraform/bootstrap/iam_deploy.tf`: `aws_iam_role "deploy"` with trust policy condition `sub = "repo:${var.github_repo}:*"` and `aud = "sts.amazonaws.com"`; `aws_iam_role_policy "deploy"` with the inline policy from design.md §5 (the GitHub OIDC deploy role row, including the SSM Parameter Store statement on `arn:aws:ssm:eu-west-1:${data.aws_caller_identity.current.account_id}:parameter/moodle/*`).
  - Wire `deploy_role_arn` output.
- **Acceptance criteria:**
  - `terraform plan` shows the OIDC provider and one IAM role with one inline policy.
  - The policy document explicitly contains: `ses:*` on the SES identity ARN; the 8 SSM Parameter Store actions on the `/moodle/*` parameter ARN; `s3:*` only on the state bucket and CloudTrail bucket ARNs; `dynamodb:*` only on the lock table ARN; `iam:PassRole` only to roles tagged `Project = moodle-academy`.
  - No statement contains `Action = "*"` or `Resource = "*"` together.
  - `tfsec` rule `aws-iam-no-policy-wildcards` audited; any flagged wildcards have an inline justification comment.
- **Depends on:** T-004 (for state-bucket ARN reference)
- **Touch points:** 3 files (`github_oidc.tf`, `iam_deploy.tf`, `outputs.tf`)

### T-006 — Bootstrap ACM certificate (us-east-1)

- **Stage / module:** 0 / `terraform/bootstrap/`
- **Deliverable:**
  - `terraform/bootstrap/acm.tf`:
    - `aws_acm_certificate "cloudfront"` in `provider = aws.us_east_1` for `var.domain_name` with `subject_alternative_names = var.acm_subject_alternative_names`, `validation_method = "DNS"`.
    - `aws_route53_record` for each validation option using `for_each = { for o in aws_acm_certificate.cloudfront.domain_validation_options : o.domain_name => o }` writing CNAMEs into `data.aws_route53_zone.main`.
    - `aws_acm_certificate_validation "cloudfront"` to wait for issuance.
  - Wire `acm_certificate_arn` output.
- **Acceptance criteria:**
  - `terraform plan` shows the cert created in `us-east-1` (verified by `provider` in plan output) and N validation records in the eu-west-1 hosted zone.
  - `tfsec` rule `aws-cloudfront-use-secure-tls-policy` not triggered here (CloudFront is in `dns_cdn`); cert resource passes encryption rules.
- **Depends on:** T-003 (data sources)
- **Touch points:** 2 files (`acm.tf`, `outputs.tf`)

### T-007 — Bootstrap CloudTrail

- **Stage / module:** 0 / `terraform/bootstrap/`
- **Deliverable:**
  - `terraform/bootstrap/cloudtrail.tf`:
    - `aws_s3_bucket "cloudtrail"` named `"wirfo-moodle-cloudtrail-${data.aws_caller_identity.current.account_id}"`, `lifecycle { prevent_destroy = true }`, `object_lock_enabled = true`.
    - Sub-resources: versioning on, public-access-block all-on, SSE with `aws/s3`, ownership `BucketOwnerEnforced`, `aws_s3_bucket_object_lock_configuration` with COMPLIANCE mode + 90-day default retention.
    - `aws_s3_bucket_policy "cloudtrail"` granting `cloudtrail.amazonaws.com` `s3:GetBucketAcl` and `s3:PutObject` with `aws:SourceArn` condition referencing the trail ARN.
    - `aws_cloudtrail "moodle_mgmt"` (`is_multi_region_trail = true`, `enable_log_file_validation = true`, `include_global_service_events = true`, no event-selectors → management events only).
  - Wire `cloudtrail_bucket_name` and `cloudtrail_arn` outputs.
- **Acceptance criteria:**
  - `terraform plan` shows trail with `is_multi_region_trail = true` and bucket with object-lock enabled.
  - `tfsec` rules `aws-cloudtrail-enable-log-validation`, `aws-cloudtrail-ensure-cloudwatch-integration` (latter intentionally skipped — no CW Logs target in P1 — with inline comment), `aws-s3-enable-bucket-logging` reviewed.
  - `checkov` `CKV_AWS_36` (CloudTrail log validation) passes.
- **Depends on:** T-003
- **Touch points:** 2 files (`cloudtrail.tf`, `outputs.tf`)

### T-008 — Bootstrap apply + GitHub repo wiring + Budgets reminder

- **Stage / module:** 0 / operator action (no Terraform code change)
- **Deliverable:**
  - Operator runs `terraform -chdir=terraform/bootstrap init && terraform -chdir=terraform/bootstrap plan -out=tfplan && terraform -chdir=terraform/bootstrap apply tfplan` locally under SSO credentials.
  - Operator captures the four runtime outputs: `state_bucket_name`, `lock_table_name`, `cloudtrail_bucket_name`, `deploy_role_arn`, `acm_certificate_arn` and pastes them into a tracking note.
  - Operator sets the `AWS_DEPLOY_ROLE_ARN` repository variable in GitHub, protects `main` (require PR + status checks), and creates the `production` GitHub Environment with required reviewer = the operator's GitHub account.
  - Operator creates an AWS Budgets billing alarm at 120% of $80/month with email notification (manual; not in Terraform — see design.md §9 row 5).
  - Operator updates `terraform/environments/pilot/backend.tf` to substitute the literal `<account-id>` placeholder with the real account ID. Commit this change with message documenting which account.
- **Acceptance criteria:**
  - Bootstrap S3 bucket and DynamoDB table visible in eu-west-1 console.
  - GitHub `AWS_DEPLOY_ROLE_ARN` variable populated; `main` protection rules visible in repo settings.
  - AWS Budgets alarm visible in Billing console with confirmed SNS subscription.
  - PR opened that swaps the placeholder account ID in `backend.tf`; CI green; merged.
- **Depends on:** T-004, T-005, T-006, T-007
- **Touch points:** `terraform/environments/pilot/backend.tf` (one substitution); manual ops

---

## Stage 1 — Network module

### T-009 — `modules/network`: VPC, subnets, gateways, routes

- **Stage / module:** 1 / `terraform/modules/network/`
- **Deliverable:**
  - `terraform/modules/network/versions.tf` (Terraform + AWS provider pins).
  - `terraform/modules/network/variables.tf` (matches design.md §2.1 inputs).
  - `terraform/modules/network/main.tf`:
    - `aws_vpc` (10.0.0.0/16, IPv6 Amazon-provided /56, DNS hostnames + DNS support enabled).
    - `aws_subnet` × 4 with `for_each` keyed on AZ × tier; IPv6 /64 cidrs derived; `map_public_ip_on_launch = true` only on public subnets.
    - `aws_internet_gateway` and `aws_egress_only_internet_gateway`.
    - `aws_route_table` × 2 (public → IGW for v4 + v6; private → EIGW for v6 only, no v4 default route → no NAT).
    - `aws_route_table_association` × 4.
    - `aws_default_route_table` (override empty).
  - `terraform/modules/network/outputs.tf` (`vpc_id`, `vpc_cidr_block`, `public_subnet_ids[]`, `private_subnet_ids[]`, `igw_id`, `eigw_id`).
- **Acceptance criteria:**
  - `terraform validate` clean.
  - `terraform plan` shows 4 subnets, 1 IGW, 1 EIGW, 2 route tables, 4 route-table associations.
  - Subnet `for_each` produces deterministic addresses across `terraform plan` re-runs (no order-dependent diffs).
  - `tfsec` `aws-vpc-no-public-ingress-sgr` not yet relevant (no SGs); `aws-ec2-require-vpc-flow-logs-for-all-vpcs` flagged here, **silenced with inline justification** until T-010 lands flow logs.
- **Depends on:** T-002, T-003
- **Touch points:** 4 files in `terraform/modules/network/`

### T-010 — `modules/network`: VPC Flow Logs + root wiring

- **Stage / module:** 1 / `terraform/modules/network/` + workload root
- **Deliverable:**
  - `terraform/modules/network/flow_logs.tf`:
    - `aws_iam_role "vpc_flow_logs"` with trust policy on `vpc-flow-logs.amazonaws.com`.
    - `aws_iam_role_policy "vpc_flow_logs"` granting `logs:CreateLogStream`, `logs:PutLogEvents`, `logs:DescribeLogGroups`, `logs:DescribeLogStreams` scoped to the flow-logs log-group ARN only.
    - `aws_cloudwatch_log_group "vpc_flow_logs"` (`/aws/vpc-flow-logs/<vpc-id>`, 14-day retention, encrypted with `aws/logs`).
    - `aws_flow_log "vpc"` (VPC-level, traffic type ALL, destination CW Logs, IAM role = role above).
  - Extend `outputs.tf` with `vpc_flow_logs_role_arn`.
  - `terraform/environments/pilot/main.tf`: add `module "network" { source = "../../modules/network" … }` passing the relevant variables.
- **Acceptance criteria:**
  - `terraform plan` from `terraform/environments/pilot/` shows the network module's 13+ resources rolled into the workload state.
  - `tfsec` `aws-ec2-require-vpc-flow-logs-for-all-vpcs` now passes; the inline silence comment from T-009 is removed.
  - `tflint` `terraform_unused_required_providers` and `terraform_module_pinned_source` pass.
- **Depends on:** T-009
- **Touch points:** `flow_logs.tf`, `outputs.tf`, `environments/pilot/main.tf`

---

## Stage 2 — Security & Secrets module

### T-011 — `modules/security`: Security Groups (matrix in design.md §4)

- **Stage / module:** 2 / `terraform/modules/security/`
- **Deliverable:**
  - `terraform/modules/security/versions.tf`, `variables.tf`, `outputs.tf` skeleton.
  - `terraform/modules/security/sg.tf`:
    - `aws_security_group` × 4 (`web_sg`, `db_sg`, `cache_sg`, `efs_sg`); each declares `egress = []` inline to override AWS default-allow-all (per design.md §4 note 5).
    - `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` resources implementing every row of the §4 matrix. The CloudFront prefix list is looked up via `data "aws_ec2_managed_prefix_list" "cloudfront_origin"` with `name = "com.amazonaws.global.cloudfront.origin-facing"`.
  - Extend `outputs.tf` with `web_sg_id`, `db_sg_id`, `cache_sg_id`, `efs_sg_id`.
- **Acceptance criteria:**
  - `terraform plan` shows exactly 4 SGs + the 13 rules from §4.
  - `tfsec` `aws-vpc-no-public-ingress-sgr` passes for all SGs (no `0.0.0.0/0` ingress).
  - No SG has port 22 in ingress (hard rule §6).
  - `aws_vpc_security_group_egress_rule` count for `db_sg`/`cache_sg`/`efs_sg` is zero (default deny via `egress = []`).
- **Depends on:** T-010 (needs `vpc_id`)
- **Touch points:** 4 files in `terraform/modules/security/`

### T-012 — `modules/security`: IAM (EC2 instance role + Backup role)

- **Stage / module:** 2 / `terraform/modules/security/`
- **Deliverable:**
  - `terraform/modules/security/iam.tf`:
    - `aws_iam_role "moodle_ec2"` (trust `ec2.amazonaws.com`).
    - `aws_iam_role_policy_attachment` × 2 (`AmazonSSMManagedInstanceCore`, `CloudWatchAgentServerPolicy`).
    - `aws_iam_role_policy` × 3 implementing the design.md §5 row for `moodle_ec2_role`: SecretsManager read on `arn:…:secret:moodle/*`; SES `SendEmail`/`SendRawEmail` with `ses:FromAddress` condition `*@wirfoncloud.com`; KMS Decrypt/GenerateDataKey on `aws/secretsmanager` with `kms:ViaService` condition.
    - `aws_iam_instance_profile "moodle_ec2"` referencing the role.
    - `aws_iam_role "aws_backup"` with both `AWSBackupServiceRolePolicyForBackup` and `…ForRestores` attachments.
  - Extend `outputs.tf` with `ec2_instance_profile_name`, `backup_role_arn`.
- **Acceptance criteria:**
  - `terraform plan` shows the two roles, the instance profile, two managed-policy attachments, three inline policies for EC2 role.
  - No statement in any inline policy contains `Action = "*"` or `Resource = "*"` simultaneously.
  - `tfsec` `aws-iam-no-policy-wildcards` reviewed; any wildcard has an inline justification.
- **Depends on:** T-011
- **Touch points:** 2 files (`iam.tf`, `outputs.tf`)

### T-013 — `modules/security`: Secrets Manager + root wiring

- **Stage / module:** 2 / `terraform/modules/security/` + workload root
- **Deliverable:**
  - `terraform/modules/security/secrets.tf`:
    - `random_password "db_master"` (length 32, special chars excluded that PG dislikes — `"@\"/"`).
    - `random_password "moodle_admin"` (length 24).
    - `aws_secretsmanager_secret "db_master"` (name `moodle/db/master`, encrypted with `aws/secretsmanager`).
    - `aws_secretsmanager_secret "moodle_admin"` (name `moodle/admin`).
    - Two `aws_secretsmanager_secret_version` resources writing JSON payloads (`{"username":..., "password":...}`).
  - Extend `outputs.tf` with `db_secret_arn`, `admin_secret_arn`, `db_master_password` (sensitive).
  - `terraform/environments/pilot/main.tf`: add `module "security" { source = "../../modules/security" … }` wired to network outputs.
- **Acceptance criteria:**
  - `terraform plan` shows 2 random_passwords, 2 secrets, 2 secret_versions.
  - All `terraform output` items containing passwords marked `sensitive = true`.
  - `tfsec` `aws-secretsmanager-use-customer-key` flagged but accepted (no CMK in P1 — inline justification cites design.md hard-rule #3).
- **Depends on:** T-012
- **Touch points:** `secrets.tf`, `outputs.tf`, `environments/pilot/main.tf`

---

## Stage 3 — Data layer (RDS)

### T-014 — `modules/data`: RDS subnet group + parameter group + instance + root wiring

- **Stage / module:** 3 / `terraform/modules/data/` + workload root
- **Deliverable:**
  - `terraform/modules/data/versions.tf`, `variables.tf`, `outputs.tf`.
  - `terraform/modules/data/main.tf`:
    - `aws_db_subnet_group "rds"` across both private subnet IDs.
    - `aws_db_parameter_group "rds"` with `family = "postgres15"` and parameters: `rds.force_ssl = "1"`, `log_statement = "ddl"`, `log_min_duration_statement = "5000"`.
    - `aws_db_instance "rds"` (`db.t4g.small`, engine `postgres` `var.db_engine_version`, `multi_az = false`, `storage_type = "gp3"`, `allocated_storage`, `max_allocated_storage`, `storage_encrypted = true` (`aws/rds`), `backup_retention_period`, `backup_window = "01:00-02:00"`, `maintenance_window = "sun:02:30-sun:03:30"`, `deletion_protection = true`, `performance_insights_enabled = true`, `auto_minor_version_upgrade = true`, `copy_tags_to_snapshot = true`, `username = var.db_master_username`, `password = var.db_master_password`, `lifecycle { prevent_destroy = true }`).
  - Outputs: `db_endpoint`, `db_port`, `db_id`, `db_arn`, `db_resource_id`.
  - Add `module "data" { … }` to workload root, reading password from `module.security.db_master_password`.
- **Acceptance criteria:**
  - `terraform plan` shows the subnet group, parameter group, and one DB instance.
  - `tfsec` rules `aws-rds-encrypt-instance-storage-data` (passes), `aws-rds-no-public-db-access` (passes), `aws-rds-enable-performance-insights-encryption` (reviewed; default uses `aws/rds`).
  - `checkov` `CKV_AWS_16` (encryption), `CKV_AWS_157` (multi-AZ — **skipped** with inline `# checkov:skip=CKV_AWS_157` citing hard-rule #2), `CKV_AWS_118` (deletion protection) pass.
- **Depends on:** T-013 (needs subnet IDs and SG and password)
- **Touch points:** 4 module files + 1 root edit

---

## Stage 4 — Cache layer (ElastiCache Valkey)

### T-015 — `modules/cache`: Valkey replication group + root wiring

- **Stage / module:** 4 / `terraform/modules/cache/` + workload root
- **Deliverable:**
  - `terraform/modules/cache/versions.tf`, `variables.tf`, `outputs.tf`.
  - `terraform/modules/cache/main.tf`:
    - `aws_elasticache_subnet_group "cache"` across both private subnets.
    - `aws_elasticache_parameter_group "cache"` with appropriate Valkey 7.x family.
    - `aws_elasticache_replication_group "cache"` (`engine = "valkey"`, `engine_version = var.cache_engine_version`, `num_node_groups = 1`, `replicas_per_node_group = 0`, `automatic_failover_enabled = false`, `multi_az_enabled = false`, `at_rest_encryption_enabled = true`, `transit_encryption_enabled = true`, `transit_encryption_mode = "required"`, `auth_token = random_password.valkey_auth.result`, `node_type = var.cache_node_type`).
    - `random_password "valkey_auth"` (length 64, `override_special = "!&#$^<>-"`).
  - Outputs: `cache_endpoint` (primary), `cache_port`, `cache_cluster_id`, `cache_auth_token` (sensitive).
  - Add `module "cache" { … }` to workload root.
- **Acceptance criteria:**
  - `terraform plan` shows 1 subnet group, 1 parameter group, 1 replication group.
  - `tfsec` `aws-elasticache-enable-at-rest-encryption`, `aws-elasticache-enable-in-transit-encryption`, `aws-elasticache-add-description-for-security-group` pass.
  - `transit_encryption_mode = "required"` confirmed in plan.
  - `aws_elasticache_parameter_group` `family` is `"valkey7"` (no dot, no patch version — matches `engine_version = "7.2"` as required by the AWS API). `terraform apply` must succeed first time without `InvalidParameterCombinationException`.
- **Depends on:** T-013
- **Touch points:** 4 module files + 1 root edit

---

## Stage 5 — Storage layer (EFS)

### T-016 — `modules/storage`: EFS file system + mount target + policy

- **Stage / module:** 5 / `terraform/modules/storage/`
- **Deliverable:**
  - `terraform/modules/storage/versions.tf`, `variables.tf`, `outputs.tf`.
  - `terraform/modules/storage/efs.tf`:
    - `aws_efs_file_system "moodledata"` (`throughput_mode = "bursting"`, `encrypted = true` (`aws/elasticfilesystem`), `lifecycle_policy { transition_to_ia = "AFTER_30_DAYS" }`, tags include `BackupPolicy = "daily-7d"`, `lifecycle { prevent_destroy = true }`).
    - `aws_efs_mount_target "az_a"` × 1 in the active-AZ private subnet.
    - `aws_efs_file_system_policy "moodledata"` enforcing `aws:SecureTransport = true` for all `elasticfilesystem:Client*` actions.
  - Outputs: `efs_id`, `efs_arn`, `efs_dns_name`.
- **Acceptance criteria:**
  - `terraform plan` shows 1 file system, 1 mount target (not 2 — single-AZ design), 1 policy.
  - `tfsec` `aws-efs-enable-at-rest-encryption` passes.
  - `checkov` `CKV_AWS_184` (KMS CMK encryption) skipped with inline justification (no CMK in P1).
- **Depends on:** T-013 (needs `efs_sg_id` and active-AZ private subnet)
- **Touch points:** 4 files in module

### T-017 — `modules/storage`: AWS Backup vault + plan + selection + root wiring

- **Stage / module:** 5 / `terraform/modules/storage/` + workload root
- **Deliverable:**
  - `terraform/modules/storage/backup.tf`:
    - `aws_backup_vault "moodle"` (uses `aws/backup` AWS-managed key — **no CMK** per design.md §10 row 3).
    - `aws_backup_plan "moodle"` with one rule: schedule `cron(0 2 ? * * *)` UTC, lifecycle `delete_after = var.efs_backup_retention_days`, target vault.
    - `aws_backup_selection "moodle_efs"` with `iam_role_arn = var.backup_role_arn`, selection by tag `BackupPolicy = "daily-7d"`.
  - Add `module "storage" { … }` to workload root.
- **Acceptance criteria:**
  - `terraform plan` shows 1 vault, 1 plan, 1 selection. Selection's `iam_role_arn` resolves to the `aws_backup` role from `modules/security`.
  - `tfsec` `aws-backup-vault-encryption` passes (default key acceptable per design rule).
- **Depends on:** T-016, T-013 (`backup_role_arn`)
- **Touch points:** `backup.tf`, `environments/pilot/main.tf`

---

## Stage 6 — Compute (EC2)

### T-018 — `modules/compute`: AMI lookup + EC2 + EIP + user-data template

- **Stage / module:** 6 / `terraform/modules/compute/`
- **Deliverable:**
  - `terraform/modules/compute/versions.tf`, `variables.tf`, `outputs.tf`.
  - `terraform/modules/compute/main.tf`:
    - `data "aws_ami" "ubuntu"` (`owners = ["099720109477"]`, `filter { name = "name", values = ["ubuntu/images/hvm-ssd*/ubuntu-jammy-22.04-arm64-server-*"] }`, `most_recent = true`).
    - `aws_instance "moodle"` (`t4g.small`, `ami = data.aws_ami.ubuntu.id`, root EBS gp3 30 GB encrypted with `aws/ebs`, `metadata_options { http_tokens = "required", http_put_response_hop_limit = 1 }`, `iam_instance_profile`, `vpc_security_group_ids = [var.web_sg_id]`, `subnet_id = var.public_subnet_id`, `user_data_replace_on_change = true`).
    - `aws_eip "moodle"` (vpc) + `aws_eip_association`.
  - `terraform/modules/compute/templates/user_data.sh.tftpl`: bash that:
    1. `apt-get update`, `apt-get install -y` Apache, PHP 8.1, php-pgsql, php-redis, php-xml, php-curl, php-zip, php-gd, php-intl, php-mbstring, postgresql-client, redis-tools, fail2ban, unattended-upgrades, awscli, amazon-cloudwatch-agent.
    2. Mounts EFS `${efs_id}.efs.${aws_region}.amazonaws.com:/` at `/var/moodledata` with `tls,iam` options (NFS-over-TLS).
    3. `aws secretsmanager get-secret-value` for the DB master and Moodle admin secrets; renders `/etc/moodle/config.php` with PG/Valkey endpoints, `$CFG->wwwroot = "https://${domain_name}"`, `$CFG->cookiesecure = true`, `$CFG->sslproxy = true` (because TLS terminates at CloudFront).
    4. Downloads Moodle 4.3 LTS from official source, runs CLI installer with `moodle_admin_email`.
    5. Loads CW Agent config from SSM parameter `/moodle/cloudwatch-agent/config` (created in T-023) and starts the agent.
- **Acceptance criteria:**
  - `terraform plan` shows 1 instance, 1 EIP, 1 association. Instance has IMDSv2 required, gp3 encrypted root, and the user-data hash is a function of all referenced inputs.
  - `tfsec` `aws-ec2-no-public-ip` reviewed and explicitly skipped (hard-rule #1: EC2 in public subnet); `aws-ec2-enforce-http-token-imds` passes; `aws-ec2-enable-at-rest-encryption` passes.
  - First line of user-data after the shebang is: `exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1`.
  - Second line of user-data is: `set -euxo pipefail`.
  - Final action of user-data writes `/var/log/user-data.success` on full completion (used by a CloudWatch alarm or manual `stat` check via SSM Session Manager after first boot).
  - Apache VirtualHost block in the rendered template includes `ServerName academy.wirfoncloud.com` and `UseCanonicalName On` (verified in `user_data.sh.tftpl` directly, or via SSM Session Manager post-boot).
- **Depends on:** T-013 (sg, instance profile), T-014 (db endpoint), T-015 (cache endpoint), T-017 (efs id)
- **Touch points:** 4 module files + 1 template file

### T-019 — `modules/compute`: Auto Recovery alarm + root wiring

- **Stage / module:** 6 / `terraform/modules/compute/` + workload root
- **Deliverable:**
  - `terraform/modules/compute/alarms.tf`: `aws_cloudwatch_metric_alarm "ec2_status_check"` on `StatusCheckFailed_System` with `recover` action ARN (`arn:aws:automate:${region}:ec2:recover`).
  - Add `module "compute" { … }` to workload root.
- **Acceptance criteria:**
  - `terraform plan` adds 1 alarm with recover action.
  - Module outputs `instance_id`, `instance_arn`, `eip_public_ip`, `eip_public_dns` resolve in the workload.
- **Depends on:** T-018
- **Touch points:** `alarms.tf`, `environments/pilot/main.tf`

---

## Stage 7 — DNS & CDN

### T-020 — `modules/dns_cdn`: CloudFront distribution + Route 53 alias records

- **Stage / module:** 7 / `terraform/modules/dns_cdn/`
- **Deliverable:**
  - `terraform/modules/dns_cdn/versions.tf` declares the module's required `aws.us_east_1` provider configuration alias (consumed from the workload root).
  - `terraform/modules/dns_cdn/variables.tf`, `outputs.tf`.
  - `terraform/modules/dns_cdn/cloudfront.tf`:
    - `data "aws_route53_zone" "main" { name = "wirfoncloud.com." }`.
    - `data "aws_acm_certificate" "cloudfront" { provider = aws.us_east_1, domain = var.domain_name, statuses = ["ISSUED"], most_recent = true }`.
    - `aws_cloudfront_distribution "moodle"` per design.md §2.7: custom origin = `var.origin_domain_name`, origin protocol HTTPS-only, default behavior `Managed-CachingDisabled` + `Managed-AllViewer`, ordered cache behaviors for `/theme/*`, `/pluginfile.php/*`, `/lib/*`, `*.css`, `*.js` using `Managed-CachingOptimized`, viewer cert TLSv1.2_2021 SNI-only, aliases `[var.domain_name]`, no logging block.
    - `aws_route53_record "a"` and `aws_route53_record "aaaa"` alias records to the CloudFront distribution.
  - Outputs: `cloudfront_distribution_id`, `cloudfront_distribution_arn`, `cloudfront_domain_name`.
- **Acceptance criteria:**
  - `terraform plan` shows 1 distribution + 2 Route 53 records.
  - `tfsec` `aws-cloudfront-enable-waf` flagged and skipped with inline comment (WAF is Phase 2); `aws-cloudfront-use-secure-tls-policy` passes (`TLSv1.2_2021`).
  - Default cache behavior's `origin_request_policy_id` resolves to the AWS-managed `Managed-AllViewer` policy (must **not** be `Managed-AllViewerExceptHostHeader`) — forwards `Host`, all query strings, and all cookies to the dynamic Moodle origin, enabling correct wwwroot link generation via Apache `UseCanonicalName On`.
- **Depends on:** T-019 (origin DNS), T-006 (cert exists)
- **Touch points:** 4 files in module

### T-021 — `modules/dns_cdn`: SES domain identity + DKIM + SPF + DMARC + verification + root wiring

- **Stage / module:** 7 / `terraform/modules/dns_cdn/` + workload root
- **Deliverable:**
  - `terraform/modules/dns_cdn/ses.tf`:
    - `aws_ses_domain_identity "main"` for `wirfoncloud.com`.
    - `aws_ses_domain_dkim "main"`.
    - `aws_route53_record "ses_dkim"` × 3 with `for_each` over `aws_ses_domain_dkim.main.dkim_tokens` writing CNAMEs.
    - `aws_route53_record "spf"` TXT (`"v=spf1 include:amazonses.com -all"`) on apex.
    - `aws_route53_record "dmarc"` TXT (`"v=DMARC1; p=quarantine; rua=mailto:${var.dmarc_rua_address}"`) on `_dmarc.wirfoncloud.com`.
    - `aws_ses_domain_identity_verification "main"` waits for SES to confirm.
  - Extend `outputs.tf` with `ses_domain_identity_arn`.
  - Add `module "dns_cdn" { source = "../../modules/dns_cdn", providers = { aws.us_east_1 = aws.us_east_1 }, … }` to workload root.
- **Acceptance criteria:**
  - `terraform plan` shows the SES identity, DKIM, 3 DKIM CNAMEs, 1 SPF TXT, 1 DMARC TXT, 1 verification.
  - After apply, `aws ses get-identity-verification-attributes --identities wirfoncloud.com` returns `Success`.
- **Depends on:** T-020
- **Touch points:** `ses.tf`, `outputs.tf`, `environments/pilot/main.tf`

---

## Stage 8 — Observability

### T-022 — `modules/observability`: CloudWatch Log Groups + SSM parameter

- **Stage / module:** 8 / `terraform/modules/observability/`
- **Deliverable:**
  - `terraform/modules/observability/versions.tf`, `variables.tf`, `outputs.tf`.
  - `terraform/modules/observability/logs.tf`:
    - `aws_cloudwatch_log_group` × 4: `/moodle/app`, `/moodle/web`, `/moodle/system`, `/aws/canary/moodle`. All `retention_in_days = var.log_retention_days`, encrypted with `aws/logs`.
    - `aws_ssm_parameter "cloudwatch_agent_config"` (name `/moodle/cloudwatch-agent/config`, type `String`, value = templated JSON for CW Agent: collect memory, disk, CPU credits, push to the four log groups).
- **Acceptance criteria:**
  - `terraform plan` shows 4 LG + 1 SSM parameter.
  - SSM parameter value is non-empty and parses as JSON (`jq` validation in PR description).
- **Depends on:** T-019 (instance for context; LG names are static, but we wire it into the workload root in T-026)
- **Touch points:** 4 files

### T-023 — `modules/observability`: SNS topic + 10 alarms

- **Stage / module:** 8 / `terraform/modules/observability/`
- **Deliverable:**
  - `terraform/modules/observability/sns.tf`: `aws_sns_topic "alarms"` (KMS = `aws/sns`), `aws_sns_topic_subscription "email"` (protocol `email`, endpoint `var.alarm_email`).
  - `terraform/modules/observability/alarms.tf`: the 10 alarms enumerated in design.md §2.8 / requirements §8.3 — EC2 CPU > 80%, EC2 CPU credits < 20%, EC2 status check failed (separate from Auto Recovery — alerts the operator), disk > 85% (CW Agent metric), RDS connections > 80% of max, RDS storage > 85%, RDS CPU > 80%, ElastiCache evictions > 0, Synthetics canary failed, ACM cert expiry < 30 days. All publish to the SNS topic.
- **Acceptance criteria:**
  - `terraform plan` shows 1 topic + 1 subscription + 10 alarms.
  - Each alarm has an `alarm_actions = [aws_sns_topic.alarms.arn]` line.
- **Depends on:** T-022
- **Touch points:** 2 files

### T-024 — `modules/observability`: Synthetics canary

- **Stage / module:** 8 / `terraform/modules/observability/`
- **Deliverable:**
  - `terraform/modules/observability/synthetics.tf`:
    - `aws_iam_role "canary"` with the trust + inline policy from design.md §5.
    - `aws_s3_bucket "canary_artifacts"` (versioning on, public-access-block, encryption, 30-day lifecycle expiration).
    - `aws_synthetics_canary "moodle_login"` (Node.js runtime version pinned, schedule rate `rate(5 minutes)`, handler hits `https://${var.domain_name}/login/index.php` and asserts HTTP 200, `start_canary = var.enable_synthetics_canary`).
  - Inline canary script in `terraform/modules/observability/canary/`.
- **Acceptance criteria:**
  - `terraform plan` shows 1 IAM role, 1 S3 bucket, 1 canary.
  - When `var.enable_synthetics_canary = false`, the canary's `start_canary` is `false` (verified in plan).
- **Depends on:** T-022, T-021 (target URL must resolve before first canary run, but creation order alone is fine)
- **Touch points:** 2-3 files

### T-025 — `modules/observability`: GuardDuty (account-wide) + root wiring

- **Stage / module:** 8 / `terraform/modules/observability/` + workload root
- **Deliverable:**
  - `terraform/modules/observability/guardduty.tf`:
    - `data "aws_regions" "available"` filtered to `opt_in_status` ∈ `{"opted-in", "opt-in-not-required"}`.
    - One provider alias per region declared in the workload root's `versions.tf` (see touch points).
    - `aws_guardduty_detector` created via `for_each` over the regions; each detector uses default settings; `count`/`for_each = var.enable_guardduty ? toset(...) : toset([])` to honour the flag.
  - `terraform/environments/pilot/versions.tf` extended with one aliased AWS provider per opted-in region. (This is an unavoidable one-time burst of provider declarations because Terraform requires static provider blocks.)
  - Add `module "observability" { … }` to workload root, wiring inputs from compute/data/cache/storage/dns_cdn.
- **Acceptance criteria:**
  - `terraform plan` shows one detector per opted-in region (typically ~17 for default eu-west-1 accounts).
  - Setting `enable_guardduty = false` reduces the count to zero in plan.
- **Depends on:** T-024
- **Touch points:** `guardduty.tf`, `environments/pilot/versions.tf`, `environments/pilot/main.tf`

---

## Stage 9 — CI/CD

### T-026 — Linting and policy configs

- **Stage / module:** 9 / repo root + `.github/`
- **Deliverable:**
  - Refine `.tflint.hcl` with `terraform_required_providers`, `terraform_unused_required_providers`, `terraform_module_pinned_source` rules + AWS plugin rule set.
  - `tfsec.yml` at repo root listing intentionally suppressed rules (each with a `# reason: …` comment): cross-region replication on state bucket, no CMK on RDS/EFS/Backup, public IP on EC2.
  - `.checkov.yaml` at repo root with the matching skip-list and `--soft-fail false` policy.
- **Acceptance criteria:**
  - All three configs validated by running each tool locally and producing the expected zero-failure outcome on the existing modules.
  - PR comment lists each suppressed rule with its design.md justification.
- **Depends on:** T-009 (something for tflint to lint)
- **Touch points:** `.tflint.hcl`, `tfsec.yml`, `.checkov.yaml`

### T-027 — `.github/workflows/terraform-plan.yml`

- **Stage / module:** 9 / `.github/workflows/`
- **Deliverable:** the workflow described in design.md §7.1, including OIDC `configure-aws-credentials@v4`, all 5 quality gates, `terraform plan -out=tfplan`, and PR-comment posting via `actions/github-script` or `marocchino/sticky-pull-request-comment`.
- **Acceptance criteria:**
  - First PR opened against `main` after this workflow exists triggers it; all 5 gates run and pass on the `main`-branch state.
  - Plan comment appears on the PR.
- **Depends on:** T-026, T-008 (deploy role must exist)
- **Touch points:** 1 workflow file

### T-028 — `.github/workflows/terraform-apply.yml`

- **Stage / module:** 9 / `.github/workflows/`
- **Deliverable:** the workflow described in design.md §7.2, with `environment: production`, `concurrency: group: terraform-apply-pilot`, OIDC, identical quality gates, then `terraform apply tfplan`.
- **Acceptance criteria:**
  - GitHub `production` Environment exists from T-008; required-reviewer rule is honoured (manual click required).
  - Push to `main` triggers a workflow that **pauses** at the environment gate; on operator approval, apply runs.
- **Depends on:** T-027
- **Touch points:** 1 workflow file

---

## Stage 10 — Validation

### T-029 — First operator-driven workload apply

- **Stage / module:** 10 / operator action
- **Deliverable:**
  - Operator runs `terraform -chdir=terraform/environments/pilot init && plan && apply` locally under SSO credentials. Required tfvars supplied: `alarm_email`, `moodle_admin_email`.
  - First apply takes ~30–60 minutes (CloudFront propagation, EC2 first-boot user-data ~10 min).
  - Operator records duration, any drift, and unexpected manual steps into `docs/runbooks/first-deploy.md` (created in T-033).
- **Acceptance criteria:**
  - `terraform output` populates non-empty values for `cloudfront_domain_name`, `db_endpoint`, `efs_id`, `instance_id`.
  - `aws ssm start-session --target <instance-id>` succeeds (Session Manager works, validating SSM agent + IAM instance profile).
  - SNS subscription email arrives and is confirmed.
- **Depends on:** T-028 (workflow exists for follow-on changes), T-025 (last module wired)
- **Touch points:** none in code; updates `docs/runbooks/first-deploy.md`

### T-030 — End-to-end smoke test

- **Stage / module:** 10 / operator action
- **Deliverable:**
  - `curl -I https://academy.wirfoncloud.com/login/index.php` returns HTTP 200.
  - `dig academy.wirfoncloud.com` resolves to a CloudFront edge.
  - `dig _dmarc.wirfoncloud.com TXT` returns the DMARC record.
  - Synthetics canary in CloudWatch console shows green for 3 consecutive runs (15 min observation).
  - GuardDuty home-region detector enabled; no findings within first hour.
  - Login page renders; admin user (from `moodle_admin_email`) can sign in using the Secrets-Manager-stored initial password.
  - Operator changes the admin password via Moodle UI, enables Moodle MFA, adds a second admin.
- **Acceptance criteria:**
  - All checks above pass; results captured in a short PR-style report appended to `docs/runbooks/first-deploy.md`.
- **Depends on:** T-029
- **Touch points:** documentation only

### T-031 — Restore-drill rehearsal

- **Stage / module:** 10 / operator action
- **Deliverable:**
  - Operator triggers an out-of-band RDS snapshot, then restores it as `moodle-pg-restore-test` (different identifier — does not overwrite prod).
  - Operator triggers an out-of-band AWS Backup recovery job for EFS into a new file system.
  - Operator times both procedures, confirms the restored DB is queryable and the restored EFS mounts.
  - Operator deletes both restore artifacts (snapshot copy + restored EFS) to avoid cost drift.
- **Acceptance criteria:**
  - Restore times documented; both artefacts confirmed deleted.
  - `docs/runbooks/restore-drill.md` (created in T-033) updated with measured RTO and any deviation from the documented procedure.
- **Depends on:** T-029
- **Touch points:** documentation only

### T-035 — Remove scaffold lint suppression

- **Stage / module:** 10 / cross-cutting
- **Deliverable:** Delete `terraform/environments/pilot/.tflint.hcl` (scaffold lint suppression introduced in T-002).
- **Acceptance criteria:**
  - File no longer exists.
  - `tflint --recursive terraform/environments/pilot` reports zero warnings WITHOUT the suppression — meaning every variable and the `us_east_1` provider alias is genuinely consumed.
- **Depends on:** T-009 through T-026 (all module-wiring tasks).
- **Touch points:** delete 1 file.

---

## Cross-cutting

### T-032 — README polish

- **Stage / module:** cross-cutting / repo root
- **Deliverable:** update `README.md` to:
  - Remove the stray "Add a line to README.md" instruction left over from scaffolding.
  - Add a Status section reflecting that Phase 1 is built and validated.
  - Link to each runbook produced in T-033.
  - Add a 1-line "How to deploy a change" section: open PR → CI plan → review → merge to main → approve `production` environment → CI applies.
- **Acceptance criteria:** rendered README on GitHub displays correctly; all internal links resolve.
- **Depends on:** T-030 (the smoke test, so the README can claim it works)
- **Touch points:** `README.md`

### T-033 — Operator runbooks

- **Stage / module:** cross-cutting / `docs/runbooks/`
- **Deliverable:** four runbooks as separate files:
  - `docs/runbooks/bootstrap.md` — how to re-run bootstrap (rare; account migration).
  - `docs/runbooks/ses.md` — how to request SES production access; how to verify pilot recipient addresses while sandboxed.
  - `docs/runbooks/first-deploy.md` — the full operator sequence for the first workload apply (acts as the populated runbook updated in T-029, T-030, T-031).
  - `docs/runbooks/restore-drill.md` — quarterly RDS + EFS restore procedure with documented pass/fail criteria.
- **Acceptance criteria:** each runbook is one short page (≤ 200 lines), action-oriented, with copy-pasteable commands. No prose padding.
- **Depends on:** T-008 (knowledge of bootstrap), T-029, T-030, T-031.
- **Touch points:** 4 files

### T-034 — Banjika first-run validation checklist

- **Stage / module:** cross-cutting / `docs/`
- **Deliverable:** `docs/first-run-checklist.md` — single-page checklist for the operator covering the manual prerequisites and the order of `terraform apply` runs:
  - [ ] Verify Route 53 hosted zone (T-008 step 2)
  - [ ] AWS Budgets billing alarm at 120% (T-008 step 1)
  - [ ] SES sandbox: verified recipient email addresses
  - [ ] Tfvars file populated: `alarm_email`, `moodle_admin_email`
  - [ ] `terraform/bootstrap` applied; outputs captured
  - [ ] `AWS_DEPLOY_ROLE_ARN` repo variable set; `production` GitHub Environment created
  - [ ] `terraform/environments/pilot` applied; smoke tests pass
  - [ ] Initial Moodle admin password rotated; MFA enabled
  - [ ] Restore drill completed; results in `docs/runbooks/restore-drill.md`
  - [ ] SES production-access support case opened (before go-live)
- **Acceptance criteria:** checklist printable on one page; every checkbox traces to a specific T-NNN or runbook section.
- **Depends on:** T-033
- **Touch points:** 1 file

---

## Task index

| ID | Title | Stage | Depends on |
|---|---|---|---|
| T-001 | Repo skeleton | 0 | — |
| T-002 | Workload root scaffold | 0 | T-001 |
| T-003 | Bootstrap skeleton | 0 | T-001 |
| T-004 | Bootstrap state bucket + DynamoDB lock | 0 | T-003 |
| T-005 | Bootstrap GitHub OIDC + deploy role | 0 | T-004 |
| T-006 | Bootstrap ACM (us-east-1) | 0 | T-003 |
| T-007 | Bootstrap CloudTrail | 0 | T-003 |
| T-008 | Bootstrap apply + GitHub wiring + Budgets | 0 | T-004…T-007 |
| T-009 | Network module: VPC, subnets, gateways, routes | 1 | T-002, T-003 |
| T-010 | Network module: Flow Logs + root wiring | 1 | T-009 |
| T-011 | Security: SGs | 2 | T-010 |
| T-012 | Security: IAM (EC2 + Backup roles) | 2 | T-011 |
| T-013 | Security: Secrets Manager + root wiring | 2 | T-012 |
| T-014 | Data: RDS subnet/parameter/instance + root wiring | 3 | T-013 |
| T-015 | Cache: Valkey + root wiring | 4 | T-013 |
| T-016 | Storage: EFS + mount + policy | 5 | T-013 |
| T-017 | Storage: AWS Backup + root wiring | 5 | T-016 |
| T-018 | Compute: AMI + EC2 + EIP + user-data | 6 | T-013, T-014, T-015, T-017 |
| T-019 | Compute: Auto Recovery + root wiring | 6 | T-018 |
| T-020 | dns_cdn: CloudFront + Route 53 records | 7 | T-019, T-006 |
| T-021 | dns_cdn: SES + root wiring | 7 | T-020 |
| T-022 | Observability: CW Logs + SSM param | 8 | T-019 |
| T-023 | Observability: SNS + 10 alarms | 8 | T-022 |
| T-024 | Observability: Synthetics canary | 8 | T-022, T-021 |
| T-025 | Observability: GuardDuty + root wiring | 8 | T-024 |
| T-026 | Linting / policy configs | 9 | T-009 |
| T-027 | GitHub Actions plan workflow | 9 | T-026, T-008 |
| T-028 | GitHub Actions apply workflow | 9 | T-027 |
| T-029 | First operator-driven workload apply | 10 | T-028, T-025 |
| T-030 | End-to-end smoke test | 10 | T-029 |
| T-031 | Restore-drill rehearsal | 10 | T-029 |
| T-032 | README polish | cross | T-030 |
| T-033 | Operator runbooks | cross | T-029, T-030, T-031, T-008 |
| T-034 | Banjika first-run validation checklist | cross | T-033 |
| T-035 | Remove scaffold lint suppression | 10 | T-009…T-026 |

**Total:** 35 tasks. Critical path runs `T-001 → T-002 → T-003 → T-004 → T-005 → T-008 → T-010 → T-013 → T-018 → T-019 → T-020 → T-021 → T-025 → T-029 → T-030`, ≈ 15 sequential PRs.

---

**End of tasks. No Terraform code is written until the user explicitly says "approved" or "implement T-001."**
