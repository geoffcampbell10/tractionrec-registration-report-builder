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
2. Under **Assets**, click **Workbench Deploy ZIP** to download it — do not unzip it

**Step 2 — Open Workbench and log in**

1. Go to [workbench.developerforce.com](https://workbench.developerforce.com)
2. Set **Environment** to Production (or Sandbox if that is where you are installing)
3. Set **API Version** to 62.0 or higher
4. Check the box to agree to the terms
5. Click **Login with Salesforce** and log in to your org

**Step 3 — Deploy the ZIP**

1. In the top menu click **migration → Deploy**
2. Click **Choose File** and select the ZIP you downloaded
3. Set **Test Level** to `RunLocalTests` (required for production)
4. Click **Next**, then **Deploy**
5. Wait for the deployment to finish — it will show a green success message when done

Deploying to a sandbox? Set **Test Level** to `NoTestRun` instead — tests are only
required for production.

---

## Option B — Salesforce CLI

Requires a one-time install of a free tool. Best for repeated deployments across
multiple orgs.

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
sf project deploy start --source-dir "force-app/main/default/objects/Question_Report_Config__c" --target-org my-org
```

2 of 6 — Apex controller

```
sf project deploy start --source-dir force-app/main/default/classes/RegistrationReportController.cls --target-org my-org
```

3 of 6 — Apex test class

```
sf project deploy start --source-dir force-app/main/default/classes/RegistrationReportControllerTest.cls --target-org my-org
```

4 of 6 — Excel library

```
sf project deploy start --source-dir force-app/main/default/staticresources --target-org my-org
```

5 of 6 — component

```
sf project deploy start --source-dir force-app/main/default/lwc/registrationReportBuilder --target-org my-org
```

6 of 6 — App Launcher tab

```
sf project deploy start --source-dir force-app/main/default/tabs/Registration_Report_Builder.tab-meta.xml --target-org my-org
```

---

## Both paths — verify it works

1. Click the App Launcher (9-dot grid, top left of Salesforce)
2. Search for **Registration Report Builder** and click it
3. Click **Run Report** to confirm data loads from TractionRec
