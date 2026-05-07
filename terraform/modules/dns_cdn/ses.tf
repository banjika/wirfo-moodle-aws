# ---------------------------------------------------------------------
# SES domain identity for outbound transactional email
# ---------------------------------------------------------------------
# Phase 1 sends transactional email (registration verification,
# password reset, course notifications) via Amazon SES with the
# verified sender domain wirfoncloud.com. While the account is in
# the SES sandbox in eu-west-1, recipient addresses must be
# verified manually in the SES console; production access is a
# one-time AWS support request per docs/runbooks/ses.md.
# ---------------------------------------------------------------------

resource "aws_ses_domain_identity" "main" {
  domain = "wirfoncloud.com"
}

resource "aws_ses_domain_dkim" "main" {
  domain = aws_ses_domain_identity.main.domain
}

# ---------------------------------------------------------------------
# DKIM CNAME records — 3 tokens written to Route 53
# ---------------------------------------------------------------------
# SES generates 3 random DKIM tokens. Each needs its own CNAME at
# <token>._domainkey.wirfoncloud.com → <token>.dkim.amazonses.com.
# Using for_each on the dkim_tokens list creates all 3 records
# from one resource block.
# ---------------------------------------------------------------------

resource "aws_route53_record" "ses_dkim" {
  count = 3

  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${aws_ses_domain_dkim.main.dkim_tokens[count.index]}._domainkey.wirfoncloud.com"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.main.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# ---------------------------------------------------------------------
# SPF TXT record on apex
# ---------------------------------------------------------------------
# Tells receiving mail servers that Amazon SES servers are
# authorised to send mail for wirfoncloud.com. -all means "reject
# everything else." Strict policy because we have only one
# legitimate sender (SES).
# ---------------------------------------------------------------------

resource "aws_route53_record" "spf" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "wirfoncloud.com"
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:amazonses.com -all"]
}

# ---------------------------------------------------------------------
# DMARC TXT record on _dmarc subdomain
# ---------------------------------------------------------------------
# Tells receiving servers what to do if SPF or DKIM fails:
# quarantine (spam folder). p=quarantine is more permissive than
# p=reject — appropriate for a Phase 1 pilot where false positives
# would block legitimate transactional mail. Phase 2 may tighten
# to p=reject after monitoring rua reports for false positives.
# rua=mailto:<address> requests aggregate reports of authentication
# failures.
# ---------------------------------------------------------------------

resource "aws_route53_record" "dmarc" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "_dmarc.wirfoncloud.com"
  type    = "TXT"
  ttl     = 600
  records = [
    "v=DMARC1; p=quarantine; rua=mailto:${var.dmarc_rua_address}"
  ]
}

# ---------------------------------------------------------------------
# SES domain identity verification — BLOCKING resource
# ---------------------------------------------------------------------
# Polls SES until it confirms the SPF and DKIM records have
# propagated and validated. This blocks terraform apply until the
# email setup is genuinely ready — not just "Terraform thinks it's
# done" but "SES has actually verified the domain." Default timeout
# is 45 minutes; Route 53 propagation typically completes in 5-15
# minutes within AWS.
# ---------------------------------------------------------------------

resource "aws_ses_domain_identity_verification" "main" {
  domain = aws_ses_domain_identity.main.domain

  depends_on = [
    aws_route53_record.ses_dkim,
    aws_route53_record.spf
  ]
}
