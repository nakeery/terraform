# range-05-mcp-agent-compromise - scaffolding notes

## What's provisioned

| File | Resources | Role in the chain |
|---|---|---|
| `main.tf` | `azurerm_resource_group`, provider/locals/tags | project scaffolding |
| `identity.tf` | `azurerm_user_assigned_identity.agent`, two `azurerm_role_assignment`s | **the vulnerability** - the over-scoped identity |
| `ai_foundry.tf` | `azurerm_cognitive_account` (kind `AIServices`), `azurerm_cognitive_account_project`, `azurerm_cognitive_account_rai_policy` (Prompt Shields), `azurerm_cognitive_deployment` | the agent's compute + model + guardrail |
| `keyvault.tf` | `azurerm_key_vault`, `azurerm_key_vault_secret` (dummy) | pivot target 1 |
| `storage.tf` | `azurerm_storage_account`, two containers, two blobs | pivot target 2 + the agent's legitimate tool data |
| `outputs.tf` | outputs incl. `warning` | reference values + the standard safety reminder |

No document store, no vector index, no RAG pipeline anywhere in this stack - out of scope per the spec.

## Why the managed identity is over-scoped (the documented vulnerability)

The agent's **stated job**, as modeled in `identity.tf`'s header comment: answer
employee support questions using one read-only tool that looks up a single FAQ
blob (`agent-tool-data/support_faq.txt`) in the storage account. That's the
entire job. It never writes anything, anywhere, and it never touches Key Vault.

What `azurerm_user_assigned_identity.agent` actually holds, attached directly to
the Foundry account (`azurerm_cognitive_account.foundry`) via its `identity {}`
block:

1. **`Key Vault Secrets User` on the whole vault** (`azurerm_key_vault.main`).
   The agent has no legitimate reason to resolve *any* Key Vault secret - the
   correctly-scoped answer is no Key Vault grant at all. This identity can read
   the unrelated `internal-billing-db-connection-string` dummy secret anyway.
2. **`Storage Blob Data Contributor` - read *and* write - at the storage
   account scope** (`azurerm_storage_account.main`), not scoped to the one
   container (`agent-tool-data`) the tool actually reads. That one grant also
   reaches the sibling `sensitive-customer-records` container holding the fake
   "sensitive" dataset, and grants write/delete there too, when the tool only
   ever needs read access to one blob in one container.

