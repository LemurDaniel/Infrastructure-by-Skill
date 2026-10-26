# Infrastructure by Skill

> Short, deterministic runbooks for the infrastructure work that does **not** belong in
> Terraform, rendered from a reviewed spec into PowerShell or Bash.

---

# ⚠️ ⚠️ ⚠️  PROTOTYPE WARNING  ⚠️ ⚠️ ⚠️

> ## 🚧 THIS IS A CONCEPT. NOTHING HERE IS BUILT, NONE OF IT IS PRODUCTION-READY. 🚧
>
> **What that means in practice:**
>
> - 🧪 **An experiment, not a product.** This repo explores whether imperative ops work can be captured as a spec and rendered into scripts you can trust. The answer is still open.
> - 📝 **Concept stage.** The spec format, the renderer and the templates below are a design, not code. Nothing in this README can be run yet.
> - 💥 **Runbooks change real systems.** There is no state and no `terraform destroy`. A rendered script that rotates, deletes or fails over does exactly that.
> - 🔒 **Never against production.** Dev and staging. Prod only with a second human approval, and even then at your own risk.
> - 👀 **Not an autopilot.** Every mutating step has an approval gate. Anyone who passes `-Confirm:$false` without reading the plan has missed the point.
> - 📉 **Everything can change.** Spec format, step kinds, templates, protocol format. No stability guarantees, no migration paths, no versioning.
> - 🙅 **No warranty, no support.** Use at your own risk.
>
> **If it is desired state: use Terraform. Use Bicep. Use Pulumi. A runbook is not a substitute for IaC.**

---

## Why

Terraform describes what *should exist*. A lot of infrastructure work is not that. It is
something that has to *happen*, once or on a schedule:

- rotate a Key Vault secret, swap an App Gateway certificate
- drain an AKS node pool, trigger a Cosmos DB failover
- purge soft-deleted resources, re-run a stuck deployment
- create a user in a SaaS admin API, set a DNS record at a provider without a Terraform provider

Today that lives in ad-hoc scripts, wiki pages and shell history. Every one of them is
written differently, half of them have no dry run, and none of them leave a record.

This repo gives that work one shape: a **spec** that is reviewed, a **renderer** that
turns it into a script, and a **protocol** for every run.

## Scope

| | Terraform / Bicep | Infrastructure by Skill |
|---|---|---|
| Describes | desired state | an **operation** |
| Typical work | VNet, AKS, Key Vault | rotate, swap, drain, purge, failover, onboard |
| State | state file, drift detection | none: each step checks the live state itself |
| Plan | `terraform plan` | `-WhatIf` / `--dry-run` |
| Result | reproducible infrastructure | reproducible operation, recorded in `runs/` |

**Order of preference:** Terraform > API runbook > guided manual step. A runbook is the
answer to "this is an action, not a state", never to "Terraform feels like too much
work".

## Core idea

```
runbook.yaml  ──►  renderer (template-based)  ──►  <name>.ps1 / <name>.sh  ──►  run  ──►  runs/<protocol>.md
  reviewed           deterministic                   generated, committed      gated
```

1. **The spec is the source of truth.** It is what humans write and review.
2. **The renderer is deterministic.** A PowerShell module with one template per target
   and step kind. Same spec + same renderer version → byte-identical script. No LLM in
   the render path.
3. **The script is a build artefact.** Committed, never edited by hand. Its header
   carries the spec hash and the renderer version; CI re-renders and fails on a diff.
4. **The skill helps author specs.** Claude carries the API knowledge, the pitfalls and
   the rollback, writes the spec, validates it against the schema and calls the
   renderer. It does not write the script and it does not execute anything.

That moves the LLM from *runtime* to *authoring time*: what runs is a plain script that
was reviewed and behaves the same on every run.

## Spec (draft)

```yaml
apiVersion: runbook/v1
name: keyvault-rotate-secret
description: Rotate a secret and set a new expiry date
environments: [dev, staging]        # prod requires a second approval
targets: [pwsh, bash]               # pwsh is mandatory, bash optional
runtimes: [local, pipeline, automation]

inputs:
  vaultName:     { type: string, pattern: '^[a-z0-9-]{3,24}$' }
  secretName:    { type: string }
  expiresInDays: { type: int, default: 90 }

auth:
  provider: azure                   # azure | bearer | basic | none
  scope: https://vault.azure.net/.default

steps:
  - id: read
    kind: http
    request: GET https://{vaultName}.vault.azure.net/secrets/{secretName}?api-version=7.4
    capture: { currentVersion: $.id }

  - id: rotate
    kind: http
    mutating: true                  # → plan entry + approval gate
    request: PUT https://{vaultName}.vault.azure.net/secrets/{secretName}?api-version=7.4
    body:
      value: '{{ random.password(32) }}'
      attributes: { exp: '{{ now + expiresInDays.days }}' }
    sensitive: [body.value]         # never printed, never in the protocol

  - id: verify
    kind: http
    request: GET https://{vaultName}.vault.azure.net/secrets/{secretName}?api-version=7.4
    assert: $.id != currentVersion

rollback:
  - note: The previous version stays in Key Vault; re-enable {currentVersion} if needed
```

