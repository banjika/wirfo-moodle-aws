# Bootstrap Runbook

**Purpose:** Re-run `terraform/bootstrap` to recreate the state backend, OIDC trust, deploy role, ACM cert, and CloudTrail after loss or account migration.

**When to use:**
- State bucket accidentally deleted (`prevent_destroy` should prevent this - treat as catastrophic)
- AWS account migration (new account, same workload pattern)
- Initial setup of a new environment mirroring pilot

**Preconditions:**
- AWS CLI configured with SSO credentials for the target account
- Active SSO session: `aws sso login`
- Route 53 hosted zone for `wirfoncloud.com` confirmed in target account
- Terraform >= 1.7 installed locally

**Estimated time:** 15-20 minutes (ACM DNS validation is the slow step at ~5 min)

**Last updated:** 2026-05-14 (T-033 review: corrected trail name to `moodle_mgmt`, refreshed resource counts, added verification checks)

> **Reference values in this runbook are from the current pilot deployment in account `288761747885`, repo `banjika/wirfo-moodle-aws`.** For a different account or a fork, substitute your own values where appropriate.

---

## Steps

### 1. Verify Route 53 hosted zone

```bash
aws route53 list-hosted-zones --query "HostedZones[?Name=='wirfoncloud.com.']"
```

Expected: exactly one zone. If missing, create it and update registrar NS records before continuing - both `terraform/bootstrap` (ACM DNS validation) and `modules/dns_cdn` use this zone via data source with no fallback.

### 2. Init

```bash
terraform -chdir=terraform/bootstrap init
```

### 3. Plan

```bash
terraform -chdir=terraform/bootstrap plan -out=tfplan
```

Read the plan. Expected: **24-26 resources** to be created. Notable groupings:

| Group | Resources |
|---|---|
| State bucket | `aws_s3_bucket` `tfstate` + versioning + SSE config + public-access-block + ownership-controls + lifecycle-configuration |
| State lock | `aws_dynamodb_table` `tflock` |
| OIDC + deploy | `aws_iam_openid_connect_provider` + `aws_iam_role` `deploy` + `aws_iam_role_policy` |
| ACM | `aws_acm_certificate` (in us-east-1) + ~3 `aws_route53_record` validation entries + `aws_acm_certificate_validation` |
| CloudTrail | `aws_s3_bucket` `cloudtrail` + versioning + SSE + public-access-block + ownership-controls + object-lock-configuration + bucket-policy + `aws_cloudtrail` `moodle_mgmt` |

If the resource count is significantly higher than 26, stop and investigate before applying.

### 4. Apply

```bash
terraform -chdir=terraform/bootstrap apply tfplan
```

Wall-clock: ~6-8 minutes. ACM DNS validation is the long pole; everything else completes in seconds. If apply seems to hang on `aws_acm_certificate_validation.cloudfront: Still creating...`, that is normal - it polls for DNS propagation until the certificate is signed.

### 5. Capture outputs

```bash
terraform -chdir=terraform/bootstrap output
```

Expected six values:

```
acm_certificate_arn    = "arn:aws:acm:us-east-1:<account-id>:certificate/<uuid>"
cloudtrail_arn         = "arn:aws:cloudtrail:eu-west-1:<account-id>:trail/moodle_mgmt"
cloudtrail_bucket_name = "wirfo-moodle-cloudtrail-<account-id>"
deploy_role_arn        = "arn:aws:iam::<account-id>:role/moodle-deploy"
lock_table_name        = "wirfo-moodle-tflock"
state_bucket_name      = "wirfo-moodle-tfstate-<account-id>"
```

These are not consumed by the workload via remote state - they must be wired manually (steps 6-7).

### 6. Update workload backend.tf

The workload's `terraform/environments/pilot/backend.tf` hardcodes the state bucket name (Terraform backend blocks cannot reference variables or remote state). If running in a fresh account, replace the `<account-id>` placeholder with the new account ID:

```bash
git checkout -b wire-backend-account-<new-account-id>
# edit terraform/environments/pilot/backend.tf
git add terraform/environments/pilot/backend.tf
git commit -m "wire backend: account <new-account-id>"
```

In the current pilot setup, this file is already wired with the literal account ID (`288761747885`); this step is only relevant on account migration or initial setup of a fork.

### 7. Wire GitHub repo

Set repository variable (replace `<your-org>/<your-repo>` with the target repo path):

```
GitHub -> <your-org>/<your-repo> -> Settings -> Secrets and variables -> Actions -> Variables
  AWS_DEPLOY_ROLE_ARN     = <deploy_role_arn from step 5>
  ALARM_EMAIL             = <operator email>
  MOODLE_ADMIN_EMAIL      = <Moodle admin email>
  DMARC_RUA_ADDRESS       = <DMARC reports email>
```

Create the `production` environment:

```
GitHub -> Settings -> Environments -> New environment
  Name: production
  Required reviewers: <operator GitHub account>
```

Protect main branch (if not already):

