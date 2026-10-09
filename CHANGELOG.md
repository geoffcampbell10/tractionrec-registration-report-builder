# Changelog

## Package versions and the Traction Rec version they need

The install link is an unmanaged package built out of a production org, which means
each published version records the Traction Rec version installed in that org **at
the moment it was published**, and requires that version or later.

That requirement is frozen per link. Publishing a newer version later does not
change an older one, so **older links keep working for orgs on older Traction Rec**
and are never removed.

| Package version | Needs Traction Rec | Install link |
|---|---|---|
| 1.1 (`v1.1.0`) | 60.37 or later | [install](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tRQ000000BFq9YAG) |

Pick the newest row your org's Traction Rec version satisfies. On an older version
than any row lists, use the ZIP from the matching release below and deploy it through
Workbench — the ZIP has no version floor at all.

You can check your version at **Setup → Installed Packages → Traction Rec**.

---

## v1.1.0 — 2026-10-01

Reported by the DC JCC (Shoshana Strom and Courtney Brown) after their first run
with the tool.

### Fixed

- **PDF export works.** It previously failed in every org with "Could not open
  PDF preview: Unsupported MIME type". Now builds a real PDF that downloads in
  one click, like CSV and Excel.
- **Wide reports no longer crash** with "Maximum call stack size exceeded". This
  was column count, not row count. Tested at 99 columns.
- **Paragraph-length question text no longer breaks the layout.** Long consent
  questions produced a header tall enough to fill the page. Headers are trimmed.
- Error messages no longer linger after a successful export.

### Added

- **Configurable filter example text**, so each org sets its own wording in
  **Setup → Custom Metadata Types → Registration Report Setting → Manage
  Records**. Blank fields fall back to the defaults, and only the first record
  is read.

  | Field | Shows up in | Default |
  |---|---|---|
  | Program Name Placeholder | Program Name filter | `e.g. Aquatics` |
  | Course Name Placeholder | Course Name filter | `e.g. Swim Lessons` |
  | Course Session Placeholder | Course Session filter | `e.g. Spring 2025` |
  | Folder Name Placeholder | New folder name when saving | `e.g. Aquatics, Summer 2025` |

  The package ships the metadata type and its fields but deliberately ships no
  records, so **your values survive upgrades**.

- **`JsPDF` static resource** — jsPDF 2.5.1 and AutoTable 3.8.2, both MIT. Adds
  about 400KB.

### Changed

- The printed report is titled "Registration Report" and saves as
  `RegistrationReport_<date>.pdf`.
- The Course Name default example is now `e.g. Swim Lessons`.

### Upgrading

Redeploy over your existing install. Nothing to uninstall, saved reports are
untouched. Hard refresh afterwards (Ctrl+Shift+R / Cmd+Shift+R) or Salesforce
serves the cached old version.

---

## v1.0.0 — 2026-06-24

Initial release.

- Filter registrations by program, course, course session, start date range and
  registration status.
- Pivot answered questions into one column per question, grouped by question
  group, so each registration is a single flat row.
- Add any accessible field from Registration or Contact as an extra column.
- Save and reload report configurations, organised into folders and private to
  each user.
- Export to CSV, Excel and PDF.
- `Registration Report Builder User` permission set covering the Apex
  controller, the App Launcher tab and saved reports, with no TractionRec
  permissions granted.
