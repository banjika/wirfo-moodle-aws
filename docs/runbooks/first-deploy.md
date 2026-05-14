# First Deploy Runbook

**Purpose:** Walk through the first operator-driven workload apply for `terraform/environments/pilot`.

**When to use:**
- THE first workload apply (T-029)
- Workload state lost and recreation required (disaster recovery)

**Preconditions:**
- Bootstrap complete: state bucket exists, lock table exists, deploy role ARN wired as `AWS_DEPLOY_ROLE_ARN` repo variable (see `bootstrap.md`)
- `terraform/environments/pilot/terraform.tfvars` exists with real values for `alarm_email`, `moodle_admin_email`, and `dmarc_rua_address`
- Both `alarm_email` and `moodle_admin_email` are SES-verified (see `ses.md`, Part A)
- AWS Budgets alarm at 120% of $80/month configured (see `bootstrap.md`, step 8)
- Operator has 60-90 minutes available

**Estimated time:** 25-35 minutes apply (measured during T-029 on 2026-05-10) + 15 minutes post-apply

**Last updated:** 2026-05-14 (T-033 review - corrected resource count, real timings from T-029, EC2 tag name, and added 4 common-failure cases discovered during T-029)

> **Reference values in this runbook are from the current pilot deployment in account `288761747885`, repo `banjika/wirfo-moodle-aws`.** For a different account or a fork, substitute your own values where appropriate.

---

## Phase 1 - Pre-apply verification (~5 min)

```bash
git checkout main
git status
# Expected: nothing to commit, working tree clean

git fetch --prune && git pull

aws s3 ls s3://wirfo-moodle-tfstate-<account-id>/
# Expected: lists objects (or empty on first apply - bucket must be accessible)

aws dynamodb describe-table --table-name wirfo-moodle-tflock \
  --query 'Table.TableStatus' --region eu-west-1
# Expected: "ACTIVE"
```

Confirm the `production` GitHub Environment has a required reviewer:

```
GitHub -> <your-org>/<your-repo> -> Settings -> Environments -> production
```

Confirm required repo variables are set:

```
Settings -> Secrets and variables -> Actions -> Variables
  AWS_DEPLOY_ROLE_ARN     = <from bootstrap output>
  ALARM_EMAIL             = <operator email>
  MOODLE_ADMIN_EMAIL      = <Moodle admin email>
  DMARC_RUA_ADDRESS       = <DMARC reports email>
```

## Phase 2 - Init and plan (local apply path)

Per `CLAUDE.md`, the operator drives the first 2-3 applies locally rather than via CI, so failures are easier to debug.

```bash
terraform -chdir=terraform/environments/pilot init
terraform -chdir=terraform/environments/pilot plan -out=tfplan
```

**Read the plan carefully.** Expected: **~75 resources** added (measured during T-029: 76 created), 0 changed, 0 destroyed. Flag anything unexpected before applying.

Apply:

```bash
terraform -chdir=terraform/environments/pilot apply tfplan
```

## Phase 3 - Watch the apply (~25-35 min)

Real timings measured during T-029 (2026-05-10):

| Resource group | Typical duration |
|---|---|
| Networking (VPC, subnets, RT, IGW, endpoints) | 1-2 min |
| Security groups + IAM roles | <1 min |
| RDS instance creation | 5-7 min |
| EFS + mount target | 2-3 min |
| ElastiCache Valkey replication group | 5-8 min |
| EC2 instance + user-data (Moodle install via cloud-init) | 8-12 min (runs in parallel with the data layer) |
| CloudFront distribution (initial deploy) | 10-20 min (the long pole) |
| Route 53 records (academy + DNSSEC + DMARC + DKIM) | <1 min once CloudFront is ready |

Expected terminal output: `Apply complete! Resources: 76 added, 0 changed, 0 destroyed.`

Monitor in AWS Console:
- EC2 -> Instances (look for the `moodle-academy-pilot-moodle` instance)
- RDS -> Databases (instance `moodle-academy-pilot-rds`)
- CloudFront -> Distributions (wait for Status: Deployed)

## Phase 4 - Alternative: trigger via CI

If using the CI apply workflow instead of local apply:

```bash
git commit --allow-empty -m "trigger first apply"
git push
```

Then:

```
GitHub -> Actions -> latest "Terraform Apply" run
  -> Deployment protection rules -> Approve and deploy
  -> Comment: "First Phase 1 deploy"
```

> **Note:** The `terraform-apply.yml` workflow triggers on push to `main`, scoped by a paths filter. Empty commits push a new commit SHA but no file changes - if the workflow does not start, push a small change to a path-matching file (e.g., a Terraform comment update).

## Phase 5 - Post-apply verification

The workload's `outputs.tf` is intentionally minimal; most operator-facing values are surfaced via direct API queries:

```bash
# EC2 instance ID (used for SSM Session Manager access):
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=moodle-academy-pilot-moodle" "Name=instance-state-name,Values=running" \
  --region eu-west-1 \
  --query "Reservations[0].Instances[0].InstanceId" --output text

# CloudFront distribution domain:
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[?contains(@,'academy.wirfoncloud.com')]].DomainName" --output text

# RDS endpoint:
aws rds describe-db-instances \
  --db-instance-identifier moodle-academy-pilot-rds \
  --region eu-west-1 \
  --query "DBInstances[0].Endpoint.Address" --output text

# EFS file system ID:
aws efs describe-file-systems \
  --query "FileSystems[?Tags[?Key=='Name' && contains(Value, 'moodle-academy-pilot')]].FileSystemId" \
  --region eu-west-1 --output text
```

All values must be non-empty.

