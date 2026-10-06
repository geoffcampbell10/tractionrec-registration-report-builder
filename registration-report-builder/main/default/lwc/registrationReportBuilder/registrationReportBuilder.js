import { LightningElement } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import SheetJS from '@salesforce/resourceUrl/SheetJS';
import JsPDF from '@salesforce/resourceUrl/JsPDF';
import getRegistrationStatuses from '@salesforce/apex/RegistrationReportController.getRegistrationStatuses';
import getEnrollmentStatuses from '@salesforce/apex/RegistrationReportController.getEnrollmentStatuses';
import runEnrollmentReport from '@salesforce/apex/RegistrationReportController.runEnrollmentReport';
import getAvailableFields from '@salesforce/apex/RegistrationReportController.getAvailableFields';
import runReport from '@salesforce/apex/RegistrationReportController.runReport';
import getSavedConfigs from '@salesforce/apex/RegistrationReportController.getSavedConfigs';
import loadConfig from '@salesforce/apex/RegistrationReportController.loadConfig';
import saveConfig from '@salesforce/apex/RegistrationReportController.saveConfig';
import deleteConfig from '@salesforce/apex/RegistrationReportController.deleteConfig';

import getPlaceholders from '@salesforce/apex/RegistrationReportController.getPlaceholders';

// The two report types. These strings are stored on Question_Report_Config__c
// and matched in Apex, so they are not free text.
const TYPE_REGISTRATIONS = 'Registrations';
const TYPE_ENROLLMENTS   = 'Enrollments';

const FIXED_COLUMN_DEFS = [
    { label: 'Name',                fieldName: 'contactName',        type: 'text',       initialWidth: 180, sortable: true  },
    { label: 'Email',               fieldName: 'email',              type: 'email',      initialWidth: 200, sortable: false },
    { label: 'Phone',               fieldName: 'phone',              type: 'phone',      initialWidth: 140, sortable: false },
    { label: 'Mailing Address',     fieldName: 'mailingAddress',     type: 'text',       initialWidth: 240, sortable: false },
    { label: 'Program',             fieldName: 'programName',        type: 'text',       initialWidth: 180, sortable: true  },
    { label: 'Course',              fieldName: 'courseName',         type: 'text',       initialWidth: 200, sortable: true  },
    { label: 'Course Session',      fieldName: 'courseSession',      type: 'text',       initialWidth: 180, sortable: true  },
    { label: 'Start Date',          fieldName: 'startDate',          type: 'date-local', initialWidth: 130, sortable: true  },
    { label: 'Registration Status', fieldName: 'registrationStatus', type: 'text',       initialWidth: 160, sortable: true  },
];

// Enrollment rows carry the enrollment's own status and dates alongside the parent
// registration's. Withdrawal and waitlist columns start hidden: most orgs barely use
// the waitlist, and showing six near-empty columns by default buries the useful ones.
const ENROLLMENT_COLUMN_DEFS = [
    { label: 'Name',                fieldName: 'contactName',        type: 'text',       initialWidth: 180, sortable: true,  defaultOn: true  },
    { label: 'Email',               fieldName: 'email',              type: 'email',      initialWidth: 200, sortable: false, defaultOn: true  },
    { label: 'Phone',               fieldName: 'phone',              type: 'phone',      initialWidth: 140, sortable: false, defaultOn: true  },
    { label: 'Mailing Address',     fieldName: 'mailingAddress',     type: 'text',       initialWidth: 240, sortable: false, defaultOn: true  },
    { label: 'Course Option',       fieldName: 'courseOption',       type: 'text',       initialWidth: 240, sortable: true,  defaultOn: true  },
    { label: 'Enrollment Status',   fieldName: 'enrollmentStatus',   type: 'text',       initialWidth: 160, sortable: true,  defaultOn: true  },
    { label: 'Start Date',          fieldName: 'startDate',          type: 'date-local', initialWidth: 130, sortable: true,  defaultOn: true  },
    { label: 'Program',             fieldName: 'programName',        type: 'text',       initialWidth: 180, sortable: true,  defaultOn: true  },
    { label: 'Course',              fieldName: 'courseName',         type: 'text',       initialWidth: 200, sortable: true,  defaultOn: true  },
    { label: 'Course Session',      fieldName: 'courseSession',      type: 'text',       initialWidth: 180, sortable: true,  defaultOn: true  },
    { label: 'Registration Status', fieldName: 'registrationStatus', type: 'text',       initialWidth: 160, sortable: true,  defaultOn: false },
    { label: 'Withdrawal Date',     fieldName: 'withdrawalDate',     type: 'date-local', initialWidth: 140, sortable: true,  defaultOn: false },
    { label: 'Waitlist Status',     fieldName: 'waitlistStatus',     type: 'text',       initialWidth: 140, sortable: true,  defaultOn: false },
    { label: 'Waitlist Priority',   fieldName: 'waitlistPriority',   type: 'text',       initialWidth: 140, sortable: true,  defaultOn: false },
    { label: 'Waitlist Expires',    fieldName: 'waitlistExpireDate', type: 'date-local', initialWidth: 140, sortable: true,  defaultOn: false },
];

