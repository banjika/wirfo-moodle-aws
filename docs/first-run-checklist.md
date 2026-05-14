# Phase 1 First-Run Checklist

**Purpose:** Single-page operator checklist for the first workload apply. Every item points to the task or runbook that establishes it.

**Print this page** before starting. Tick items as you complete them.

> **Reference values in this checklist are from the current pilot deployment in account `288761747885`, repo `banjika/wirfo-moodle-aws`.** For a different account or a fork, substitute your own values.

---

## Pre-bootstrap (one-time, manual)

- [ ] AWS account ready; root MFA enabled; IAM Identity Center configured (T-008)
- [ ] Route 53 hosted zone for the deployment domain (e.g., `wirfoncloud.com`) confirmed in the target account (bootstrap.md step 1)
- [ ] AWS Budgets cost alarm at 120% of $80/month; SNS subscription confirmed (bootstrap.md step 8)
- [ ] SES sandbox limits understood (ses.md "Current sandbox limits")

## Bootstrap (T-008 / bootstrap.md)

- [ ] `terraform/bootstrap` applied; 24-26 resources created; all six outputs captured (bootstrap.md steps 3-5)
- [ ] `terraform/environments/pilot/backend.tf` wired with the target account ID (bootstrap.md step 6)
- [ ] Required GitHub repo variables set (bootstrap.md step 7):
  - [ ] `AWS_DEPLOY_ROLE_ARN`
  - [ ] `ALARM_EMAIL`
  - [ ] `MOODLE_ADMIN_EMAIL`
  - [ ] `DMARC_RUA_ADDRESS`
- [ ] `production` GitHub Environment created with a required reviewer (bootstrap.md step 7)
- [ ] `main` branch protection: PR required + `Terraform Plan / Plan` status check (bootstrap.md step 7)

## Pre-workload-apply

- [ ] `terraform/environments/pilot/terraform.tfvars` created with real values (T-029 / first-deploy.md preconditions):
  - [ ] `alarm_email`
  - [ ] `moodle_admin_email`
  - [ ] `dmarc_rua_address`
- [ ] `alarm_email` SES-verified (ses.md Part A)
- [ ] `moodle_admin_email` SES-verified (ses.md Part A)
- [ ] All pilot user emails SES-verified (ses.md Part A; sandbox limit applies)
- [ ] CI stub variables set in GitHub repo (T-027): `ALARM_EMAIL`, `MOODLE_ADMIN_EMAIL`, `DMARC_RUA_ADDRESS` can be `test@example.com` for plan-only runs

## First workload apply (T-029 / first-deploy.md)

- [ ] Pre-apply verification passed (first-deploy.md Phase 1)
- [ ] `terraform plan` reviewed - approximately 75 resources to add, 0 to change, 0 to destroy (first-deploy.md Phase 2)
- [ ] `terraform apply` complete: 76 added, 0 changed, 0 destroyed (first-deploy.md Phase 2)
- [ ] Phase 5 AWS API queries return non-empty values for: EC2 instance, CloudFront distribution, RDS endpoint, EFS file system (first-deploy.md Phase 5)
- [ ] SNS subscription email confirmed (first-deploy.md Phase 5)
- [ ] First login to `https://academy.wirfoncloud.com` succeeded (first-deploy.md Phase 5)
- [ ] Admin password rotated via Moodle UI (first-deploy.md Phase 5)
- [ ] Moodle MFA enabled for admin account (first-deploy.md Phase 5)
- [ ] Second admin account created (first-deploy.md Phase 5)

---

**GO / NO-GO - do not open to pilot users until all boxes above are ticked**

---

## Smoke test (T-030)

- [ ] `curl -I https://academy.wirfoncloud.com/login/index.php` returns HTTP/2 200 (T-030)
- [ ] Synthetics canary green for 3 consecutive runs (T-024, T-030)
- [ ] GuardDuty enabled in eu-west-1; no findings in first hour (T-025, T-030)
- [ ] DMARC TXT record resolves at `_dmarc.wirfoncloud.com` (T-021 / ses.md Part B)
- [ ] Login + new course creation works end-to-end (T-030)

## Restore drill (T-031 / restore-drill.md)

- [ ] First drill completed within ~1 week of first apply (restore-drill.md)
- [ ] RTO < 4h; RPO < 24h confirmed (restore-drill.md pass/fail criteria)
- [ ] RDS restore artifact (`moodle-pg-restore-test`) deleted post-drill (restore-drill.md Part A)
- [ ] EFS restore artifact (new FS + mount target) deleted post-drill (restore-drill.md Part B)
- [ ] Drill history table updated at the bottom of `restore-drill.md`

## Pre-go-live (before opening to non-allowlisted users)

- [ ] SES production access requested and granted (ses.md Part C; `Max24HourSend` greater than 200)
- [ ] At least 1 nightly RDS snapshot exists in AWS Backup vault (T-017)
- [ ] At least 1 day of CloudWatch metrics populated for EC2, RDS, ElastiCache (T-023)
- [ ] Moodle policy tool published: privacy policy and terms-of-service at `/admin/tool/policy/` (required by AWS for SES production access; needed regardless)

---

**Last updated:** 2026-05-14 (T-034)
**Next review:** Before Phase 1 -> Phase 2 transition (when payment gateway integration begins)