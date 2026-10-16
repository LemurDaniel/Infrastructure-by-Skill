# Infrastructure as Skills

> Geführte, ausführbare Runbooks für Infrastruktur, die sich **nicht** per IaC ausrollen lässt.

---

# ⚠️ ⚠️ ⚠️  PROTOTYPE WARNING  ⚠️ ⚠️ ⚠️

> ## 🚧 DAS HIER IST EIN PROTOTYP. NICHTS DAVON IST PRODUKTIONSREIF. 🚧
>
> **Was das konkret heißt:**
>
> - 🧪 **Experiment, kein Produkt.** Das Repo erkundet, ob sich ClickOps überhaupt sinnvoll als Skill fassen lässt. Die Antwort ist offen.
> - 🤖 **Ein LLM klickt in echten Oberflächen.** Es kann das falsche Feld treffen, den falschen Knopf drücken, den falschen Datensatz erwischen. Es gibt keinen `plan`, keinen State, kein `apply` das abbricht.
> - 💥 **Kein Undo.** Eine GUI hat kein `terraform destroy`. Was hier schiefgeht, geht per Hand zurück — wenn überhaupt.
> - 🔒 **Niemals gegen Produktion.** Dev und Staging. Prod nur mit zweiter menschlicher Freigabe, und auch dann auf eigenes Risiko.
> - 👀 **Kein Vollautomat.** Jeder Lauf braucht einen Menschen, der mitliest und freigibt. Wer das Fenster unbeaufsichtigt laufen lässt, hat das Konzept nicht verstanden.
> - 📉 **Alles kann sich ändern.** Struktur, Konventionen, Skill-Format, Protokollformat. Keine Stabilitätsgarantie, keine Migrationspfade, keine Versionierung.
> - 🙅 **Keine Haftung, kein Support.** Nutzung auf eigene Verantwortung.
>
> **Wenn es eine API gibt: nimm Terraform. Nimm Pulumi. Nimm Ansible. Nimm alles andere zuerst.**

---

## Warum

Es gibt Infrastruktur, für die es kein Terraform-Modul gibt und auch keins geben wird:
Vendor-Portale, Legacy-Appliances, Firewall- und Netzwerk-GUIs, SaaS-Admin-Konsolen,
Behördenportale. Dort passiert ClickOps — nach Gedächtnis, nach Wiki-Screenshots von
2021, nach dem Kollegen, der es letztes Mal gemacht hat.

Dieses Repo versucht nicht, diese Lücke wegzudefinieren. Es versucht, sie zu
dokumentieren — in einer Form, die ein Agent ausführen kann und ein Mensch prüfen kann.

## Abgrenzung

| | IaC (Terraform, Pulumi, Ansible) | Infrastructure as Skills |
|---|---|---|
| Voraussetzung | Es gibt eine API | Es gibt **keine** API |
| Ausführung | deterministisch, idempotent | best effort, GUI-abhängig |
| Sicherheitsnetz | State, Plan, Drift-Detection | menschliche Freigabepunkte |
| Ergebnis | reproduzierbar | protokolliert |

**IaC bleibt die erste Wahl.** Ein Skill ist die Antwort auf "es gibt hier nichts
anderes", nicht auf "Terraform ist mir zu umständlich". Existiert ein Modul, greift der
Skill nicht — das steht in jedem `SKILL.md` unter *Wann NICHT*.

## Rollenverteilung

- **Der Skill liefert das Wissen**: Reihenfolge, Klickpfad, Stolpersteine, Rollback.
- **Die Ausführung** läuft über Browser-Steuerung oder Computer Use; deterministische
  Teilschritte über mitgelieferte Skripte.
- **Der Mensch gibt frei** — an festen Haltepunkten, nicht nach Gefühl.

Erwartung: ein Copilot mit Freigabepunkten. Captchas und MFA unterbrechen jede
Automatisierung; dort übernimmt der Mensch kurz und gibt zurück.

## Repo-Struktur

```
Infrastructure-as-Skills/
├── README.md                  # dieses Dokument
├── CONVENTIONS.md             # Pflicht-Phasen, Checkpoint-Regeln, Protokollformat
├── _templates/
│   └── SKILL.md               # Vorlage für neue Skills
├── _shared/
│   ├── checkpoint.md          # Standardtext für Freigabe-Schritte
│   ├── protocol-template.md   # Aufbau eines Ausführungsprotokolls
│   └── scripts/               # gemeinsame Helfer (Validierung, Logging)
├── <system>-<aktion>/         # z. B. firewall-add-rule, portal-create-user
│   ├── SKILL.md               # Ablauf, Klickpfad, Stolpersteine
│   ├── inputs.schema.json     # erwartete Eingaben + Validierung
│   ├── scripts/               # deterministische Teilschritte (optional)
│   ├── reference/             # Screenshots der GUI, bekannte Fehlermeldungen
│   └── state/                 # Soll-Zustand als YAML (optional, für Drift-Check)
└── runs/                      # Protokolle je Ausführung
```

