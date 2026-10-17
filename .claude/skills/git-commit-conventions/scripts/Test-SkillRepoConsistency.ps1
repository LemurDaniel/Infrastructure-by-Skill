<#
.SYNOPSIS
    Pre-commit consistency checks for the Infrastructure-by-Skill repo.

.DESCRIPTION
    Read-only. Verifies the things that can actually go wrong in a repo of
    ClickOps runbooks:

      1. Secrets in tracked files. The skills describe portals, admin consoles
         and service accounts; a pasted token, password or private key is the
         realistic leak here, and this repo is public.
      2. Skill folder structure: every <system>-<aktion>/ carries a SKILL.md
         whose frontmatter name matches the folder and which has a description.
      3. The six-phase contract: a SKILL.md names plan, checkpoint,
         verification, rollback, protocol and abort rules.
      4. Run protocol naming: runs/<YYYY-MM-DD>_<skill>_<ticket>.md, naming a
         skill that exists.
      5. Broken relative links in tracked Markdown, and spaces in tracked
         paths (the PowerShell helpers walk these paths).

    Checks 1, 2, 4 (name shape) and 5 are errors. Check 3 and an unknown skill
    in a protocol name are warnings that need human judgement.

.PARAMETER SkipLinks
    Skip the link check (it reads every tracked Markdown file).

.PARAMETER SkipSecrets
    Skip the secret scan (it reads every tracked text file).

.EXAMPLE
    pwsh -NoProfile -File .claude/skills/git-commit-conventions/scripts/Test-SkillRepoConsistency.ps1

.OUTPUTS
    Exit code 0 = ok (warnings allowed), 1 = at least one error.