Confirm SNS subscription: check the `alarm_email` inbox for the AWS confirmation email and click the link. The CloudWatch alarms cannot deliver to the SNS topic until this is done.

Retrieve the initial Moodle admin password:

```bash
aws secretsmanager get-secret-value \
  --secret-id moodle/admin \
  --query SecretString \
  --output text \
  --region eu-west-1
```

Test that Moodle is reachable through CloudFront:

```bash
curl -I https://academy.wirfoncloud.com/login/index.php
# Expected: HTTP/2 200
```

**Immediately after first login:**
1. Log in as `moodle_admin_email` using the Secrets Manager password
2. Change the admin password via **User menu -> Preferences -> Change password**
3. Enable Moodle MFA: **Site administration -> Plugins -> Authentication -> MFA**
4. Add a second admin account (operator's personal address) with manager role
5. Verify outbound mail by triggering a password reset to a verified address

Run the smoke test per T-030 acceptance criteria. The restore drill (T-031) should be run **after first-deploy is operationally stable** - not concurrently. Typically wait 1-2 days so the first automated RDS snapshot exists.

---

## Common failures

**CloudFront stuck "In Progress"**
Normal - propagation takes 10-20 min. Do not cancel. Wait it out.

**RDS creation fails**
Check: parameter group compatibility with PostgreSQL 15, storage type `gp3` supported in eu-west-1, KMS key ARN accessible by the RDS service principal.

**EC2 status checks fail**
SSM into the instance and inspect cloud-init logs:

```bash
aws ssm start-session --target <instance-id> --region eu-west-1
# In session:
sudo tail -100 /var/log/cloud-init-output.log
sudo journalctl -u amazon-ssm-agent --since "10 minutes ago"
```

Most user-data failures are package install timeouts on first boot or EFS mount failures (NFS port 2049 blocked by security group). Taint and re-apply if unrecoverable:

```bash
terraform -chdir=terraform/environments/pilot taint module.compute.aws_instance.moodle
terraform -chdir=terraform/environments/pilot apply
```

**EFS mount target fails**
Verify: private subnet exists in eu-west-1a, EFS security group allows NFS 2049 inbound from the EC2 (web) security group.

**State lock error**
Another apply is running or crashed.

```bash
terraform -chdir=terraform/environments/pilot force-unlock <LOCK_ID>
```

Only run this if you are certain no concurrent apply is in progress. The lock ID is in the error message.

**`terraform output` shows empty values**
Expected - this workload's `outputs.tf` is intentionally minimal. Query AWS APIs directly per Phase 5.

**Moodle redirects in a loop after first login attempt**
Discovered during T-029. Two distinct causes look identical:

1. `$CFG->reverseproxy = true` in `config.php` - Moodle's reverse-proxy guard rejects requests where the request `Host` equals the configured `wwwroot` Host. CloudFront forwards `Host` unchanged, so this condition is always true and the server returns HTTP 500 disguised as a redirect loop. Fix: ensure `$CFG->reverseproxy` is NOT set (only `$CFG->sslproxy = true` should be present). This was patched in user-data via PR #40.

2. `registrationpending = 1` in the Moodle config row of `mdl_config`. Set during initial install for hub registration; Moodle then redirects to a registration prompt indefinitely. Fix: SSM into the instance and run `mysql -e "UPDATE mdl_config SET value=0 WHERE name='registrationpending';"` - this was absorbed into user-data Step 8.5 (then merged into Step 8 in T-029.5).

**Login page returns HTTP 502 from CloudFront**
The origin (CloudFront -> ALB or directly to EC2) is not returning a valid response. Check that:

1. The EC2 instance is `running` and has passed status checks
2. The EC2 security group allows inbound 443 from the CloudFront managed prefix list (NOT from 0.0.0.0/0)
3. Cloud-init has completed: `sudo cloud-init status --wait` returns `status: done`
4. Apache is running: `sudo systemctl status apache2`

The 502 cycle during T-029 was a combination of (1) cloud-init still running and (2) the CloudFront managed prefix list IDs in the security group module being region-specific - the wrong ID in the security group manifests as 502 because no traffic gets through.

**File uploads fail in Moodle with "stale page" error**
Discovered after T-029. The default CloudFront cache behavior only forwards GET/HEAD requests. Moodle's file picker (and many other AJAX endpoints) use POST to `/lib/ajax/service.php` and similar paths. Without an explicit cache behavior for `/lib/ajax/*` allowing POST, the upload request is rejected at CloudFront. Fix: PR #44 added a CloudFront behavior for `/lib/ajax/*` with `allowed_methods = ["GET","HEAD","POST","PUT","DELETE","OPTIONS","PATCH"]`. If this PR was rolled back or a fresh apply somehow lost it, re-apply the `dns_cdn` module.

---

## Post-apply log

| Item | Value | Date |
|---|---|---|
| Apply duration | ~25 minutes | 2026-05-10 |
| Instance ID | `i-09c6712e555ec9447` | 2026-05-10 |
| CloudFront domain | `d6c9swbbz1aod.cloudfront.net` | 2026-05-10 |
| Account ID | `288761747885` | 2026-05-10 |
| Region | eu-west-1 | 2026-05-10 |
| SNS subscription confirmed | [x] | 2026-05-10 |
| Admin password rotated from Secrets Manager value | [x] | 2026-05-11 |
| Moodle MFA enabled for admin | [x] | 2026-05-11 |
| Second admin account added | [x] | 2026-05-11 |
| Smoke test (T-030) | PASS | 2026-05-11 |
| Restore drill (T-031) | PASS - RTO 57 min, RPO ~9h | 2026-05-14 |