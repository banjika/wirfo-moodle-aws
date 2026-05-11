# Restore Drill Runbook

**Purpose:** Quarterly verification that RDS and EFS backups are restorable. Validates RTO (4h) and RPO (24h) claims from requirements §4.4.
**When to use:**
- Quarterly (per requirements §8.4)
- After any change to backup configuration
- Before a planned major workload change (verify recoverability first)

**Preconditions:**
- First workload apply completed (T-029) — RDS automated backups enabled, AWS Backup vault `moodle-academy-pilot-moodle-backup-vault` active
- Operator has SSM Session Manager access to the EC2 instance
- At least one automated RDS snapshot exists (backups run nightly; allow 24h after first apply)
- 60–90 minutes available uninterrupted

**Estimated time:** 30–60 minutes (both parts combined)
**Last updated:** 2026-05-11 (T-031 first drill execution)

---

## Pass/fail criteria (requirements §4.4)

| Metric | Target | Pass if |
|---|---|---|
| RTO | 4 hours | Wall clock from "start drill" to both artifacts verified queryable < 4h |
| RPO | 24 hours | Restored snapshot is ≤ 24h old |

**Record wall-clock start time before Part A, step 1.**

---

## Part A — RDS snapshot restore (~15–30 min)

### A1. Identify latest automated snapshot

```bash
aws rds describe-db-snapshots \
  --db-instance-identifier moodle-academy-pilot-rds \
  --snapshot-type automated \
  --region eu-west-1 \
  --query 'reverse(sort_by(DBSnapshots, &SnapshotCreateTime))[0].{ID:DBSnapshotIdentifier,Time:SnapshotCreateTime}'
```

Record the snapshot ID and creation time. Verify the snapshot is ≤ 24h old (RPO check).

### A2. Restore as a separate instance

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier moodle-pg-restore-test \
  --db-snapshot-identifier <snapshot-id-from-A1> \
  --db-subnet-group-name moodle-academy-pilot-rds \
  --vpc-security-group-ids <db_sg_id> \
  --no-publicly-accessible \
  --region eu-west-1
```

> `<db_sg_id>` — retrieve from: `terraform -chdir=terraform/environments/pilot output` or AWS Console → EC2 → Security Groups → filter by `moodle-academy-pilot-db`.

This creates a **separate instance** (`moodle-pg-restore-test`) — it does NOT overwrite production.

### A3. Wait for "available"

```bash
aws rds describe-db-instances \
  --db-instance-identifier moodle-pg-restore-test \
  --region eu-west-1 \
  --query 'DBInstances[0].DBInstanceStatus'
```

Poll every 2 minutes until `"available"` (typically 10–15 min).

### A4. Verify queryable via EC2

```bash
aws ssm start-session --target <instance-id> --region eu-west-1
```

In the session:
```bash
RESTORE_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier moodle-pg-restore-test \
  --region eu-west-1 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)
psql -h "$RESTORE_HOST" -U moodle_admin -d moodle -c 'SELECT count(*) FROM mdl_user;'
# Enter DB password from Secrets Manager (returns JSON with username + password):
# aws secretsmanager get-secret-value --secret-id moodle/db/master --region eu-west-1 --query SecretString --output text
```

Expected: row count matches production (check production with the same query against the live endpoint).

### A5. DELETE the restore artifact (CRITICAL — prevents cost drift)

```bash
aws rds delete-db-instance \
  --db-instance-identifier moodle-pg-restore-test \
  --skip-final-snapshot \
  --delete-automated-backups \
  --region eu-west-1
```

Confirm deletion (poll until instance disappears):
```bash
aws rds describe-db-instances \
  --db-instance-identifier moodle-pg-restore-test \
  --region eu-west-1 2>&1 | grep -i "DBInstanceNotFound\|not found"
# Expected: error message confirming instance not found
```

---

## Part B — EFS restore via AWS Backup (~15–20 min)

### B1. Identify latest recovery point

```bash
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name moodle-academy-pilot-moodle-backup-vault \
  --region eu-west-1 \
  --query 'reverse(sort_by(RecoveryPoints, &CreationDate))[0].{ARN:RecoveryPointArn,Date:CreationDate,Status:Status}'
