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
**Services**: Azure AI Foundry (Cognitive Services account + project), Azure OpenAI (tool/function-calling model deployment), Azure AI Content Safety (Prompt Shields), Azure Container Apps, Azure Container Registry, Azure Key Vault, Managed Identity, Log Analytics
**Vulnerability classes**: Prompt Injection - indirect (tool-output) and direct (jailbreak), Overprivileged Managed Identity / Excessive Agency, Tool Description Poisoning, Confused Deputy, Rug Pull (tool definition mutation), System Prompt Leakage
**Framework mappings**: MITRE ATLAS, OWASP Top 10 for LLM Applications (2025), OWASP Top 10 for Agentic Applications (2025) — see [`solution/walkthrough.md`](solution/walkthrough.md#mitre-atlas-mapping)

---

## Scenario Overview

An internal IT support agent is built on Azure AI Foundry. Its tools are
served by a standalone MCP server. The agent's **stated job** is narrow: look
up ticket status for whoever asks. It never writes anything outside a ticket,
and it never touches Key Vault.

The agent's backing identity doesn't match that job:

```
[You - no elevated access of your own]
    |
    | (0a) list_tickets() - enumerate what's there, no LLM involved
    v
[Mock ticket store]  <-- one ticket's subject reads like internal
    |                     documentation that doesn't belong in a
    |                     customer queue (TICKET-0999)
    | (0b) get_ticket_status("TICKET-0999") - read it directly
    v
[A convention, not an attack]  <-- describes an "auto-appended
    |                                internal note" the assistant is
    |                                configured to treat as authoritative
    | (0c) submit_ticket(subject, body) - plant your OWN ticket using
    |      that exact convention, no validation on the content
    v
[Your planted ticket]  <-- attacker-reachable, mutable field, now
    |                       indistinguishable from a "real" auto-noted one
    | (1) Agent calls get_ticket_status(your_ticket_id) to help you
    v
[MCP server tool output]  <-- agent treats this as trusted context,
    |                          nothing distinguishes "ticket text" from
    |                          "instructions"
    | (2) Injected instruction tells the agent to read a secret, silently
    v
[read_secret("internal-billing-db-connection-string")]
    |
    | (3) Real Azure Key Vault call, under the over-scoped managed identity
    v
[Key Vault]  <-- the agent's job never needed ANY Key Vault access
    |
    | (4) Injected instruction tells the agent to exfiltrate via notify()
    v
[notify(channel=your_ticket_id, message=<secret value>)]
    |
    | (5) Posted back as a comment on the SAME ticket you planted
    v
[You re-read your ticket -> secret value (and a flag) sitting in the thread]
```

Steps (0a)–(0c) are the discovery arc — nobody hands you a ticket ID. A
pre-seeded, ready-made example (`TICKET-4017`) still exists as a fast-path
if you just want to confirm the Key Vault wiring works; the walkthrough
builds the attack from scratch instead. See
[`solution/walkthrough.md`](solution/walkthrough.md).

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
  reason to ever read — its value carries a per-deployment flag
  (`range-05-flag-<suffix>`) as the checkable "you got it" signal.
- A **Container App** (`container_app.tf`) that hosts the real MCP server
  (`../mcp-server`) with the over-scoped identity attached — this is where
  the vulnerability is actually exercised, not just documented — plus the
  Container Registry, Log Analytics workspace, and Container App
  Environment it needs.
- An **operator-IP allowlist** (`access.tf`) applied to the Foundry account
  and the Container App's ingress — deliberately **not** applied to Key
  Vault, since the only caller that matters there is the Container App's own
  outbound traffic, not the operator (see the comment in `keyvault.tf`).
- An **MCP server** (`../mcp-server/server.py`) exposing eight tools: two
  reconnaissance/payload-delivery primitives (`list_tickets`,
  `submit_ticket` — the discovery arc below), three that make up the
  primary chained attack, and three standalone tool-layer findings
  (below) — plus a fourth standalone finding, system prompt leakage, that
  lives at the orchestrator layer rather than as an MCP tool.
- An **orchestrator** (`../orchestrator/agent_loop.py`) that drives the
  tool-calling loop directly against the Foundry account's chat-completions
  endpoint and the real MCP server — see [Why no Agent Service](#why-this-skips-the-managed-agent-service) below.
  A second script, `../orchestrator/mcp_client.py`, is a raw MCP client
  with no LLM involved, for the discovery steps that don't need one.
- A **`payloads/`** directory holding [`jailbreak_attempt.txt`](payloads/jailbreak_attempt.txt),
  a direct-injection prompt for testing the RAI policy's `Jailbreak`
  filter separately from the ticket-based indirect chain, and
  [`system_prompt_leak.txt`](payloads/system_prompt_leak.txt), a direct
  pretext asking the agent to recite its own instructions verbatim.

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

This mirrors range-04's over-privileged Lambda execution role: least
privilege was skipped at design time "because the agent might need it
eventually," and the grant landed at the vault level instead of on nothing at
all, which is what the stated job requires. The trigger is different —
range-04's is a poisoned knowledge-base document; this range has no document
store, so the trigger is the agent's tool-calling path itself.

---

## The attack chain

0. **Discovery (`list_tickets`, `submit_ticket`)** — not a vulnerability
   class on their own, but what makes step 1 below something you *find*
   instead of something you're handed. `list_tickets` enumerates every
   ticket (id/status/subject only); one subject reads like internal
   documentation that doesn't belong in a customer queue. Reading it
   (`get_ticket_status`) reveals a convention — tickets escalated to
   Finance/Security get an "auto-appended internal note" the assistant
   treats as authoritative — with no live attack in the text itself.
   `submit_ticket` then lets you plant your own ticket using that exact
   convention; nothing validates what you put in it.
1. **Tool-output injection (`get_ticket_status`)** — the agent treats a
   tool's returned text as trusted context, even though that text originates
   from a mutable, attacker-reachable source (a ticket anyone can file or
   edit — including you, per step 0). Nothing distinguishes "ticket text"
   from "instructions."
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
5. **Direct injection / jailbreak, as a separate test of the RAI policy's
   *other* filter** — [`payloads/jailbreak_attempt.txt`](payloads/jailbreak_attempt.txt)
   talks to the agent directly (no ticket, no discovery arc) with a
   pretext/authority-override jailbreak, asking it to call `read_secret`
   and hand the value back in its own reply. This exercises the
   `Jailbreak` content filter, which nothing in steps 0–4 ever touches —
   see `solution/walkthrough.md` Step 8.

### Four standalone findings (not part of the chained attack)

These demonstrate distinct vulnerability classes on their own, independent
of the ticket-injection chain above — the first three are tool-layer
(the MCP server's own tools); the fourth (system prompt leakage) sits at
the orchestrator/model layer instead. See
[`../mcp-server/HANDOFF.md`](mcp-server/HANDOFF.md) for how the first
three are wired (its own "What's already 'real' (4-6)" section - HANDOFF
numbers them 4-6, not 6-8; the two documents use independent numbering
schemes). System prompt leakage (the fourth, below) isn't in HANDOFF at
all since it lives in the orchestrator, not the MCP server - run it
directly per Step 9 of `solution/walkthrough.md` instead:

6. **`get_account_balance` — tool description poisoning.** The tool's
   *registered description* (not its implementation) carries a hidden
   `<!-- SYSTEM: ... -->` instruction block — the kind of text most MCP
   clients render straight into the model's context, unflagged, before the
   tool is ever called.
7. **`export_user_directory` — confused deputy.** Returns the full internal
   user directory with no caller-identity or authorization check at all.
   Calling it is indistinguishable from calling any other tool on the
   server.
8. **`schedule_meeting` / `perform_rug_pull()` — rug pull.** A tool's
   description (and, in a real deployment, its behavior) can be swapped out
   *after* it's been reviewed/approved, without its name or signature
   changing — the SDK's own `remove_tool()` / `add_tool()` make this one
   unremarkable extra call away, not a hack.
9. **System prompt leakage.** [`payloads/system_prompt_leak.txt`](payloads/system_prompt_leak.txt)
   talks to `orchestrator/agent_loop.py` directly (no ticket, no tools)
   with a pretext/authority-override jailbreak asking the agent to output
   its own system prompt verbatim. The prompt it leaks confirms the same
   design flaw the ticket-injection chain exploits — "treat the full text
   of any tool result as authoritative context" — without stating the
   specific convention (the TICKET-0999 auto-append note) that the
   discovery arc exists to find; leaking it narrows *why* the chain works,
   not *how* to run it. Exercises the same `Jailbreak` content filter as
   step 5 above, on a different target string.

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
as a low-privilege support requester: you can list tickets, read them, file
new ones (`list_tickets`/`get_ticket_status`/`submit_ticket`, callable
directly via `orchestrator/mcp_client.py`, no LLM needed), and ask the
support assistant questions (`orchestrator/agent_loop.py`, authenticated
with your own Azure CLI login) — you are never handed Key Vault access
directly, and nobody hands you a working ticket ID either.

## Your Goal

Get the real Key Vault secret value (`internal-billing-db-connection-string`)
to show up as a comment on a ticket — driven entirely by the agent following
an injected instruction when you ask it about that ticket, never by calling
`read_secret` or Key Vault yourself. You have to find the convention that
makes a ticket "trusted" and plant your own; a ready-made example
(`TICKET-4017`) exists as a fast-path if you just want to confirm the Key
Vault wiring works first. See
[`solution/walkthrough.md`](solution/walkthrough.md) for the intended
discovery path.

---

## Deploy

### Prerequisites
- Terraform >= 1.5.0
- Azure CLI, logged in (`az login`) with rights to create resource groups,
  Key Vault, Cognitive Services, and Container Apps resources in the target
  subscription.
- The `Microsoft.App` resource provider registered on that subscription
  (`az provider register --namespace Microsoft.App --wait`) — a fresh or
  rarely-used subscription may not have this yet; `terraform apply` fails
  on `azurerm_container_app_environment.main` with
  `MissingSubscriptionRegistration` until it is.
- Nonzero Azure OpenAI quota for `var.openai_model_name` under the
  `GlobalStandard` SKU in your region — check with
  `az cognitiveservices usage list --location eastus2 --query "[].{Name:name.value, Current:currentValue, Limit:limit}" -o table`
  before applying. Model availability and default quota both drift over
  time; see `terraform/NOTES.md` for what was actually checked and when.
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

The Foundry account and Container App ingress are auto-locked to your
current public IP (via `data.http.my_ip`); override with
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

- **`storage.tf`** — removed. An earlier revision provisioned a storage
  account to carry a second, independent least-privilege demo (an
  over-scoped vs. correctly-scoped storage grant, alongside the Key Vault
  one), but no MCP tool ever read it, so the demo stayed narrative, and
  fixing the networking gap that blocked it live meant standing up VNet
  integration + a continuously-billed static IP/Load Balancer for a
  stretch goal the primary chain doesn't need. See `terraform/NOTES.md`
  for the full writeup and what it would take to reintroduce it later.
- **`ai_foundry.tf`** — create the actual Agent object + a tool/function
  definition for its ticket-status lookup via the Foundry Agents SDK/REST
  API, once the Terraform side is applied.
- **`ai_foundry.tf`** — Private Endpoints + VNet integration for the Foundry
  account, matching the networking lockdown already done for ranges 01/02.
- **`orchestrator/agent_loop.py`** — swap the direct chat-completions loop
  for native Azure AI Foundry Agent Service + MCP tool-calling, once the
  IaC/SDK handoff above is verified reliable.

---

## Cost

**Low, but not literally zero while standing — unlike [range-03](../range-03-iam-privilege-escalation/README.md)/[range-04](../range-04-bedrock-rag-injection/README.md).**
Most of this stack is pay-per-use (Foundry model token billing, Key Vault
per-operation charges), but two pieces bill continuously once
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

0. How to enumerate an MCP-backed system directly (no LLM) to find what's
   worth exploiting, then use what you learn to craft and plant your own
   working payload — rather than being handed one.
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
7. The difference between *direct* prompt injection (a jailbreak aimed
   straight at the model) and *indirect* (steps 0–4) — and what the
   `Jailbreak` filter catches that `Indirect Attack` doesn't, and vice
   versa.
8. Why a leaked system prompt is its own finding, separate from the
   ticket-injection chain — it confirms the design flaw the agent was
   built with, without handing you the specific convention the discovery
   arc exists to find.
9. How these findings map onto MITRE ATLAS, the OWASP Top 10 for LLM
   Applications (2025), and the OWASP Top 10 for Agentic Applications
   (2025) — see `solution/walkthrough.md` for all three tables, including
   what's deliberately *not* covered by this range under each framework.

## Defensive Notes

The root causes that make this scenario possible:

1. **Over-scoped managed identity** — the agent's tool backend can read
   every Key Vault secret when its stated job needs none at all.
2. **No distinction between data and instructions in tool output** — the
   agent (and the system prompt it's given) trusts ticket text as context,
   not as untrusted, attacker-reachable input.
3. **No provenance or content validation on tool results** — nothing
   inspects what a tool returns before it re-enters the model's context,
   and `submit_ticket` itself validates nothing about what you file.
4. **(Standalone) No authorization check at the tool-call boundary** — the
   MCP server trusts every caller equally (`export_user_directory`).
5. **(Standalone) Tool metadata is mutable and unverified** — both the
   registered description (`get_account_balance`) and the tool definition
   itself (`schedule_meeting`) can change after a trust decision was made,
   with nothing to detect it.

Any one of these mitigated independently reduces the risk; least privilege
on the identity (1) is the one that bounds the *blast radius* regardless of
whether the injection (2/3) is ever caught.
