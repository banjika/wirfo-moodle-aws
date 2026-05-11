data "aws_route53_zone" "main" {
  name = "wirfoncloud.com."
  # Trailing dot is intentional - fully-qualified zone name reduces lookup ambiguity.
  private_zone = false
  # Explicit - only one public zone for wirfoncloud.com exists in this account.
}

data "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1
  domain   = var.domain_name
  statuses = ["ISSUED"]
  # Filters out PENDING_VALIDATION certs - CloudFront requires a fully issued cert.
  most_recent = true
}

# CloudFront distribution for Moodle Academy.
# Phase 1: no WAF web ACL (deferred to Phase 2 alongside payment gateway integration per design.md §10.1).
# Phase 1: no access logging (cost stance per design.md §2.7; Phase 2 may add S3 logging when WAF analytics need it).
# Phase 1: no origin failover (single EC2 instance; Phase 3 introduces ALB and HA per design.md §10.1).
# Phase 1: geo restriction = none (Phase 2 BNR REG 89/2025 may add pricing variation, not geo-blocking).
# Phase 1: no response headers policy (Phase 2 may add HSTS/CSP hardening for production).
# origin_protocol_policy = "http-only": EC2 origin has no TLS cert; viewer HTTPS enforced by redirect-to-https.
# default_root_object = "": Moodle handles URL routing - empty lets /login/index.php, /course/view.php, etc. work.
#checkov:skip=CKV_AWS_68: Phase 2 deferral - WAF managed rule sets attach to CloudFront in Phase 2 alongside payment gateway integration per design.md §10.1.
#checkov:skip=CKV_AWS_86: Phase 1 cost stance per design.md §2.7 - logging omitted to keep cost down. Phase 2 may add S3 logging when WAF analytics need it.
#checkov:skip=CKV_AWS_305: Moodle handles URL routing - empty default_root_object lets /login/index.php, /course/view.php, etc. work. Setting "index.php" breaks Moodle routing.
#checkov:skip=CKV_AWS_310: Single EC2 origin in Phase 1 - no failover origin. Phase 3 introduces ALB and HA per design.md §10.1.
#checkov:skip=CKV_AWS_374: No geo-blocking in Phase 1 per CLAUDE.md hard rule #5. Phase 2 BNR REG 89/2025 may add country-based pricing variation, not geo-blocking.
#checkov:skip=CKV2_AWS_32: No response headers policy in Phase 1. Phase 2 may add HSTS/CSP security headers policy for production hardening.
#checkov:skip=CKV2_AWS_47: WAFv2 Log4j AMR requires WAF attachment - deferred to Phase 2 with CKV_AWS_68.
#tfsec:ignore:aws-cloudfront-enable-waf
#tfsec:ignore:aws-cloudfront-enable-logging
resource "aws_cloudfront_distribution" "moodle" {
  enabled         = true
  is_ipv6_enabled = true
  # Dual-stack - CloudFront serves over both IPv4 and IPv6.
  comment             = "Moodle Academy - Phase 1 single-instance origin"
  aliases             = [var.domain_name]
  default_root_object = ""
  price_class         = "PriceClass_100"
  # Edge locations: North America + Europe. Cheapest tier; Rwanda traffic served via
  # European edges (~50 ms latency). PriceClass_All adds Asia/SA/Africa/Australia for ~30%+ cost.

  origin {
    domain_name = var.origin_domain_name
    origin_id   = "moodle-ec2-origin"

    custom_origin_config {
      http_port  = 80
      https_port = 443
      # origin_protocol_policy = "https-only": Phase 1 EC2 origin has no TLS cert.
      # Viewer-facing HTTPS is enforced by viewer_protocol_policy = "redirect-to-https".
      # Phase 2 may add ACM Private CA + cert on the origin to switch to "https-only".
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      # Required attribute even when origin_protocol_policy = "http-only".
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.cloudfront.arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      # No geo-blocking in Phase 1. Phase 2 BNR REG 89/2025 may add country-based pricing
      # variation but not geo-blocking.
    }
  }

  default_cache_behavior {
    target_origin_id       = "moodle-ec2-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    # Moodle uses POST for form submissions - all methods must be allowed.
    cached_methods = ["GET", "HEAD"]
    compress       = true

    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    # AWS-managed Managed-CachingDisabled. Moodle is mostly dynamic; caching
    # login pages/forms would break sessions.

    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    # AWS-managed Managed-AllViewer. Forwards Host + ALL query strings + ALL cookies.
    # Critical for Moodle wwwroot consistency (design.md §2.7): Apache UseCanonicalName On
    # needs the Host header to build correct absolute URLs. DO NOT switch to
    # Managed-AllViewerExceptHostHeader - that strips Host and breaks Moodle links.
  }

  ordered_cache_behavior {
    path_pattern           = "/theme/*"
    target_origin_id       = "moodle-ec2-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    # AWS-managed Managed-CachingOptimized - aggressive caching for static assets
    # (Rwanda latency mitigation per design.md §2.7 and requirements §4.2).

    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    # Managed-AllViewer - same as default behavior for Host header consistency.
  }

  ordered_cache_behavior {
    path_pattern           = "/pluginfile.php/*"
    target_origin_id       = "moodle-ec2-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
  }

  ordered_cache_behavior {
    path_pattern           = "/lib/*"
    target_origin_id       = "moodle-ec2-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
  }

  ordered_cache_behavior {
    path_pattern           = "*.css"
    target_origin_id       = "moodle-ec2-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
  }

  ordered_cache_behavior {
    path_pattern           = "*.js"
    target_origin_id       = "moodle-ec2-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-moodle-cdn"
  }

  lifecycle {
    prevent_destroy = false
    # CloudFront is a routing layer with no stateful data. The underlying data lives
    # at the EC2 origin / RDS / EFS - all of which have their own prevent_destroy.
    # Replacing CloudFront has no data implications.
  }
}

resource "aws_route53_record" "a" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.moodle.domain_name
    zone_id                = aws_cloudfront_distribution.moodle.hosted_zone_id
    evaluate_target_health = false
    # CloudFront does not expose health state to Route 53 alias health checks.
  }
}

resource "aws_route53_record" "aaaa" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.moodle.domain_name
    zone_id                = aws_cloudfront_distribution.moodle.hosted_zone_id
    evaluate_target_health = false
  }
}
