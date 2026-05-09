# tflint configuration for the project.
#
# Plugin and rule choices are documented in design.md §7 (CI/CD).
# Version-pinning gotchas live in CLAUDE.md "CI/CD lessons" —
# notably that the top-level `tflint { required_version }` block
# (introduced in tflint v0.51.0) is intentionally absent here so
# that the v0.50.3 pinned in .github/workflows/terraform-*.yml
# can parse this file.
# Operator runbooks for failure scenarios live in docs/runbooks/.

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.35.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_unused_required_providers" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
}
