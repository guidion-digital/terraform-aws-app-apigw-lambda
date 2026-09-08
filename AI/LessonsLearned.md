# Lessons Learned

Correction memory for whoever (or whatever) regenerates `AI/CONTEXT.md`. Short, imperative entries. This is not documentation — prune an entry once the generator stops making the mistake.

## Things that look wrong but are not — do not report these as defects

- `data.aws_caller_identity.current.id` at `main.tf:235` vs `.account_id` at `main.tf:161`: both return the account id. Inconsistent, not broken.
- `DEPRECATED_acm_mode` forces the parent zone into the _certificate_ (`dns.tf:33`) while `parent_zone_in_domains` still gates the _domain name and DNS record_ (`dns.tf:50`). That asymmetry is the documented backwards-compatibility shim, not a bug. `README.md` says so explicitly.
- `put_rest_api_mode = "overwrite"` as the default is a deliberate choice with a written rationale, not an oversight. `merge` produces plans that misrepresent what will happen.
- The single API stage named `live` is a convention, not a missing feature. Guidion uses separate AWS accounts where others use stages.
- `source_arn` on `aws_lambda_permission.this` is string-built instead of referenced to break a dependency cycle. The comment above it explains why; do not "fix" it into a resource reference.
- `aws_security_group.this` (`main.tf:553`) is intentionally orphaned for state-migration reasons.

## Facts to get right

- `owner:` is `Cinfra`, supplied by the `repo_owner` input in `.github/workflows/regenerate-context.yaml` and set deliberately by the repo owner. Do not rewrite it to the `@guidion-digital/cinfra` CODEOWNERS handle, and do not substitute a person's name.
- This is a reusable **module**, not a deployment. It owns no business data and has no environments of its own — the only environment it touches is the CI test workspace. Do not invent an account/environment inventory.
- The repo's real consumer-facing API is its Terraform interface (`variables.tf` in, `outputs.tf` out). HTTP endpoints belong to consumers; only the examples' endpoints can be cited.
- `acc` is the default and integration branch; `master` is the released state. Do not assume `main`.

## Sourcing rules

- Cite only **tracked** identifiers. `.terraform/`, `.terraform.lock.hcl` and `backend.tf` are all gitignored, so resolved module and provider versions from them are not repo facts — cite the constraints in `main.tf`/`versions.tf`, and label anything from the local lockfile as untracked and observed.
- `123456789012` in `README.md` and the examples is a placeholder account id. Never present it as a real Guidion account.
- `${{secrets.TFC_PLANNER_API_TOKEN}}` in `.github/dependabot.yml` is a secret _reference_. It is not a committed credential and is not a rotation candidate.
- The only IP literals in tracked source are `0.0.0.0/0` and `10.0.0.1/32`. Do not invent an illustrative CIDR — the verifier greps every IPv4-shaped string against tracked source.
- `git log -S` is useless in this repo: everything resolves to the squashed `e0c210c` "Initial commit". Do not claim intent from history; use `README.md`, `Development Notes.md` and code comments, and say when provenance is unavailable.

## Verify empirically, do not reason

Four claims in Known risks are counter-intuitive and were confirmed by running Terraform in a scratch workspace. Re-confirm rather than re-deriving, and re-check if any are fixed:

- `try(module.X[0].y, null)` over a `for_each` module always falls through to the fallback — hence the permanently-`null` `elasticache_*` outputs.
- A conditional **does** short-circuit around a count-0 module index when the other branch is taken, so `memcached.tf:27` is fine _if_ `vpc_id` is set…
- …but fails the plan with `Invalid index … empty tuple` when it is not. `var.elasticache` therefore requires either `var.vpc_config` or explicit `vpc_id` **and** `subnet_ids`.

## Do not compress Known risks

Generic risk bullets ("IAM changes are risky", "verify integrations") are worthless here. Every entry needs `file:line`, the concrete failure, and a classification: intentional, dormant, or broken now. There are roughly fifteen real ones — a short Known risks section means the generator skimmed.

## Structure

- Where `CONTEXT_TEMPLATE.md` specifies a table, write a table. Prose in "Source of truth", "External integrations", "APIs exposed" or "APIs / services consumed" fails verification and drops the repo out of the company matrices — `n/a` with an explanation is not an escape hatch for those four.
- Keep the "Module interface and naming contracts" section. It is the highest-value repo-specific addition, and the `dyanmodb_table_stream_arns` typo in particular must keep being reported as load-bearing so nobody "tidies" it.
- The file ends at Freshness. Do not append a git log block; git already has that history.
- Keep `review_confidence: low` and `validated_by: none` until a human validates. Thorough generation does not raise them.
