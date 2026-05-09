# First Deploy Runbook

**Purpose:** Walk through the first operator-driven workload apply for `terraform/environments/pilot`.
**When to use:**
- THE first workload apply (T-029)
- Workload state lost and recreation required (disaster recovery)

**Preconditions:**
- Bootstrap complete: `wirfo-moodle-tfstate-288761747885` exists, `wirfo-moodle-tflock` exists, deploy role ARN wired as `AWS_DEPLOY_ROLE_ARN` in GitHub (see `docs/runbooks/bootstrap.md`)
- `terraform/environments/pilot/terraform.tfvars` exists with real values for `alarm_email` and `moodle_admin_email`
- Both `alarm_email` and `moodle_admin_email` SES-verified (see `docs/runbooks/ses.md`, Part A)
- AWS Budgets billing alarm at 120% of $80/month configured (see `docs/runbooks/bootstrap.md`, step 8)
- Operator has 60–90 minutes available

**Estimated time:** 30–60 minutes apply + 15 minutes post-apply
**Last updated:** 2026-05-09

---

## Phase 1 — Pre-apply verification (~5 min)

```bash
git checkout main
git status
# Expected: nothing to commit, working tree clean

git fetch --prune && git pull

aws s3 ls s3://wirfo-moodle-tfstate-288761747885/
# Expected: lists objects (or empty on first apply — bucket must be accessible)

aws dynamodb describe-table --table-name wirfo-moodle-tflock \
  --query 'Table.TableStatus'
# Expected: "ACTIVE"
```

Confirm the `production` GitHub Environment has a required reviewer (banjika):
```
GitHub → banjika/wirfo-moodle-aws → Settings → Environments → production
```

## Phase 2 — Init and plan (local apply path)

Per `CLAUDE.md`, the operator drives the first 2–3 applies locally rather than via CI.

```bash
terraform -chdir=terraform/environments/pilot init
terraform -chdir=terraform/environments/pilot plan -out=tfplan
```

**Read the plan carefully.** Expected: ~125 resources added, 0 changed, 0 destroyed. Flag anything unexpected before applying.

```bash
terraform -chdir=terraform/environments/pilot apply tfplan
```

## Phase 3 — Watch the apply (~30–60 min)

Resources that take longest (in rough order):

| Resource | Typical duration |
|---|---|
| RDS instance creation | 5–10 min |
| EFS + mount targets | 3–5 min |
| ElastiCache replication group | 5–10 min |
| CloudFront distribution | 15–30 min |
| EC2 user-data (Moodle install) | ~10 min |

Expected terminal output: `Apply complete! Resources: N added, 0 changed, 0 destroyed.`

Monitor in AWS Console: EC2 → Instances, RDS → Databases, CloudFront → Distributions.

## Phase 4 — Alternative: trigger via CI

If using the CI apply workflow instead of local apply:

```bash
git commit --allow-empty -m "trigger first apply"
git push
```

Then:
```
GitHub → Actions → latest "Terraform Apply" run
  → Deployment protection rules → Approve and deploy
  → Comment: "First Phase 1 deploy"
```

> **Note:** Empty commits do not trigger workflows with `paths` filters. If the workflow doesn't start, push a trivial change to a path-matching file instead (e.g., add/remove a blank line in `README.md`).

## Phase 5 — Post-apply verification

```bash
terraform -chdir=terraform/environments/pilot output
# All values must be non-empty: cloudfront_domain_name, db_endpoint, efs_id, instance_id
```

Confirm SNS subscription: check `alarm_email` inbox for AWS confirmation email and click the link.

Retrieve Moodle admin password:
```bash
aws secretsmanager get-secret-value \
  --secret-id moodle/admin \
  --query SecretString \
  --output text \
  --region eu-west-1
```

Test Moodle login:
```bash
curl -I https://academy.wirfoncloud.com/login/index.php
# Expected: HTTP/2 200
```

**Immediately after first login:**
1. Log in as `moodle_admin_email` using the Secrets Manager password
2. Change the admin password via **User menu → Preferences → Change password**
3. Enable Moodle MFA: **Site administration → Plugins → Authentication → MFA**
4. Add a second admin account

Complete the restore drill per `docs/runbooks/restore-drill.md`.

---

## Common failures

**CloudFront stuck "In Progress"**
Normal — propagation takes 15–30 min. Do not cancel. Wait it out.

**RDS creation fails**
Check: parameter group compatibility with PostgreSQL 15, storage type `gp3` supported in eu-west-1.

**EC2 status checks fail**
```bash
aws ssm start-session --target <instance-id> --region eu-west-1
# In session:
sudo tail -100 /var/log/cloud-init-output.log
```
Most user-data failures are missing packages or network timeouts on first boot. Taint and re-apply if unrecoverable.

**EFS mount target fails**
Verify: private subnet exists in eu-west-1a, EFS security group allows NFS 2049 inbound from the web security group.

**State lock error**
Another apply is running or crashed.
```bash
terraform -chdir=terraform/environments/pilot force-unlock <LOCK_ID>
```
Only run this if you are certain no concurrent apply is in progress. The lock ID is in the error message.

**`terraform output` shows empty values**
Apply may have partially succeeded. Check AWS Console for the specific resource and run `terraform apply` again — it is idempotent.

---

## Post-apply log

| Item | Value | Date |
|---|---|---|
| Apply duration | | |
| `instance_id` | | |
| `cloudfront_domain_name` | | |
| `db_endpoint` | | |
| `efs_id` | | |
| SNS subscription confirmed | ☐ | |
| Admin password changed | ☐ | |
| MFA enabled | ☐ | |
| Restore drill completed | ☐ | |
| Smoke test results | See T-030 output | |
