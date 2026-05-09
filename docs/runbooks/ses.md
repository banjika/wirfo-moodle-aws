# SES Runbook

**Purpose:** Manage SES recipient verification while sandboxed and request production access before public launch.
**When to use:**
- Adding a pilot user whose email must receive Moodle notifications (during sandbox)
- Verifying `alarm_email` and `moodle_admin_email` before first workload apply
- Before go-live: requesting SES production access (sandbox exit)

**Preconditions:**
- SES domain identity `wirfoncloud.com` provisioned by Terraform (T-021 — `modules/dns_cdn`)
- DKIM, SPF, DMARC records exist in Route 53 (verified by T-021)
- AWS Console or CLI access in eu-west-1 with SES permissions

**Estimated time:** 5 minutes per address (verification); 24–48 hours for production access approval
**Last updated:** 2026-05-09

---

## Current sandbox limits

| Limit | Value |
|---|---|
| Recipients | Verified addresses only |
| Send quota | 200 emails/day |
| Sending rate | 1 email/second |

All pilot email addresses (including `alarm_email` and `moodle_admin_email`) **must** be verified before those users attempt signup or password reset.

---

## Part A — Verify a recipient address (console)

1. AWS Console → **SES** → eu-west-1 → **Verified identities** → **Create identity**
2. Identity type: **Email address**
3. Enter the recipient's email address
4. Click **Create identity**
5. AWS sends a verification link to that mailbox within ~1 minute
6. Recipient clicks the link — status flips to **Verified** within ~5 minutes
7. Send a test email to confirm:
   ```
   SES console → Verified identities → select address → Send test email
   ```

Repeat for every pilot participant before they attempt Moodle login.

## Part A (CLI alternative)

```bash
aws ses verify-email-identity --email-address user@example.com --region eu-west-1
```

Check status:
```bash
aws ses get-identity-verification-attributes \
  --identities user@example.com \
  --region eu-west-1 \
  --query 'VerificationAttributes."user@example.com".VerificationStatus'
# Expected: "Success"
```

---

## Part B — Verify domain identity is configured

```bash
aws ses get-identity-verification-attributes \
  --identities wirfoncloud.com \
  --region eu-west-1 \
  --query 'VerificationAttributes."wirfoncloud.com".VerificationStatus'
# Expected: "Success"

aws ses get-identity-dkim-attributes \
  --identities wirfoncloud.com \
  --region eu-west-1 \
  --query 'DkimAttributes."wirfoncloud.com".DkimVerificationStatus'
# Expected: "Success"
```

If either returns `"Pending"`, check that the Route 53 DKIM/SPF/DMARC records from T-021 are present:
```bash
dig TXT wirfoncloud.com +short
dig TXT _amazonses.wirfoncloud.com +short
dig TXT _dmarc.wirfoncloud.com +short
```

---

## Part C — Request production access (sandbox exit)

**Do not submit until:**
- First workload apply completed (T-029)
- Smoke tests passing (T-030)
- At least 1 week of pilot send data visible in SES metrics (bounce rate < 5%, complaint rate < 0.1%)

### Steps

1. AWS Console → **SES** → **Account dashboard** → **Request production access**
2. Fill the form:
   - **Mail type:** Transactional
   - **Website URL:** `https://academy.wirfoncloud.com`
   - **Use case description:**
     ```
     Moodle LMS for a 50-100 user pilot cohort (wirfoncloud.com). Email types:
     registration verification, password reset, course notifications. Expected
     volume: <500 emails/month. Bounce handling: Moodle built-in suppression
     list. Complaints: transactional-only mail; no marketing. Opt-out: users
     manage notification preferences in Moodle account settings.
     ```
3. Submit
4. AWS responds within 24–48 hours
5. Once approved, sandbox restrictions lift automatically — no further action needed

---

## Verification

```bash
aws ses get-account-sending-enabled --region eu-west-1
# Expected: true

aws ses get-send-quota --region eu-west-1
# Sandbox: MaxSendRate 1.0, Max24HourSend 200
# Post-production access: MaxSendRate 14.0+, Max24HourSend 50000+
```

---

## Common failures

**Verification email doesn't arrive**
Check spam folder. If still missing after 5 minutes:
```bash
aws ses verify-email-identity --email-address user@example.com --region eu-west-1
```
(Resends the verification email.)

**Domain identity shows "Pending" after T-021 apply**
DNS propagation lag. Wait 10–15 minutes and recheck. If still pending after 30 minutes, confirm the CNAME records exist in Route 53.

**Production access denied**
AWS rejects vague descriptions. Add specifics: expected volume, bounce/complaint handling mechanism, link to the Moodle UI showing notification settings. Resubmit.

**"MessageRejected: Email address not verified"**
A recipient address wasn't verified before the send. Verify it (Part A) and have the user retry.
