# Suppresses lints that are wrong for this project's design, not scaffolding artifacts.
#
# terraform_unused_declarations is disabled because variables.tf intentionally declares
# six variables that are unused by the workload but exist by design:
#   - github_repo: traceability for the bootstrap config (design.md section 3 row 5).
#   - active_availability_zone: operator documentation; effective AZ is index 0
#     of public_subnet_cidrs[]/private_subnet_cidrs[] (design.md section 3 row 8).
#   - enable_high_availability, rds_multi_az, enable_alb, cache_cluster_mode:
#     Phase 3 toggles surfaced now so the variable surface is operator-visible
#     today (design.md section 3 rows 31-34, section 10.2).
#
# T-035 evaluated removing this file. The conclusion was to narrow its scope
# (removed terraform_required_providers, which is no longer needed once all
# modules wire their own provider blocks) and keep terraform_unused_declarations
# disabled with a documented permanent reason.
rule "terraform_unused_declarations" {
  enabled = false
}
