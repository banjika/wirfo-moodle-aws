# SES Runbook

**Purpose:** Manage SES recipient verification while sandboxed, and request production access before public launch.

**When to use:**
- Adding a pilot user whose email must receive Moodle notifications (during sandbox)
- Verifying `alarm_email` and `moodle_admin_email` before first workload apply
- Before go-live: requesting SES production access (sandbox exit)

**Preconditions:**
- SES domain identity `wirfoncloud.com` provisioned by Terraform (T-021, `modules/dns_cdn`)
- DKIM (3 CNAME records), SPF, and DMARC records exist in Route 53 (created by T-021)
- AWS Console or CLI access in eu-west-1 with SES permissions

**Estimated time:** 5 minutes per recipient address; 24-48 hours for production access approval after submission

**Last updated:** 2026-05-14 (T-033 review - DKIM dig commands corrected, sesv2 API usage added)

---

## Current sandbox limits (verified 2026-05-14)

| Limit | Value | Source |
|---|---|---|
| Recipients | Verified addresses only | `aws ses get-account-sending-enabled` returns `true`, but `aws ses get-send-quota` returns sandbox quotas |
| Send quota | 200 emails / 24 hours | `Max24HourSend: 200.0` |
| Sending rate | 1 email / second | `MaxSendRate: 1.0` |

All pilot email addresses (including `alarm_email` and `moodle_admin_email`) **must** be verified before those users attempt signup or password reset. Unverified sends fail silently with `MessageRejected: Email address not verified`.

To check current sandbox status at any time:

```bash
aws ses get-account-sending-enabled --region eu-west-1
aws ses get-send-quota --region eu-west-1
```

Sandbox -> `Max24HourSend: 200`. After production access -> `Max24HourSend: 50000+` (initial allocation; grows with reputation).

---

## Part A - Verify a recipient address (console)

1. AWS Console -> **SES** -> region **eu-west-1** -> **Verified identities** -> **Create identity**
2. Identity type: **Email address**
3. Enter the recipient's email address
4. Click **Create identity**
5. AWS sends a verification link to that mailbox within ~30 seconds
6. Recipient clicks the link - status flips to **Verified** within seconds
7. Send a test email to confirm:
```
   SES console -> Verified identities -> select address -> Send test email
```

Repeat for every pilot participant before they attempt Moodle login.

## Part A (CLI alternative)

```bash
aws ses verify-email-identity --email-address user@example.com --region eu-west-1
```

Check status (works for both v1 and v2):

```bash
aws ses get-identity-verification-attributes \
  --identities user@example.com \
  --region eu-west-1 \
  --query 'VerificationAttributes."user@example.com".VerificationStatus'
# Expected: "Success"
```

---

## Part B - Verify domain identity is correctly configured

Use the modern SES v2 API for a richer status object:

```bash
aws sesv2 get-email-identity \
  --email-identity wirfoncloud.com \
  --region eu-west-1 \
  --query "{Verified:VerifiedForSendingStatus,DkimStatus:DkimAttributes.Status,DkimEnabled:DkimAttributes.SigningEnabled,Tokens:DkimAttributes.Tokens}"
```

Expected output:

```json
{
  "Verified": true,
  "DkimStatus": "SUCCESS",
  "DkimEnabled": true,
  "Tokens": ["<token1>", "<token2>", "<token3>"]
}
```

If `Verified` is `false` or `DkimStatus` is anything other than `SUCCESS`, troubleshoot via the dig commands below.

### How AWS SES verification works (two distinct mechanisms)

AWS SES uses two separate DNS records for two different purposes - they are easy to confuse:

| Record purpose | Record type | Record name | What it proves |
|---|---|---|---|
| Domain ownership | TXT | `_amazonses.wirfoncloud.com` | You control the domain |
| DKIM signing | CNAME (three of them) | `<token>._domainkey.wirfoncloud.com` | Outbound mail can be cryptographically signed |

Both must succeed for sending to work.

### Dig checks

**Domain ownership** (single TXT record):

```bash
dig TXT _amazonses.wirfoncloud.com +short
# Expected: a single TXT value, e.g. "abc123def456..."
```

**DKIM signing** (three CNAME records, one per token from the API output above):

```bash
dig CNAME <token1>._domainkey.wirfoncloud.com +short
dig CNAME <token2>._domainkey.wirfoncloud.com +short
dig CNAME <token3>._domainkey.wirfoncloud.com +short
# Each expected: <token>.dkim.amazonses.com.
```

**SPF and DMARC** (separate concerns from DKIM/verification, but the runbook covers them here for completeness):

```bash
dig TXT wirfoncloud.com +short | grep spf1
# Expected: "v=spf1 include:amazonses.com ~all" (or similar, depending on what else uses this domain)

dig TXT _dmarc.wirfoncloud.com +short
# Expected: "v=DMARC1; p=none; rua=mailto:..." (or your policy)
```