This mirrors the lesson from range-04 (the Bedrock RAG range): the
over-privileged identity sits one hop behind the thing an attacker actually
touches (there, a Lambda invoked through an AgentCore gateway target; here, the
Foundry account's own managed identity), and the design mistake is the same -
granting at the account/vault level because "the agent might need more later,"
instead of granting to the one object the stated job requires. The trigger
differs by range: range-04's injection vector is a poisoned knowledge-base
document; this range has no document store, so the trigger is the agent's
tool-calling path itself (a crafted tool argument, a compromised MCP-style tool
backend, or an unvalidated tool result) reaching an identity that was scoped to
"the account" instead of "the one container and zero secrets" the job needed.

`identity.tf` leaves a `TODO (yours to complete)` to add the *correctly*-scoped
role assignment (`Storage Blob Data Reader` on
`azurerm_storage_container.tool_data` alone) alongside the over-scoped one, as
a before/after demonstration, then drop the over-scoped grant and re-walk the
scenario to show the tool still works at least privilege.

## Open item: current Azure support, what I confirmed vs. couldn't

The task asked me to check current docs/provider schema rather than assume.
Checked against the `hashicorp/azurerm` provider's own markdown source
(`website/docs/...` on the `main` branch, fetched directly - not paraphrased
from memory) and confirmed empirically via `terraform validate` against
provider **4.81.0** (pinned here as `~> 4.0`):

**Confirmed:**
- **No stable azurerm (or widely-documented azapi) resource exists for the
  Agent object itself** - `Microsoft.CognitiveServices/accounts/projects/agents`
  - or for its tool/function manifest. `azurerm_ai_foundry` /
  `azurerm_ai_foundry_project` exist, but they model the **legacy Hub/Workspace**
  pattern (an Azure Machine Learning workspace) and the provider's own docs flag
  hub-based projects as not compatible with "the new Foundry experience" -
  explicitly pointing at `azurerm_cognitive_account` +
  `azurerm_cognitive_account_project` instead, which is what this stack uses.
  Agent creation (name, instructions, tool/function JSON schema) happens
  through the Azure AI Foundry Agents SDK or REST API against the project
  endpoint this stack exports (`ai_foundry_project_endpoints` output), **after**
  `terraform apply` - there's a `TODO` for this in `ai_foundry.tf`.
- **Tool/function calling is a model capability, not a separate resource.**
  `azurerm_cognitive_deployment` deploys the model (`gpt-4o-mini` by default,
  swappable to `gpt-4o`); tool-calling is enabled by handing the model a tool
  manifest at inference time as part of the Agent object above, not by any
  Terraform argument.
- **Content Safety "Prompt Shields" maps onto `azurerm_cognitive_account_rai_policy`'s
  `content_filter` blocks named `Jailbreak` and `Indirect Attack` (`source = "Prompt"`).**
  No separate "Content Safety account"/"Prompt Shields" resource exists in
  azurerm - it's a content-filter category on a custom RAI policy, which is
  then attached to the model deployment via `rai_policy_name`. This is wired up
  in `ai_foundry.tf` and is the resource the later guardrail test should target.
  One correction to the provider's own doc text, found only by running
  `terraform validate`: the docs say `severity_threshold` "does not apply" to
  Jailbreak/Indirect Attack, but the 4.x schema still marks it a **required**
  argument on every `content_filter` block regardless of type. Set to `"Low"`
  on both blocks here as a required-but-inert placeholder.
- **`azurerm_ai_foundry`/`azurerm_ai_foundry_project` are legacy** and were
  deliberately not used for that reason (see above) - this was the one naming
  decision the open item forced: the "obvious" resource names are the wrong
  ones for a current (2026) Foundry deployment.

**Could not verify / remains uncertain:**
- Whether an azapi-based attempt at creating
  `Microsoft.CognitiveServices/accounts/projects/agents` directly (bypassing
  the SDK) is viable. Search results surfaced *multiple* live Microsoft Q&A
  reports (dated as recently as November 2025) of Terraform/azapi/CLI-created
  Foundry projects hitting 404s or failed asset creation when the Agents SDK
  or AI Search tooling touched them afterward - i.e. even the infra this stack
  *does* provision has a reported history of friction with the Agent Service
  layer. I did not have credentials to test this myself, so I left Agent
  creation as an explicit SDK/REST TODO rather than guessing at an azapi body
  I couldn't verify against a live account.
  - This means the real risk to the deliverable is not "does this validate" (it does) but "does the Foundry project this produces actually let the Agent Service create an agent against it cleanly" - that can only be checked with a live `terraform apply` + a real SDK call, which the hard constraint in this task ruled out running this round.
- Exact regional availability of the Agent Service + `Indirect Attack` content
  filter + `gpt-4o-mini` tool calling, all three together, for `eastus2`
  (`variables.tf` default). I picked `eastus2` as a generally well-covered
  region based on search results, not a region-by-region matrix I verified
  directly against a live subscription.
- Whether `base_policy_name = "Microsoft.DefaultV2"` is still the correct/
  current base policy name to extend - the provider doc didn't enumerate valid
  values, only that one's required and forces a new resource if changed.

## `terraform validate` output

```
Success! The configuration is valid.
```

(After fixing three real schema mismatches `validate` caught against live
provider 4.81.0 - not hypothetical: `enable_rbac_authorization` renamed to
`rbac_authorization_enabled` in 4.x, `content_filter.severity_threshold` is
required despite the docs saying otherwise, and `azurerm_storage_blob` has no
`tags` argument.)

## `terraform plan` - could not complete, for lack of credentials

This environment has no `az` CLI and no `ARM_*` environment variables
configured, so the `azurerm` provider cannot authenticate. `terraform plan`
got as far as planning the one resource that needs no cloud auth
(`random_id.suffix`) and then failed on the first `azurerm`-backed data
source/resource with:

```
Error: unable to build authorizer for Resource Manager API: could not configure
AzureCli Authorizer: could not parse Azure CLI version: launching Azure CLI:
exec: "az": executable file not found in %PATH%
```

No fabricated plan output is included here. To actually see a plan, configure
`az login` (or `ARM_CLIENT_ID`/`ARM_CLIENT_SECRET`/`ARM_SUBSCRIPTION_ID`/
`ARM_TENANT_ID`) against a sandbox subscription and re-run `terraform plan` in
this directory.

## Real finding from a live `apply`: Storage/Cognitive Services firewalls reject `/32`

With real credentials configured (outside this environment), the first live
`apply` got past authentication and failed on `azurerm_storage_account.main`:

```
Error: "network_rules.0.ip_rules.0" must start with IPV4 address and/or slash,
number of bits (0-30) as prefix. Example: 23.45.1.0/30 but got
"71.207.149.181/32"
```

Azure's Storage (and, on inspection, Cognitive Services) firewall `ip_rules`
schema only accepts a bare IPv4 address or a CIDR with a 0-30 prefix - /31 and
/32 are rejected outright, so a single host has to be passed with no prefix at
all rather than as a /32. This is the same constraint on both resources
(confirmed via third-party docs/policy-tooling references for Cognitive
Services, since Microsoft's own schema docs don't spell out the 0-30 bound
explicitly), but notably **`terraform validate` does not catch it** - it only
surfaces once the provider evaluates a concrete IP value against the live
API during `plan`/`apply`. `access.tf` now derives `local.firewall_ip_rules`
(a `trimsuffix(cidr, "/32")` over `local.allowed_source_cidrs`) for exactly
this reason, used by `storage.tf` and `ai_foundry.tf`'s `ip_rules`.
`container_app.tf`'s ingress `ip_security_restriction` is a different API
(`Microsoft.App`, not `Microsoft.Storage`/`CognitiveServices`) and accepts
`/32` fine, so it keeps using `local.allowed_source_cidrs` directly - not
changed, and not verified further since nothing reported it broken.

## Real finding from a provider major-version bump: azurerm 4.x -> 5.x

The project owner moved `required_providers.azurerm` to `~> 5.0` (now
`5.11.0` per the lock file) outside this environment. That surfaced two more
schema changes on `storage.tf`, caught on `plan` this time, not `validate`
(these ARE pure schema changes - "Unsupported argument" is normally a
`validate`-time error with no credentials needed, but the file had already
drifted out of sync with what `validate` had last checked, so they only
showed up once a live `plan` was run against the new provider):

- **`azurerm_storage_blob`** dropped `storage_account_name` and
  `storage_container_name` entirely in 5.x. Both blob resources now take a
  single `storage_container_id = azurerm_storage_container.<x>.id` instead -
  confirmed against the provider's own current example
  (`website/docs/r/storage_blob.html.markdown` on `main`), which no longer
  documents either of the old arguments.
- **`azurerm_storage_account.public_network_access_enabled`** (bool) became
  `public_network_access` (string: `Enabled` / `Disabled` /
  `SecuredByPerimeter`, defaulting to `Enabled`) in 5.x - confirmed against
  the same provider docs. `azurerm_cognitive_account` (`ai_foundry.tf`) was
  **not** renamed the same way and still takes the old boolean
  `public_network_access_enabled` as of 5.11.0 - the two resources didn't
  move in lockstep, so don't assume one implies the other on the next bump
  either.

One of these got inverted mid-edit (`public_network_access` briefly set to
`"Disabled"`, which - with no Private Endpoint anywhere in this stack -
would have blocked Terraform's own data-plane container/blob creation, not
just the IP-allowlist story the surrounding comment describes). Fixed back
to `"Enabled"` with `network_rules` doing the actual restricting, which is
what "reachable, but only from `local.allowed_source_cidrs`" has always
meant here.

## Design decisions that needed the project owner's sign-off (resolved)

1. **The Agent object + tool manifest is not in Terraform at all.**
   **Resolved:** instead of closing this gap, the project owner chose to
   sidestep the managed Agent Service entirely for now. `../orchestrator/`
   drives the tool-calling loop directly against this account's standard
   chat-completions endpoint, with a `TODO` left to swap in native Foundry
   Agent Service + MCP integration once that IaC/SDK handoff is verified
   reliable.
2. **Where the "compute" lives.** **Resolved:** added `container_app.tf` -
   a dedicated Container App hosts the MCP server (`../mcp-server`), with
   the over-scoped UAMI attached there instead of only to the Foundry
   account. This is what makes the `read_secret` -> Key Vault pivot a real,
   literally-exercised managed-identity call rather than a documented one.
3. **Networking is wide open.** **Resolved, partially:** `access.tf` adds
   an auto-detected operator-IP allowlist, applied to the storage account
   (`storage.tf`), the Foundry account (`ai_foundry.tf`), and the Container
   App's ingress (`container_app.tf`) - everywhere the operator or the
   orchestrator is the actual caller. Deliberately **not** applied to the
   Key Vault (see the comment in `keyvault.tf`): the only caller that
   matters there is the Container App's own outbound traffic, whose IP
   isn't known at plan time and isn't the operator's - firewalling to the
   operator's `/32` would block the exact call this range exists to
   demonstrate. Private Endpoints/VNet integration remain a further-
   hardening `TODO` on the Foundry account.
4. **`shared_access_key_enabled = true` on the storage account.** **Resolved:**
   flipped to `false`. The provider itself now authenticates to the storage
   data plane via Azure AD (`storage_use_azuread = true` in `main.tf`'s
   provider block) through a new `deployer_storage_blob_contributor` RBAC
   grant (`storage.tf`), rather than falling back to the account key - no
   shared key exists anywhere in this stack now, matching the Key Vault's
   RBAC-only posture. One caveat found in the provider's own docs, not
   assumed: changing (not creating) a container's `container_access_type`
   always falls back to Shared Key, which no longer exists here - noted
   in `storage.tf` directly above the two container resources. The storage
   over-privilege itself is still a documented (not live-exercised)
   finding in this project's current scope, since none of the six MCP
   tools reads storage.
5. **Model choice (`gpt-4o-mini` default).** Unchanged; revisit once the
   orchestrator's walkthrough is run against a live deployment.

## Known gap: storage network ACL would block the agent's own "legitimate" tool if it's ever built

Found by an `architecture-integrity-reviewer` pass, not yet fixed because
nothing exercises it today: `storage.tf`'s `network_rules` firewalls the
storage account to `local.allowed_source_cidrs` (the operator's IP) with
`bypass = ["AzureServices"]`. That's the wrong caller for this resource -
the agent's documented legitimate data source is the FAQ blob
(`agent-tool-data/support_faq.txt`), which would be read by a tool running
in the Container App, not by the operator, and a Container App's
data-plane blob read is not covered by the `AzureServices` trusted-bypass
list. `identity.tf`'s `agent_storage_read_scoped` grant (the correctly-scoped
`Storage Blob Data Reader`, added alongside the over-scoped grant as a
documented before/after) can't actually be demonstrated live until this is
fixed too.

This is latent, not live, because none of the six MCP tools in
`../mcp-server/server.py` reads storage yet (see design decision #4 above)
- the "storage pivot" is still narrative, not demonstrated.

**What the real fix costs (checked against current Microsoft Learn docs,
2026-10-26, not assumed):** the available azurerm mechanism is
`virtual_network_subnet_ids` on the storage account's `network_rules` (an
Azure Storage *service endpoint*, not an IP allowlist, so it survives the
Container App's outbound IP changing), paired with
`infrastructure_subnet_id` on `azurerm_container_app_environment.main`. But
giving the Container App Environment its own VNet integration isn't free or
simple:

- **Subnet sizing/delegation differ by environment type and the provider's
  own docs disagree with Microsoft's.** The azurerm provider's
  `container_app_environment` page states a `/21` minimum; Microsoft's
  Container Apps networking docs say `/27` minimum **with mandatory
  delegation to `Microsoft.App/environments`** for a workload-profile
  environment (the current default), or `/23` minimum **with no delegation
  allowed at all** for the legacy consumption-only environment type - this
  stack doesn't declare which type it gets, so that would need pinning down
  explicitly first.
- **It adds standing cost this range's README doesn't currently budget
  for.** Per Microsoft's docs, VNet-integrating a Container Apps environment
  provisions a managed resource group with at least one standard **static
  public IP** (for egress) and a **standard Load Balancer**, billed
  continuously - on top of, not instead of, the Container App itself. That
  changes this range's cost posture from "a small flat ACR fee" to
  "meaningful standing infrastructure," which is a deliberate decision the
  project owner should make, not something to default into.
- **Private Endpoints** (the alternative `TODO` already called out on the
  Foundry account in `ai_foundry.tf`) sidestep the delegation question but
  still need the same dedicated subnet and carry their own per-endpoint
  hourly charge.

Given that cost/complexity and no live subscription available to verify
either path actually plans and applies cleanly, this remains a `TODO (yours
to complete)` rather than something implemented blind. Whoever builds the
FAQ-lookup tool should decide workload-profile-with-delegation vs.
consumption-only-without-delegation *first*, size the subnet accordingly,
add the service endpoint, and budget for the new standing IP/LB cost before
wiring it in.