### Building blocks

| Element | Purpose |
|---|---|
| `inputs` | Typed and validated before anything runs; rendered as `param()` with validation attributes or as Bash argument parsing |
| `targets` / `runtimes` | Which scripts are rendered and where they may run. The renderer rejects combinations that cannot work (see below) |
| `auth.provider` | Where the token comes from: `azure` (Entra ID), `bearer` and `basic` for third-party APIs, `none` |
| `steps[].kind` | What a step does. Each kind is one template per target |
| `mutating` | Marks a step that changes something: it appears in the plan and gets an approval gate |
| `capture` / `assert` | Read values from a response, check them later. A restricted JSONPath subset |
| `sensitive` | Fields the renderer masks in output and protocol |
| `rollback` | What to do if a later step fails. Notes, steps, or both |

### Step kinds (proposal)

| Kind | Content |
|---|---|
| `http` | Generic REST call. The first and most important kind |
| `manual` | A step that has no API: the script prints the instructions, waits for the human, records the confirmation. What is left of the original ClickOps idea. **Interactive only:** a spec with a `manual` step may only declare `runtimes: [local]` |
| `wait` | Poll until a condition holds or a timeout hits (e.g. a long-running Azure operation) |

### Expression language

Deliberately small, so the renderer can stay deterministic and both targets can support
all of it:

- `{name}`: interpolate an input or a captured value
- `$.path`: JSONPath subset for `capture` and `assert`
- `{{ ... }}`: a fixed list of functions (`random.password(n)`, `now`, `+ n.days`, …).
  Anything not on the list is a schema error, not a template guess.

## The six phases, built into every rendered script

The phases no longer live in each skill's prose. The renderer emits them, so every
script has them:

| # | Phase | In the rendered script |
|---|---|---|
| 1 | **Preparation** | Validate inputs, check the environment against `environments`, acquire the token |
| 2 | **Plan** 🛑 | `-WhatIf` / `--dry-run`: run the read steps, list every mutating step with its target, print the **plan hash** |
| 3 | **Execution** | Steps in order; each one checks the live state first and skips if already done |
| 4 | **Checkpoint** 🛑 | Interactive: confirmation before each mutating step. Non-interactive: the run requires the approved plan hash (see below) |
| 5 | **Verification** | The `assert` steps |
| 6 | **Protocol** | Write the run to `runs/`: inputs (masked), plan, approvals, results, spec hash |

On a failed step the script stops, runs the `rollback`, and writes the protocol anyway.

### Approval gate: the plan hash

One gate that works the same in every runtime:

1. The **plan run** executes the read steps and prints the plan: every mutating step with
   its resolved target and the values it will write (sensitive ones masked). It also
   prints a hash over that plan.
2. A human reviews the plan and approves it: in the console, as a pipeline approval, or
   by handing the hash to the Automation job.
3. The **apply run** requires `-ApprovedPlanHash` (`--approved-plan-hash`). It builds the
   plan again from the live state and **aborts if the hash differs**: something changed
   between review and execution, so what was approved is not what would run.

Interactive local runs may skip the hash and confirm each mutating step instead.
Pipeline approvals and environment protection come on top; they do not replace the hash.

## Targets

| Target | Requires | Plan flag | Gate |
|---|---|---|---|
| `pwsh` | PowerShell 7 | `-WhatIf` | `SupportsShouldProcess` / `-ApprovedPlanHash` |
| `bash` | `curl`, `jq` | `--dry-run` | `read -p` / `--approved-plan-hash` |

**pwsh first.** Every step kind must exist as a pwsh template; the bash template follows
when needed. A spec lists its `targets`, and the renderer refuses a target that has no
template for one of the spec's step kinds.

## Runtimes

