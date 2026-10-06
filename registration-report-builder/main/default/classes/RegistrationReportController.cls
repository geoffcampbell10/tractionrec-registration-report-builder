public with sharing class RegistrationReportController {

    // Course Option Enrollment rows created by Traction Rec's Classroom Management
    // app are not registrations anyone made. They never belong on a roster, so the
    // enrollment report filters to this type and offers no way to change it.
    private static final String STANDARD_ENROLLMENT = 'Standard Enrollment';

    // Pre-flight ceilings. Both reports share them so the two paths fail the same way.
    private static final Integer MAX_PARENT_ROWS = 2000;
    private static final Integer MAX_ANSWERS     = 20000;

    // Report types, mirrored in Question_Report_Config__c.Report_Type__c.
    private static final String TYPE_ENROLLMENTS = 'Enrollments';

    // Fields the enrollment query already selects. Asking for one of these again as
    // an extra column makes SOQL reject the whole query as a duplicate select, and
    // the value is already on the row under its own key.
    private static final Set<String> BASE_REG_FIELDS = new Set<String>{
        'trex1__program_name__c', 'trex1__course_name__c',
        'trex1__course_session_name__c', 'trex1__registration_status__c'
    };
    private static final Set<String> BASE_CNT_FIELDS = new Set<String>{
        'name', 'email', 'phone', 'mailingstreet', 'mailingcity',
        'mailingstate', 'mailingpostalcode'
    };

    // Example text for the filter boxes when the org has not set its own.
    private static final Map<String, String> DEFAULT_PLACEHOLDERS = new Map<String, String>{
        'programName'  => 'e.g. Aquatics',
        'courseName'   => 'e.g. Swim Lessons',
        'courseSession'=> 'e.g. Spring 2025',
        'folderName'   => 'e.g. Aquatics, Summer 2025'
    };

    /**
     * Example text shown in the filter boxes. Naming conventions differ from org
     * to org, so this reads Registration_Report_Setting__mdt when a record exists
     * and falls back to the defaults above otherwise.
     *
     * The package deliberately ships no records of this type, so an upgrade never
     * overwrites what an admin configured.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getPlaceholders() {
        Map<String, String> result = new Map<String, String>(DEFAULT_PLACEHOLDERS);

        List<Registration_Report_Setting__mdt> settings = [
            SELECT Program_Name_Placeholder__c, Course_Name_Placeholder__c,
                   Course_Session_Placeholder__c, Folder_Name_Placeholder__c
            FROM Registration_Report_Setting__mdt
            ORDER BY DeveloperName
            LIMIT 1
        ];
        if (settings.isEmpty()) return result;

        Registration_Report_Setting__mdt s = settings[0];
        if (String.isNotBlank(s.Program_Name_Placeholder__c))   result.put('programName',   s.Program_Name_Placeholder__c);
        if (String.isNotBlank(s.Course_Name_Placeholder__c))    result.put('courseName',    s.Course_Name_Placeholder__c);
        if (String.isNotBlank(s.Course_Session_Placeholder__c)) result.put('courseSession', s.Course_Session_Placeholder__c);
        if (String.isNotBlank(s.Folder_Name_Placeholder__c))    result.put('folderName',    s.Folder_Name_Placeholder__c);
        return result;
    }

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

    /**
     * Status values for the enrollment report. Course Option Enrollment carries its
     * own status, independent of the parent registration's: an Active registration
     * can hold a Withdrawn enrollment, so the two lists must not be interchanged.
     *
     * @return Active picklist entries on TREX1__Course_Option_Enrollment__c.TREX1__Status__c
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getEnrollmentStatuses() {
        List<PicklistOption> options = new List<PicklistOption>();
        Schema.DescribeFieldResult fieldResult =
            TREX1__Course_Option_Enrollment__c.TREX1__Status__c.getDescribe();
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
            if (regCount > MAX_PARENT_ROWS) {
                throw new AuraHandledException(
                    'LIMIT:Your current filters match approximately ' + regCount + ' registrations — ' +
                    'too many to load at once. Try narrowing by Program, Course Name, ' +
                    'Start Date range, or Registration Status to bring this under ' +
                    MAX_PARENT_ROWS + ' records.'
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
            if (aqCount > MAX_ANSWERS) {
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

    /**
     * The enrollment report: one row per Course Option Enrollment rather than per
     * Registration. A registration covering three course options becomes three rows.
     *
     * Status and start date filter on the ENROLLMENT's own fields, not the parent
     * registration's. Program, course and course session still filter on the parent,
     * because the enrollment does not carry them.
     *
     * Answered questions hang off Registration and have no link to Course Option
     * Enrollment, so a registration's answers repeat across each of its rows.
     *
     * @param courseNameFilter    contains-match on the parent registration's course name
     * @param courseSessionFilter contains-match on the parent registration's course session
     * @param programNameFilter   contains-match on the parent registration's program
     * @param courseOptionFilter  contains-match on the Course Option's name
     * @param statusFilters       enrollment statuses to include; empty means all
     * @param startDateFrom       lower bound on the enrollment's start date
     * @param startDateTo         upper bound on the enrollment's start date
     * @param extraFields         xreg_/xcnt_ keys from the field picker
     * @return rows, question columns and a row count
     */
    @AuraEnabled
    public static ReportResult runEnrollmentReport(
        String courseNameFilter,
        String courseSessionFilter,
        String programNameFilter,
        String courseOptionFilter,
        List<String> statusFilters,
        String startDateFrom,
        String startDateTo,
        List<String> extraFields
    ) {
        if (!Schema.sObjectType.TREX1__Course_Option_Enrollment__c.isAccessible()) {
            throw new AuraHandledException('You do not have permission to view Course Option Enrollment records.');
        }
        if (!Schema.sObjectType.TREX1__Registration__c.isAccessible()) {
            throw new AuraHandledException('You do not have permission to view Registration records.');
        }
        if (!Schema.sObjectType.TREX1__Answered_Question__c.isAccessible()) {
            throw new AuraHandledException('You do not have permission to view Answered Question records.');
        }

        try {
            // ── Build bind variables ──────────────────────────────────────────
            String enrollmentType       = STANDARD_ENROLLMENT;
            String courseNamePattern    = buildLike(courseNameFilter);
            String courseSessionPattern = buildLike(courseSessionFilter);
            String programNamePattern   = buildLike(programNameFilter);
            String courseOptionPattern  = buildLike(courseOptionFilter);
            Date   startFrom = String.isNotBlank(startDateFrom) ? Date.valueOf(startDateFrom) : null;
            Date   startTo   = String.isNotBlank(startDateTo)   ? Date.valueOf(startDateTo)   : null;

            // ── Build Enrollment WHERE ────────────────────────────────────────
            String coeWhere = 'TREX1__Type__c = :enrollmentType';
            if (courseOptionPattern != null) {
                coeWhere += ' AND TREX1__coe_Course_Option__r.Name LIKE :courseOptionPattern';
            }
            if (courseNamePattern != null) {
                coeWhere += ' AND TREX1__coe_Registration__r.TREX1__Course_Name__c LIKE :courseNamePattern';
            }
            if (courseSessionPattern != null) {
                coeWhere += ' AND TREX1__coe_Registration__r.TREX1__Course_Session_Name__c LIKE :courseSessionPattern';
            }
            if (programNamePattern != null) {
                coeWhere += ' AND TREX1__coe_Registration__r.TREX1__Program_Name__c LIKE :programNamePattern';
            }
            if (statusFilters != null && !statusFilters.isEmpty()) {
                coeWhere += ' AND TREX1__Status__c IN :statusFilters';
            }
            if (startFrom != null) coeWhere += ' AND TREX1__Start_Date__c >= :startFrom';
            if (startTo   != null) coeWhere += ' AND TREX1__Start_Date__c <= :startTo';

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
                        if (BASE_REG_FIELDS.contains(api)) continue;
                        if (regFm.containsKey(api) && regFm.get(api).getDescribe().isAccessible()) {
                            extraRegFields.put(api, key);
                        }
                    } else if (key.startsWith('xcnt_')) {
                        String api = key.substringAfter('xcnt_').toLowerCase();
                        if (BASE_CNT_FIELDS.contains(api)) continue;
                        if (cntFm.containsKey(api) && cntFm.get(api).getDescribe().isAccessible()) {
                            extraCntFields.put(api, key);
                        }
                    }
                }
            }

            // ── Pre-flight: enrollment count ──────────────────────────────────
            Integer coeCount = Database.countQuery(
                'SELECT COUNT() FROM TREX1__Course_Option_Enrollment__c WHERE ' + coeWhere
            );
            if (coeCount > MAX_PARENT_ROWS) {
                throw new AuraHandledException(
                    'LIMIT:Your current filters match approximately ' + coeCount + ' enrollments — ' +
                    'too many to load at once. Try narrowing by Course Option, Program, Course Name, ' +
                    'Start Date range, or Enrollment Status to bring this under ' +
                    MAX_PARENT_ROWS + ' records.'
                );
            }

            // ── Query enrollments ─────────────────────────────────────────────
            String extraRegSel = '';
            for (String api : extraRegFields.keySet()) {
                extraRegSel += ', TREX1__coe_Registration__r.' + api;
            }
            String extraCntSel = '';
            for (String api : extraCntFields.keySet()) {
                extraCntSel += ', TREX1__Contact__r.' + api;
            }
            String coeSOQL =
                'SELECT Id, TREX1__Status__c, TREX1__Start_Date__c, TREX1__Withdrawal_Date__c,' +
                ' TREX1__Waitlist_Status__c, TREX1__Waitlist_Priority__c, TREX1__Waitlist_Expire_Date__c,' +
                ' TREX1__coe_Course_Option__r.Name,' +
                ' TREX1__coe_Registration__c,' +
                ' TREX1__coe_Registration__r.TREX1__Program_Name__c,' +
                ' TREX1__coe_Registration__r.TREX1__Course_Name__c,' +
                ' TREX1__coe_Registration__r.TREX1__Course_Session_Name__c,' +
                ' TREX1__coe_Registration__r.TREX1__Registration_Status__c,' +
                ' TREX1__Contact__r.Name, TREX1__Contact__r.Email, TREX1__Contact__r.Phone,' +
                ' TREX1__Contact__r.MailingStreet, TREX1__Contact__r.MailingCity,' +
                ' TREX1__Contact__r.MailingState, TREX1__Contact__r.MailingPostalCode' +
                extraRegSel + extraCntSel +
                ' FROM TREX1__Course_Option_Enrollment__c WHERE ' + coeWhere +
                ' ORDER BY TREX1__Contact__r.Name ASC NULLS LAST,' +
                ' TREX1__coe_Course_Option__r.Name ASC NULLS LAST, Id ASC';

            List<TREX1__Course_Option_Enrollment__c> enrollments = Database.query(coeSOQL);

            // Strip fields the running user cannot read (FLS enforcement)
            enrollments = (List<TREX1__Course_Option_Enrollment__c>)
                Security.stripInaccessible(AccessType.READABLE, enrollments).getRecords();

            if (enrollments.isEmpty()) {
                ReportResult empty = new ReportResult();
                empty.rows            = new List<Map<String, Object>>();
                empty.questionColumns = new List<ColumnInfo>();
                empty.totalRows       = 0;
                return empty;
            }

            // ── Collect the registrations behind these enrollments ────────────
            Set<Id> regIds = new Set<Id>();
            for (TREX1__Course_Option_Enrollment__c e : enrollments) {
                if (e.TREX1__coe_Registration__c != null) {
                    regIds.add(e.TREX1__coe_Registration__c);
                }
            }

            Map<Id, ColumnInfo>      questionMeta = new Map<Id, ColumnInfo>();
            Map<Id, Map<Id, String>> regAnswers   = new Map<Id, Map<Id, String>>();

            if (!regIds.isEmpty()) {
                // ── Pre-flight: AQ count ──────────────────────────────────────
                Integer aqCount = Database.countQuery(
                    'SELECT COUNT() FROM TREX1__Answered_Question__c WHERE TREX1__Registration__c IN :regIds'
                );
                if (aqCount > MAX_ANSWERS) {
                    throw new AuraHandledException(
                        'LIMIT:Your current filters match approximately ' + coeCount + ' enrollments with a high ' +
                        'volume of question responses — too many to load at once. Try narrowing by Course Option, ' +
                        'Program, Course Name, Start Date range, or Enrollment Status.'
                    );
                }

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

                aqs = (List<TREX1__Answered_Question__c>)
                    Security.stripInaccessible(AccessType.READABLE, aqs).getRecords();

                for (TREX1__Answered_Question__c aq : aqs) {
                    Id qId = aq.TREX1__aq_Custom_Question__c;
                    Id rId = aq.TREX1__Registration__c;
                    if (qId == null || rId == null) continue;

                    if (!questionMeta.containsKey(qId)) {
                        ColumnInfo ci = new ColumnInfo();
                        ci.questionId   = qId;
                        ci.label        = String.isNotBlank(aq.TREX1__aq_Custom_Question__r?.TREX1__Question_Text__c)
                                          ? aq.TREX1__aq_Custom_Question__r.TREX1__Question_Text__c
                                          : String.valueOf(qId);
                        ci.groupName    = aq.TREX1__aq_Question_Group__r != null
                                          ? aq.TREX1__aq_Question_Group__r.Name
                                          : '';
                        ci.sortPriority = aq.TREX1__aq_Custom_Question__r?.TREX1__Sort_Priority__c;
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

            // ── Build result rows, one per enrollment ─────────────────────────
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            for (TREX1__Course_Option_Enrollment__c e : enrollments) {
                TREX1__Registration__c parent = e.TREX1__coe_Registration__r;

                Map<String, Object> row = new Map<String, Object>();
                row.put('enrollmentId',       e.Id);
                row.put('registrationId',     e.TREX1__coe_Registration__c);
                row.put('contactName',        e.TREX1__Contact__r?.Name);
                row.put('email',              e.TREX1__Contact__r?.Email);
                row.put('phone',              e.TREX1__Contact__r?.Phone);
                row.put('mailingAddress',     buildAddress(e.TREX1__Contact__r));
                row.put('courseOption',       e.TREX1__coe_Course_Option__r?.Name);
                row.put('enrollmentStatus',   e.TREX1__Status__c);
                row.put('startDate',          e.TREX1__Start_Date__c);
                row.put('withdrawalDate',     e.TREX1__Withdrawal_Date__c);
                row.put('waitlistStatus',     e.TREX1__Waitlist_Status__c);
                row.put('waitlistPriority',   e.TREX1__Waitlist_Priority__c);
                row.put('waitlistExpireDate', e.TREX1__Waitlist_Expire_Date__c);
                row.put('programName',        parent?.TREX1__Program_Name__c);
                row.put('courseName',         parent?.TREX1__Course_Name__c);
                row.put('courseSession',      parent?.TREX1__Course_Session_Name__c);
                row.put('registrationStatus', parent?.TREX1__Registration_Status__c);

                // The same registration's answers repeat on each of its enrollment rows.
                Map<Id, String> ansMap = regAnswers.get(e.TREX1__coe_Registration__c);
                if (ansMap != null) {
                    for (Id qId : ansMap.keySet()) {
                        String fk = qFieldMap.get(qId);
                        if (fk != null) row.put(fk, ansMap.get(qId));
                    }
                }

                for (String api : extraRegFields.keySet()) {
                    row.put(extraRegFields.get(api), parent != null ? parent.get(api) : null);
                }
                for (String api : extraCntFields.keySet()) {
                    SObject cntRel = e.getSObject('TREX1__Contact__r');
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

    /**
     * Saved reports owned by the running user, scoped to one report type.
     *
     * Reports saved before the enrollment report existed have no Report_Type__c.
     * They are registration reports, so a blank value counts as Registrations.
     *
     * @param reportType 'Enrollments', or anything else for registration reports
     * @return the user's saved reports of that type
     */
    @AuraEnabled
    public static List<ConfigSummary> getSavedConfigs(String reportType) {
        if (!Schema.sObjectType.Question_Report_Config__c.isAccessible()) {
            return new List<ConfigSummary>();
        }
        Id      currentUser     = UserInfo.getUserId();
        String  enrollmentType  = TYPE_ENROLLMENTS;
        Boolean wantsEnrollment = TYPE_ENROLLMENTS.equalsIgnoreCase(reportType);

        List<Question_Report_Config__c> configs = wantsEnrollment
            ? [
                SELECT Id, Name, Description__c, Last_Run_Date__c, Folder_Name__c, Report_Type__c
                FROM Question_Report_Config__c
                WHERE OwnerId = :currentUser AND Report_Type__c = :enrollmentType
                ORDER BY Folder_Name__c ASC NULLS LAST, LastModifiedDate DESC
                LIMIT 50
              ]
            : [
                SELECT Id, Name, Description__c, Last_Run_Date__c, Folder_Name__c, Report_Type__c
                FROM Question_Report_Config__c
                WHERE OwnerId = :currentUser AND (Report_Type__c = null OR Report_Type__c != :enrollmentType)
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
            s.reportType  = c.Report_Type__c;
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
        String folderName,
        String reportType
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
        // Stored so the saved report loads back into the report type it was built in.
        config.Report_Type__c   = TYPE_ENROLLMENTS.equalsIgnoreCase(reportType)
            ? TYPE_ENROLLMENTS
            : 'Registrations';
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
        @AuraEnabled public String reportType;
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
