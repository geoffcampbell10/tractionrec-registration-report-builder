public with sharing class RegistrationReportController {

    // ─── Metadata Lookups ─────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getRegistrationStatuses() {
        List<PicklistOption> options = new List<PicklistOption>();
        Schema.DescribeFieldResult fieldResult =
            TREX1__Registration__c.TREX1__Registration_Status__c.getDescribe();
        for (Schema.PicklistEntry e : fieldResult.getPicklistValues()) {
            if (e.isActive()) {
                PicklistOption opt = new PicklistOption();
                opt.value = e.getValue();
                opt.label = e.getLabel();
                options.add(opt);
            }
        }
        return options;
    }

    // ─── Report Execution ─────────────────────────────────────────────────────

    @AuraEnabled
    public static ReportResult runReport(
        String courseNameFilter,
        String courseSessionFilter,
        String programNameFilter,
        List<String> statusFilters,
        String startDateFrom,
        String startDateTo,
        List<String> extraFields
    ) {
        // Object-level read access check
        if (!Schema.sObjectType.TREX1__Registration__c.isAccessible()) {
            throw new AuraHandledException('You do not have permission to view Registration records.');
        }
        if (!Schema.sObjectType.TREX1__Answered_Question__c.isAccessible()) {
            throw new AuraHandledException('You do not have permission to view Answered Question records.');
        }

        try {
            // ── Build bind variables ──────────────────────────────────────────
            String courseNamePattern    = buildLike(courseNameFilter);
            String courseSessionPattern = buildLike(courseSessionFilter);
            String programNamePattern   = buildLike(programNameFilter);
            Date   startFrom = String.isNotBlank(startDateFrom) ? Date.valueOf(startDateFrom) : null;
            Date   startTo   = String.isNotBlank(startDateTo)   ? Date.valueOf(startDateTo)   : null;

            // ── Build Registration WHERE ───────────────────────────────────────
            String regWhere = 'Id != null';
            if (courseNamePattern   != null) regWhere += ' AND TREX1__Course_Name__c LIKE :courseNamePattern';
            if (courseSessionPattern != null) regWhere += ' AND TREX1__Course_Session_Name__c LIKE :courseSessionPattern';
            if (programNamePattern  != null) regWhere += ' AND TREX1__Program_Name__c LIKE :programNamePattern';
            if (statusFilters != null && !statusFilters.isEmpty()) {
                regWhere += ' AND TREX1__Registration_Status__c IN :statusFilters';
            }
            if (startFrom != null) regWhere += ' AND TREX1__Start_Date__c >= :startFrom';
            if (startTo   != null) regWhere += ' AND TREX1__Start_Date__c <= :startTo';

            // ── Validate and parse extra fields ───────────────────────────────
            Map<String, String> extraRegFields = new Map<String, String>();
            Map<String, String> extraCntFields = new Map<String, String>();
            if (extraFields != null && !extraFields.isEmpty()) {
                Map<String, Schema.SObjectField> regFm =
                    Schema.SObjectType.TREX1__Registration__c.fields.getMap();
                Map<String, Schema.SObjectField> cntFm =
                    Schema.SObjectType.Contact.fields.getMap();
                for (String key : extraFields) {
                    if (String.isBlank(key)) continue;
                    if (key.startsWith('xreg_')) {
                        String api = key.substringAfter('xreg_').toLowerCase();
                        if (regFm.containsKey(api) && regFm.get(api).getDescribe().isAccessible()) {
                            extraRegFields.put(api, key);
                        }
                    } else if (key.startsWith('xcnt_')) {
                        String api = key.substringAfter('xcnt_').toLowerCase();
                        if (cntFm.containsKey(api) && cntFm.get(api).getDescribe().isAccessible()) {
                            extraCntFields.put(api, key);
                        }
                    }
                }
            }

            // ── Pre-flight: registration count ────────────────────────────────
            Integer regCount = Database.countQuery(
                'SELECT COUNT() FROM TREX1__Registration__c WHERE ' + regWhere
            );
            if (regCount > 2000) {
                throw new AuraHandledException(
                    'LIMIT:Your current filters match approximately ' + regCount + ' registrations — ' +
                    'too many to load at once. Try narrowing by Program, Course Name, ' +
                    'Start Date range, or Registration Status to bring this under 2,000 records.'
                );
            }

            // ── Query registrations ───────────────────────────────────────────
            String extraRegSel = '';
            for (String api : extraRegFields.keySet()) {
                extraRegSel += ', ' + api;
            }
            String extraCntSel = '';
            for (String api : extraCntFields.keySet()) {
                extraCntSel += ', TREX1__Contact__r.' + api;
            }
            String regSOQL =
                'SELECT Id, TREX1__Course_Name__c, TREX1__Course_Session_Name__c,' +
                ' TREX1__Program_Name__c, TREX1__Registration_Status__c, TREX1__Start_Date__c,' +
                ' TREX1__Contact__r.Name, TREX1__Contact__r.Email,' +
                ' TREX1__Contact__r.Phone,' +
                ' TREX1__Contact__r.MailingStreet, TREX1__Contact__r.MailingCity,' +
                ' TREX1__Contact__r.MailingState, TREX1__Contact__r.MailingPostalCode' +
                extraRegSel + extraCntSel +
                ' FROM TREX1__Registration__c WHERE ' + regWhere +
                ' ORDER BY TREX1__Contact__r.Name ASC NULLS LAST, Id ASC';

            List<TREX1__Registration__c> regs = Database.query(regSOQL);

            // Strip fields the running user cannot read (FLS enforcement)
            regs = (List<TREX1__Registration__c>)
                Security.stripInaccessible(AccessType.READABLE, regs).getRecords();

            if (regs.isEmpty()) {
                ReportResult empty = new ReportResult();
                empty.rows            = new List<Map<String, Object>>();
                empty.questionColumns = new List<ColumnInfo>();
                empty.totalRows       = 0;
                return empty;
            }

            // ── Collect ordered reg IDs ───────────────────────────────────────
            List<Id> regOrder = new List<Id>();
            Map<Id, TREX1__Registration__c> regMap = new Map<Id, TREX1__Registration__c>();
            for (TREX1__Registration__c r : regs) {
                regOrder.add(r.Id);
                regMap.put(r.Id, r);
            }
            Set<Id> regIds = regMap.keySet();

            // ── Pre-flight: AQ count ──────────────────────────────────────────
            Integer aqCount = Database.countQuery(
                'SELECT COUNT() FROM TREX1__Answered_Question__c WHERE TREX1__Registration__c IN :regIds'
            );
            if (aqCount > 20000) {
                throw new AuraHandledException(
                    'LIMIT:Your current filters match approximately ' + regCount + ' registrations with a high ' +
                    'volume of question responses — too many to load at once. Try narrowing by Program, Course Name, ' +
                    'Start Date range, or Registration Status to bring this under 2,000 records.'
                );
            }

            // ── Main AQ query ─────────────────────────────────────────────────
            List<TREX1__Answered_Question__c> aqs = Database.query(
                'SELECT TREX1__Registration__c, TREX1__aq_Custom_Question__c,' +
                ' TREX1__aq_Custom_Question__r.TREX1__Question_Text__c,' +
                ' TREX1__aq_Custom_Question__r.TREX1__Sort_Priority__c,' +
                ' TREX1__aq_Question_Group__r.Name,' +
                ' TREX1__Answer__c, CreatedDate' +
                ' FROM TREX1__Answered_Question__c' +
                ' WHERE TREX1__Registration__c IN :regIds' +
                ' ORDER BY TREX1__Registration__c, TREX1__aq_Custom_Question__c, CreatedDate DESC'
            );

            // Strip fields the running user cannot read (FLS enforcement)
            aqs = (List<TREX1__Answered_Question__c>)
                Security.stripInaccessible(AccessType.READABLE, aqs).getRecords();

            // ── Collect question metadata + answers ───────────────────────────
            Map<Id, ColumnInfo> questionMeta = new Map<Id, ColumnInfo>();
            Map<Id, Map<Id, String>> regAnswers = new Map<Id, Map<Id, String>>();

            for (TREX1__Answered_Question__c aq : aqs) {
                Id qId = aq.TREX1__aq_Custom_Question__c;
                Id rId = aq.TREX1__Registration__c;
                if (qId == null || rId == null) continue;

                if (!questionMeta.containsKey(qId)) {
                    ColumnInfo ci = new ColumnInfo();
                    ci.questionId    = qId;
                    ci.label         = String.isNotBlank(aq.TREX1__aq_Custom_Question__r?.TREX1__Question_Text__c)
                                       ? aq.TREX1__aq_Custom_Question__r.TREX1__Question_Text__c
                                       : String.valueOf(qId);
                    ci.groupName     = aq.TREX1__aq_Question_Group__r != null
                                       ? aq.TREX1__aq_Question_Group__r.Name
                                       : '';
                    ci.sortPriority  = aq.TREX1__aq_Custom_Question__r?.TREX1__Sort_Priority__c;
                    questionMeta.put(qId, ci);
                }

                if (!regAnswers.containsKey(rId)) {
                    regAnswers.put(rId, new Map<Id, String>());
                }
                Map<Id, String> ansMap = regAnswers.get(rId);
                if (!ansMap.containsKey(qId)) {
                    ansMap.put(qId, aq.TREX1__Answer__c != null ? aq.TREX1__Answer__c : '');
                }
            }

            // ── Sort questions: group ASC, priority NULLS LAST, label ASC ─────
            List<ColumnInfo> sortedCols = new List<ColumnInfo>(questionMeta.values());
            sortedCols.sort(new ColumnSorter());
            for (Integer i = 0; i < sortedCols.size(); i++) {
                sortedCols[i].fieldName = 'q_' + i;
            }

            Map<Id, String> qFieldMap = new Map<Id, String>();
            for (ColumnInfo ci : sortedCols) {
                qFieldMap.put(ci.questionId, ci.fieldName);
            }

            // ── Build result rows ─────────────────────────────────────────────
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            for (Id rId : regOrder) {
                TREX1__Registration__c r = regMap.get(rId);
                Map<String, Object> row = new Map<String, Object>();
                row.put('registrationId',     rId);
                row.put('contactName',         r.TREX1__Contact__r?.Name);
                row.put('email',               r.TREX1__Contact__r?.Email);
                row.put('phone',               r.TREX1__Contact__r?.Phone);
                row.put('mailingAddress',      buildAddress(r.TREX1__Contact__r));
                row.put('programName',         r.TREX1__Program_Name__c);
                row.put('courseName',          r.TREX1__Course_Name__c);
                row.put('courseSession',       r.TREX1__Course_Session_Name__c);
                row.put('startDate',           r.TREX1__Start_Date__c);
                row.put('registrationStatus',  r.TREX1__Registration_Status__c);

                Map<Id, String> ansMap = regAnswers.get(rId);
                if (ansMap != null) {
                    for (Id qId : ansMap.keySet()) {
                        String fk = qFieldMap.get(qId);
                        if (fk != null) row.put(fk, ansMap.get(qId));
                    }
                }

                for (String api : extraRegFields.keySet()) {
                    row.put(extraRegFields.get(api), r.get(api));
                }
                for (String api : extraCntFields.keySet()) {
                    SObject cntRel = r.getSObject('TREX1__Contact__r');
                    row.put(extraCntFields.get(api), cntRel != null ? cntRel.get(api) : null);
                }

                rows.add(row);
            }

            ReportResult result = new ReportResult();
            result.rows            = rows;
            result.questionColumns = sortedCols;
            result.totalRows       = rows.size();
            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Report error: ' + e.getMessage());
        }
    }

    // ─── Inner Types ──────────────────────────────────────────────────────────

    public class PicklistOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class ColumnInfo {
        @AuraEnabled public String  fieldName;
        @AuraEnabled public String  label;
        @AuraEnabled public String  groupName;
        // internal sort helpers — not serialized to LWC
        public Id      questionId;
        public Decimal sortPriority;
    }

    public class ReportResult {
        @AuraEnabled public List<Map<String, Object>> rows;
        @AuraEnabled public List<ColumnInfo>          questionColumns;
        @AuraEnabled public Integer                   totalRows;
    }

    private class ColumnSorter implements Comparator<ColumnInfo> {
        public Integer compare(ColumnInfo a, ColumnInfo b) {
            String gA = a.groupName != null ? a.groupName : '';
            String gB = b.groupName != null ? b.groupName : '';
            Integer gCmp = gA.compareTo(gB);
            if (gCmp != 0) return gCmp;

            if (a.sortPriority == null && b.sortPriority != null) return 1;
            if (a.sortPriority != null && b.sortPriority == null) return -1;
            if (a.sortPriority != null && b.sortPriority != null) {
                Integer pCmp = (Integer)(a.sortPriority - b.sortPriority);
                if (pCmp != 0) return pCmp;
            }

            String lA = a.label != null ? a.label : '';
            String lB = b.label != null ? b.label : '';
            return lA.compareTo(lB);
        }
    }

    // ─── Saved Configurations ─────────────────────────────────────────────────

    @AuraEnabled
    public static List<ConfigSummary> getSavedConfigs() {
        if (!Schema.sObjectType.Question_Report_Config__c.isAccessible()) {
            return new List<ConfigSummary>();
        }
        Id currentUser = UserInfo.getUserId();
        List<Question_Report_Config__c> configs = [
            SELECT Id, Name, Description__c, Last_Run_Date__c, Folder_Name__c
            FROM Question_Report_Config__c
            WHERE OwnerId = :currentUser
            ORDER BY Folder_Name__c ASC NULLS LAST, LastModifiedDate DESC
            LIMIT 50
        ];
        List<ConfigSummary> summaries = new List<ConfigSummary>();
        for (Question_Report_Config__c c : configs) {
            ConfigSummary s = new ConfigSummary();
            s.id          = c.Id;
            s.name        = c.Name;
            s.description = c.Description__c;
            s.folderName  = c.Folder_Name__c;
            s.lastRunDate = c.Last_Run_Date__c != null
                ? c.Last_Run_Date__c.format('M/d/yyyy h:mm a')
                : null;
            summaries.add(s);
        }
        return summaries;
    }

    @AuraEnabled
    public static String loadConfig(String configId) {
        if (!Schema.sObjectType.Question_Report_Config__c.isAccessible()) {
            throw new AuraHandledException('You do not have permission to access saved configurations.');
        }
        Id currentUser = UserInfo.getUserId();
        List<Question_Report_Config__c> configs = [
            SELECT Config_JSON__c
            FROM Question_Report_Config__c
            WHERE Id = :configId AND OwnerId = :currentUser
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            throw new AuraHandledException('Configuration not found.');
        }
        return configs[0].Config_JSON__c;
    }

    @AuraEnabled
    public static String saveConfig(
        String configId,
        String name,
        String description,
        String configJSON,
        String folderName
    ) {
        if (String.isBlank(name)) {
            throw new AuraHandledException('Configuration name is required.');
        }

        Boolean isUpdate = String.isNotBlank(configId);

        if (isUpdate) {
            if (!Schema.sObjectType.Question_Report_Config__c.isUpdateable()) {
                throw new AuraHandledException('You do not have permission to update saved configurations.');
            }
            // Verify ownership before allowing update
            List<Question_Report_Config__c> existing = [
                SELECT Id FROM Question_Report_Config__c
                WHERE Id = :configId AND OwnerId = :UserInfo.getUserId()
                LIMIT 1
            ];
            if (existing.isEmpty()) {
                throw new AuraHandledException('You can only update configurations that you created.');
            }
        } else {
            if (!Schema.sObjectType.Question_Report_Config__c.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create saved configurations.');
            }
        }

        Question_Report_Config__c config = isUpdate
            ? new Question_Report_Config__c(Id = configId)
            : new Question_Report_Config__c();
        config.Name             = name;
        config.Description__c   = description;
        config.Config_JSON__c   = configJSON;
        config.Folder_Name__c   = String.isNotBlank(folderName) ? folderName.trim() : null;
        config.Last_Run_Date__c = Datetime.now();
        upsert config;
        return config.Id;
    }

    @AuraEnabled
    public static void deleteConfig(String configId) {
        if (!Schema.sObjectType.Question_Report_Config__c.isDeletable()) {
            throw new AuraHandledException('You do not have permission to delete saved configurations.');
        }
        // Only allow deletion of configs owned by the running user
        List<Question_Report_Config__c> toDelete = [
            SELECT Id FROM Question_Report_Config__c
            WHERE Id = :configId AND OwnerId = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (toDelete.isEmpty()) {
            throw new AuraHandledException('You can only delete configurations that you created.');
        }
        delete toDelete;
    }

    public class ConfigSummary {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String folderName;
        @AuraEnabled public String lastRunDate;
    }

    // ─── Available Fields for Field Picker ───────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getAvailableFields() {
        List<FieldInfo> result = new List<FieldInfo>();

        Set<String> skipReg = new Set<String>{
            'id', 'ownerid', 'isdeleted', 'createddate', 'createdbyid',
            'lastmodifieddate', 'lastmodifiedbyid', 'systemmodstamp',
            'lastactivitydate', 'lastreferenceddate', 'lastvieweddate',
            'trex1__contact__c',
            'trex1__course_name__c', 'trex1__course_session_name__c',
            'trex1__program_name__c', 'trex1__registration_status__c',
            'trex1__start_date__c'
        };

        Set<String> skipCnt = new Set<String>{
            'id', 'ownerid', 'masterrecordid', 'isdeleted',
            'createddate', 'createdbyid', 'lastmodifieddate', 'lastmodifiedbyid',
            'systemmodstamp', 'lastactivitydate', 'lastreferenceddate', 'lastvieweddate',
            'lastcurequestdate', 'lastcuupdatedate',
            'name', 'email', 'phone',
            'mailingstreet', 'mailingcity', 'mailingstate', 'mailingpostalcode',
            'mailinglatitude', 'mailinglongitude', 'mailinggeocodeaccuracy', 'mailingaddress',
            'otherlatitude', 'otherlongitude', 'othergeocodeaccuracy', 'otheraddress',
            'jigsawcontactid', 'jigsaw'
        };

        Set<Schema.DisplayType> supported = new Set<Schema.DisplayType>{
            Schema.DisplayType.STRING,      Schema.DisplayType.TEXTAREA,
            Schema.DisplayType.PICKLIST,    Schema.DisplayType.MULTIPICKLIST,
            Schema.DisplayType.EMAIL,       Schema.DisplayType.PHONE,
            Schema.DisplayType.URL,         Schema.DisplayType.INTEGER,
            Schema.DisplayType.DOUBLE,      Schema.DisplayType.CURRENCY,
            Schema.DisplayType.BOOLEAN,     Schema.DisplayType.DATE,
            Schema.DisplayType.DATETIME,    Schema.DisplayType.PERCENT
        };

        Map<String, Schema.SObjectField> regFm =
            Schema.SObjectType.TREX1__Registration__c.fields.getMap();
        for (String apiName : regFm.keySet()) {
            if (skipReg.contains(apiName)) continue;
            Schema.DescribeFieldResult fr = regFm.get(apiName).getDescribe();
            if (!fr.isAccessible() || fr.isAutoNumber() || !supported.contains(fr.getType())) continue;
            FieldInfo fi = new FieldInfo();
            fi.apiKey    = 'xreg_' + apiName;
            fi.label     = fr.getLabel();
            fi.groupName = 'Registration';
            fi.fieldType = mapApexTypeToLwc(fr.getType());
            result.add(fi);
        }

        Map<String, Schema.SObjectField> cntFm = Schema.SObjectType.Contact.fields.getMap();
        for (String apiName : cntFm.keySet()) {
            if (skipCnt.contains(apiName)) continue;
            Schema.DescribeFieldResult fr = cntFm.get(apiName).getDescribe();
            if (!fr.isAccessible() || fr.isAutoNumber() || !supported.contains(fr.getType())) continue;
            FieldInfo fi = new FieldInfo();
            fi.apiKey    = 'xcnt_' + apiName;
            fi.label     = fr.getLabel();
            fi.groupName = 'Contact';
            fi.fieldType = mapApexTypeToLwc(fr.getType());
            result.add(fi);
        }

        result.sort(new FieldSorter());
        return result;
    }

    public class FieldInfo {
        @AuraEnabled public String apiKey;
        @AuraEnabled public String label;
        @AuraEnabled public String groupName;
        @AuraEnabled public String fieldType;
    }

    private class FieldSorter implements Comparator<FieldInfo> {
        public Integer compare(FieldInfo a, FieldInfo b) {
            Integer gCmp = a.groupName.compareTo(b.groupName);
            if (gCmp != 0) return gCmp;
            return a.label.compareTo(b.label);
        }
    }

    private static String mapApexTypeToLwc(Schema.DisplayType t) {
        if (t == Schema.DisplayType.BOOLEAN)  return 'boolean';
        if (t == Schema.DisplayType.DATE)     return 'date-local';
        if (t == Schema.DisplayType.DATETIME) return 'date';
        if (t == Schema.DisplayType.EMAIL)    return 'email';
        if (t == Schema.DisplayType.PHONE)    return 'phone';
        if (t == Schema.DisplayType.URL)      return 'url';
        if (t == Schema.DisplayType.CURRENCY) return 'currency';
        if (t == Schema.DisplayType.INTEGER || t == Schema.DisplayType.DOUBLE ||
            t == Schema.DisplayType.PERCENT)  return 'number';
        return 'text';
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    private static String buildLike(String raw) {
        return String.isNotBlank(raw) ? '%' + raw + '%' : null;
    }

    private static String buildAddress(Contact c) {
        if (c == null) return '';
        List<String> parts = new List<String>();
        if (String.isNotBlank(c.MailingStreet))    parts.add(c.MailingStreet);
        if (String.isNotBlank(c.MailingCity))       parts.add(c.MailingCity);
        if (String.isNotBlank(c.MailingState))      parts.add(c.MailingState);
        if (String.isNotBlank(c.MailingPostalCode)) parts.add(c.MailingPostalCode);
        return String.join(parts, ', ');
    }
}