#>
[CmdletBinding()]
param(
    [switch]$SkipLinks,
    [switch]$SkipSecrets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (git rev-parse --show-toplevel 2>$null)
if (-not $repo) { Write-Host 'Not inside a git repository.' -ForegroundColor Red; exit 1 }
$repo = $repo.Trim()
Push-Location $repo
try {
    $errors   = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    Write-Host "`nSkill repo consistency check — $repo" -ForegroundColor Cyan
    Write-Host ('-' * 64)

    # Tracked files, plus anything staged in a repo without commits yet.
    $tracked = @(git ls-files)
    if ($tracked.Count -eq 0) {
        Write-Host '[info] nothing tracked yet — checks run against the index only' -ForegroundColor DarkYellow
    }

    # Skill folders: top-level directories that are not infrastructure of the
    # repo itself. A skill is "<system>-<aktion>" by convention.
    $reserved = @('_templates', '_shared', 'runs', '.claude', '.git', '.github')
    $skillDirs = @(
        Get-ChildItem -Directory -LiteralPath $repo |
            Where-Object { $reserved -notcontains $_.Name } |
            Select-Object -ExpandProperty Name
    )

    # --- 1. secrets in tracked files -----------------------------------------
    if ($SkipSecrets) {
        Write-Host '[skip] secret scan'
    } else {
        # Deliberately narrow: patterns that are a secret rather than a mention
        # of one. "password" as prose is fine; "password = hunter2" is not.
        $secretPatterns = @(
            @{ Name = 'private key block';  Pattern = '-----BEGIN (RSA |OPENSSH |EC |PGP )?PRIVATE KEY' }
            @{ Name = 'bearer token';       Pattern = '(?i)\bbearer\s+[A-Za-z0-9\-_\.=]{20,}' }
            @{ Name = 'JWT';                Pattern = '\beyJ[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]{10,}\.' }
            @{ Name = 'assigned secret';    Pattern = '(?i)\b(password|passwd|pwd|secret|client_secret|api[_-]?key|token)\b\s*[:=]\s*["'']?[^\s"''<>{}$]{8,}' }
            @{ Name = 'Azure storage key';  Pattern = '(?i)AccountKey\s*=\s*[A-Za-z0-9+/=]{20,}' }
            @{ Name = 'PAT-looking string'; Pattern = '\b[a-z2-7]{52}\b' }
            @{ Name = 'GitHub token';       Pattern = '\bgh[pousr]_[A-Za-z0-9]{20,}' }
            @{ Name = 'connection string';  Pattern = '(?i)(mongodb|postgres(ql)?|mysql|amqps?)://[^\s:/@]+:[^\s/@]+@' }
        )
        # Placeholders the skills legitimately contain.
        $placeholder = '(?i)(\{\{?\s*\w+\s*\}?\}|<[^>\r\n]{1,40}>|\$\{?\w+\}?|xxx+|\*\*\*+|REDACTED|PLACEHOLDER|CHANGEME|example|dummy)'

        $textExt = @('.md', '.json', '.yml', '.yaml', '.ps1', '.sh', '.py', '.txt', '.env', '.ini', '.cfg', '.toml')
        $candidates = @($tracked | Where-Object { $textExt -contains [System.IO.Path]::GetExtension($_).ToLowerInvariant() })

        $hits = [System.Collections.Generic.List[string]]::new()
        foreach ($f in $candidates) {
            if (-not (Test-Path -LiteralPath $f)) { continue }
            $lineNo = 0
            foreach ($line in (Get-Content -LiteralPath $f)) {
                $lineNo++
                foreach ($p in $secretPatterns) {
                    if ($line -match $p.Pattern) {
                        if ($line -match $placeholder) { continue }
                        $hits.Add("${f}:${lineNo}  [$($p.Name)]")
                        break
                    }
                }
            }
        }

        if ($hits.Count -eq 0) {
            Write-Host "[ ok ] secret scan — $($candidates.Count) text file(s), nothing found" -ForegroundColor Green
        } else {
            Write-Host "[fail] secret scan — $($hits.Count) suspicious line(s)" -ForegroundColor Red
            foreach ($h in $hits) { Write-Host "         $h" -ForegroundColor DarkGray }
            $errors.Add("$($hits.Count) line(s) look like a committed credential. Replace with a placeholder and rotate the real value.")
        }
    }

    # --- 2. skill folder structure -------------------------------------------
    if ($skillDirs.Count -eq 0) {
        Write-Host '[info] no skill folders yet' -ForegroundColor DarkYellow
    } else {
        $structureOk = $true
        foreach ($d in $skillDirs) {
            $skillFile = Join-Path $d 'SKILL.md'
            if (-not (Test-Path -LiteralPath $skillFile)) {
                Write-Host "[fail] $d/ has no SKILL.md" -ForegroundColor Red
                $errors.Add("$d/ has no SKILL.md — every skill folder needs one.")
                $structureOk = $false
                continue
            }

            $raw = Get-Content -LiteralPath $skillFile -Raw
            $fm = [regex]::Match($raw, '(?s)\A---\r?\n(.*?)\r?\n---')
            if (-not $fm.Success) {
                Write-Host "[fail] $skillFile has no YAML frontmatter" -ForegroundColor Red
                $errors.Add("$skillFile has no frontmatter — name and description decide when the skill triggers.")
                $structureOk = $false
                continue
            }

            $block = $fm.Groups[1].Value
            $name = [regex]::Match($block, '(?m)^name:\s*(\S.*?)\s*$').Groups[1].Value
            $desc = [regex]::Match($block, '(?m)^description:\s*(\S.*?)\s*$').Groups[1].Value

            if ($name -ne $d) {
                Write-Host "[fail] $skillFile — name '$name' does not match folder '$d'" -ForegroundColor Red
                $errors.Add("$skillFile frontmatter name '$name' must equal the folder name '$d'.")
                $structureOk = $false
            }
            if ([string]::IsNullOrWhiteSpace($desc)) {
                Write-Host "[fail] $skillFile has no description" -ForegroundColor Red
                $errors.Add("$skillFile needs a description naming the system and the action.")
                $structureOk = $false
            }
            if ($d -notmatch '^[a-z0-9]+(-[a-z0-9]+)+$') {
                Write-Host "[warn] $d/ does not look like <system>-<aktion>" -ForegroundColor Yellow
                $warnings.Add("Folder '$d' does not follow the <system>-<aktion> naming scheme.")
            }
            if (-not (Test-Path -LiteralPath (Join-Path $d 'inputs.schema.json'))) {
                Write-Host "[warn] $d/ has no inputs.schema.json" -ForegroundColor Yellow
                $warnings.Add("$d/ has no inputs.schema.json — inputs are validated before a run.")
            }
        }
        if ($structureOk) {
            Write-Host "[ ok ] skill structure — $($skillDirs.Count) skill folder(s)" -ForegroundColor Green
        }
    }

    # --- 3. six-phase contract in each SKILL.md ------------------------------
    if ($skillDirs.Count -gt 0) {
        $required = @(
            @{ Label = 'plan';        Pattern = '(?im)^#{1,3}\s*.*\bplan\b' }
            @{ Label = 'checkpoint';  Pattern = '(?i)checkpoint' }
            @{ Label = 'verifikation';Pattern = '(?i)verif' }
            @{ Label = 'rollback';    Pattern = '(?i)rollback' }
            @{ Label = 'protokoll';   Pattern = '(?i)protokoll|protocol' }
            @{ Label = 'abbruch';     Pattern = '(?i)abbruch|abort' }
        )
        $incomplete = [System.Collections.Generic.List[string]]::new()
        foreach ($d in $skillDirs) {
            $skillFile = Join-Path $d 'SKILL.md'
            if (-not (Test-Path -LiteralPath $skillFile)) { continue }
            $raw = Get-Content -LiteralPath $skillFile -Raw
            $missing = @($required | Where-Object { $raw -notmatch $_.Pattern } | ForEach-Object { $_.Label })
            if ($missing.Count -gt 0) { $incomplete.Add("$skillFile  missing: $($missing -join ', ')") }
        }
        if ($incomplete.Count -eq 0) {
            Write-Host '[ ok ] six-phase contract present in every SKILL.md' -ForegroundColor Green
        } else {
            Write-Host "[warn] $($incomplete.Count) SKILL.md file(s) miss a mandatory section" -ForegroundColor Yellow
            foreach ($i in $incomplete) { Write-Host "         $i" -ForegroundColor DarkGray }
            $warnings.Add("CONVENTIONS.md requires plan, checkpoint, verification, rollback, protocol and abort rules in every skill. Judge whether the deviation is intended.")
        }
    }

    # --- 4. run protocol naming ----------------------------------------------
    if (Test-Path -LiteralPath (Join-Path $repo 'runs')) {
        $runFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo 'runs') -File -Filter '*.md' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'README.md' } | Select-Object -ExpandProperty Name)
        if ($runFiles.Count -eq 0) {
            Write-Host '[info] runs/ is empty — no executions recorded yet' -ForegroundColor DarkYellow
        } else {
            $badName = [System.Collections.Generic.List[string]]::new()
            $unknown = [System.Collections.Generic.List[string]]::new()
            foreach ($r in $runFiles) {
                $m = [regex]::Match($r, '^(\d{4}-\d{2}-\d{2})_([a-z0-9][a-z0-9-]*)_([^_]+)\.md$')
                if (-not $m.Success) { $badName.Add($r); continue }
                $skill = $m.Groups[2].Value
                if ($skillDirs -notcontains $skill) { $unknown.Add("$r  ->  $skill") }
            }
            if ($badName.Count -eq 0) {
                Write-Host "[ ok ] run protocols — $($runFiles.Count) file(s), names well formed" -ForegroundColor Green
            } else {
                Write-Host "[fail] $($badName.Count) run protocol name(s) malformed" -ForegroundColor Red
                foreach ($b in $badName) { Write-Host "         $b" -ForegroundColor DarkGray }
                $errors.Add("Run protocols must be named <YYYY-MM-DD>_<skill>_<ticket>.md so the audit trail stays sortable and greppable.")
            }
            if ($unknown.Count -gt 0) {
                Write-Host "[warn] $($unknown.Count) protocol(s) name a skill folder that does not exist" -ForegroundColor Yellow
                foreach ($u in $unknown) { Write-Host "         $u" -ForegroundColor DarkGray }
                $warnings.Add('A protocol references a skill that is not in the repo — renamed or deleted skill? The protocol stays, the reference needs explaining.')
            }
        }
    }

    # --- 5. broken relative links + spaces in paths --------------------------
    if ($SkipLinks) {
        Write-Host '[skip] relative links'
    } else {
        $mdFiles = @($tracked | Where-Object { $_ -like '*.md' })
        $broken = [System.Collections.Generic.List[string]]::new()

        foreach ($md in $mdFiles) {
            if (-not (Test-Path -LiteralPath $md)) { continue }
            $dir = Split-Path -Parent $md
            if ([string]::IsNullOrEmpty($dir)) { $dir = '.' }

            # Strip fenced blocks and inline code first: a skill may legitimately
            # show "](target)" as an example, which is not a link.
            $text = Get-Content -LiteralPath $md -Raw
            $text = [regex]::Replace($text, '(?s)```.*?```', '')
            $text = [regex]::Replace($text, '`[^`\r\n]*`', '')

            foreach ($m in [regex]::Matches($text, '\]\(([^)]+)\)')) {
                $target = $m.Groups[1].Value.Trim()
                if ($target -match '^(https?:|mailto:|#)') { continue }
                $target = ($target -split '\s+')[0]
                $target = ($target -split '#')[0]
                if ([string]::IsNullOrWhiteSpace($target)) { continue }
                $target = [uri]::UnescapeDataString($target)
                $full = Join-Path $dir $target
                if (-not (Test-Path -LiteralPath $full)) { $broken.Add("$md  ->  $target") }
            }
        }

        if ($broken.Count -eq 0) {
            Write-Host "[ ok ] relative links — $($mdFiles.Count) Markdown file(s), none broken" -ForegroundColor Green
        } else {
            Write-Host "[fail] relative links — $($broken.Count) broken" -ForegroundColor Red
            foreach ($b in $broken) { Write-Host "         $b" -ForegroundColor DarkGray }
            $errors.Add("$($broken.Count) broken relative link(s) in tracked Markdown.")
        }
    }

    $spaced = @($tracked | Where-Object { $_ -match ' ' })
    if ($spaced.Count -eq 0) {
        Write-Host '[ ok ] no spaces in tracked paths' -ForegroundColor Green
    } else {
        Write-Host "[fail] $($spaced.Count) tracked path(s) contain a space" -ForegroundColor Red
        foreach ($s in $spaced) { Write-Host "         $s" -ForegroundColor DarkGray }
        $errors.Add("$($spaced.Count) tracked path(s) contain a space (breaks the shell and PowerShell helpers).")
    }

    Write-Host ('-' * 64)

    foreach ($w in $warnings) { Write-Host "  ! $w" -ForegroundColor Yellow }
    foreach ($e in $errors)   { Write-Host "  X $e" -ForegroundColor Red }

    if ($errors.Count -gt 0) {
        Write-Host "`n$($errors.Count) error(s) — fix before committing.`n" -ForegroundColor Red
        exit 1
    }
    if ($warnings.Count -gt 0) {
        Write-Host "`nNo errors, $($warnings.Count) warning(s) to judge.`n" -ForegroundColor Yellow
        exit 0
    }
    Write-Host "`nAll checks passed.`n" -ForegroundColor Green
    exit 0
}
finally {
    Pop-Location
}
