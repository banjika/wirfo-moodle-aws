# Phase 1 First-Run Checklist

**Purpose:** Single-page operator checklist for the first workload apply. Every item points to the task or runbook that establishes it.

**Print this page** before starting. Tick items as you complete them.

---

## Pre-bootstrap (one-time, manual)

- [ ] AWS account 288761747885 root MFA enabled; IAM Identity Center configured (T-008)
- [ ] Route 53 hosted zone for `wirfoncloud.com` confirmed in account 288761747885 (bootstrap.md §1)
- [ ] AWS Budgets cost alarm at 120% of $80/month; SNS subscription confirmed (bootstrap.md §8)
- [ ] SES sandbox limits understood (ses.md "Current sandbox limits")

## Bootstrap (T-008 / bootstrap.md)

- [ ] `terraform/bootstrap` applied; ~20 resources created, all outputs captured (bootstrap.md §3–5)
- [ ] `terraform/environments/pilot/backend.tf` placeholder replaced with `288761747885` (bootstrap.md §6)
- [ ] `AWS_DEPLOY_ROLE_ARN` repo variable set in GitHub (bootstrap.md §7)
- [ ] `production` GitHub Environment created; required reviewer: banjika (bootstrap.md §7)
- [ ] `main` branch protection: PR required + `terraform-plan` status check (bootstrap.md §7)

## Pre-workload-apply

- [ ] `terraform/environments/pilot/terraform.tfvars` created with real values (T-029 / first-deploy.md Preconditions):
  - [ ] `alarm_email`
  - [ ] `moodle_admin_email`
  - [ ] `dmarc_rua_address`
- [ ] `alarm_email` SES-verified (ses.md Part A)
- [ ] `moodle_admin_email` SES-verified (ses.md Part A)
- [ ] All pilot user emails SES-verified (ses.md Part A; sandbox limit applies)
- [ ] CI stub variables set in GitHub repo: `ALARM_EMAIL`, `MOODLE_ADMIN_EMAIL`, `DMARC_RUA_ADDRESS` = `test@example.com` (T-027)

## First workload apply (T-029 / first-deploy.md)

- [ ] Pre-apply verification passed (first-deploy.md Phase 1)
- [ ] `terraform plan` reviewed — ~125 resources to add, 0 to change, 0 to destroy (first-deploy.md Phase 2)
- [ ] `terraform apply` complete: N added, 0 changed, 0 destroyed (first-deploy.md Phase 2)
- [ ] `terraform output` non-empty: `cloudfront_domain_name`, `db_endpoint`, `efs_id`, `instance_id` (first-deploy.md Phase 5)
- [ ] SNS subscription email confirmed (first-deploy.md Phase 5)
- [ ] First login to `https://academy.wirfoncloud.com` succeeded (first-deploy.md Phase 5)
- [ ] Admin password rotated via Moodle UI (first-deploy.md Phase 5)
- [ ] Moodle MFA enabled for admin account (first-deploy.md Phase 5)
- [ ] Second admin account created (first-deploy.md Phase 5)

---
**GO / NO-GO — do not open to pilot users until all boxes above are ticked**
---

## Smoke test (T-030 / runbooks/smoke-test.md when written)

- [ ] `curl -I https://academy.wirfoncloud.com/login/index.php` → HTTP/2 200 (T-030)
- [ ] Synthetics canary green for 3 consecutive runs (T-024, T-030)
- [ ] GuardDuty enabled in eu-west-1; no findings in first hour (T-025, T-030)
- [ ] DMARC TXT record resolves (T-021 / ses.md Part B)
- [ ] Login + new course creation works end-to-end (T-030)

## Restore drill (T-031 / restore-drill.md)

- [ ] First drill completed within 1 week of first apply (restore-drill.md)
- [ ] RTO < 4h; RPO < 24h confirmed (restore-drill.md pass/fail criteria)
- [ ] RDS restore artifact (`moodle-pg-restore-test`) deleted (restore-drill.md Part A §A5)
- [ ] EFS restore artifact deleted (restore-drill.md Part B §B6)
- [ ] Drill history table updated in `restore-drill.md`

## Pre-go-live (before opening to non-allowlisted users)

- [ ] SES production access requested (ses.md Part C)
- [ ] At least 1 nightly RDS snapshot exists in AWS Backup (T-017)
- [ ] At least 1 day of CloudWatch metrics populated for EC2, RDS, ElastiCache (T-023)

---

**Last updated:** 2026-05-09  
**Next review:** Before Phase 1 → Phase 2 transition
