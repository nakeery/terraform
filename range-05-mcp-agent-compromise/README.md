# range-05 — MCP Agent Compromise

An over-scoped managed identity behind an Azure AI Foundry tool-calling agent,
reached not through a poisoned document but through the agent's own
tool-calling path: a hidden instruction smuggled into a support ticket's text
drives the agent to misuse a legitimate-looking tool.

> **Series:** [Offensive Cloud & AI Range](../README.md)
> [range-01 · Secure Baseline](../range-01-eks-secure-baseline/README.md) → [range-02 · Attack Chain](../range-02-eks-attack-chain/README.md) → [range-03 · IAM Privesc](../range-03-iam-privilege-escalation/README.md) → [range-04 · RAG Injection](../range-04-bedrock-rag-injection/README.md) → **range-05 · MCP Agent Compromise**

This is the series' second AI/agentic entry, and it deliberately changes two
things from [range-04](../range-04-bedrock-rag-injection/README.md) at once: a
different cloud (Azure instead of AWS) and a different trigger. Range-04's
injection rides in on a RAG document; this range has **no knowledge base and
no document store at all** — the injected instruction arrives through a
tool's own *output* (a support ticket's body), and the blast radius is an
**over-scoped user-assigned managed identity** sitting behind the agent's MCP
tool backend, the same class of least-privilege failure as range-04's
over-privileged Lambda role, one layer further from the model.

