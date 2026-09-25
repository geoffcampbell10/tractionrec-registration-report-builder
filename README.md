# TractionRec Registration Report Builder

A Salesforce Lightning Web Component that lets users build, save, and export custom reports on TractionRec (TREX1__) registrations. It pivots custom question answers into their own dedicated columns, ensuring you get a clean, flat report with exactly one row per registration.

## Why This Exists

TractionRec stores each custom question's answer as its own record
(`TREX1__Answered_Question__c`), related to a Registration. Standard Salesforce
reporting can't pivot those answer *records* into one column per question next to the
registration and contact details — you'd only ever get a report with one row per
answered question, not one row per registration with all its answers laid out side by
side.

This tool solves that: the Apex controller pulls the answered-question rows for the
matching registrations and pivots them in-memory into dynamic columns (one per
question, grouped by question group), so staff get the flat, spreadsheet-style view —
one row per registration — that TractionRec's data model can't produce through
out-of-the-box reports.

## Features

- **Filter registrations** by Program Name, Course Name, Course Session, Registration
  Status, and Start Date range.
- **Dynamic columns** — pulls every custom question answered on a registration
  (`TREX1__Answered_Question__c`) and displays them as columns, grouped by question
  group, alongside standard Registration and Contact fields.
- **Column picker** — add any accessible field from `TREX1__Registration__c` or
  `Contact` as an extra column, and toggle fixed columns and question groups on/off.
- **Sortable results table** built on `lightning-datatable`.
- **Save / load report configurations** — filters and column selections are saved per
  user (organized into folders) as `Question_Report_Config__c` records, so a report can
  be re-run later without re-entering criteria.
- **Export** to CSV, Excel (via bundled SheetJS static resource), or a print-friendly
  PDF view.
- **Guardrails** on large result sets — pre-flight `COUNT()` queries warn the user to
  narrow filters before pulling back more than ~2,000 registrations or ~20,000 answered
  questions, avoiding governor-limit failures.
- Enforces object/field-level security (FLS) and sharing on every query via
  `with sharing`, `isAccessible()` checks, and `Security.stripInaccessible`.

## Requirements

- A Salesforce org with the **TractionRec** managed package (`TREX1__` namespace)
  installed.
- A way to deploy metadata to the org — either the Salesforce CLI (`sf`) or Workbench
  (no CLI install required). See [Deployment](#deployment) below.

## Project Structure

```
registration-report-builder/main/default/
├── classes/
│   ├── RegistrationReportController.cls       Apex controller (queries, saved-config CRUD)
│   └── RegistrationReportControllerTest.cls   Apex test class
├── lwc/registrationReportBuilder/             The report builder LWC (UI, export, state)
├── objects/Question_Report_Config__c/         Custom object for saved report configs
├── permissionsets/                            Registration Report Builder User perm set
├── flexipages/Registration_Report_Builder.flexipage-meta.xml
├── tabs/Registration_Report_Builder.tab-meta.xml
└── staticresources/SheetJS.js                 Bundled SheetJS library for Excel export
```

## Deployment

For a full, step-by-step walkthrough (no CLI required), see **[install.md](install.md)**.
It covers both:

- **Workbench** — download the release ZIP and deploy it through a browser, no local
  tooling needed.
- **Salesforce CLI** — clone/download the project and deploy with `sf project deploy
  start`.

Short version for CLI users already set up:

```powershell
sf project deploy start --source-dir registration-report-builder --target-org <your-org-alias>
```

## Granting Access

The deploy includes a **Registration Report Builder User** permission set. Nobody can
see the tab until they have it, including the admin who installed it:

```powershell
sf org assign permset --name Registration_Report_Builder_User --target-org <your-org-alias>
```

Or from Setup → Permission Sets → Registration Report Builder User → Manage Assignments.

It grants the Apex controller, the App Launcher tab, and read/create/edit/delete on
`Question_Report_Config__c` and its fields. It deliberately grants **no TractionRec
object or field permissions** — users still see only the registrations their existing
profile allows, so assigning it cannot widen anyone's access to program data.

## Notes

- `Question_Report_Config__c` uses a Read/Write sharing model, but Apex enforces that
  users may only load, update, or delete configurations they own.
- Excel export requires the `SheetJS` static resource to finish loading; the UI
  disables the Excel button until it's ready (CSV and PDF/Print are always available).
