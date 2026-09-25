# Registration Report Builder — Install Guide

For Salesforce system admins. Choose the method that works best for you.

**Requirement:** TractionRec must already be installed in your org before deploying
this tool.

---

## Option A — Workbench (recommended)

No installation needed. Just a browser and your Salesforce login.

**Step 1 — Download the deploy ZIP**

1. Go to
   [github.com/geoffcampbell10/tractionrec-registration-report-builder/releases/latest](https://github.com/geoffcampbell10/tractionrec-registration-report-builder/releases/latest)
2. Under **Assets**, click **registration-report-builder-deploy.zip** to download it —
   do not unzip it

**Step 2 — Open Workbench and log in**

1. Go to [workbench.developerforce.com](https://workbench.developerforce.com)
2. Set **Environment** to Production (or Sandbox if that is where you are installing)
3. Set **API Version** to 67.0. If login fails with
   `UNSUPPORTED_API_VERSION: Invalid Api version specified on URL`, the selected
   version is newer than your org supports — step down one version at a time until
   the login goes through
4. Check the box to agree to the terms
5. Click **Login with Salesforce** and log in to your org

**Step 3 — Deploy the ZIP**

1. In the top menu click **migration → Deploy**
2. Click **Choose File** and select the ZIP you downloaded
3. Tick **Single Package** — this one is required
4. Tick **Rollback On Error** so a partial failure leaves nothing behind
5. Set **Test Level** to `RunSpecifiedTests`
6. In the **Run Tests** box that appears, enter `RegistrationReportControllerTest`
7. Click **Next**, then **Deploy**
8. Wait for the deployment to finish — it will show a green success message when done

If the deploy fails with **"No package.xml found"** repeated several times, **Single
Package** was left unticked. Without it Salesforce treats every folder inside the ZIP
as a separate package and looks for a `package.xml` in each one, producing one error
per folder.

Running only this tool's own test class keeps the deploy independent of the rest of
your org, so an unrelated failing test elsewhere cannot block the install.

---

## Option B — Salesforce CLI

Requires a one-time install of a free tool.

**Step 1 — Install the Salesforce CLI (skip if already installed)**

1. Go to [developer.salesforce.com/tools/salesforcecli](https://developer.salesforce.com/tools/salesforcecli)
2. Download and run the installer for your computer (Windows or Mac)
3. Confirm it worked: open Terminal (Mac) or Command Prompt (Windows) and type
   `sf --version`

**Step 2 — Download the project files**

1. Go to
   [github.com/geoffcampbell10/tractionrec-registration-report-builder](https://github.com/geoffcampbell10/tractionrec-registration-report-builder)
2. Click the green **Code** button → **Download ZIP**
3. Unzip it and move the folder somewhere easy to find (Desktop or Documents)

**Step 3 — Open a terminal in that folder**

- **Windows:** Open the folder → click the address bar → type `cmd` → press Enter
- **Mac:** Right-click the folder → hold Option → click **New Terminal at Folder**

**Step 4 — Connect to your Salesforce org**

Paste the right command below, press Enter, and log in through the browser that opens.
Replace `my-org` with any nickname you like.

Sandbox:

```
sf org login web --instance-url https://test.salesforce.com --alias my-org
```

Production:

```
sf org login web --instance-url https://login.salesforce.com --alias my-org
```

**Step 5 — Run these commands in order**

Paste each one and press Enter. Wait for `Status: Succeeded` before running the next.
Replace `my-org` with the nickname from Step 4.

1 of 6 — custom object

```
sf project deploy start --source-dir "registration-report-builder/main/default/objects/Question_Report_Config__c" --target-org my-org
```

2 of 6 — Apex classes

```
sf project deploy start --source-dir registration-report-builder/main/default/classes --test-level RunSpecifiedTests --tests RegistrationReportControllerTest --target-org my-org
```

This deploys the controller and its test class together and runs only that one test.
Deploying to a sandbox? Drop the `--test-level` and `--tests` flags to skip tests.

3 of 6 — Excel library

```
sf project deploy start --source-dir registration-report-builder/main/default/staticresources --target-org my-org
```

4 of 6 — component

```
sf project deploy start --source-dir registration-report-builder/main/default/lwc/registrationReportBuilder --target-org my-org
```

5 of 6 — App Launcher tab

```
sf project deploy start --source-dir registration-report-builder/main/default/tabs/Registration_Report_Builder.tab-meta.xml --target-org my-org
```

6 of 6 — permission set

```
sf project deploy start --source-dir registration-report-builder/main/default/permissionsets --target-org my-org
```

This goes last because it references the object, the tab and the Apex class above it.

---

## Both paths — assign the permission set

The deploy includes a permission set called **Registration Report Builder User**.
Nobody can see the tab until they have it, including you.

**From Setup**

1. Setup → **Permission Sets**
2. Click **Registration Report Builder User**
3. Click **Manage Assignments** → **Add Assignment**
4. Tick yourself and anyone else who needs it, then **Assign**

**Or from the CLI**

```
sf org assign permset --name Registration_Report_Builder_User --target-org my-org
```

To assign it to someone else, add their username:

```
sf org assign permset --name Registration_Report_Builder_User --on-behalf-of person@yourorg.com --target-org my-org
```

This permission set grants the Apex controller, the App Launcher tab, and access to
saved reports. It deliberately grants **no TractionRec permissions** — people still
see exactly the registrations their existing profile already allows, so assigning it
cannot widen anyone's access to program data.

---

## Both paths — verify it works

1. Click the App Launcher (9-dot grid, top left of Salesforce)
2. Search for **Registration Report Builder** and click it
3. Type a program name you know exists and click **Run Report**
