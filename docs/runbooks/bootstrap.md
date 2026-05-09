# Bootstrap Runbook

**Purpose:** Re-run `terraform/bootstrap` to recreate the state backend, OIDC trust, deploy role, ACM cert, and CloudTrail after loss or account migration.
**When to use:**
- State bucket accidentally deleted (`prevent_destroy` should prevent this — treat as catastrophic)
- AWS account migration (new account, same workload pattern)
- Initial setup of a new environment mirroring pilot

**Preconditions:**
- AWS CLI configured with SSO credentials for account 288761747885
- Active SSO session: `aws sso login`
- Route 53 hosted zone for `wirfoncloud.com` confirmed in target account
- Terraform >= 1.7 installed locally

**Estimated time:** 15–20 minutes
**Last updated:** 2026-05-09

---

## Steps

### 1. Verify Route 53 hosted zone

```bash
aws route53 list-hosted-zones --query "HostedZones[?Name=='wirfoncloud.com.']"
```

Expected: exactly one zone. If missing, create it and update registrar NS records before continuing — both `terraform/bootstrap` (ACM DNS validation) and `modules/dns_cdn` use this zone via data source with no fallback.

### 2. Init

```bash
terraform -chdir=terraform/bootstrap init
```

### 3. Plan

```bash
terraform -chdir=terraform/bootstrap plan -out=tfplan
```

Read the plan. Expected new resources (~20):
- S3 bucket `wirfo-moodle-tfstate-288761747885` + 5 sub-resources
- DynamoDB table `wirfo-moodle-tflock`
- IAM OIDC provider + deploy role + inline policy
- ACM certificate (us-east-1) + N Route 53 DNS validation records + certificate validation
- S3 bucket `wirfo-moodle-cloudtrail-288761747885` + sub-resources + bucket policy
- CloudTrail `moodle-mgmt`

If count is significantly higher, stop and investigate before applying.

### 4. Apply

```bash
terraform -chdir=terraform/bootstrap apply tfplan
```

### 5. Capture outputs

```bash
terraform -chdir=terraform/bootstrap output
```

Record all six values: `state_bucket_name`, `lock_table_name`, `cloudtrail_bucket_name`, `cloudtrail_arn`, `deploy_role_arn`, `acm_certificate_arn`. These are not consumed by the workload via remote state — they must be wired manually (steps 6–7).

### 6. Update backend.tf

Edit `terraform/environments/pilot/backend.tf`: replace the `<account-id>` placeholder with `288761747885`. Commit:

```bash
git add terraform/environments/pilot/backend.tf
git commit -m "wire backend: account 288761747885"
```

### 7. Wire GitHub repo

Set repository variable:
```
GitHub → banjika/wirfo-moodle-aws → Settings → Secrets and variables → Actions → Variables
  AWS_DEPLOY_ROLE_ARN = <deploy_role_arn from step 5>
```

Create production environment:
```
GitHub → Settings → Environments → New environment
  Name: production
  Required reviewers: banjika
```

Protect main branch (if not already):
```
GitHub → Settings → Branches → Add rule
  Pattern: main
  ✓ Require pull request before merging
  ✓ Require status checks to pass → add: terraform-plan
```

### 8. AWS Budgets billing alarm (manual; not in Terraform)

```
AWS Console → Billing → Budgets → Create budget
  Type: Cost budget
  Period: Monthly
  Amount: $80
  Alert: 120% of actual spend
  Notification: operator email via SNS/email
```

Kept out of Terraform so it survives complete state loss. Confirm the SNS subscription email.

---

## Verification

```bash
aws s3 ls | grep wirfo-moodle-tfstate-
# Expected: wirfo-moodle-tfstate-288761747885

aws dynamodb describe-table --table-name wirfo-moodle-tflock --query 'Table.TableStatus'
# Expected: "ACTIVE"

aws cloudtrail describe-trails --trail-name-list moodle-mgmt --query 'trailList[0].IsMultiRegionTrail'
# Expected: true

aws acm list-certificates --region us-east-1 \
  --query 'CertificateSummaryList[?DomainName==`academy.wirfoncloud.com`].Status'
# Expected: ["ISSUED"]
```

---

## Common failures

**ACM cert stuck "PENDING_VALIDATION"**
Route 53 NS records at registrar don't match the hosted zone.
```bash
dig NS wirfoncloud.com +short
aws route53 get-hosted-zone --id <zone-id> --query 'DelegationSet.NameServers'
```
Update registrar if they differ. ACM issues within ~5 min of DNS propagation.

**"AccessDenied" on any resource**
SSO session expired. Run `aws sso login` and retry from step 2.

**"BucketAlreadyOwnedByYou"**
Partial prior run left the bucket. Re-apply — Terraform is idempotent. If bucket is from a different account, choose a distinct name.

**"EntityAlreadyExists" on OIDC provider**
Import the existing provider before re-applying:
```bash
terraform -chdir=terraform/bootstrap import aws_iam_openid_connect_provider.github <arn>
terraform -chdir=terraform/bootstrap plan -out=tfplan
terraform -chdir=terraform/bootstrap apply tfplan
```