| Runtime | Targets | Auth | Gate |
|---|---|---|---|
| `local` | pwsh, bash | Azure CLI / `Connect-AzAccount`, env vars for third-party | console confirmation or plan hash |
| `pipeline` (GitHub Actions, Azure DevOps) | pwsh, bash | OIDC / workload identity federation, pipeline secrets | plan job → approval → apply job with plan hash |
| `automation` (Azure Automation) | **pwsh only** | managed identity, Automation credentials or Key Vault | plan hash as job parameter |

The renderer checks the combination: `bash` with `automation`, or `manual` with anything
but `local`, is a spec error.

## Repository layout (planned)

```
Infrastructure-by-Skill/
├── README.md                     # this document
├── CONVENTIONS.md                # spec rules, phase contract, protocol format
├── schema/
│   └── runbook-spec.schema.json  # validates every runbook.yaml
├── renderer/                     # PowerShell module: spec → script
│   ├── templates/
│   │   ├── pwsh/                 # one template per step kind
│   │   └── bash/
│   └── tests/                    # golden files: spec in, expected script out
├── runbooks/
│   └── <system>-<action>/        # e.g. keyvault-rotate-secret
│       ├── runbook.yaml          # the spec, reviewed
│       └── dist/                 # generated, committed, never edited by hand
│           ├── <name>.ps1
│           └── <name>.sh
├── .claude/skills/               # authoring skill: write specs, validate, render
└── runs/                         # one protocol per execution
```

- **Naming scheme `<system>-<action>`**, so runbooks stay grouped by system.
- **`dist/` is committed.** The review covers the spec; the diff in `dist/` shows what
  the renderer made of it.
- **`runs/` is versioned** (or written to a separate audit repo):
  `runs/<date>_<runbook>_<ticket>.md`.

## Guardrails

| Topic | Rule |
|---|---|
| **Credentials** | Tokens at runtime only (Azure CLI / managed identity / env var). Never in the spec, never in `dist/`, never in a protocol |
| **Destructive actions** | Delete, overwrite and force are `mutating` and get their own gate. The renderer refuses to emit a mutating step without one |
| **Environments** | Each spec declares its allowed environments; prod only with a second approval |
| **Determinism** | No LLM in the render path. CI re-renders every spec and fails on a diff in `dist/` |
| **Audit** | Every run writes a protocol to `runs/` |
| **Idempotence** | Every mutating step checks the live state first. A second run of the same script changes nothing |

## Decisions

| Topic | Decision | Why |
|---|---|---|
| **Scope** | Azure and third-party APIs | `auth.provider` (`azure`, `bearer`, `basic`) keeps the step kinds API-agnostic |
| **Runtimes** | local, pipeline, Azure Automation | Same script everywhere; the gate is the plan hash, not the runtime |
| **Spec format** | YAML, parsed with `powershell-yaml` | Readable and reviewable, comments allowed |
| **Template engine** | Own mini engine: template files with fixed placeholders, no code in templates | Determinism and a small surface that golden-file tests can cover |
| **`manual` steps** | Kept, local runtime only | Covers the API-less step without an LLM clicking |
| **Bash** | pwsh first, bash follows per step kind | Automation is pwsh-only, and pwsh is the main tool |
| **Gate** | Approved plan hash | One mechanism for every runtime; aborts if the live state changed after review |

## Open questions

- **Secrets for third-party auth:** where `bearer` / `basic` credentials come from in
  each runtime (env var, Key Vault reference, Automation credential), and how the spec
  refers to them without containing them.
- **Plan hash contents:** exactly what goes in (resolved targets, values to write, masked
  values?) so that it is stable across runs but catches real drift.
- **Mini-engine syntax:** placeholder syntax, loops over steps, escaping per target.
- **First scenario:** which runbook the PoC is built on.

## State of the concept

Goal: one runbook, rendered to pwsh, run cleanly three times in dev, with a protocol
each time.

- [x] Concept: spec → template renderer → script (this README)
- [x] Core decisions (see *Decisions*)
- [ ] Settle the remaining open questions
- [ ] Write `CONVENTIONS.md` and `schema/runbook-spec.schema.json`
- [ ] Pick a first scenario: frequent, low-risk, with a dev environment
- [ ] Write its `runbook.yaml`
- [ ] Renderer: `http` step kind for `pwsh`, golden-file tests
- [ ] Run in dev: plan, rejection at a gate, plan-hash mismatch, real run, rerun (must be a no-op)
- [ ] Check the protocol for traceability
- [ ] Authoring skill: Claude writes and validates specs, calls the renderer
- [ ] Optional: `bash` templates for the same step kinds

Until that list is checked off, the warning at the top applies in full.
