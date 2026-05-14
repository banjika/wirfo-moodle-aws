# Restore Drill Runbook

**Purpose:** Quarterly verification that RDS and EFS backups are restorable. Validates RTO (4h) and RPO (24h) claims from requirements section 4.4.

**When to use:**
- Quarterly (per requirements section 8.4)
- After any change to backup configuration
- Before a planned major workload change (verify recoverability first)

**Preconditions:**
- First workload apply completed (T-029) - RDS automated backups enabled, AWS Backup vault `moodle-academy-pilot-moodle-backup-vault` active
- Operator has SSM Session Manager access to the EC2 instance
- At least one automated RDS snapshot exists (backups run nightly; allow 24h after first apply)
- 30-60 minutes available uninterrupted (after applying T-031 corrections; first-time drill was ~57 min due to discovered bugs)

**Estimated time:** 30-60 minutes (both parts combined)
**Last updated:** 2026-05-14 (T-031 first drill execution; 10 procedural corrections baked in)

---

## Pass/fail criteria (requirements section 4.4)

| Metric | Target | Pass if |
|---|---|---|
| RTO | 4 hours | Wall clock from "start drill" to both artifacts verified queryable < 4h |
| RPO | 24 hours | Restored snapshot is <= 24h old |

**Record wall-clock start time before Part A, step 1.**

---

## Part A - RDS snapshot restore (~10-15 min)

### A1. Identify latest automated snapshot

```bash
aws rds describe-db-snapshots \
  --db-instance-identifier moodle-academy-pilot-rds \
  --snapshot-type automated \
  --region eu-west-1 \
  --query 'reverse(sort_by(DBSnapshots, &SnapshotCreateTime))[0].{ID:DBSnapshotIdentifier,Time:SnapshotCreateTime}'
```

Record the snapshot ID and creation time. Verify the snapshot is <= 24h old (RPO check).

### A2. Get the DB security group ID

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=moodle-academy-pilot-db-sg" \
  --region eu-west-1 \
  --query "SecurityGroups[0].GroupId" --output text
```

### A3. Restore as a separate instance

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier moodle-pg-restore-test \
  --db-snapshot-identifier <snapshot-id-from-A1> \
  --db-subnet-group-name moodle-academy-pilot-rds \
  --vpc-security-group-ids <db_sg_id-from-A2> \
  --no-publicly-accessible \
  --region eu-west-1
```

This creates a **separate instance** (`moodle-pg-restore-test`) - it does NOT overwrite production. Initial status `creating`; takes ~8-15 minutes to reach `available`.

### A4. Wait for "available"

```bash
aws rds describe-db-instances \
  --db-instance-identifier moodle-pg-restore-test \
  --region eu-west-1 \
  --query 'DBInstances[0].DBInstanceStatus' --output text
```

Poll every 1-2 minutes. Progression: `creating` -> `backing-up` -> `available`.

### A5. Verify queryable via EC2

The production EC2 instance has the right VPC reachability and tools. SSM into it:

```bash
aws ssm start-session --target <production-ec2-instance-id> --region eu-west-1
```

In the SSM session:

```bash
# Fetch password from Secrets Manager via env var (avoids copy/paste errors with special chars):
export PGPASSWORD=$(aws secretsmanager get-secret-value --secret-id moodle/db/master --region eu-west-1 --query SecretString --output text | jq -r .password)
echo "Password length: ${#PGPASSWORD}"   # Sanity check; expect ~32

# Get the restore instance endpoint:
RESTORE_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier moodle-pg-restore-test \
  --region eu-west-1 \
  --query 'DBInstances[0].Endpoint.Address' --output text)

# Query with TLS required (server enforces rds.force_ssl=1):
psql "host=$RESTORE_HOST user=moodle_admin dbname=moodle sslmode=require" \
  -c 'SELECT count(*) FROM mdl_user;'
```

Expected: row count matches production. For a pilot with admin + 1 manager account, count = 3 (guest + admin + your manager).

Also worth checking the actual users:

```bash
psql "host=$RESTORE_HOST user=moodle_admin dbname=moodle sslmode=require" \
  -c "SELECT id, username, firstname, lastname, email FROM mdl_user ORDER BY id;"
```

### A6. DELETE the restore artifact (CRITICAL - prevents cost drift)

Exit SSM, back in your local PowerShell/terminal:

```bash
aws rds delete-db-instance \
  --db-instance-identifier moodle-pg-restore-test \
  --skip-final-snapshot \
  --delete-automated-backups \
  --region eu-west-1
```

Confirm deletion (after ~5 min):

```bash
aws rds describe-db-instances \
  --db-instance-identifier moodle-pg-restore-test \
  --region eu-west-1 2>&1 | grep -i "DBInstanceNotFound\|not found"
# Expected: error message confirming instance not found
```

---

## Part B - EFS restore via AWS Backup (~5-10 min)

### B1. Identify latest recovery point and source EFS ID

```bash
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name moodle-academy-pilot-moodle-backup-vault \
  --region eu-west-1 \
  --query 'reverse(sort_by(RecoveryPoints, &CreationDate))[0].{ARN:RecoveryPointArn,Date:CreationDate,Status:Status,Resource:ResourceArn}'
```

Record:
- The `ARN` (RecoveryPointArn) - used in B3.
- The source EFS ID from `Resource` (the part after `file-system/`) - used in B2.
- Verify `Status` is `COMPLETED`.

### B2. Get the AWS-managed KMS key for EFS

```bash
aws kms describe-key \
  --key-id alias/aws/elasticfilesystem \
  --region eu-west-1 \
  --query "KeyMetadata.KeyId" --output text
```

Note this GUID. It will form the KmsKeyId in the restore metadata.

### B3. Write restore metadata file

The restore metadata must include **all five required keys** AWS Backup demands. Discovered during T-031:

| Key | Required? | Value |
|---|---|---|
| `newFileSystem` | Yes | `"true"` |
| `PerformanceMode` | Yes | `"generalPurpose"` |
| `Encrypted` | Yes | `"true"` |
| `CreationToken` | Yes | Unique string per drill (e.g., `restore-drill-YYYYMMDD-HHMM`) |
| `file-system-id` | Yes | Source EFS ID from B1 (NOT the new restored ID) |
| `KmsKeyId` | Yes (when `Encrypted=true`) | Full ARN of the KMS key from B2 |

**On Linux/Mac:**

```bash
cat > /tmp/efs-restore-metadata.json <<EOF
{
  "newFileSystem": "true",
  "PerformanceMode": "generalPurpose",
  "Encrypted": "true",
  "CreationToken": "restore-drill-$(date -u +%Y%m%d-%H%M)",
  "file-system-id": "<source-fs-id-from-B1>",
  "KmsKeyId": "arn:aws:kms:eu-west-1:<account-id>:key/<kms-key-id-from-B2>"
}
EOF
```

**On Windows PowerShell** (needed because PowerShell strips quotes when passing JSON inline to aws.exe):

```powershell
$today = Get-Date -Format "yyyyMMdd-HHmm"
$metadata = @{
    "newFileSystem"    = "true"
    "PerformanceMode"  = "generalPurpose"
    "Encrypted"        = "true"
    "CreationToken"    = "restore-drill-$today"
    "file-system-id"   = "<source-fs-id-from-B1>"
    "KmsKeyId"         = "arn:aws:kms:eu-west-1:<account-id>:key/<kms-key-id-from-B2>"
} | ConvertTo-Json -Compress
$metadata | Out-File -FilePath "$env:TEMP\efs-restore-metadata.json" -Encoding ASCII -NoNewline
Get-Content "$env:TEMP\efs-restore-metadata.json"
```

### B4. Start restore job

**Linux/Mac:**

```bash
aws backup start-restore-job \
  --recovery-point-arn <arn-from-B1> \
  --metadata file:///tmp/efs-restore-metadata.json \
  --iam-role-arn arn:aws:iam::<account-id>:role/moodle-academy-pilot-aws-backup-role \
  --resource-type EFS \
  --region eu-west-1
```