```
GitHub -> Settings -> Branches -> Add rule
  Pattern: main
  [x] Require pull request before merging
  [x] Require status checks to pass -> add: Terraform Plan / Plan
```

### 8. AWS Budgets billing alarm (manual; not in Terraform)

```
AWS Console -> Billing -> Budgets -> Create budget
  Type: Cost budget
  Period: Monthly
  Amount: $80
  Alert: 120% of actual spend
  Notification: operator email via SNS or direct email
```

Kept out of Terraform so it survives complete state loss. Confirm the SNS or direct subscription email.

---

## Verification

After apply completes, run these to confirm each resource group is correctly configured:

### State bucket and lock table

```bash
aws s3 ls | grep wirfo-moodle-tfstate
# Expected: wirfo-moodle-tfstate-<account-id>

aws dynamodb describe-table --table-name wirfo-moodle-tflock --query 'Table.TableStatus' --region eu-west-1
# Expected: "ACTIVE"
```

### CloudTrail

The trail resource is named `moodle_mgmt` (underscore, not hyphen):

```bash
aws cloudtrail describe-trails --trail-name-list moodle_mgmt --region eu-west-1 \
  --query "trailList[0].{Name:Name,MultiRegion:IsMultiRegionTrail,LogFileValidation:LogFileValidationEnabled,Includes_global:IncludeGlobalServiceEvents}"
# Expected:
# {
#   "Name": "moodle_mgmt",
#   "MultiRegion": true,
#   "LogFileValidation": true,
#   "Includes_global": true
# }
```

Confirm the CloudTrail bucket has object lock and is versioned:

```bash
aws s3api get-object-lock-configuration --bucket wirfo-moodle-cloudtrail-<account-id> \
  --query 'ObjectLockConfiguration.ObjectLockEnabled'
# Expected: "Enabled"

aws s3api get-bucket-versioning --bucket wirfo-moodle-cloudtrail-<account-id> --query Status
# Expected: "Enabled"
```

### ACM certificate

```bash
aws acm list-certificates --region us-east-1 \
  --query "CertificateSummaryList[?DomainName=='academy.wirfoncloud.com'].Status"
# Expected: ["ISSUED"]
```

### Deploy role + OIDC trust

```bash
aws iam get-role --role-name moodle-deploy --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition'
# Expected condition with sub = "repo:<your-org>/<your-repo>:*" and aud = "sts.amazonaws.com"

aws iam list-role-policies --role-name moodle-deploy
# Expected: one or more policy names (the inline deploy policy)

aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn,'token.actions.githubusercontent.com')].Arn"
# Expected: a single ARN
```

---

## Common failures

**ACM cert stuck "PENDING_VALIDATION"**
Route 53 NS records at the domain registrar don't match the hosted zone's delegation set.
```bash
dig NS wirfoncloud.com +short
aws route53 get-hosted-zone --id <zone-id> --query 'DelegationSet.NameServers'
```
Update registrar NS records to match. ACM issues within ~5 min of DNS propagation.

**"AccessDenied" on any resource**
SSO session expired. Run `aws sso login` and retry from step 2 (init).

**"BucketAlreadyOwnedByYou"**
A partial prior run left the bucket. Re-apply - Terraform is idempotent and will reconcile state. If the bucket was created in a different account but the name collides, choose a distinct name (modify the bucket-name template in `terraform/bootstrap/state.tf`).

**"EntityAlreadyExists" on OIDC provider**
Import the existing provider before re-applying:
```bash
terraform -chdir=terraform/bootstrap import \
  aws_iam_openid_connect_provider.github \
  arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
terraform -chdir=terraform/bootstrap plan -out=tfplan
terraform -chdir=terraform/bootstrap apply tfplan
```

**`describe-trails` returns `null`**
The trail name is wrong. The Terraform resource defines `aws_cloudtrail "moodle_mgmt"` with an underscore, NOT a hyphen. List all trails in the region to confirm:
```bash
aws cloudtrail describe-trails --region eu-west-1 --query "trailList[].Name"
```

**Object lock cannot be enabled on existing CloudTrail bucket**
S3 object lock can only be set at bucket creation; you cannot retro-fit it. If a prior bootstrap created the bucket without object lock, the bucket must be deleted (after first emptying it via `aws s3 rb --force`) and re-created. Because the bucket has `prevent_destroy = true`, this requires temporarily removing the lifecycle block in `terraform/bootstrap/cloudtrail.tf`, applying, then restoring it.

**Plan tries to recreate state bucket / lock table**
You may have lost the local `terraform.tfstate` in the bootstrap directory. Re-import the resources rather than re-creating:
```bash
terraform -chdir=terraform/bootstrap import aws_s3_bucket.tfstate wirfo-moodle-tfstate-<account-id>
terraform -chdir=terraform/bootstrap import aws_dynamodb_table.tflock wirfo-moodle-tflock
terraform -chdir=terraform/bootstrap import aws_cloudtrail.moodle_mgmt moodle_mgmt
# Then plan - should show no changes for these resources
```