```

Record the ARN and creation date. Verify status is `COMPLETED`.

### B2. Write restore metadata

```bash
cat > /tmp/efs-restore-metadata.json << 'EOF'
{
  "newFileSystem": "true",
  "PerformanceMode": "generalPurpose",
  "Encrypted": "true",
  "CreationToken": "restore-drill-2026-05-09",
  "newFileSystemEncrypted": "true"
}
EOF
```

Update `CreationToken` to today's date to ensure uniqueness.

### B3. Start restore job

```bash
aws backup start-restore-job \
  --recovery-point-arn <arn-from-B1> \
  --metadata file:///tmp/efs-restore-metadata.json \
  --iam-role-arn <aws_backup_role_arn> \
  --resource-type EFS \
  --region eu-west-1
```

> `<aws_backup_role_arn>` — known ARN: `arn:aws:iam::288761747885:role/moodle-academy-pilot-aws-backup-role` (also visible in recovery point details from B1's output, field `IamRoleArn`).

Record the `RestoreJobId` from the response.

### B4. Wait for completion

```bash
aws backup describe-restore-job \
  --restore-job-id <job-id> \
  --region eu-west-1 \
  --query '{Status:Status,CreatedResourceArn:CreatedResourceArn}'
```

Poll every 2 minutes until `Status` is `COMPLETED`. Record the new EFS ID from `CreatedResourceArn`.

### B5. Mount and verify via EC2

```bash
aws ssm start-session --target <instance-id> --region eu-west-1
```

In the session:
```bash
sudo mkdir /mnt/restore-test
sudo mount -t efs -o tls,iam <new-efs-id>:/ /mnt/restore-test
ls /mnt/restore-test
# Verify file structure matches /var/moodledata (moodledata directory, filedir/, etc.)
```

### B6. DELETE the restored EFS (CRITICAL)

```bash
# In SSM session:
sudo umount /mnt/restore-test
sudo rmdir /mnt/restore-test
exit

# Back in local terminal:
aws efs delete-file-system \
  --file-system-id <new-efs-id> \
  --region eu-west-1
```

---

## Post-drill documentation

Fill this in before closing the terminal:

```
Drill date:           _______________
Wall-clock start:     _______________
Wall-clock end:       _______________
Total elapsed:        _______________ minutes

RDS snapshot age:     _______________ hours  (RPO pass if ≤ 24h)
RDS restore time:     _______________ minutes
EFS restore time:     _______________ minutes
Total RTO:            _______________ hours  (pass if < 4h)

RDS artifact deleted: ☐
EFS artifact deleted: ☐

Deviations from this procedure:
  _______________

AWS API errors encountered:
  _______________

Drill result: PASS / FAIL
```

---

## Common failures

**No automated snapshots yet**
RDS retention starts after the first backup window (nightly, ~02:00 UTC). Run the drill at least 24h after first apply.

**RDS restore fails with "InvalidParameterValue" on subnet group**
The subnet group name must match what Terraform created. Look it up:
```bash
aws rds describe-db-subnet-groups --region eu-west-1 \
  --query 'DBSubnetGroups[?contains(DBSubnetGroupName, `moodle`)].DBSubnetGroupName'
```

**psql connection refused**
The restored instance's security group only allows inbound from the web SG. You must connect via the EC2 instance (SSM), not from your laptop.

**EFS restore job stuck "PENDING"**
Check the AWS Backup vault permissions and verify the IAM role has both `AWSBackupServiceRolePolicyForBackup` and `AWSBackupServiceRolePolicyForRestores`.

**Mount fails with "access denied" or "operation not permitted"**
EFS file system policy enforces `aws:SecureTransport`. Ensure you use `-o tls` in the mount command. Also verify the restored EFS has a mount target in eu-west-1a.

---

## Drill history

| Date | RTO (min) | RPO (h) | Result | Notes |
|---|---|---|---|---|
| *(first drill in T-031)* | | | | |