function defaultVisibility(defs) {
    const v = {};
    defs.forEach(c => { v[c.fieldName] = c.defaultOn !== false; });
    return v;
}

export default class RegistrationReportBuilder extends LightningElement {

    // Filter example text, overridable per org via Registration_Report_Setting__mdt.
    // Seeded with the same defaults the Apex side falls back to, so the inputs are
    // never blank while the call is in flight.
    placeholder = {
        programPlaceholder: 'e.g. Aquatics',
        coursePlaceholder:  'e.g. Swim Lessons',
        sessionPlaceholder: 'e.g. Spring 2025',
        folderPlaceholder:  'e.g. Aquatics, Summer 2025',
    };

    pdfLoaded = false;

    // ── Report type ────────────────────────────────────────────────────────────
    // Chosen before anything else. It decides which object the report runs over,
    // which status list applies, and which saved reports are listed.
    reportType = TYPE_REGISTRATIONS;

    // ── Filter values ──────────────────────────────────────────────────────────
    courseNameFilter    = '';
    courseSessionFilter = '';
    programNameFilter   = '';
    courseOptionFilter  = '';   // enrollment report only
    selectedStatuses    = [];
    startDateFrom       = '';
    startDateTo         = '';

    // ── Picklist / config options ──────────────────────────────────────────────
    statusOptions      = [];
    savedConfigOptions = [];
    // Each type's statuses, fetched once and kept. Registration and enrollment
    // vocabularies are close but not identical, so they must not be shared.
    statusOptionsByType = {};

    // ── Saved report state ────────────────────────────────────────────────────
    selectedConfigId      = '';
    selectedFolderFilter  = '';
    currentConfigId       = null;
    loadedConfigName      = '';
    showSaveForm          = false;
    saveConfigName        = '';
    saveConfigDesc        = '';
    saveConfigFolder      = '';
    saveConfigFolderCombo = '';   // combobox value — may be '__new__'
    showNewFolderInput    = false;

    // ── Results state ──────────────────────────────────────────────────────────
    tableColumns       = [];
    tableData          = [];
    totalRows          = 0;
    filterSummary      = '';
    allQuestionColumns = [];
    availableGroups    = [];
    selectedGroups     = [];

    // ── Column visibility ──────────────────────────────────────────────────────
    fixedColVisible = defaultVisibility(FIXED_COLUMN_DEFS);

    // ── Extra columns (field picker) ───────────────────────────────────────────
    availableFields   = [];   // { apiKey, label, groupName, fieldType } from Apex
    selectedExtraKeys = [];   // currently applied extra column api keys
    pendingExtraKeys  = [];   // keys being selected in the modal (not yet applied)
    showFieldPicker   = false;
    fieldPickerSearch = '';

    // ── Sort state ─────────────────────────────────────────────────────────────
    sortedBy        = '';
    sortedDirection = 'asc';

    // ── UI state ───────────────────────────────────────────────────────────────
    isLoading          = false;
    hasResults         = false;
    filtersPending     = false;
    errorMessage       = '';
    tooManyResultsMsg  = '';
    xlsxLoaded         = false;

