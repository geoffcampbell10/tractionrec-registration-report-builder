# TractionRec Registration Report Builder

A Salesforce Lightning Web Component that lets staff build, save, and export custom
reports on TractionRec (`TREX1__`) registrations — including registration answers to
custom questions — without needing a Salesforce admin to build a report or dashboard.

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
- Salesforce CLI (`sf`) for deployment.

## Project Structure

```
force-app/main/default/
├── classes/
│   ├── RegistrationReportController.cls       Apex controller (queries, saved-config CRUD)
│   └── RegistrationReportControllerTest.cls   Apex test class
├── lwc/registrationReportBuilder/             The report builder LWC (UI, export, state)
├── objects/Question_Report_Config__c/         Custom object for saved report configs
├── flexipages/Registration_Report_Builder.flexipage-meta.xml
├── tabs/Registration_Report_Builder.tab-meta.xml
└── staticresources/SheetJS.js                 Bundled SheetJS library for Excel export
```

## Deployment

```powershell
sf project deploy start --manifest package.xml --target-org <your-org-alias>
```

Or deploy the whole `force-app` source directory:

```powershell
sf project deploy start --source-dir force-app --target-org <your-org-alias>
```

After deployment, add the **Registration Report Builder** tab to an app, or drop the
`registrationReportBuilder` component onto a Lightning page via the App Builder.

## Notes

- `Question_Report_Config__c` uses a Read/Write sharing model, but Apex enforces that
  users may only load, update, or delete configurations they own.
- Excel export requires the `SheetJS` static resource to finish loading; the UI
  disables the Excel button until it's ready (CSV and PDF/Print are always available).
