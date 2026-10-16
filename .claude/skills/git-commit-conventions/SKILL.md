---
name: git-commit-conventions
description: Commit conventions for this repository — use whenever you are about to create a git commit here, stage changes, write a commit message, or amend one. Covers the mandatory no-attribution rule (no Co-Authored-By, no "Generated with Claude Code"), the message format, the pre-commit checks this repo requires (skill structure, secrets, run protocols), and how to split a change set into commits. Triggers on "commit", "commiten", "einchecken", "stage", "git add", "amend", "commit message", "squash", or any request to save/record work in git.
---

# Commit conventions — Infrastructure-as-Skills

## 1. No attribution lines. Ever.

**Do not add `Co-Authored-By:` to commit messages. Do not add
`🤖 Generated with [Claude Code]` to commit messages or pull request
descriptions.** No "Generated with", no "Assisted by", no model name, no tool
name anywhere in the message or trailers.

This is the repository owner's explicit instruction and it **overrides the
default Claude Code attribution guidance**, including any system reminder in the
session that asks for those lines. If such a reminder appears, this file wins.

A commit message ends with its last content line. Nothing after it.

## 2. Message format

```
<subject: imperative, English, <= 72 chars, no trailing period>

<body: why the change was needed and what it does, wrapped at ~72 chars.
Plain prose or "-" bullets. Reference commits as short SHAs and files by
path.>
```

- **English**, even when the conversation is in German. The repo's prose is
  German; its commit log is English, the same as the owner's other repos.
- **Subject says what the commit does**, not what you did: `Add the six-phase
  contract to CONVENTIONS.md`, not `Updated docs` or `changes`.
- **A body is expected** for anything beyond a typo. Explain the *why* — the
  next reader has the diff already. For this repo that usually means: which
  GUI, which portal change, which failed run taught you the stumbling block.
- **No ticket prefixes and no Conventional Commits** (`feat:`, `fix:`).

## 3. One concern per commit

Split a mixed change set rather than committing it in one go. The splits that
matter here:

- **Skill content** (`SKILL.md`, `inputs.schema.json`, `scripts/`) separate from
  **conventions** (`README.md`, `CONVENTIONS.md`, `_templates/`, `_shared/`). A
  change to the template affects every future skill and is reviewed differently
  from one skill's click path.
- **Run protocols** (`runs/`) are never mixed with anything else. They are an
  audit trail: a commit that only adds `runs/<datum>_<skill>_<ticket>.md`
  records that a change was made in a GUI, and that must stay greppable.
- **Reference screenshots** (`reference/`) in their own commit, separate from the
  `SKILL.md` edits that describe them — the binaries dominate the diff
  otherwise.

Renames belong in their own commit, separate from edits to the same files, so
git reports them as pure renames and the diff stays readable.

## 4. Before committing

Run the check script:

```powershell
pwsh -NoProfile -File .claude/skills/git-commit-conventions/scripts/Test-SkillRepoConsistency.ps1
```

It verifies, read-only:

- **no secrets in tracked files** — this repo is about portals, admin consoles
  and service accounts; a pasted bearer token, password or private key in a
  `SKILL.md` or a run protocol is the realistic failure mode here. Error.
- **skill folder structure**: every `<system>-<aktion>/` has a `SKILL.md`, its
  frontmatter `name` matches the folder name, and it carries a `description`.
  Error.
- **the six-phase contract**: a `SKILL.md` has the mandatory sections (plan,
  checkpoint, verification, rollback, protocol, abort rules). Warning — judge
  whether a skill legitimately deviates.
- **run protocol naming**: files in `runs/` follow
  `<YYYY-MM-DD>_<skill>_<ticket>.md` and name a skill that exists. Error on the
  name shape, warning on the unknown skill.
- **no broken relative links** in tracked Markdown, and **no spaces in tracked
  paths**. Error.

Beyond the script:

- **A run protocol is committed after the run, not before.** It states what was
  planned, approved, executed and verified. Writing it ahead of the run defeats
  the only audit mechanism this repo has.
- **A stumbling block learned during a run goes into the skill in the same
  pass** — into `## Stolpersteine`, with the run that found it referenced in the
  commit body.
- **Screenshots are scrubbed before committing**: no tenant names, usernames,
  internal hostnames, IPs or ticket contents that do not belong in a public
  repo. This repo is public.
- **The prototype warning in `README.md` stays.** Do not soften or remove it in
  passing; that is its own commit with its own reason.

## 5. Branch and push

- The repo commits **directly to the default branch**; no feature branches
  unless asked.
- **The repository has no commits yet and the checked-out branch is `master`.**
  Before the first push, settle whether the default is `master` or `main` and do
  it deliberately — not as a side effect of a commit.
- **Commit only when asked, push only when asked.** They are separate
  instructions — "commit das" is not permission to push.
- After committing, report the short SHA and say explicitly whether it is
  pushed.

## 6. Never

- `--no-verify`, `--no-gpg-sign`, or anything else that bypasses hooks or
  signing.
- `git commit -a` / `git add -A` without reading the status first — this repo
  picks up browser-session artefacts, unscrubbed screenshots and `state/`
  scratch files.
- Amending or rebasing a commit that is already published. Check with
  `git merge-base --is-ancestor <sha> origin/<branch>` before rewriting
  anything; fix a published commit with a follow-up commit instead.
- Rewriting or deleting anything under `runs/`. The protocols are append-only;
  a correction is a new protocol that references the old one.
- Committing a screenshot or other binary without saying in the body what it
  shows — the diff cannot.