**PowerShell:**

```powershell
aws backup start-restore-job `
  --recovery-point-arn "<arn-from-B1>" `
  --metadata "file://$env:TEMP\efs-restore-metadata.json" `
  --iam-role-arn "arn:aws:iam::<account-id>:role/moodle-academy-pilot-aws-backup-role" `
  --resource-type EFS `
  --region eu-west-1
```

Record the `RestoreJobId` from the response.

### B5. Wait for completion

```bash
aws backup describe-restore-job \
  --restore-job-id <job-id-from-B4> \
  --region eu-west-1 \
  --query '{Status:Status,Pct:PercentDone,Created:CreatedResourceArn}'
```

Poll every 1 minute. Progression: `PENDING` -> `RUNNING` -> `COMPLETED` (or `FAILED`). On COMPLETED, record the new EFS ID from `CreatedResourceArn` (after the `file-system/` prefix).

### B6. Create a mount target

AWS Backup creates the file system but does NOT create mount targets. We need at least one in the active AZ before we can mount:

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=moodle-academy-pilot-efs-sg" \
  --region eu-west-1 --query "SecurityGroups[0].GroupId" --output text
```

Note the EFS SG ID. Then create the mount target in the eu-west-1a private subnet (the same one used by production EFS - find via Terraform output or RDS subnet group):

```bash
aws efs create-mount-target \
  --file-system-id <new-efs-id-from-B5> \
  --subnet-id <eu-west-1a-private-subnet-id> \
  --security-groups <efs-sg-id> \
  --region eu-west-1
```

Record the `MountTargetId` and the assigned `IpAddress` from the response. Poll until `available`:

```bash
aws efs describe-mount-targets \
  --file-system-id <new-efs-id> \
  --region eu-west-1 \
  --query "MountTargets[0].LifeCycleState" --output text
```

Takes ~60-90 seconds.

### B7. Mount and verify via EC2

Back in SSM on production EC2:

```bash
sudo mkdir -p /mnt/restore-test
```

Mount with the IP address option (bypasses DNS lookup and the `ec2:DescribeAvailabilityZones` API call that the instance role doesn't have):

```bash
sudo mount -t efs -o tls,iam,mounttargetip=<mount-target-ip-from-B6> <new-efs-id>:/ /mnt/restore-test
```

Inspect (note: Moodle dataroot is group-only, so we use `sudo` for ls):

```bash
sudo ls -la /mnt/restore-test/
```

AWS Backup wraps restored content in a subdirectory named `aws-backup-restore_<timestamp>/`. Look inside:

```bash
sudo ls -la /mnt/restore-test/aws-backup-restore_*/
sudo ls -la /mnt/restore-test/aws-backup-restore_*/.moodle-installed
```

Expected: directory structure matching `/var/moodledata/` - `cache/`, `filedir/`, `lang/`, `localcache/`, `muc/`, `sessions/`, `temp/`, `trashdir/` - plus the `.moodle-installed` marker file from T-029.5 (proves the rebuild-safety pattern survives backup/restore).

### B8. DELETE the restored EFS and mount target (CRITICAL)

In SSM:

```bash
sudo umount /mnt/restore-test
sudo rmdir /mnt/restore-test
exit
```

Back in your local terminal, **mount target first** (EFS won't delete while a mount target exists):

```bash
aws efs delete-mount-target \
  --mount-target-id <mount-target-id-from-B6> \
  --region eu-west-1

# Poll until [] (typically 30-60 sec):
aws efs describe-mount-targets \
  --file-system-id <new-efs-id> \
  --region eu-west-1 --query "MountTargets" --output json
```

Then the file system:

```bash
aws efs delete-file-system \
  --file-system-id <new-efs-id> \
  --region eu-west-1
```

Verify:

```bash
aws efs describe-file-systems \
  --file-system-id <new-efs-id> \
  --region eu-west-1 2>&1 | grep -i "FileSystemNotFound\|not exist"
```

---

## Post-drill documentation

### First drill (T-031 baseline)