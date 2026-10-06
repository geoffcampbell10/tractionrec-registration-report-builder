@isTest
private class RegistrationReportControllerTest {

    // â”€â”€â”€ Test Setup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @TestSetup
    static void makeData() {
        Contact con = new Contact(
            FirstName    = 'Test',
            LastName     = 'User',
            Email        = 'test@example.com',
            Phone        = '555-1234',
            MailingCity  = 'Baltimore',
            MailingState = 'MD'
        );
        insert con;

        TREX1__Registration__c reg = new TREX1__Registration__c(
            TREX1__Contact__c             = con.Id,
            TREX1__Course_Name__c         = 'Test Course',
            TREX1__Course_Session_Name__c = 'Session A',
            TREX1__Program_Name__c        = 'Test Program',
            TREX1__Registration_Status__c = getFirstStatus(),
            TREX1__Start_Date__c          = Date.today()
        );
        insert reg;

        TREX1__Question_Group__c qg = new TREX1__Question_Group__c(Name = 'Test Group');
        insert qg;

        TREX1__Custom_Question__c q1 = new TREX1__Custom_Question__c(
            TREX1__Question_Group__c = qg.Id,
            TREX1__Question_Text__c  = 'Favorite color?',
            TREX1__Sort_Priority__c  = 1,
            TREX1__Data_Type__c      = 'TextArea'
        );
        TREX1__Custom_Question__c q2 = new TREX1__Custom_Question__c(
            TREX1__Question_Group__c = qg.Id,
            TREX1__Question_Text__c  = 'Allergies?',
            TREX1__Sort_Priority__c  = 2,
            TREX1__Data_Type__c      = 'TextArea'
        );
        insert new List<TREX1__Custom_Question__c>{ q1, q2 };

        insert new List<TREX1__Answered_Question__c>{
            new TREX1__Answered_Question__c(
                TREX1__Registration__c       = reg.Id,
                TREX1__Contact__c            = con.Id,
                TREX1__aq_Question_Group__c  = qg.Id,
                TREX1__aq_Custom_Question__c = q1.Id,
                TREX1__Question__c           = 'Favorite color?',
                TREX1__Answer__c             = 'Blue'
            ),
            new TREX1__Answered_Question__c(
                TREX1__Registration__c       = reg.Id,
                TREX1__Contact__c            = con.Id,
                TREX1__aq_Question_Group__c  = qg.Id,
                TREX1__aq_Custom_Question__c = q2.Id,
                TREX1__Question__c           = 'Allergies?',
                TREX1__Answer__c             = 'None'
            )
        };
    }

    private static String getFirstStatus() {
        Schema.DescribeFieldResult fr =
            TREX1__Registration__c.TREX1__Registration_Status__c.getDescribe();
        for (Schema.PicklistEntry e : fr.getPicklistValues()) {
            if (e.isActive()) return e.getValue();
        }
        return 'Active';
    }

    // â”€â”€â”€ Metadata â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @isTest
    static void testGetRegistrationStatuses() {
        List<RegistrationReportController.PicklistOption> statuses =
            RegistrationReportController.getRegistrationStatuses();
        System.assert(!statuses.isEmpty(), 'Should return registration statuses');
        System.assertNotEquals(null, statuses[0].value);
        System.assertNotEquals(null, statuses[0].label);
    }

    // ─── getPlaceholders ──────────────────────────────────────────────────────

    @isTest
    static void testGetPlaceholders_returnsAllFourKeys() {
        Map<String, String> p = RegistrationReportController.getPlaceholders();
        for (String key : new List<String>{ 'programName', 'courseName', 'courseSession', 'folderName' }) {
            System.assert(p.containsKey(key), 'Missing placeholder key: ' + key);
            System.assert(String.isNotBlank(p.get(key)), 'Placeholder should never be blank: ' + key);
        }
    }

    @isTest
    static void testGetPlaceholders_fallsBackWhenNoRecordConfigured() {
        // The package ships no Registration_Report_Setting__mdt records, so an org
        // that has not configured one must still get usable example text.
        if ([SELECT COUNT() FROM Registration_Report_Setting__mdt] == 0) {
            Map<String, String> p = RegistrationReportController.getPlaceholders();
            System.assertEquals('e.g. Aquatics',    p.get('programName'));
            System.assertEquals('e.g. Swim Lessons', p.get('courseName'));
            System.assertEquals('e.g. Spring 2025',  p.get('courseSession'));
        }
    }