    // ─────────────────────────────────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadInitialData();
        loadScript(this, SheetJS)
            .then(() => { this.xlsxLoaded = true; })
            .catch(() => { /* CSV still works */ });
        loadScript(this, JsPDF)
            .then(() => { this.pdfLoaded = true; })
            .catch(() => { /* CSV and Excel still work */ });
    }

    async loadInitialData() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const [statuses, configs, fields, placeholders] = await Promise.all([
                getRegistrationStatuses(),
                getSavedConfigs({ reportType: this.reportType }),
                getAvailableFields(),
                getPlaceholders()
            ]);
            this.statusOptionsByType[TYPE_REGISTRATIONS] =
                statuses.map(s => ({ label: s.label, value: s.value }));
            this.statusOptions    = this.statusOptionsByType[TYPE_REGISTRATIONS];
            this.selectedStatuses = this.statusOptions.map(s => s.value);
            this.availableFields  = fields || [];
            this.setSavedConfigOptions(configs);
            if (placeholders) {
                this.placeholder = {
                    programPlaceholder: placeholders.programName   || this.placeholder.programPlaceholder,
                    coursePlaceholder:  placeholders.courseName    || this.placeholder.coursePlaceholder,
                    sessionPlaceholder: placeholders.courseSession || this.placeholder.sessionPlaceholder,
                    folderPlaceholder:  placeholders.folderName    || this.placeholder.folderPlaceholder,
                };
            }
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Saved configs
    // ─────────────────────────────────────────────────────────────────────────

    setSavedConfigOptions(configs) {
        this.savedConfigOptions = configs.map(c => ({
            label:       (c.folderName ? c.folderName + '  /  ' : '') + c.name +
                         (c.lastRunDate ? '  ·  Last run ' + c.lastRunDate : ''),
            value:       c.id,
            name:        c.name,
            desc:        c.description  || '',
            folder:      c.folderName   || '',
            lastRunDate: c.lastRunDate  || ''
        }));
    }

    async refreshSavedConfigs() {
        try {
            const configs = await getSavedConfigs({ reportType: this.reportType });
            this.setSavedConfigOptions(configs);
        } catch (e) { /* non-critical */ }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Report type
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Switching type is a different report over a different object, not a filter
     * change. Results, saved-report selection and column visibility all reset, so
     * nothing from the previous type can be mistaken for the new one.
     */
    async handleReportTypeChange(event) {
        const next = event.detail.value;
        if (next === this.reportType) return;

        this.reportType = next;

        this.hasResults        = false;
        this.tableData         = [];
        this.tableColumns      = [];
        this.totalRows         = 0;
        this.allQuestionColumns = [];
        this.availableGroups   = [];
        this.selectedGroups    = [];
        this.filtersPending    = false;
        this.errorMessage      = '';
        this.tooManyResultsMsg = '';

        this.currentConfigId      = null;
        this.loadedConfigName     = '';
        this.selectedConfigId     = '';
        this.selectedFolderFilter = '';
        this.showSaveForm         = false;
        this.saveConfigName       = '';

        this.courseOptionFilter = '';
        this.fixedColVisible    = defaultVisibility(this.activeColumnDefs);

        this.isLoading = true;
        try {
            await Promise.all([ this.loadStatusesForType(), this.refreshSavedConfigs() ]);
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async loadStatusesForType() {
        if (!this.statusOptionsByType[this.reportType]) {
            const statuses = this.reportType === TYPE_ENROLLMENTS
                ? await getEnrollmentStatuses()
                : await getRegistrationStatuses();
            this.statusOptionsByType[this.reportType] =
                statuses.map(s => ({ label: s.label, value: s.value }));
        }
        this.statusOptions    = this.statusOptionsByType[this.reportType];
        this.selectedStatuses = this.statusOptions.map(s => s.value);
    }

    handleFolderFilterChange(event) {
        this.selectedFolderFilter = event.detail.value;
        this.selectedConfigId = '';
    }

    handleConfigSelect(event) { this.selectedConfigId = event.detail.value; }

    async handleLoadConfig() {
        if (!this.selectedConfigId) return;
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const jsonStr = await loadConfig({ configId: this.selectedConfigId });
            const config  = JSON.parse(jsonStr);

            this.courseNameFilter    = config.courseNameFilter    || '';
            this.courseSessionFilter = config.courseSessionFilter || '';
            this.programNameFilter   = config.programNameFilter   || '';
            this.courseOptionFilter  = config.courseOptionFilter  || '';
            this.selectedStatuses    = config.statusFilters       || [];
            this.startDateFrom       = config.startDateFrom       || '';
            this.startDateTo         = config.startDateTo         || '';
            this.selectedExtraKeys   = config.extraFields         || [];
            this.currentConfigId     = this.selectedConfigId;

            const selected = this.savedConfigOptions.find(o => o.value === this.selectedConfigId);
            this.loadedConfigName  = selected ? selected.name   : '';
            this.saveConfigName    = this.loadedConfigName;
            this.saveConfigDesc    = selected ? selected.desc   : '';
            this.saveConfigFolder  = selected ? selected.folder : '';

            this.showSaveForm   = false;
            this.filtersPending = false;
            this.rebuildVisibleColumns();
            this.toast('Report loaded', 'Click Run Report to execute.', 'success');
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async handleDeleteConfig() {
        if (!this.selectedConfigId) return;
        // eslint-disable-next-line no-alert
        if (!confirm('Delete this saved configuration? This cannot be undone.')) return;
        this.isLoading = true;
        try {
            await deleteConfig({ configId: this.selectedConfigId });
            if (this.currentConfigId === this.selectedConfigId) {
                this.currentConfigId  = null;
                this.loadedConfigName = '';
            }
            this.selectedConfigId     = '';
            this.selectedFolderFilter = '';
            await this.refreshSavedConfigs();
            this.toast('Deleted', 'Report removed.', 'success');
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Filter input handlers  (native <input> → event.target.value)
    // ─────────────────────────────────────────────────────────────────────────

    handleCourseNameChange(event)    { this.courseNameFilter    = event.target.value; this.filtersPending = true; }
    handleCourseSessionChange(event) { this.courseSessionFilter = event.target.value; this.filtersPending = true; }
    handleProgramNameChange(event)   { this.programNameFilter   = event.target.value; this.filtersPending = true; }
    handleCourseOptionChange(event)  { this.courseOptionFilter  = event.target.value; this.filtersPending = true; }
    handleStartDateFromChange(event) { this.startDateFrom       = event.target.value; this.filtersPending = true; }
    handleStartDateToChange(event)   { this.startDateTo         = event.target.value; this.filtersPending = true; }

    handleStatusPillToggle(event) {
        const val = event.currentTarget.dataset.value;
        this.selectedStatuses = this.selectedStatuses.includes(val)
            ? this.selectedStatuses.filter(s => s !== val)
            : [...this.selectedStatuses, val];
        this.filtersPending = true;
    }

    showAllStatuses()  { this.selectedStatuses = this.statusOptions.map(s => s.value); this.filtersPending = true; }
    showNoneStatuses() { this.selectedStatuses = []; this.filtersPending = true; }

    clearFilters() {
        this.courseNameFilter = this.courseSessionFilter = this.programNameFilter = '';
        this.courseOptionFilter = '';
        this.startDateFrom    = this.startDateTo = '';
        this.selectedStatuses = this.statusOptions.map(s => s.value);
        this.filtersPending   = true;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Report execution
    // ─────────────────────────────────────────────────────────────────────────

    async handleRunReport() {
        this.isLoading         = true;
        this.hasResults        = false;
        this.errorMessage      = '';
        this.tooManyResultsMsg = '';
        this.showSaveForm      = false;

        try {
            const args = {
                courseNameFilter:    this.courseNameFilter    || null,
                courseSessionFilter: this.courseSessionFilter || null,
                programNameFilter:   this.programNameFilter   || null,
                statusFilters:       this.selectedStatuses.length > 0 ? this.selectedStatuses : null,
                startDateFrom:       this.startDateFrom || null,
                startDateTo:         this.startDateTo   || null,
                extraFields:         this.selectedExtraKeys.length > 0 ? this.selectedExtraKeys : null
            };

            const result = this.isEnrollmentReport
                ? await runEnrollmentReport({ ...args, courseOptionFilter: this.courseOptionFilter || null })
                : await runReport(args);

            this.totalRows          = result.totalRows;
            this.allQuestionColumns = result.questionColumns;
            this.tableData          = result.rows.map(row => ({
                ...row,
                registrationUrl: row.registrationId ? '/' + row.registrationId : null,
                enrollmentUrl:   row.enrollmentId   ? '/' + row.enrollmentId   : null
            }));
            this.sortedBy           = '';
            this.sortedDirection    = 'asc';
            this.filterSummary      = this.buildFilterSummary();

            const seen = new Set();
            const groups = [];
            for (const col of result.questionColumns) {
                if (col.groupName && !seen.has(col.groupName)) {
                    seen.add(col.groupName);
                    groups.push(col.groupName);
                }
            }
            this.availableGroups = groups;
            this.selectedGroups  = [...groups];
            this.rebuildVisibleColumns();

            this.hasResults    = true;
            this.filtersPending = false;

            if (result.totalRows === 0) {
                this.toast('No Results', `No ${this.rowNoun}s matched your filters.`, 'info');
            }
        } catch (e) {
            const msg = this.extractError(e);
            if (msg.startsWith('LIMIT:')) {
                this.tooManyResultsMsg = msg.substring(6);
            } else {
                this.errorMessage = msg;
            }
        } finally {
            this.isLoading = false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Column visibility (fixed fields)
    // ─────────────────────────────────────────────────────────────────────────

    handleToggleColumn(event) {
        const field = event.currentTarget.dataset.field;
        this.fixedColVisible = { ...this.fixedColVisible, [field]: !this.fixedColVisible[field] };
        this.rebuildVisibleColumns();
    }

    showAllFields() {
        const v = {};
        this.activeColumnDefs.forEach(c => { v[c.fieldName] = true; });
        this.fixedColVisible = v;
        this.rebuildVisibleColumns();
    }

    showNoneFields() {
        const v = {};
        this.activeColumnDefs.forEach(c => { v[c.fieldName] = false; });
        this.fixedColVisible = v;
        this.rebuildVisibleColumns();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Field picker (extra columns)
    // ─────────────────────────────────────────────────────────────────────────

    handleOpenFieldPicker() {
        this.pendingExtraKeys  = [...this.selectedExtraKeys];
        this.fieldPickerSearch = '';
        this.showFieldPicker   = true;
    }

    handleCloseFieldPicker() {
        this.showFieldPicker = false;
    }

    handlePickerOverlayClick(event) {
        if (event.target === event.currentTarget) {
            this.showFieldPicker = false;
        }
    }

    handleFieldPickerSearch(event) {
        this.fieldPickerSearch = event.target.value;
    }

    handleFieldPickerToggle(event) {
        const key     = event.currentTarget.dataset.key;
        const checked = event.target.checked;
        if (checked) {
            if (!this.pendingExtraKeys.includes(key)) {
                this.pendingExtraKeys = [...this.pendingExtraKeys, key];
            }
        } else {
            this.pendingExtraKeys = this.pendingExtraKeys.filter(k => k !== key);
        }
    }

    handleApplyFieldPicker() {
        const prevSet  = new Set(this.selectedExtraKeys);
        const hasNew   = this.pendingExtraKeys.some(k => !prevSet.has(k));
        this.selectedExtraKeys = [...this.pendingExtraKeys];
        this.showFieldPicker   = false;
        this.rebuildVisibleColumns();
        if (hasNew && this.hasResults) {
            this.filtersPending = true;
        }
    }

    handleRemoveExtraField(event) {
        const key = event.currentTarget.dataset.key;
        this.selectedExtraKeys = this.selectedExtraKeys.filter(k => k !== key);
        this.rebuildVisibleColumns();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Group toggle (client-side, no re-query)
    // ─────────────────────────────────────────────────────────────────────────

    handleGroupPillToggle(event) {
        const g = event.currentTarget.dataset.group;
        this.selectedGroups = this.selectedGroups.includes(g)
            ? this.selectedGroups.filter(x => x !== g)
            : [...new Set([...this.selectedGroups, g])];
        this.rebuildVisibleColumns();
    }

    showAllGroups() { this.selectedGroups = [...this.availableGroups]; this.rebuildVisibleColumns(); }
    hideAllGroups() { this.selectedGroups = []; this.rebuildVisibleColumns(); }

    rebuildVisibleColumns() {
        const visibleFixed = this.activeColumnDefs
            .filter(c => this.fixedColVisible[c.fieldName] !== false)
            .map(({ defaultOn, ...col }) => col);   // defaultOn is ours, not datatable's

        const extraFieldMap = new Map(this.availableFields.map(f => [f.apiKey, f]));
        const extraCols = this.selectedExtraKeys
            .filter(key => extraFieldMap.has(key))
            .map(key => {
                const f = extraFieldMap.get(key);
                return {
                    label:        f.label,
                    fieldName:    f.apiKey,
                    type:         f.fieldType || 'text',
                    wrapText:     true,
                    initialWidth: 180,
                    sortable:     true
                };
            });

        const groupSet     = new Set(this.selectedGroups);
        const questionCols = this.allQuestionColumns
            .filter(c => groupSet.has(c.groupName))
            .map(c => ({
                label:        c.label,
                fieldName:    c.fieldName,
                type:         'text',
                wrapText:     true,
                initialWidth: 220,
                sortable:     true
            }));

        // The enrollment report links to the enrollment, since that is what the row is.
        const linkCol = {
            label:          this.isEnrollmentReport ? 'Enrollment' : 'Registration',
            fieldName:      this.isEnrollmentReport ? 'enrollmentUrl' : 'registrationUrl',
            type:           'url',
            typeAttributes: { label: 'View', target: '_blank' },
            initialWidth:   110,
            sortable:       false
        };
        this.tableColumns = [...visibleFixed, ...extraCols, ...questionCols, linkCol];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Sorting
    // ─────────────────────────────────────────────────────────────────────────

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy        = fieldName;
        this.sortedDirection = sortDirection;
        const mult = sortDirection === 'asc' ? 1 : -1;
        this.tableData = [...this.tableData].sort((a, b) => {
            const vA = (a[fieldName] ?? '').toString().toLowerCase();
            const vB = (b[fieldName] ?? '').toString().toLowerCase();
            return mult * vA.localeCompare(vB);
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Save config handlers
    // ─────────────────────────────────────────────────────────────────────────

    handleShowSaveForm() {
        if (!this.saveConfigName && !this.currentConfigId) this.saveConfigName = 'Report ' + this.isoDate();
        this.showSaveForm = true;
    }
    handleCancelSave()        { this.showSaveForm = false; }
    handleSaveNameChange(e)   { this.saveConfigName   = e.detail.value; }
    handleSaveDescChange(e)   { this.saveConfigDesc   = e.detail.value; }
    handleSaveFolderChange(e) { this.saveConfigFolder = e.detail.value; }

    handleSaveFolderComboChange(e) {
        const val = e.detail.value;
        this.saveConfigFolderCombo = val;
        if (val === '__new__') {
            this.showNewFolderInput = true;
            this.saveConfigFolder   = '';
        } else {
            this.showNewFolderInput = false;
            this.saveConfigFolder   = val;
        }
    }

    async handleSaveConfig()  { await this.persistConfig(this.currentConfigId); }
    async handleSaveAsNew()   { await this.persistConfig(null); }

    async persistConfig(idToUse) {
        if (!this.saveConfigName)   { this.errorMessage = 'Report name is required.';   return; }
        if (!this.saveConfigFolder) { this.errorMessage = 'Folder is required.';         return; }
        this.isLoading = true;
        try {
            const newId = await saveConfig({
                configId:    idToUse,
                name:        this.saveConfigName,
                description: this.saveConfigDesc,
                configJSON:  this.buildConfigJSON(),
                folderName:  this.saveConfigFolder,
                reportType:  this.reportType
            });
            this.currentConfigId  = newId;
            this.loadedConfigName = this.saveConfigName;
            this.showSaveForm     = false;
            await this.refreshSavedConfigs();
            this.toast('Saved', '"' + this.saveConfigName + '" saved successfully.', 'success');
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Export
    // ─────────────────────────────────────────────────────────────────────────

    handleExportCsv() {
        if (!this.tableData?.length) return;
        const esc  = v => '"' + (v == null ? '' : String(v)).replace(/"/g, '""') + '"';
        const rows = [
            this.tableColumns.map(c => esc(c.label)).join(','),
            ...this.tableData.map(row => this.tableColumns.map(c => esc(row[c.fieldName])).join(','))
        ];
        this.downloadFile(rows.join('\r\n'), `${this.exportBaseName}_${this.isoDate()}.csv`, 'text/csv;charset=utf-8;');
    }

    handleExportExcel() {
        if (!this.tableData?.length || !this.xlsxLoaded) return;
        // eslint-disable-next-line no-undef
        const XLSX   = window.XLSX;
        const header = this.tableColumns.map(c => c.label);
        const data   = this.tableData.map(row => this.tableColumns.map(c => row[c.fieldName] ?? ''));
        const ws     = XLSX.utils.aoa_to_sheet([header, ...data]);
        ws['!cols']  = this.tableColumns.map(c => ({ wch: Math.round((c.initialWidth || 160) / 7) }));
        const wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, ws, 'Report');
        XLSX.writeFile(wb, `${this.exportBaseName}_${this.isoDate()}.xlsx`);
    }

    handleExportPdf() {
        if (!this.tableData?.length) return;
        this.errorMessage = '';
        if (!this.pdfLoaded) {
            this.errorMessage = 'The PDF library is still loading. Try again in a moment.';
            return;
        }

        // The registration link column is not meaningful on paper
        const printCols = this.tableColumns.filter(c => c.type !== 'url');

        const now = new Date().toLocaleString('en-US', {
            year: 'numeric', month: 'long', day: 'numeric',
            hour: '2-digit', minute: '2-digit'
        });

        const head = [printCols.map(c => this.pdfHeaderLabel(c.label))];
        const body = this.tableData.map(row =>
            printCols.map(c => this.formatPdfCell(c, row[c.fieldName]))
        );

        try {
            // eslint-disable-next-line no-undef
            const { jsPDF } = window.jspdf;

            // Give every column at least a readable width. On a fixed letter page
            // a wide report forces autoTable to split the table across pages
            // horizontally, and past roughly 45 columns that recursion overflows
            // the call stack. Widening the page instead keeps it to one pass.
            // Narrow reports still come out on plain letter landscape.
            const LETTER_WIDTH = 792;
            const MARGIN       = 28;
            const MIN_COL      = 88;
            const pageWidth    = Math.max(LETTER_WIDTH, printCols.length * MIN_COL + MARGIN * 2);

            const doc = new jsPDF({
                orientation: 'landscape',
                unit: 'pt',
                format: [pageWidth, 612]
            });

            doc.autoTable({
                head,
                body,
                startY: 74,
                margin: { top: 74, right: MARGIN, bottom: 34, left: MARGIN },
                styles: {
                    font: 'helvetica', fontSize: 8, cellPadding: 4,
                    overflow: 'linebreak', valign: 'top', lineColor: [226, 232, 240], lineWidth: 0.5
                },
                headStyles: { fillColor: [15, 23, 42], textColor: [255, 255, 255], fontSize: 8, fontStyle: 'bold' },
                alternateRowStyles: { fillColor: [248, 250, 252] },
                didDrawPage: (data) => {
                    doc.setFont('helvetica', 'bold');
                    doc.setFontSize(14);
                    doc.setTextColor(15, 23, 42);
                    doc.text(this.reportTitle, data.settings.margin.left, 36);

                    doc.setFont('helvetica', 'normal');
                    doc.setFontSize(8);
                    doc.setTextColor(100, 116, 139);
                    if (this.filterSummary) {
                        const summaryWidth = Math.min(pageWidth - 260, 900);
                        doc.text(
                            doc.splitTextToSize(this.filterSummary, summaryWidth),
                            data.settings.margin.left, 50
                        );
                    }
                    doc.text(`${this.totalRows} ${this.rowNoun}(s)`, data.settings.margin.left, 62);

                    const w = doc.internal.pageSize.getWidth();
                    const h = doc.internal.pageSize.getHeight();
                    doc.setFontSize(7);
                    doc.setTextColor(148, 163, 184);
                    doc.text(now, w - data.settings.margin.right, 36, { align: 'right' });
                    doc.text(
                        'Page ' + doc.internal.getNumberOfPages(),
                        w - data.settings.margin.right, h - 18, { align: 'right' }
                    );
                }
            });

            // A data: URI on a download anchor is the only file-save route
            // Lightning Web Security allows; blob URLs are rejected.
            this.downloadDataUri(
                this.pdfDataUri(doc),
                `${this.exportBaseName}_${this.isoDate()}.pdf`
            );
        } catch (e) {
            // Salesforce runs this component inside Lightning Web Security, which
            // leaves far less call stack than a normal page. Very wide reports
            // exhaust it inside the PDF library, around 40 columns in practice.
            if (/call stack/i.test(e.message)) {
                this.errorMessage =
                    `This report is too wide for the PDF export (${printCols.length} columns). ` +
                    'Turn off some Question Groups or Additional Columns and try again, ' +
                    'or use the Excel export, which has no column limit.';
            } else {
                this.errorMessage = 'Could not build the PDF: ' + e.message +
                    '. CSV and Excel exports are unaffected.';
            }
        }
    }

    // jsPDF's own output('datauristring') base64-encodes the whole document in one
    // pass, which overflows the call stack on larger reports ("Maximum call stack
    // size exceeded"). Encode the bytes in chunks instead.
    pdfDataUri(doc) {
        const bytes = new Uint8Array(doc.output('arraybuffer'));
        const CHUNK = 0x8000;
        let binary = '';
        for (let i = 0; i < bytes.length; i += CHUNK) {
            binary += String.fromCharCode.apply(null, bytes.subarray(i, i + CHUNK));
        }
        return 'data:application/pdf;base64,' + btoa(binary);
    }

    // Question text is often a whole sentence, and consent questions can run to a
    // paragraph. Left intact it wraps into a header cell tall enough to push the
    // data off the page, so keep enough to identify the column and drop the rest.
    pdfHeaderLabel(label) {
        const text = String(label == null ? '' : label).replace(/\s+/g, ' ').trim();
        return text.length > 58 ? text.slice(0, 55).trimEnd() + '...' : text;
    }

    formatPdfCell(col, val) {
        if (val == null || val === '') return '';
        if (col.type === 'date-local' && typeof val === 'string' && val.includes('-')) {
            const [y, m, d] = val.split('-');
            return `${parseInt(m, 10)}/${parseInt(d, 10)}/${y}`;
        }
        return String(val);
    }

    escHtml(v) {
        if (v == null) return '';
        return String(v)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Computed properties
    // ─────────────────────────────────────────────────────────────────────────

    get hasTooManyResults()      { return !!this.tooManyResultsMsg; }
    get hasSavedConfigs()        { return this.savedConfigOptions.length > 0; }
    get noConfigSelected()       { return !this.selectedConfigId; }

    get saveFormTitle()    { return this.currentConfigId ? 'Save Report' : 'Save New Report'; }
    get saveTriggerLabel() { return this.currentConfigId ? 'Save / Save As...' : 'Save Report'; }

    get uniqueFolderOptions() {
        const seen = new Set();
        const opts = [];
        for (const c of this.savedConfigOptions) {
            if (c.folder && !seen.has(c.folder)) {
                seen.add(c.folder);
                opts.push({ label: c.folder, value: c.folder });
            }
        }
        opts.sort((a, b) => a.label.localeCompare(b.label));
        return opts;
    }

    get filteredConfigOptions() {
        return this.savedConfigOptions
            .filter(c => c.folder === this.selectedFolderFilter)
            .map(c => ({
                label: c.name + (c.lastRunDate ? '  ·  Last run ' + c.lastRunDate : ''),
                value: c.value
            }));
    }

    get folderOptionsForSave() {
        const opts = this.uniqueFolderOptions.map(o => ({ ...o }));
        opts.push({ label: '＋ New folder...', value: '__new__' });
        return opts;
    }
    get noStatusSelected()       { return this.selectedStatuses.length === 0; }
    get xlsxNotReady()           { return !this.xlsxLoaded; }
    get hasAvailableGroups()     { return this.availableGroups.length > 0; }
    get showPendingState()       { return this.filtersPending; }
    get hasSelectedExtraFields() { return this.selectedExtraKeys.length > 0; }

    get runBtnClass() {
        return 'aqr-run-btn' + (this.showPendingState ? ' aqr-run-btn--pending' : '');
    }

    get addColumnsLabel() {
        const n = this.selectedExtraKeys.length;
        return n > 0 ? `Edit Columns (${n} added)` : '+ Add Columns';
    }

    // ── Status All/None button classes
    get statusAllBtnClass() {
        const all = this.statusOptions.length > 0 && this.selectedStatuses.length === this.statusOptions.length;
        return 'aqr-alln-btn' + (all ? ' aqr-alln-btn--all' : '');
    }
    get statusNoneBtnClass() {
        return 'aqr-alln-btn' + (this.selectedStatuses.length === 0 ? ' aqr-alln-btn--none' : '');
    }

    // ── Fields All/None button classes
    get fieldsAllBtnClass() {
        const all = FIXED_COLUMN_DEFS.every(c => this.fixedColVisible[c.fieldName] !== false);
        return 'aqr-alln-btn' + (all ? ' aqr-alln-btn--all' : '');
    }
    get fieldsNoneBtnClass() {
        const none = FIXED_COLUMN_DEFS.every(c => this.fixedColVisible[c.fieldName] === false);
        return 'aqr-alln-btn' + (none ? ' aqr-alln-btn--none' : '');
    }

    // ── Groups All/None button classes
    get groupsAllBtnClass() {
        const all = this.availableGroups.length > 0 && this.selectedGroups.length === this.availableGroups.length;
        return 'aqr-alln-btn' + (all ? ' aqr-alln-btn--all' : '');
    }
    get groupsNoneBtnClass() {
        return 'aqr-alln-btn' + (this.selectedGroups.length === 0 ? ' aqr-alln-btn--none' : '');
    }

    get statusPillOptions() {
        return this.statusOptions.map(s => ({
            label:     s.label,
            value:     s.value,
            pillClass: 'aqr-pill' + (this.selectedStatuses.includes(s.value) ? ' aqr-pill--active' : '')
        }));
    }

    // ── Report type ────────────────────────────────────────────────────────────

    get isEnrollmentReport() { return this.reportType === TYPE_ENROLLMENTS; }

    get reportTypeOptions() {
        return [
            { label: 'Registrations',             value: TYPE_REGISTRATIONS },
            { label: 'Course Option Enrollments', value: TYPE_ENROLLMENTS   }
        ];
    }

    get activeColumnDefs() {
        return this.isEnrollmentReport ? ENROLLMENT_COLUMN_DEFS : FIXED_COLUMN_DEFS;
    }

    // A row is an enrollment or a registration, and every count, toast, export
    // name and PDF heading says which, so two exports are never confused.
    get rowNoun()         { return this.isEnrollmentReport ? 'enrollment' : 'registration'; }
    get rowNounPlural()   { return this.rowNoun + '(s)'; }
    get statusLabel()     { return this.isEnrollmentReport ? 'Enrollment Status' : 'Status'; }
    get panelTitle()      { return this.isEnrollmentReport ? 'Build Enrollment Report' : 'Build Report'; }
    get savedReportsLabel() {
        return this.isEnrollmentReport ? 'Saved Enrollment Reports' : 'Saved Reports';
    }
    get reportTitle()     { return this.isEnrollmentReport ? 'Enrollment Report' : 'Registration Report'; }
    get fieldSectionLabel() {
        return this.isEnrollmentReport ? 'Enrollment Fields' : 'Registration Fields';
    }
    get exportBaseName()  { return this.isEnrollmentReport ? 'EnrollmentReport' : 'RegistrationReport'; }

    get fixedColumnOptions() {
        return this.activeColumnDefs.map(col => ({
            label:     col.label,
            fieldName: col.fieldName,
            pillClass: 'aqr-pill' + (this.fixedColVisible[col.fieldName] !== false ? ' aqr-pill--active' : '')
        }));
    }

    get groupFilterItems() {
        return this.availableGroups.map(g => ({
            name:      g,
            pillClass: 'aqr-pill' + (this.selectedGroups.includes(g) ? ' aqr-pill--active' : '')
        }));
    }

    get selectedExtraPills() {
        const fieldMap = new Map(this.availableFields.map(f => [f.apiKey, f]));
        return this.selectedExtraKeys
            .filter(k => fieldMap.has(k))
            .map(k => ({ apiKey: k, label: fieldMap.get(k).label }));
    }

    get fieldPickerGroups() {
        const search     = (this.fieldPickerSearch || '').toLowerCase();
        const pendingSet = new Set(this.pendingExtraKeys);
        const groups     = [
            { name: 'Registration', fields: [] },
            { name: 'Contact',      fields: [] }
        ];

        for (const f of this.availableFields) {
            const grp = groups.find(g => g.name === f.groupName);
            if (!grp) continue;
            if (search && !f.label.toLowerCase().includes(search)) continue;
            grp.fields.push({
                apiKey:    f.apiKey,
                label:     f.label,
                isChecked: pendingSet.has(f.apiKey)
            });
        }

        return groups.map(g => ({ ...g, isEmpty: g.fields.length === 0 }));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    buildConfigJSON() {
        return JSON.stringify({
            reportType:          this.reportType,
            courseNameFilter:    this.courseNameFilter    || null,
            courseSessionFilter: this.courseSessionFilter || null,
            programNameFilter:   this.programNameFilter   || null,
            courseOptionFilter:  this.courseOptionFilter  || null,
            statusFilters:       this.selectedStatuses.length > 0 ? this.selectedStatuses : null,
            startDateFrom:       this.startDateFrom || null,
            startDateTo:         this.startDateTo   || null,
            extraFields:         this.selectedExtraKeys.length > 0 ? this.selectedExtraKeys : null
        });
    }

    buildFilterSummary() {
        const parts = [];
        if (this.programNameFilter)        parts.push(`Program: "${this.programNameFilter}"`);
        if (this.courseNameFilter)         parts.push(`Course: "${this.courseNameFilter}"`);
        if (this.courseSessionFilter)      parts.push(`Session: "${this.courseSessionFilter}"`);
        if (this.courseOptionFilter && this.isEnrollmentReport) {
            parts.push(`Course Option: "${this.courseOptionFilter}"`);
        }
        if (this.selectedStatuses?.length) parts.push(`${this.statusLabel}: ${this.selectedStatuses.join(', ')}`);
        if (this.startDateFrom)            parts.push(`From ${this.startDateFrom}`);
        if (this.startDateTo)              parts.push(`To ${this.startDateTo}`);
        return parts.length ? parts.join(' · ') : 'No filters applied';
    }

    downloadFile(content, filename, mimeType) {
        this.downloadDataUri(`data:${mimeType},` + encodeURIComponent(content), filename);
    }

    downloadDataUri(uri, filename) {
        const a = document.createElement('a');
        a.href = uri;
        a.setAttribute('download', filename);
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractError(e) {
        return e?.body?.message || e?.message || 'An unexpected error occurred.';
    }

    isoDate() { return new Date().toISOString().slice(0, 10); }
}
