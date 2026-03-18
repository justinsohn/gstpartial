import { LightningElement, api, wire } from "lwc";
import getVisitWithLayout from "@salesforce/apex/MostRecentVisitController.getVisitWithLayout";

/**
 * Displays the most recent Visit record for the current Account, dynamically
 * replicating the tab/section/field structure of the Visit Desktop Page layout.
 *
 * The layout is read from a static resource containing the FlexiPage metadata,
 * so changes made in App Builder are reflected after re-deploying the resource.
 */
export default class MostRecentVisit extends LightningElement {
    /** The Account record Id, automatically provided on Lightning Record Pages */
    @api recordId;

    /** Layout and visit data returned from the Apex controller */
    tabs = [];
    hasVisit = false;
    visitId;
    visitDate;
    visitorName;

    /** Loading and error states */
    isLoading = true;
    errorMessage;

    /** Tracks the currently active tab */
    activeTab;

    @wire(getVisitWithLayout, { accountId: "$recordId" })
    wiredResult({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.tabs = this.processTabs(data.tabs || []);
            this.hasVisit = data.hasVisit;
            this.visitId = data.visitId;
            this.visitDate = data.visitDate;
            this.visitorName = data.visitorName;
            this.errorMessage = undefined;

            // Default to the first tab if available
            if (this.tabs.length > 0 && !this.activeTab) {
                this.activeTab = this.tabs[0].tabValue;
            }
        } else if (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.tabs = [];
            this.hasVisit = false;
        }
    }

    /**
     * Processes the tab data from Apex to add computed properties needed
     * by the template (unique keys, formatted values, etc.)
     */
    processTabs(tabs) {
        return tabs.map((tab, tabIndex) => ({
            ...tab,
            // Unique value for lightning-tab identification
            tabValue: `tab-${tabIndex}`,
            sections: (tab.sections || []).map((section, sectionIndex) => ({
                ...section,
                sectionKey: `section-${tabIndex}-${sectionIndex}`,
                // Precomputed inverse of isHorizontal for use in lwc:elseif
                isVertical: !section.isHorizontal,
                columns: (section.columns || []).map((col, colIndex) => ({
                    ...col,
                    columnKey: `col-${tabIndex}-${sectionIndex}-${colIndex}`,
                    // Compute SLDS column size class based on number of columns
                    columnClass: this.getColumnClass(section.columns.length),
                    fields: (col.fields || [])
                        .filter((field) => field.visible !== false)
                        .map((field, fieldIndex) => ({
                            ...field,
                            fieldKey: `field-${tabIndex}-${sectionIndex}-${colIndex}-${fieldIndex}`,
                            displayValue: this.formatFieldValue(field),
                            isBoolean: field.fieldType === "BOOLEAN",
                            isChecked:
                                field.fieldType === "BOOLEAN" &&
                                field.value === true,
                            // Precomputed icon properties for boolean fields (ternaries are not allowed in LWC templates)
                            checkboxIconName:
                                field.fieldType === "BOOLEAN" && field.value === true
                                    ? "utility:check"
                                    : "utility:close",
                            checkboxIconVariant:
                                field.fieldType === "BOOLEAN" && field.value === true
                                    ? "success"
                                    : "",
                            isLongText:
                                field.fieldType === "TEXTAREA" ||
                                field.fieldType === "LONG",
                            isDate:
                                field.fieldType === "DATE" ||
                                field.fieldType === "DATETIME",
                            isOther:
                                field.fieldType !== "BOOLEAN" &&
                                field.fieldType !== "TEXTAREA" &&
                                field.fieldType !== "LONG" &&
                                field.fieldType !== "DATE" &&
                                field.fieldType !== "DATETIME"
                        }))
                }))
            }))
        }));
    }

    /**
     * Returns the SLDS grid column class based on the total number of columns.
     * Sections with 2 columns split evenly; single-column sections take full width.
     */
    getColumnClass(totalColumns) {
        if (totalColumns === 2) {
            return "slds-col slds-size_1-of-2";
        }
        return "slds-col slds-size_1-of-1";
    }

    /**
     * Formats a field value for display. Booleans are handled separately in the
     * template, so this is mainly for text and date values.
     */
    formatFieldValue(field) {
        if (field.value === null || field.value === undefined) {
            return "";
        }
        return String(field.value);
    }

    /**
     * Extracts a user-friendly error message from the wire error object.
     */
    extractErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return "An unexpected error occurred.";
    }

    /** Handles tab activation to track the active tab */
    handleTabActive(event) {
        this.activeTab = event.target.value;
    }

    /** Computed: Card title that includes the visit date and visitor name */
    get cardTitle() {
        if (this.visitDate) {
            const date = new Date(this.visitDate + "T00:00:00");
            const formatted = date.toLocaleDateString("en-US", {
                month: "numeric",
                day: "numeric",
                year: "numeric"
            });
            let title = `Most Recent Visit — ${formatted}`;
            if (this.visitorName) {
                title += ` by ${this.visitorName}`;
            }
            return title;
        }
        return "Most Recent Visit";
    }

    /** Computed: URL to navigate to the Visit record */
    get visitUrl() {
        return this.visitId ? `/${this.visitId}` : "";
    }

    /** Computed: true when there are no tabs to display */
    get noTabsAvailable() {
        return this.tabs.length === 0;
    }

    /** Computed: true when no visit is found and we are done loading with no error */
    get showNoVisitMessage() {
        return !this.isLoading && !this.hasVisit && !this.errorMessage;
    }

    /** Computed: true when we should show the visit content (has visit + has tabs) */
    get showVisitContent() {
        return this.hasVisit && this.tabs.length > 0;
    }
}