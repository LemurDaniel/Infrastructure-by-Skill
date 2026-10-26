# Infrastructure by Skill

> Guided, executable runbooks for infrastructure that **cannot** be rolled out with IaC.

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

There is infrastructure that has no Terraform module and never will: vendor portals,
legacy appliances, firewall and network GUIs, SaaS admin consoles, government portals.
That is where ClickOps happens — from memory, from wiki screenshots taken in 2021, from
the colleague who did it last time.

This repo does not try to define that gap away. It tries to document it — in a form an
agent can execute and a human can review.

## Scope

| | IaC (Terraform, Pulumi, Ansible) | Infrastructure by Skill |
|---|---|---|
| Precondition | There is an API | There is **no** API |
| Execution | deterministic, idempotent | best effort, GUI-dependent |
| Safety net | state, plan, drift detection | human approval gates |
| Result | reproducible | recorded |

**IaC remains the first choice.** A skill is the answer to "there is nothing else here",
not to "Terraform feels like too much work". If a module exists, the skill does not
apply — every `SKILL.md` says so under *When NOT to use*.

## Division of labour

- **The skill carries the knowledge**: order of steps, click path, pitfalls, rollback.
- **Execution** runs through browser control or computer use; deterministic sub-steps
  through the scripts shipped with the skill.
- **The human approves** — at fixed gates, not by feel.

Expect a copilot with approval gates. Captchas and MFA interrupt any automation; there
the human takes over briefly and hands back.

## Repository layout

```
Infrastructure-by-Skill/
├── README.md                  # this document
├── CONVENTIONS.md             # mandatory phases, checkpoint rules, protocol format
├── _templates/
│   └── SKILL.md               # template for new skills
├── _shared/
│   ├── checkpoint.md          # standard wording for approval steps
│   ├── protocol-template.md   # structure of an execution protocol
│   └── scripts/               # shared helpers (validation, logging)
├── <system>-<action>/         # e.g. firewall-add-rule, portal-create-user
│   ├── SKILL.md               # procedure, click path, pitfalls
│   ├── inputs.schema.json     # expected inputs + validation
│   ├── scripts/               # deterministic sub-steps (optional)
│   ├── reference/             # GUI screenshots, known error messages
│   └── state/                 # desired state as YAML (optional, for drift checks)
└── runs/                      # one protocol per execution
```

- **Naming scheme `<system>-<action>`**, so skills stay grouped by system.
- **`runs/` is versioned** (or written to a separate audit repo), so there is a git log
  of the manual changes: `runs/<date>_<skill>_<ticket>.md`.
- **`reference/` pins the expected state of the GUI.** If the interface deviates, the
  skill stops and asks.

## The six phases

Every skill runs the same six phases. **Phase 2 and phase 4 are mandatory stops** where
a human approves.

| # | Phase | Content |
|---|---|---|
| 1 | **Preparation** | Collect inputs and validate them against `inputs.schema.json`, check environment and access |
| 2 | **Plan** 🛑 | List the intended changes and **wait for approval** |
| 3 | **Execution** | Work through the click path, step by step |
| 4 | **Checkpoint** 🛑 | Before the writing step: show a screenshot, **wait for approval**, then save |
| 5 | **Verification** | Reload the page, check the values, run a functional test |
| 6 | **Protocol** | Write the run to `runs/`: planned, approved, executed, verified |

If a checkpoint is rejected, the skill corrects the step in the GUI and presents it for
approval again. It does not move on and it does not decide on its own.

## Guardrails

The full rules belong in `CONVENTIONS.md` (not written yet) and will then apply to every
skill in the repo.

| Topic | Rule |
|---|---|
| **Credentials** | Least privilege, short-lived tokens or dedicated service accounts where possible, no admin keys in the skill |
| **Destructive actions** | Delete, overwrite and force are always a separate confirmation step, hard-wired into the skill |
| **Environments** | Each skill declares which environments are allowed; prod only with a second approval |
| **Audit** | Every run writes a protocol to `runs/` |
| **GUI deviation** | If the interface deviates from `reference/`, the skill stops and asks |
| **Limits** | Captchas and MFA interrupt the run; the human takes over briefly and hands back |

## Adding a skill

1. Check the scenario: is there really no API? If there is — use IaC.
2. Create the folder `<system>-<action>/`.
3. Walk the click path **manually once**, put the screenshots in `reference/`.
4. Copy `_templates/SKILL.md`, fill it in, add the pitfalls you hit.
5. Write `inputs.schema.json` for the inputs.
6. Run it in dev, test the checkpoints — **including a rejection**.
7. Review the protocol: could a third party tell what was changed?

## State of the PoC

Goal: a single skill that runs one real ClickOps scenario cleanly three times, with a
protocol each time.

- [ ] Pick a scenario: frequent, low-risk, with a dev or staging environment
- [ ] Repo scaffolding: `README.md`, `CONVENTIONS.md`, `_templates/`, `_shared/`, `runs/`
- [ ] Walk the click path manually, screenshots to `reference/`
- [ ] Write `SKILL.md` from the template
- [ ] Write `inputs.schema.json`
- [ ] Load the skill in Claude, run it in dev, test the checkpoints (including rejection)
- [ ] Check the protocol for traceability
- [ ] Capture lessons learned, sharpen the template
- [ ] Optional: desired state as YAML in `state/`, a second skill for the drift check

Until that list is checked off, the warning at the top applies in full.