**Status: infrastructure and the primary chained attack are implemented and
`terraform validate` clean; this has not been applied against a live Azure
subscription in this environment** (no Azure credentials were available while
building it — see [`terraform/NOTES.md`](terraform/NOTES.md) for exactly what
was checked against the provider schema vs. what remains unverified). A
handful of `TODO (yours to complete)` items are left deliberately unfinished —
see [What's left](#whats-left-todo-yours-to-complete) below.

**Difficulty**: Medium
**Category**: AI / ML Security (agent & tool layer)
**Services**: Azure AI Foundry (Cognitive Services account + project), Azure OpenAI (tool/function-calling model deployment), Azure AI Content Safety (Prompt Shields), Azure Container Apps, Azure Container Registry, Azure Key Vault, Azure Storage, Managed Identity, Log Analytics
**Vulnerability classes**: Indirect Prompt Injection (tool-output), Overprivileged Managed Identity / Excessive Agency, Tool Description Poisoning, Confused Deputy, Rug Pull (tool definition mutation)

---

## Scenario Overview

An internal IT support agent is built on Azure AI Foundry. Its tools are
served by a standalone MCP server. The agent's **stated job** is narrow: look
up ticket status, and — per its one legitimate data tool — answer questions
from a single FAQ blob in storage. It never writes anything, and it never
touches Key Vault.

The agent's backing identity doesn't match that job:

```
[Attacker/support user]
    |
    | (1) Files or edits a ticket (TICKET-4017) containing a hidden
    |     "SYSTEM" instruction in its body
    v
[Mock ticket store]  <-- attacker-reachable, mutable field
    |
    | (2) Agent calls get_ticket_status("TICKET-4017") to help the user
    v
[MCP server tool output]  <-- agent treats this as trusted context,
    |                          nothing distinguishes "ticket text" from
    |                          "instructions"
    | (3) Injected instruction tells the agent to read a secret, silently
    v
[read_secret("internal-billing-db-connection-string")]
    |
    | (4) Real Azure Key Vault call, under the over-scoped managed identity
    v
[Key Vault]  <-- the agent's job never needed ANY Key Vault access
    |
    | (5) Injected instruction tells the agent to exfiltrate via notify()
    v
[notify(channel="TICKET-4017", message=<secret value>)]
    |
    | (6) Posted back as a comment on the SAME ticket the injection came from
    v
[Attacker re-reads TICKET-4017 -> secret value sitting in the comment thread]
```

No separate exfil infrastructure is needed: the attacker already controls
the ticket the secret gets posted back to.

---

## What this builds

- A **resource group** and a **user-assigned managed identity** (`identity.tf`)
  holding far more than its one job requires — see [The over-scoped identity](#the-over-scoped-identity-the-vulnerability) below.
- An **Azure AI Foundry account + project** (`ai_foundry.tf`) with a
  tool/function-calling-capable Azure OpenAI model deployment, and a custom
  **Prompt Shields** (Jailbreak + Indirect Attack) content-filter policy —
  toggleable between present-but-not-blocking and actively blocking via
  `var.enable_prompt_shields`.
- A **Key Vault** (`keyvault.tf`) holding one dummy secret
  (`internal-billing-db-connection-string`) the agent has no legitimate
  reason to ever read.
- A **storage account** (`storage.tf`) with two containers: `agent-tool-data`
  (the FAQ blob the agent's tool is actually supposed to read) and
  `sensitive-customer-records` (a fake customer export the over-scoped
  identity can also reach, read **and** write).
- A **Container App** (`container_app.tf`) that hosts the real MCP server
  (`../mcp-server`) with the over-scoped identity attached — this is where
  the vulnerability is actually exercised, not just documented — plus the
  Container Registry, Log Analytics workspace, and Container App
  Environment it needs.
- An **operator-IP allowlist** (`access.tf`) applied to the storage account,
  the Foundry account, and the Container App's ingress — deliberately **not**
  applied to Key Vault, since the only caller that matters there is the
  Container App's own outbound traffic, not the operator (see the comment in
  `keyvault.tf`).
- An **MCP server** (`../mcp-server/server.py`) exposing six tools: the
  three that make up the primary chained attack, plus three standalone
  tool-layer findings (below).
- An **orchestrator** (`../orchestrator/agent_loop.py`) that drives the
  tool-calling loop directly against the Foundry account's chat-completions
  endpoint and the real MCP server — see [Why no Agent Service](#why-this-skips-the-managed-agent-service) below.

No document store, no vector index, no RAG pipeline anywhere in this stack —
that's range-04's trigger, not this one.

---

## The over-scoped identity (the vulnerability)

`azurerm_user_assigned_identity.agent` is attached to the Foundry account
*and* to the Container App that runs the MCP server (the identity that's
actually exercised). It holds:

1. **`Key Vault Secrets User` on the whole vault** — every secret, not one
   scoped to a real need. The correctly-scoped answer is no Key Vault grant
   at all.
2. **`Storage Blob Data Contributor` — read *and* write — at the storage
   account scope**, not the one container (`agent-tool-data`) the tool
   actually reads. That one grant also reaches the sibling
   `sensitive-customer-records` container, with write/delete, when the tool
   only ever needs read access to one blob in one container.

This mirrors range-04's over-privileged Lambda execution role: least
privilege was skipped at design time "because the agent might need it
eventually," and the grant landed at the account/vault level instead of on
the one object the stated job touches. The trigger is different — range-04's
is a poisoned knowledge-base document; this range has no document store, so
the trigger is the agent's tool-calling path itself.

---

## The attack chain

1. **Tool-output injection (`get_ticket_status`)** — the agent treats a
   tool's returned text as trusted context, even though that text originates
   from a mutable, attacker-reachable source (a ticket anyone can file or
   edit). Nothing distinguishes "ticket text" from "instructions."
2. **Over-privileged tool (`read_secret`)** — the tool's *backing identity*,
   not the MCP protocol, is the least-privilege failure: it can resolve
   every secret in the vault, not one scoped to a real need.
3. **Exfil channel (`notify`)** — a plausible, innocuous-sounding tool
   ("send a notification") becomes the exfiltration step, posting the
   secret back onto the same ticket the injection came from.
4. **Prompt Shields as the (optional) control** — Azure AI Content Safety's
   Indirect Attack filter is wired in and defaults to blocking. The
   walkthrough runs the chain with it on (the realistic default) and off
   (`-var="enable_prompt_shields=false"`) so you can see what it actually
   catches.

### Three standalone findings (not part of the chained attack)

These demonstrate distinct tool-layer vulnerability classes on their own,
independent of the ticket-injection chain above — see
[`../mcp-server/HANDOFF.md`](mcp-server/HANDOFF.md) for how each is wired:

5. **`get_account_balance` — tool description poisoning.** The tool's
   *registered description* (not its implementation) carries a hidden
   `<!-- SYSTEM: ... -->` instruction block — the kind of text most MCP
   clients render straight into the model's context, unflagged, before the
   tool is ever called.
6. **`export_user_directory` — confused deputy.** Returns the full internal
   user directory with no caller-identity or authorization check at all.
   Calling it is indistinguishable from calling any other tool on the
   server.
7. **`schedule_meeting` / `perform_rug_pull()` — rug pull.** A tool's
   description (and, in a real deployment, its behavior) can be swapped out
   *after* it's been reviewed/approved, without its name or signature
   changing — the SDK's own `remove_tool()` / `add_tool()` make this one
   unremarkable extra call away, not a hack.

---

## Why this skips the managed Agent Service

As of this writing, the `azurerm` provider has no stable resource for the
Foundry **Agent object** itself
(`Microsoft.CognitiveServices/accounts/projects/agents`) or its tool/function
manifest — only for the account, project, model deployment, and
content-filter policy that back it. Creating the Agent object is a
documented Terraform gap (`ai_foundry.tf` has the `TODO`), not an oversight.

Rather than leave the scenario undemonstrable until that SDK/REST handoff is
verified reliable, [`orchestrator/agent_loop.py`](orchestrator/agent_loop.py)
drives the same tool-calling loop directly against the Foundry account's
standard chat-completions endpoint — a real Azure OpenAI model deciding to
call real MCP tools over `streamable-http`, exercising the exact same
over-scoped identity. See [`terraform/NOTES.md`](terraform/NOTES.md) for the
full writeup, including live reports of exactly this
Terraform-provisioned-project → Agents-SDK handoff failing on other
deployments.

---

## Scenario Start

Unlike ranges 01–04, this range has no separate low-privilege attacker
credential to hand you — the vulnerability under test is the identity behind
the agent's tool backend, not caller authentication to the agent (that gap
*is* its own standalone finding — see `export_user_directory` above). You act
as:

- whoever can file or edit a support ticket (in this scaffold, the injected
  ticket `TICKET-4017` is pre-seeded in `mock_data.py` — standing in for a
  ticket an attacker already filed, since no ticket-creation tool is
  exposed here), and
- the operator running `orchestrator/agent_loop.py`, which authenticates
  with your own Azure CLI login — you are never handed Key Vault or Storage
  access directly.

## Your Goal

Get the real Key Vault secret value (`internal-billing-db-connection-string`)
to show up as a comment on `TICKET-4017` — driven entirely by the agent
following the injected instruction when you ask it about that ticket, never
by calling `read_secret` or Key Vault yourself.

---

## Deploy

### Prerequisites
- Terraform >= 1.5.0
- Azure CLI, logged in (`az login`) with rights to create resource groups,
  Key Vault, Storage, Cognitive Services, and Container Apps resources in
  the target subscription.
- A region with Azure AI Foundry Agent Service, tool/function-calling model
  deployments, and the Content Safety `Indirect Attack` filter available —
  this range defaults to `eastus2` (`variables.tf`); re-check regional
  availability before changing it (see `terraform/NOTES.md`).
- Docker (or `az acr build`, which needs no local Docker) to build and push
  the real MCP server image — the first `apply` stands up a placeholder
  image so the stack applies cleanly before that's done.
- Python 3.11+ to run `orchestrator/agent_loop.py` locally.
- The identity you run the orchestrator as (your own `az login` identity)
  needs data-plane access to the model deployment — typically the
  `Cognitive Services OpenAI User` role on the Foundry account. This stack
  doesn't grant it, since that script stands in for the agent's caller, not
  part of the documented attack surface.

```bash
cd terraform
terraform init
terraform apply
```

The storage account, Foundry account, and Container App ingress are
auto-locked to your current public IP (via `data.http.my_ip`); override with
`-var='allowed_source_cidrs=["YOUR_IP/32"]'` if you're applying and walking
the chain from different networks. Key Vault is deliberately **not**
IP-restricted — see the comment in `keyvault.tf`.

### Build and push the real MCP server image

```bash
az acr build --registry $(terraform output -raw mcp_server_registry_name) \
  --image mcp-server:latest ../mcp-server

terraform apply \
  -var="mcp_server_image=$(terraform output -raw mcp_server_registry_name).azurecr.io/mcp-server:latest"
```

Until this runs, the Container App serves a public placeholder image and
`read_secret` is never actually reachable over the network.

### Collect the values the orchestrator needs

```bash
terraform output ai_foundry_account_endpoint
terraform output model_deployment_name
terraform output mcp_server_url
```

```bash
export AZURE_OPENAI_ENDPOINT=$(terraform output -raw ai_foundry_account_endpoint)
export AZURE_OPENAI_DEPLOYMENT=$(terraform output -raw model_deployment_name)
export MCP_SERVER_URL=$(terraform output -raw mcp_server_url)
```

## Verify / walk the chain

Work the chain end to end using the commands in
[`solution/walkthrough.md`](solution/walkthrough.md) — confirm benign tool
use, trigger the injection, and watch the secret leak into the ticket
thread.

---

## What's left (`TODO (yours to complete)`)

Left deliberately unfinished, same house convention as the other ranges'
stretch goals:

- **`storage.tf`** — ✅ `shared_access_key_enabled` is now `false`; the
  provider authenticates to the storage data plane via Azure AD
  (`storage_use_azuread` in `main.tf`, backed by a new deployer RBAC grant)
  instead of an account key. No shared key exists anywhere in this stack
  now, matching the Key Vault's posture.
- **`identity.tf`** — ✅ the *correctly*-scoped `Storage Blob Data Reader`
  grant (`agent_storage_read_scoped`, on `azurerm_storage_container.tool_data`
  alone) now exists alongside the over-scoped one, as a documented
  before/after. What's still yours to complete: comment out (or destroy)
  the over-scoped `agent_storage_readwrite` grant, re-apply, and re-run the
  walkthrough to show the tool still works on the scoped grant alone —
  true least privilege, demonstrated live. **Blocked on a known gap until
  then:** `storage.tf`'s network rule firewalls to the operator's IP with
  only an `AzureServices` bypass, which doesn't cover the Container App's
  own data-plane blob reads. The real fix (a dedicated subnet + storage
  service endpoint) is more involved than it looks — it needs the Container
  App Environment's workload-profile-vs-consumption-only type pinned down
  first (different subnet size *and* opposite delegation rules apply), and
  it adds a standing public-IP + load-balancer cost this range doesn't
  currently budget for. See `terraform/NOTES.md`, "Known gap," for exactly
  what was checked against current docs.
- **`ai_foundry.tf`** — create the actual Agent object + its one
  FAQ-lookup tool/function definition via the Foundry Agents SDK/REST API,
  once the Terraform side is applied.
- **`ai_foundry.tf`** — Private Endpoints + VNet integration for the Foundry
  account, matching the networking lockdown already done for ranges 01/02.
- **`orchestrator/agent_loop.py`** — swap the direct chat-completions loop
  for native Azure AI Foundry Agent Service + MCP tool-calling, once the
  IaC/SDK handoff above is verified reliable.

---

## Cost

**Low, but not literally zero while standing — unlike [range-03](../range-03-iam-privilege-escalation/README.md)/[range-04](../range-04-bedrock-rag-injection/README.md).**
Most of this stack is pay-per-use (Foundry model token billing, Key
Vault/Storage per-operation charges), but two pieces bill continuously once
deployed: the Container App is pinned to exactly one replica
(`min_replicas = 1`, `max_replicas = 1` — it never scales to zero, by design,
since the mock ticket/secret/comment state the walkthrough depends on is
in-memory and per-process), and the Container Registry (Basic SKU) carries a
small flat daily fee regardless of use. Tear down when you're done with a
session rather than leaving it standing between walkthroughs.

## Teardown

```bash
terraform destroy
```

---

## Solution

See [`solution/walkthrough.md`](solution/walkthrough.md) — but try it
yourself first.

---

## What this scenario demonstrates

1. Why tool *output*, not just tool *input*, is an untrusted-data boundary —
   indirect prompt injection doesn't need a document store to arrive through.
2. How an over-scoped identity behind a narrow-looking tool turns one
   injected instruction into a real secrets-management breach.
3. Why a tool's registered *description* is itself an attacker-reachable
   instruction channel, separate from its implementation.
4. The confused-deputy failure of a shared backend identity with no
   per-caller authorization check.
5. How a tool's definition can change out from under an approval decision
   made earlier (rug pull).
6. What Azure AI Content Safety's Prompt Shields (the Indirect Attack
   filter) does and doesn't catch, with the on/off comparison built in.

## Defensive Notes

The root causes that make this scenario possible:

1. **Over-scoped managed identity** — the agent's tool backend can read
   every Key Vault secret and read/write the whole storage account, when its
   stated job needs neither.
2. **No distinction between data and instructions in tool output** — the
   agent (and the system prompt it's given) trusts ticket text as context,
   not as untrusted, attacker-reachable input.
3. **No provenance or content validation on tool results** — nothing
   inspects what a tool returns before it re-enters the model's context.
4. **(Standalone) No authorization check at the tool-call boundary** — the
   MCP server trusts every caller equally (`export_user_directory`).
5. **(Standalone) Tool metadata is mutable and unverified** — both the
   registered description (`get_account_balance`) and the tool definition
   itself (`schedule_meeting`) can change after a trust decision was made,
   with nothing to detect it.

Any one of these mitigated independently reduces the risk; least privilege
on the identity (1) is the one that bounds the *blast radius* regardless of
whether the injection (2/3) is ever caught.