- **Namensschema `<system>-<aktion>`**, damit Skills nach System gruppiert bleiben.
- **`runs/` wird versioniert** (oder in ein separates Audit-Repo geschrieben), damit es
  ein Git-Log der manuellen Änderungen gibt: `runs/<datum>_<skill>_<ticket>.md`.
- **`reference/` hält den erwarteten GUI-Stand fest.** Weicht die Oberfläche ab, stoppt
  der Skill und fragt nach.

## Die sechs Phasen

Jeder Skill durchläuft dieselben sechs Phasen. **Phase 2 und Phase 4 sind
Pflicht-Haltepunkte**, an denen ein Mensch freigibt.

| # | Phase | Inhalt |
|---|---|---|
| 1 | **Vorbereitung** | Eingaben abfragen und gegen `inputs.schema.json` validieren, Umgebung und Zugang prüfen |
| 2 | **Plan** 🛑 | Geplante Änderungen auflisten und **auf Freigabe warten** |
| 3 | **Ausführung** | Klickpfad abarbeiten, Schritt für Schritt |
| 4 | **Checkpoint** 🛑 | Vor dem schreibenden Schritt: Screenshot zeigen, **auf Freigabe warten**, dann speichern |
| 5 | **Verifikation** | Seite neu laden, Werte prüfen, Funktionstest |
| 6 | **Protokoll** | Lauf nach `runs/` schreiben: geplant, freigegeben, ausgeführt, verifiziert |

Wird ein Checkpoint abgelehnt, korrigiert der Skill den Schritt in der GUI und zeigt ihn
erneut zur Freigabe vor. Er geht nicht weiter und er entscheidet nicht selbst.

## Leitplanken

Die vollständigen Regeln gehören nach `CONVENTIONS.md` (folgt noch) und gelten dann für
jeden Skill im Repo.

| Thema | Regel |
|---|---|
| **Credentials** | Minimale Rechte, möglichst kurzlebige Tokens oder eigene Service-Accounts, keine Admin-Keys im Skill |
| **Destruktive Aktionen** | Löschen, Überschreiben, Force immer als eigener Bestätigungsschritt, im Skill fest verankert |
| **Umgebungen** | Pro Skill festlegen, welche erlaubt sind; Prod nur mit zweiter Freigabe |
| **Audit** | Jeder Lauf schreibt ein Protokoll nach `runs/` |
| **GUI-Abweichung** | Weicht die Oberfläche von `reference/` ab, stoppt der Skill und fragt nach |
| **Grenzen** | Captchas und MFA unterbrechen den Lauf; der Mensch übernimmt kurz und gibt zurück |

## Einen Skill hinzufügen

1. Szenario prüfen: Gibt es wirklich keine API? Wenn doch — IaC.
2. Ordner `<system>-<aktion>/` anlegen.
3. Klickpfad **einmal manuell** durchgehen, Screenshots nach `reference/` legen.
4. `_templates/SKILL.md` kopieren und ausfüllen, Stolpersteine ergänzen.
5. `inputs.schema.json` für die Eingaben anlegen.
6. In Dev ausführen, Checkpoints testen — **auch die Ablehnung**.
7. Protokoll prüfen: Ist für einen Dritten nachvollziehbar, was geändert wurde?

## Stand des PoC

Ziel: ein einziger Skill, der ein echtes ClickOps-Szenario dreimal sauber durchläuft,
jedes Mal mit Protokoll.

- [ ] Szenario wählen: häufig, risikoarm, mit Dev- oder Staging-Umgebung
- [ ] Repo-Gerüst: `README.md`, `CONVENTIONS.md`, `_templates/`, `_shared/`, `runs/`
- [ ] Klickpfad manuell durchgehen, Screenshots nach `reference/`
- [ ] `SKILL.md` aus der Vorlage schreiben
- [ ] `inputs.schema.json` anlegen
- [ ] Skill in Claude laden, in Dev ausführen, Checkpoints testen (auch Ablehnung)
- [ ] Protokoll auf Nachvollziehbarkeit prüfen
- [ ] Lessons learned festhalten, Vorlage nachschärfen
- [ ] Optional: Soll-Zustand als YAML in `state/`, zweiter Skill für Drift-Check

Bis diese Liste nicht abgehakt ist, gilt die Warnung oben in voller Länge.