If any record is missing, the Terraform code in `modules/dns_cdn/ses.tf` is the source of truth - re-apply that module.

---

## Part C - Request production access (sandbox exit)

**Do not submit until:**
- First workload apply completed (T-029) - DONE
- Smoke tests passing (T-030) - DONE
- At least 1 week of pilot send data visible in SES metrics (bounce rate < 5%, complaint rate < 0.1%)
- Privacy policy + terms-of-service pages exist at `https://academy.wirfoncloud.com/admin/tool/policy/` (Moodle's built-in policy tool)

AWS Trust & Safety rejects vague applications. Provide concrete answers to every question on the form.

### Steps

1. AWS Console -> **SES** -> **Account dashboard** -> **Request production access**
2. Fill the form precisely:

   **Mail type:** Transactional

   **Website URL:** `https://academy.wirfoncloud.com`

   **Use case description** (paste verbatim, edit the volume figure if your pilot is larger):

```
   Moodle Learning Management System for a pilot cohort of 50-100 learners
   in Rwanda, hosted at academy.wirfoncloud.com.

   Mail types: registration confirmations, password reset links, course
   enrollment notifications, forum post digests, assignment grade feedback,
   and scheduled course reminders. All transactional - no marketing.

   Expected volume: ~500 emails / month, peaking to ~1500 during course
   launch weeks.

   Recipient list management: Recipients are pilot-cohort learners who
   have actively registered on the LMS. Moodle's built-in notification
   preferences let each user opt out of categories at
   /message/notificationpreferences.php. Users can also delete their
   account entirely under GDPR.

   Bounce handling: Moodle's "messageinbound" handler captures
   hard-bounce notifications via SES Notification topics; the user's
   "emailstop" flag is set, preventing further sends. Soft bounces are
   retried via Moodle's built-in queue.

   Complaint handling: SES complaint notifications also fire the
   "emailstop" flag and are reviewed weekly by the operator.

   Privacy: Privacy policy and terms-of-service published at
   academy.wirfoncloud.com/admin/tool/policy/. Account deletion supported.

   Sending IP allowlist: Not required - SES manages the sending IPs.
```

   **Additional information** (free text - skip unless asked):

```
   This is a non-profit pilot run by Wirfon Cloud (Rwanda). The infrastructure
   is Terraform-managed and the Moodle deployment follows AWS best practices
   for educational workloads. Bounce / complaint metrics dashboards are
   exported to CloudWatch and reviewed via the SNS alarm topic.
```

3. Submit
4. AWS responds within 24-48 hours. Approval comes via email to the AWS account's root email; the SES console will also show the new quota.
5. Once approved, sandbox restrictions lift automatically - no further action needed. Verify via:

```bash
   aws ses get-send-quota --region eu-west-1
   # Expected: Max24HourSend >= 50000, MaxSendRate >= 14
```

---

## Common failures

**Verification email doesn't arrive**
Check spam folder first. If still missing after 5 minutes:
```bash
aws ses verify-email-identity --email-address user@example.com --region eu-west-1
```
(Resends the verification email.) Some mail providers (Microsoft 365, Yahoo) are slower than Gmail by 1-2 minutes.

**`get-email-identity` returns "Pending" for DKIM after T-021 apply**
DNS propagation lag - SES is waiting for the 3 DKIM CNAMEs to be visible in public DNS. Wait 10-15 minutes and recheck. If still pending after 30 minutes, dig each CNAME individually (Part B) and compare to the Terraform-produced records in `modules/dns_cdn/ses.tf`. AWS will give up checking after 72 hours and require a manual re-trigger via the console.

**Production access denied**
AWS Trust & Safety typically rejects for one of three reasons:
1. Vague use case ("send emails to users"). Use the template above.
2. Missing privacy/ToS pages. Publish them via Moodle's policy tool first.
3. Bounce rate over 5% in the pilot's send history. Improve list quality - all addresses must be verified (sandbox enforces this anyway).

Resubmit with the specific issue addressed; do not just re-paste the same form.

**`MessageRejected: Email address not verified`**
A recipient address wasn't verified before the send. Verify it (Part A) and have the user retry. While sandboxed, ALL recipient addresses must be verified - the sender being verified is not enough.

**`SignatureDoesNotMatch` or `MessageRejected: Email address not verified` despite verification**
SES is region-specific. Identities verified in `us-east-1` cannot send from `eu-west-1`. Confirm all CLI calls and console actions use `--region eu-west-1`.

**SES sending quota exhausted**
Sandbox limit is 200 / 24h. If pilot traffic exceeds this before production access is granted, request approval immediately (Part C). There is no temporary-quota-bump mechanism in sandbox - only production access lifts the limit.