    @isTest
    static void testGetPlaceholders_configuredRecordWins() {
        List<Registration_Report_Setting__mdt> settings = [
            SELECT Program_Name_Placeholder__c
            FROM Registration_Report_Setting__mdt
            ORDER BY DeveloperName
            LIMIT 1
        ];
        Map<String, String> p = RegistrationReportController.getPlaceholders();
        if (!settings.isEmpty() && String.isNotBlank(settings[0].Program_Name_Placeholder__c)) {
            System.assertEquals(settings[0].Program_Name_Placeholder__c, p.get('programName'),
                'A configured record should override the default');
        } else {
            System.assertEquals('e.g. Aquatics', p.get('programName'),
                'With nothing configured the default should win');
        }
    }

    // â”€â”€â”€ runReport â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @isTest
    static void testRunReport_noFilters() {
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, null, null, null, null, null, null);
        Test.stopTest();

        System.assertEquals(1, result.totalRows, 'Should return 1 registration row');
        System.assertEquals(2, result.questionColumns.size(), 'Should have 2 question columns');
        System.assertEquals('Blue', result.rows[0].get('q_0'), 'First answer should be Blue');
        System.assertEquals('None', result.rows[0].get('q_1'), 'Second answer should be None');
    }

    @isTest
    static void testRunReport_courseNameFilter_matches() {
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport('Test', null, null, null, null, null, null);
        Test.stopTest();

        System.assertEquals(1, result.totalRows, 'Course filter "Test" should match "Test Course"');
    }

    @isTest
    static void testRunReport_courseNameFilter_excludes() {
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport('NoSuchCourse', null, null, null, null, null, null);
        Test.stopTest();

        System.assertEquals(0, result.totalRows, 'Course filter should exclude non-matching records');
    }

    @isTest
    static void testRunReport_courseSessionFilter_matches() {
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, 'Session', null, null, null, null, null);
        Test.stopTest();

        System.assertEquals(1, result.totalRows, 'Session filter "Session" should match "Session A"');
    }

    @isTest
    static void testRunReport_programFilter_matches() {
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, null, 'Test', null, null, null, null);
        Test.stopTest();

        System.assertEquals(1, result.totalRows, 'Program filter should match "Test Program"');
    }

    @isTest
    static void testRunReport_statusFilter_matches() {
        String status = getFirstStatus();
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, null, null, new List<String>{ status }, null, null, null);
        Test.stopTest();

        System.assertEquals(1, result.totalRows, 'Status filter should match the registration');
    }

    @isTest
    static void testRunReport_statusFilter_excludes() {
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, null, null, new List<String>{ '__INVALID__' }, null, null, null);
        Test.stopTest();

        System.assertEquals(0, result.totalRows, 'Non-matching status should return 0 rows');
    }

    @isTest
    static void testRunReport_startDateFrom_matches() {
        String fromDate = Date.today().addDays(-1).format();
        // Date.format() returns locale format; use toStartOfMonth trick to get ISO
        String isoFrom = String.valueOf(Date.today().addDays(-1));
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, null, null, null, isoFrom, null, null);
        Test.stopTest();

        System.assertEquals(1, result.totalRows, 'Start date from yesterday should include today registration');
    }

    @isTest
    static void testRunReport_startDateTo_excludes() {
        String isoTo = String.valueOf(Date.today().addDays(-1));
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, null, null, null, null, isoTo, null);
        Test.stopTest();

        System.assertEquals(0, result.totalRows, 'End date before today should exclude today registration');
    }

    @isTest
    static void testRunReport_noAnswers_rowStillReturned() {
        // Registration with no answered questions should still appear as a row
        // Re-use the existing Contact to avoid Account-creation triggers
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'User' LIMIT 1];
        TREX1__Registration__c reg2 = new TREX1__Registration__c(
            TREX1__Contact__c             = con.Id,
            TREX1__Course_Name__c         = 'Empty Course',
            TREX1__Registration_Status__c = getFirstStatus()
        );
        insert reg2;

        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport('Empty', null, null, null, null, null, null);
        Test.stopTest();

        System.assertEquals(1, result.totalRows, 'Registration with no answers should still appear');
        System.assertEquals(0, result.questionColumns.size(), 'No question columns when no answers');
    }

    @isTest
    static void testRunReport_columnsSortedByGroupThenPriority() {
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, null, null, null, null, null, null);
        Test.stopTest();

        System.assertEquals(2, result.questionColumns.size());
        System.assertEquals('Favorite color?', result.questionColumns[0].label, 'Priority 1 first');
        System.assertEquals('Allergies?',       result.questionColumns[1].label, 'Priority 2 second');
    }

    @isTest
    static void testRunReport_columnInfoHasGroupName() {
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, null, null, null, null, null, null);
        Test.stopTest();

        System.assertEquals('Test Group', result.questionColumns[0].groupName);
        System.assertEquals('q_0',        result.questionColumns[0].fieldName);
    }

    // â”€â”€â”€ Saved Configurations â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @isTest
    static void testSaveAndLoadConfig() {
        String configJSON = '{"courseNameFilter":"Judaism","statusFilters":["Active"]}';

        Test.startTest();
        String newId = RegistrationReportController.saveConfig(null, 'My Test Config', 'A description', configJSON, 'Test Folder', 'Registrations');
        Test.stopTest();

        System.assertNotEquals(null, newId);
        Question_Report_Config__c saved = [
            SELECT Name, Description__c, Config_JSON__c, Last_Run_Date__c
            FROM Question_Report_Config__c WHERE Id = :newId
        ];
        System.assertEquals('My Test Config', saved.Name);
        System.assertEquals('A description', saved.Description__c);
        System.assertEquals(configJSON, saved.Config_JSON__c);
        System.assertNotEquals(null, saved.Last_Run_Date__c);
    }

    @isTest
    static void testSaveConfig_update() {
        String id1 = RegistrationReportController.saveConfig(null, 'Original', null, '{}', 'Test Folder', 'Registrations');
        Test.startTest();
        String id2 = RegistrationReportController.saveConfig(id1, 'Updated', 'desc', '{}', 'Test Folder', 'Registrations');
        Test.stopTest();

        System.assertEquals(id1, id2, 'Update should return same Id');
        Question_Report_Config__c updated = [SELECT Name, Description__c FROM Question_Report_Config__c WHERE Id = :id1];
        System.assertEquals('Updated', updated.Name);
    }

    @isTest
    static void testSaveConfig_blankName_throws() {
        Boolean threw = false;
        try {
            RegistrationReportController.saveConfig(null, '', null, '{}', 'Test Folder', 'Registrations');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AuraHandledException for blank name');
    }

    @isTest
    static void testLoadConfig() {
        String json = '{"courseNameFilter":"Intro to Judaism"}';
        String id = RegistrationReportController.saveConfig(null, 'Load Test', null, json, 'Test Folder', 'Registrations');
        Test.startTest();
        String loaded = RegistrationReportController.loadConfig(id);
        Test.stopTest();
        System.assertEquals(json, loaded);
    }

    @isTest
    static void testGetSavedConfigs() {
        RegistrationReportController.saveConfig(null, 'Config A', null, '{}', 'Test Folder', 'Registrations');
        RegistrationReportController.saveConfig(null, 'Config B', 'desc', '{}', 'Test Folder', 'Registrations');
        Test.startTest();
        List<RegistrationReportController.ConfigSummary> configs = RegistrationReportController.getSavedConfigs('Registrations');
        Test.stopTest();
        System.assert(configs.size() >= 2);
    }

    @isTest
    static void testDeleteConfig() {
        String id = RegistrationReportController.saveConfig(null, 'To Delete', null, '{}', 'Test Folder', 'Registrations');
        System.assertEquals(1, [SELECT COUNT() FROM Question_Report_Config__c WHERE Id = :id]);
        Test.startTest();
        RegistrationReportController.deleteConfig(id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Question_Report_Config__c WHERE Id = :id]);
    }

    // ─── getAvailableFields ────────────────────────────────────────────────────

    @isTest
    static void testGetAvailableFields() {
        Test.startTest();
        List<RegistrationReportController.FieldInfo> fields = RegistrationReportController.getAvailableFields();
        Test.stopTest();

        System.assert(!fields.isEmpty(), 'Should return available fields');
        RegistrationReportController.FieldInfo f = fields[0];
        System.assertNotEquals(null, f.apiKey);
        System.assertNotEquals(null, f.label);
        System.assertNotEquals(null, f.groupName);
        System.assert(
            f.apiKey.startsWith('xreg_') || f.apiKey.startsWith('xcnt_'),
            'apiKey must have xreg_ or xcnt_ prefix'
        );
    }

    @isTest
    static void testRunReport_withExtraFields() {
        // Dynamically pick an accessible xreg_ field that isn't already in the fixed SELECT
        List<RegistrationReportController.FieldInfo> available = RegistrationReportController.getAvailableFields();
        String xregField = null;
        for (RegistrationReportController.FieldInfo f : available) {
            if (f.apiKey.startsWith('xreg_')) { xregField = f.apiKey; break; }
        }
        if (xregField == null) return; // no xreg_ fields in this org — skip

        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, null, null, null, null, null,
                new List<String>{ xregField });
        Test.stopTest();

        System.assertEquals(1, result.totalRows, 'Should return 1 row with extra field');
        System.assert(result.rows[0].containsKey(xregField), 'Extra field key should be present in the row map');
    }

    @isTest
    static void testRunReport_withExtraCntField() {
        // Covers the xcnt_ branch in extra-field parsing
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, null, null, null, null, null,
                new List<String>{ 'xcnt_firstname' });
        Test.stopTest();

        System.assertEquals(1, result.totalRows);
        System.assert(result.rows[0].containsKey('xcnt_firstname'), 'xcnt_ field should appear in row');
    }

    @isTest
    static void testRunReport_blankExtraField_isSkipped() {
        // Covers the String.isBlank(key) continue branch — pass only a blank entry
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, null, null, null, null, null,
                new List<String>{ '' });
        Test.stopTest();

        System.assertEquals(1, result.totalRows, 'Blank extra field should be silently skipped');
    }

    @isTest
    static void testRunReport_bothDateFilters_match() {
        String isoFrom = String.valueOf(Date.today().addDays(-1));
        String isoTo   = String.valueOf(Date.today().addDays(1));
        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport(null, null, null, null, isoFrom, isoTo, null);
        Test.stopTest();

        System.assertEquals(1, result.totalRows, 'Both date filters should include today registration');
    }

    // ─── ColumnSorter edge cases ──────────────────────────────────────────────

    @isTest
    static void testRunReport_columnSorter_differentGroups() {
        // Covers gCmp != 0 branch in ColumnSorter
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'User' LIMIT 1];
        TREX1__Registration__c reg = new TREX1__Registration__c(
            TREX1__Contact__c             = con.Id,
            TREX1__Course_Name__c         = 'MultiGroup Course',
            TREX1__Registration_Status__c = getFirstStatus()
        );
        insert reg;

        TREX1__Question_Group__c gAlpha = new TREX1__Question_Group__c(Name = 'Alpha Group');
        TREX1__Question_Group__c gBeta  = new TREX1__Question_Group__c(Name = 'Beta Group');
        insert new List<TREX1__Question_Group__c>{ gAlpha, gBeta };

        TREX1__Custom_Question__c qB = new TREX1__Custom_Question__c(
            TREX1__Question_Group__c = gBeta.Id,
            TREX1__Question_Text__c  = 'Beta Q',
            TREX1__Sort_Priority__c  = 1,
            TREX1__Data_Type__c      = 'TextArea'
        );
        TREX1__Custom_Question__c qA = new TREX1__Custom_Question__c(
            TREX1__Question_Group__c = gAlpha.Id,
            TREX1__Question_Text__c  = 'Alpha Q',
            TREX1__Sort_Priority__c  = 1,
            TREX1__Data_Type__c      = 'TextArea'
        );
        insert new List<TREX1__Custom_Question__c>{ qB, qA };

        insert new List<TREX1__Answered_Question__c>{
            new TREX1__Answered_Question__c(
                TREX1__Registration__c       = reg.Id,
                TREX1__Contact__c            = con.Id,
                TREX1__aq_Question_Group__c  = gBeta.Id,
                TREX1__aq_Custom_Question__c = qB.Id,
                TREX1__Question__c           = 'Beta Q',
                TREX1__Answer__c             = 'B'
            ),
            new TREX1__Answered_Question__c(
                TREX1__Registration__c       = reg.Id,
                TREX1__Contact__c            = con.Id,
                TREX1__aq_Question_Group__c  = gAlpha.Id,
                TREX1__aq_Custom_Question__c = qA.Id,
                TREX1__Question__c           = 'Alpha Q',
                TREX1__Answer__c             = 'A'
            )
        };

        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport('MultiGroup', null, null, null, null, null, null);
        Test.stopTest();

        System.assertEquals(2, result.questionColumns.size());
        System.assertEquals('Alpha Group', result.questionColumns[0].groupName, 'Alpha Group should sort first');
        System.assertEquals('Beta Group',  result.questionColumns[1].groupName, 'Beta Group should sort second');
    }

    @isTest
    static void testRunReport_columnSorter_nullAndNonNullPriority() {
        // Covers both null-priority branches: (null vs nonNull) and (nonNull vs null)
        // Uses 3 questions to force both comparison directions
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'User' LIMIT 1];
        TREX1__Registration__c reg = new TREX1__Registration__c(
            TREX1__Contact__c             = con.Id,
            TREX1__Course_Name__c         = 'NullPriority Course',
            TREX1__Registration_Status__c = getFirstStatus()
        );
        insert reg;

        TREX1__Question_Group__c qg = new TREX1__Question_Group__c(Name = 'Priority Group');
        insert qg;

        TREX1__Custom_Question__c qHigh = new TREX1__Custom_Question__c(
            TREX1__Question_Group__c = qg.Id,
            TREX1__Question_Text__c  = 'High Priority',
            TREX1__Sort_Priority__c  = 5,
            TREX1__Data_Type__c      = 'TextArea'
        );
        TREX1__Custom_Question__c qLow = new TREX1__Custom_Question__c(
            TREX1__Question_Group__c = qg.Id,
            TREX1__Question_Text__c  = 'Low Priority',
            TREX1__Sort_Priority__c  = 2,
            TREX1__Data_Type__c      = 'TextArea'
        );
        TREX1__Custom_Question__c qNone = new TREX1__Custom_Question__c(
            TREX1__Question_Group__c = qg.Id,
            TREX1__Question_Text__c  = 'No Priority',
            TREX1__Data_Type__c      = 'TextArea'
        );
        insert new List<TREX1__Custom_Question__c>{ qHigh, qLow, qNone };

        insert new List<TREX1__Answered_Question__c>{
            new TREX1__Answered_Question__c(
                TREX1__Registration__c       = reg.Id,
                TREX1__Contact__c            = con.Id,
                TREX1__aq_Question_Group__c  = qg.Id,
                TREX1__aq_Custom_Question__c = qHigh.Id,
                TREX1__Question__c           = 'High Priority',
                TREX1__Answer__c             = 'H'
            ),
            new TREX1__Answered_Question__c(
                TREX1__Registration__c       = reg.Id,
                TREX1__Contact__c            = con.Id,
                TREX1__aq_Question_Group__c  = qg.Id,
                TREX1__aq_Custom_Question__c = qLow.Id,
                TREX1__Question__c           = 'Low Priority',
                TREX1__Answer__c             = 'L'
            ),
            new TREX1__Answered_Question__c(
                TREX1__Registration__c       = reg.Id,
                TREX1__Contact__c            = con.Id,
                TREX1__aq_Question_Group__c  = qg.Id,
                TREX1__aq_Custom_Question__c = qNone.Id,
                TREX1__Question__c           = 'No Priority',
                TREX1__Answer__c             = 'N'
            )
        };

        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport('NullPriority', null, null, null, null, null, null);
        Test.stopTest();

        System.assertEquals(3, result.questionColumns.size());
        // Questions with priorities should come before question with null priority
        System.assertEquals('No Priority', result.questionColumns[2].label, 'Null priority should sort last');
    }

    @isTest
    static void testRunReport_columnSorter_equalPriorities_sortsByLabel() {
        // Covers pCmp == 0 → falls through to label comparison
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'User' LIMIT 1];
        TREX1__Registration__c reg = new TREX1__Registration__c(
            TREX1__Contact__c             = con.Id,
            TREX1__Course_Name__c         = 'EqualPriority Course',
            TREX1__Registration_Status__c = getFirstStatus()
        );
        insert reg;

        TREX1__Question_Group__c qg = new TREX1__Question_Group__c(Name = 'Equal Group');
        insert qg;

        TREX1__Custom_Question__c qZ = new TREX1__Custom_Question__c(
            TREX1__Question_Group__c = qg.Id,
            TREX1__Question_Text__c  = 'Zebra Question',
            TREX1__Sort_Priority__c  = 3,
            TREX1__Data_Type__c      = 'TextArea'
        );
        TREX1__Custom_Question__c qA = new TREX1__Custom_Question__c(
            TREX1__Question_Group__c = qg.Id,
            TREX1__Question_Text__c  = 'Apple Question',
            TREX1__Sort_Priority__c  = 3,
            TREX1__Data_Type__c      = 'TextArea'
        );
        insert new List<TREX1__Custom_Question__c>{ qZ, qA };

        insert new List<TREX1__Answered_Question__c>{
            new TREX1__Answered_Question__c(
                TREX1__Registration__c       = reg.Id,
                TREX1__Contact__c            = con.Id,
                TREX1__aq_Question_Group__c  = qg.Id,
                TREX1__aq_Custom_Question__c = qZ.Id,
                TREX1__Question__c           = 'Zebra Question',
                TREX1__Answer__c             = 'Z'
            ),
            new TREX1__Answered_Question__c(
                TREX1__Registration__c       = reg.Id,
                TREX1__Contact__c            = con.Id,
                TREX1__aq_Question_Group__c  = qg.Id,
                TREX1__aq_Custom_Question__c = qA.Id,
                TREX1__Question__c           = 'Apple Question',
                TREX1__Answer__c             = 'A'
            )
        };

        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport('EqualPriority', null, null, null, null, null, null);
        Test.stopTest();

        System.assertEquals(2, result.questionColumns.size());
        System.assertEquals('Apple Question', result.questionColumns[0].label, 'Apple sorts before Zebra');
        System.assertEquals('Zebra Question', result.questionColumns[1].label);
    }

    @isTest
    static void testRunReport_aqWithNoQuestionGroup() {
        // Covers the null question-group branch: groupName set to '' when group is null
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'User' LIMIT 1];
        TREX1__Registration__c reg = new TREX1__Registration__c(
            TREX1__Contact__c             = con.Id,
            TREX1__Course_Name__c         = 'NoGroup Course',
            TREX1__Registration_Status__c = getFirstStatus()
        );
        insert reg;

        TREX1__Custom_Question__c q = new TREX1__Custom_Question__c(
            TREX1__Question_Text__c = 'Ungrouped Question',
            TREX1__Sort_Priority__c = 1,
            TREX1__Data_Type__c     = 'TextArea'
        );
        insert q;

        insert new TREX1__Answered_Question__c(
            TREX1__Registration__c       = reg.Id,
            TREX1__Contact__c            = con.Id,
            TREX1__aq_Custom_Question__c = q.Id,
            TREX1__Question__c           = 'Ungrouped Question',
            TREX1__Answer__c             = 'Answer'
        );

        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runReport('NoGroup', null, null, null, null, null, null);
        Test.stopTest();

        System.assertEquals(1, result.totalRows);
        System.assertEquals(1, result.questionColumns.size());
        System.assertEquals('', result.questionColumns[0].groupName, 'groupName should be empty string when no group');
    }

    // ─── Saved Reports — ownership & folder coverage ──────────────────────────

    @isTest
    static void testGetSavedConfigs_verifyFolder() {
        RegistrationReportController.saveConfig(null, 'Folder Check', null, '{}', 'My Folder', 'Registrations');
        Test.startTest();
        List<RegistrationReportController.ConfigSummary> configs = RegistrationReportController.getSavedConfigs('Registrations');
        Test.stopTest();

        Boolean found = false;
        for (RegistrationReportController.ConfigSummary c : configs) {
            if (c.name == 'Folder Check') {
                System.assertEquals('My Folder', c.folderName, 'folderName should be returned in ConfigSummary');
                found = true;
            }
        }
        System.assert(found, 'Saved config with folder should appear in getSavedConfigs');
    }

    @isTest
    static void testLoadConfig_notFound_throws() {
        // Covers the configs.isEmpty() throw in loadConfig
        Boolean threw = false;
        try {
            RegistrationReportController.loadConfig('a000000000000000AA');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'loadConfig with bad/unowned ID should throw');
    }

    @isTest
    static void testSaveConfig_updateNotOwned_throws() {
        // Covers the existing.isEmpty() throw in saveConfig update path
        Boolean threw = false;
        try {
            RegistrationReportController.saveConfig('a000000000000000AA', 'Name', null, '{}', 'Folder', 'Registrations');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Updating a config with bad/unowned ID should throw');
    }

    @isTest
    static void testDeleteConfig_notOwned_throws() {
        // Covers the toDelete.isEmpty() throw in deleteConfig
        Boolean threw = false;
        try {
            RegistrationReportController.deleteConfig('a000000000000000AA');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Deleting a config with bad/unowned ID should throw');
    }

    // ─── Enrollment Report ────────────────────────────────────────────────────

    private static String getFirstEnrollmentStatus() {
        Schema.DescribeFieldResult fr =
            TREX1__Course_Option_Enrollment__c.TREX1__Status__c.getDescribe();
        for (Schema.PicklistEntry e : fr.getPicklistValues()) {
            if (e.isActive()) return e.getValue();
        }
        return null;
    }

    /**
     * Two course options against the one registration from setup, so the fan-out
     * of a registration's answers across its enrollment rows is exercised.
     */
    private static void makeEnrollments() {
        TREX1__Registration__c reg = [SELECT Id, TREX1__Contact__c FROM TREX1__Registration__c LIMIT 1];

        List<TREX1__Course_Option__c> options = new List<TREX1__Course_Option__c>{
            new TREX1__Course_Option__c(Name = 'Beginner Swim | Mondays'),
            new TREX1__Course_Option__c(Name = 'Advanced Swim | Fridays')
        };
        insert options;

        insert new List<TREX1__Course_Option_Enrollment__c>{
            new TREX1__Course_Option_Enrollment__c(
                TREX1__coe_Registration__c   = reg.Id,
                TREX1__coe_Course_Option__c  = options[0].Id,
                TREX1__Contact__c            = reg.TREX1__Contact__c,
                TREX1__Type__c               = 'Standard Enrollment',
                TREX1__Status__c             = getFirstEnrollmentStatus(),
                TREX1__Start_Date__c         = Date.today()
            ),
            new TREX1__Course_Option_Enrollment__c(
                TREX1__coe_Registration__c   = reg.Id,
                TREX1__coe_Course_Option__c  = options[1].Id,
                TREX1__Contact__c            = reg.TREX1__Contact__c,
                TREX1__Type__c               = 'Standard Enrollment',
                TREX1__Status__c             = getFirstEnrollmentStatus(),
                TREX1__Start_Date__c         = Date.today()
            )
        };
    }

    @isTest
    static void testGetEnrollmentStatuses_returnsActiveValues() {
        Test.startTest();
        List<RegistrationReportController.PicklistOption> statuses =
            RegistrationReportController.getEnrollmentStatuses();
        Test.stopTest();

        Assert.isFalse(statuses.isEmpty(), 'Enrollment status picklist should return values');
        for (RegistrationReportController.PicklistOption opt : statuses) {
            Assert.isNotNull(opt.value, 'Every status option should carry a value');
            Assert.isNotNull(opt.label, 'Every status option should carry a label');
        }
    }

    @isTest
    static void testRunEnrollmentReport_oneRowPerEnrollment() {
        makeEnrollments();

        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runEnrollmentReport(
                null, null, null, null, null, null, null, null
            );
        Test.stopTest();

        Assert.areEqual(2, result.totalRows,
            'One registration with two course options should produce two enrollment rows');
        Assert.areEqual(2, result.questionColumns.size(),
            'Both setup questions should appear as columns');

        // The registration's answers repeat on each of its enrollment rows.
        for (Map<String, Object> row : result.rows) {
            Assert.isNotNull(row.get('courseOption'), 'Each row should name its course option');
            Assert.isNotNull(row.get('enrollmentId'), 'Each row should carry its enrollment id');
            Assert.areEqual('Test User', row.get('contactName'),
                'Contact comes from the enrollment, not the registration');
            Assert.areEqual('Test Program', row.get('programName'),
                'Program is read through the parent registration');
        }
    }

    @isTest
    static void testRunEnrollmentReport_excludesClassroomManagement() {
        makeEnrollments();

        TREX1__Registration__c reg = [SELECT Id, TREX1__Contact__c FROM TREX1__Registration__c LIMIT 1];
        TREX1__Course_Option__c extra = new TREX1__Course_Option__c(Name = 'Classroom Generated');
        insert extra;
        insert new TREX1__Course_Option_Enrollment__c(
            TREX1__coe_Registration__c  = reg.Id,
            TREX1__coe_Course_Option__c = extra.Id,
            TREX1__Contact__c           = reg.TREX1__Contact__c,
            TREX1__Type__c              = 'Classroom Management',
            TREX1__Status__c            = getFirstEnrollmentStatus(),
            TREX1__Start_Date__c        = Date.today()
        );

        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runEnrollmentReport(
                null, null, null, null, null, null, null, null
            );
        Test.stopTest();

        Assert.areEqual(2, result.totalRows,
            'Classroom Management enrollments are generated by Traction Rec and must never appear on a roster');
    }

    @isTest
    static void testRunEnrollmentReport_filtersByCourseOption() {
        makeEnrollments();

        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runEnrollmentReport(
                null, null, null, 'Beginner', null, null, null, null
            );
        Test.stopTest();

        Assert.areEqual(1, result.totalRows,
            'Course Option filter should match on a fragment of the name');
        Assert.areEqual('Beginner Swim | Mondays', result.rows[0].get('courseOption'),
            'The matching course option should be the one returned');
    }

    @isTest
    static void testRunEnrollmentReport_noMatchesReturnsEmpty() {
        makeEnrollments();

        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runEnrollmentReport(
                null, null, null, 'Nothing Matches This', null, null, null, null
            );
        Test.stopTest();

        Assert.areEqual(0, result.totalRows, 'No matching enrollments should return no rows');
        Assert.isTrue(result.questionColumns.isEmpty(),
            'No rows means no question columns to show');
    }

    @isTest
    static void testRunEnrollmentReport_withExtraFields() {
        makeEnrollments();

        Test.startTest();
        RegistrationReportController.ReportResult result =
            RegistrationReportController.runEnrollmentReport(
                null, null, null, null, null, null, null,
                new List<String>{ 'xreg_trex1__start_date__c', 'xcnt_mailingcity', 'bogus_key' }
            );
        Test.stopTest();

        Assert.areEqual(2, result.totalRows, 'Extra fields should not change the row count');
        Assert.areEqual(Date.today(), result.rows[0].get('xreg_trex1__start_date__c'),
            'Registration field should be read through the parent relationship');
        Assert.isFalse(result.rows[0].containsKey('xcnt_mailingcity'),
            'A field the base query already selects is skipped; it is on the row as mailingAddress');
        Assert.isFalse(result.rows[0].containsKey('bogus_key'),
            'Unrecognised field keys should be ignored');
    }

    // ─── Saved Report Scoping ─────────────────────────────────────────────────

    @isTest
    static void testGetSavedConfigs_scopedByReportType() {
        RegistrationReportController.saveConfig(null, 'Reg Report', null, '{}', 'Shared', 'Registrations');
        RegistrationReportController.saveConfig(null, 'Enr Report', null, '{}', 'Shared', 'Enrollments');

        Test.startTest();
        List<RegistrationReportController.ConfigSummary> regConfigs =
            RegistrationReportController.getSavedConfigs('Registrations');
        List<RegistrationReportController.ConfigSummary> enrConfigs =
            RegistrationReportController.getSavedConfigs('Enrollments');
        Test.stopTest();

        Assert.areEqual(1, regConfigs.size(), 'Registration list should hold only the registration report');
        Assert.areEqual('Reg Report', regConfigs[0].name, 'Wrong report returned for Registrations');
        Assert.areEqual(1, enrConfigs.size(), 'Enrollment list should hold only the enrollment report');
        Assert.areEqual('Enr Report', enrConfigs[0].name, 'Wrong report returned for Enrollments');
    }

    @isTest
    static void testGetSavedConfigs_blankTypeCountsAsRegistrations() {
        // A report saved before the enrollment report existed carries no type.
        Question_Report_Config__c legacy = new Question_Report_Config__c(
            Name = 'Legacy Report', Config_JSON__c = '{}', Folder_Name__c = 'Old'
        );
        insert legacy;

        Test.startTest();
        List<RegistrationReportController.ConfigSummary> regConfigs =
            RegistrationReportController.getSavedConfigs('Registrations');
        List<RegistrationReportController.ConfigSummary> enrConfigs =
            RegistrationReportController.getSavedConfigs('Enrollments');
        Test.stopTest();

        Assert.areEqual(1, regConfigs.size(), 'A blank report type should list under Registrations');
        Assert.areEqual('Legacy Report', regConfigs[0].name, 'Legacy report should be the one listed');
        Assert.isTrue(enrConfigs.isEmpty(), 'A blank report type must not appear under Enrollments');
    }
}

