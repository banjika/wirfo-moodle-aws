# T-002 SCAFFOLD ONLY - remove this entire file when:
# (a) all module calls are wired in main.tf (after T-026), AND
# (b) terraform plan shows zero unused variables.
# Tracking: see tasks.md Stage 10 cleanup task T-035.
rule "terraform_unused_declarations" {
  enabled = false
}

rule "terraform_required_providers" {
  enabled = false
}
