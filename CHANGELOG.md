# Changelog

## v1.1.0 — 2026-10-01

Reported by the DC JCC (Shoshana Strom and Courtney Brown) after their first run
with the tool.

### Fixed

- **PDF export no longer fails with "Could not open PDF preview: Unsupported
  MIME type."** Lightning Web Security blocks `URL.createObjectURL()` for
  `text/html`, which is what the old export relied on, so the button failed in
  every org. PDF / Print now builds a real PDF with jsPDF and downloads it the
  same way the CSV export already did. One click, a genuine `.pdf` file, no
  print dialog and no popup blocker in the way.

  The generated PDF is landscape, repeats the report title, filter summary and
  registration count on every page, stripes alternate rows, and numbers the
  pages.

### Added

- **Custom Labels for the filter example text.** The greyed-out examples in
  Program Name, Course Name and Course Session were hardcoded, and they assumed
  naming conventions that do not match every org. They are now Custom Labels, so
  each org sets its own wording in **Setup → Custom Labels** without touching
  code:

  | Label | Default |
  |---|---|
  | `RRB_Program_Name_Placeholder` | `e.g. Aquatics` |
  | `RRB_Course_Name_Placeholder` | `e.g. Swim Lessons` |
  | `RRB_Course_Session_Placeholder` | `e.g. Spring 2025` |
  | `RRB_Folder_Name_Placeholder` | `e.g. Aquatics, Summer 2025` |

- **`JsPDF` static resource** — jsPDF 2.5.1 and jsPDF-AutoTable 3.8.2, both MIT
  licensed. Adds roughly 400KB to the package.

### Changed

- The Course Name default example is now `e.g. Swim Lessons` instead of
  `e.g. Judaism`.
- The printed report is titled "Registration Report" rather than the old
  "Answered Questions Report", and the file is named
  `RegistrationReport_<date>.pdf`.

### Upgrading

Redeploy over your existing install. Nothing needs to be uninstalled first, and
saved reports are unaffected. If you already set your own Custom Label values,
redeploying **will** overwrite them back to the defaults above, so note them
down first.

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
