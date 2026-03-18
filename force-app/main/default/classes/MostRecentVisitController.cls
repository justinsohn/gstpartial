/**
 * Controller for the mostRecentVisit LWC component.
 * Reads the Visit Desktop Page (FlexiPage) layout from a static resource
 * and queries the most recent Visit for a given Account.
 *
 * The layout JSON is stored in the VisitFlexiPageLayout static resource.
 * When the Visit page layout changes in App Builder, re-retrieve the metadata
 * from the Tooling API and redeploy the static resource to reflect changes.
 */
public with sharing class MostRecentVisitController {

    // The static resource containing the FlexiPage metadata JSON
    private static final String LAYOUT_RESOURCE_NAME = 'VisitFlexiPageLayout';

    // Maps tab titles to custom permission API names.
    // Tabs in this map require the corresponding custom permission to be visible.
    // Tabs not in this map are visible to all users.
    private static final Map<String, String> TAB_PERMISSION_MAP = new Map<String, String>{
        'Sales Ops' => 'Sales_Ops_Visit_Tab',
        'Fixed Ops' => 'Fixed_Ops_Visit_Tab'
    };

    // ─── Inner classes for structured layout data ───

    /**
     * Represents a single field on the layout, including its value from the
     * queried Visit record and whether it should be visible based on visibility rules.
     */
    public class FieldDefinition {
        @AuraEnabled public String fieldName;
        @AuraEnabled public String label;
        @AuraEnabled public Object value;
        @AuraEnabled public String fieldType;
        @AuraEnabled public Boolean visible;
        // The field API name referenced in the visibility rule (e.g., checkbox field)
        @AuraEnabled public String visibilityField;
        @AuraEnabled public String visibilityOperator;
        @AuraEnabled public String visibilityValue;
    }

    /**
     * Represents a column within a field section. Sections can have one or two columns.
     */
    public class ColumnDefinition {
        @AuraEnabled public List<FieldDefinition> fields;

        public ColumnDefinition() {
            this.fields = new List<FieldDefinition>();
        }
    }

    /**
     * Represents a field section on the page (e.g., "Sales Ops Consultative Model").
     * A section has a label and one or more columns of fields.
     */
    public class SectionDefinition {
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isHorizontal;
        @AuraEnabled public List<ColumnDefinition> columns;

        public SectionDefinition() {
            this.columns = new List<ColumnDefinition>();
        }
    }

    /**
     * Represents a tab on the page (e.g., "Sales Ops", "Fixed Ops").
     * Each tab contains one or more field sections.
     */
    public class TabDefinition {
        @AuraEnabled public String title;
        @AuraEnabled public List<SectionDefinition> sections;

        public TabDefinition() {
            this.sections = new List<SectionDefinition>();
        }
    }

    /**
     * The top-level result returned to the LWC, containing the layout structure
     * with populated field values and visit metadata.
     */
    public class VisitLayoutResult {
        @AuraEnabled public List<TabDefinition> tabs;
        @AuraEnabled public Boolean hasVisit;
        @AuraEnabled public String visitId;
        @AuraEnabled public Date visitDate;
        @AuraEnabled public String visitorName;

        public VisitLayoutResult() {
            this.tabs = new List<TabDefinition>();
            this.hasVisit = false;
        }
    }

    /**
     * Main entry point for the LWC. Retrieves the Visit page layout and the most
     * recent Visit for the given Account in a single call.
     *
     * @param accountId The Account record Id to find visits for
     * @return VisitLayoutResult containing layout structure with field values
     */
    @AuraEnabled(cacheable=true)
    public static VisitLayoutResult getVisitWithLayout(Id accountId) {
        try {
            // Step 1: Load the FlexiPage metadata from the static resource
            Map<String, Object> flexiPageMetadata = loadFlexiPageMetadata();

            // Step 2: Parse the metadata into our structured layout
            List<TabDefinition> allTabs = parseFlexiPageTabs(flexiPageMetadata);

            // Step 3: Filter tabs by custom permission access
            List<TabDefinition> visibleTabs = filterTabsByPermission(allTabs);

            // Step 4: Collect all field API names from the visible layout
            Set<String> allFieldNames = collectFieldNames(visibleTabs);

            // Step 5: Filter fields by FLS and remove lookup fields
            Map<String, Schema.DescribeFieldResult> fieldDescribes = getAccessibleFieldDescribes(allFieldNames);
            // Copy keySet into a mutable set (Map.keySet() returns a read-only view)
            Set<String> accessibleFields = new Set<String>(fieldDescribes.keySet());

            // Always include Id and Visit_Date__c for linking and sorting (lowercase to match)
            accessibleFields.add('Id');
            accessibleFields.add('visit_date__c');

            // Step 6: Query the most recent Visit
            SObject visit = queryMostRecentVisit(accountId, accessibleFields);

            // Step 7: Build the result with field values populated
            VisitLayoutResult result = new VisitLayoutResult();
            result.hasVisit = (visit != null);
            if (visit != null) {
                result.visitId = (String) visit.get('Id');
                result.visitDate = (Date) visit.get('visit_date__c');
                // Get visitor name from the Visitor__c custom lookup relationship
                SObject visitorRef = visit.getSObject('Visitor__r');
                if (visitorRef != null) {
                    result.visitorName = (String) visitorRef.get('Name');
                }
            }

            // Populate field values and evaluate visibility rules
            for (TabDefinition tab : visibleTabs) {
                TabDefinition enrichedTab = new TabDefinition();
                enrichedTab.title = tab.title;
                for (SectionDefinition section : tab.sections) {
                    SectionDefinition enrichedSection = new SectionDefinition();
                    enrichedSection.label = section.label;
                    enrichedSection.isHorizontal = section.isHorizontal;
                    for (ColumnDefinition col : section.columns) {
                        ColumnDefinition enrichedCol = new ColumnDefinition();
                        for (FieldDefinition field : col.fields) {
                            // Skip fields the user cannot access
                            if (!accessibleFields.contains(field.fieldName)) {
                                continue;
                            }
                            FieldDefinition enrichedField = new FieldDefinition();
                            enrichedField.fieldName = field.fieldName;
                            enrichedField.label = field.label;
                            enrichedField.visibilityField = field.visibilityField;
                            enrichedField.visibilityOperator = field.visibilityOperator;
                            enrichedField.visibilityValue = field.visibilityValue;

                            // Set the field type from the describe
                            Schema.DescribeFieldResult dfr = fieldDescribes.get(field.fieldName);
                            if (dfr != null) {
                                enrichedField.fieldType = dfr.getType().name();
                                enrichedField.label = dfr.getLabel();
                            }

                            // Populate the value from the visit record
                            if (visit != null) {
                                enrichedField.value = visit.get(field.fieldName);
                            }

                            // Evaluate visibility rule
                            enrichedField.visible = evaluateVisibility(field, visit, accessibleFields);

                            enrichedCol.fields.add(enrichedField);
                        }
                        // Only add columns that have at least one accessible field
                        if (!enrichedCol.fields.isEmpty()) {
                            enrichedSection.columns.add(enrichedCol);
                        }
                    }
                    // Only add sections that have at least one column with fields
                    if (!enrichedSection.columns.isEmpty()) {
                        enrichedTab.sections.add(enrichedSection);
                    }
                }
                // Only add tabs that have at least one section
                if (!enrichedTab.sections.isEmpty()) {
                    result.tabs.add(enrichedTab);
                }
            }

            return result;
        } catch (Exception e) {
            String errorMsg = 'Unable to load visit information: ' + e.getTypeName() + ' - ' + e.getMessage()
                + ' at ' + e.getStackTraceString();
            AuraHandledException ahe = new AuraHandledException(errorMsg);
            ahe.setMessage(errorMsg);
            throw ahe;
        }
    }

    // ─── Private helper methods ───

    /**
     * Loads and parses the FlexiPage metadata JSON from the static resource.
     * This avoids needing a Tooling API callout at runtime, which would require
     * an API-enabled session that is not available in Lightning context.
     */
    @TestVisible
    private static Map<String, Object> loadFlexiPageMetadata() {
        List<StaticResource> resources = [
            SELECT Body FROM StaticResource
            WHERE Name = :LAYOUT_RESOURCE_NAME
            LIMIT 1
        ];
        if (resources.isEmpty()) {
            throw new AuraHandledException(
                'Layout resource "' + LAYOUT_RESOURCE_NAME + '" not found. '
                + 'Please deploy the VisitFlexiPageLayout static resource.'
            );
        }
        String jsonBody = resources[0].Body.toString();
        return (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
    }

    /**
     * Parses the FlexiPage metadata JSON into a list of TabDefinition objects.
     * Navigates the facet-based structure to resolve tabs → sections → columns → fields.
     */
    @TestVisible
    private static List<TabDefinition> parseFlexiPageTabs(Map<String, Object> metadata) {
        List<TabDefinition> tabs = new List<TabDefinition>();

        // Build a lookup of facet name → facet region data for resolving references
        Map<String, Object> facetMap = buildFacetMap(metadata);

        // Find the tabset component in the main region to get tab references
        List<Object> regions = (List<Object>) metadata.get('flexiPageRegions');
        if (regions == null) {
            return tabs;
        }

        // Locate the tabset facet — it contains the list of tab components
        String tabsFacetName = findTabsFacetName(regions);
        if (tabsFacetName == null) {
            return tabs;
        }

        // Get the tab components from the tabs facet
        List<Object> tabFacetItems = getFacetItems(facetMap, tabsFacetName);
        if (tabFacetItems == null) {
            return tabs;
        }

        for (Object tabItemObj : tabFacetItems) {
            Map<String, Object> tabItem = (Map<String, Object>) tabItemObj;
            Map<String, Object> compInstance = (Map<String, Object>) tabItem.get('componentInstance');
            if (compInstance == null) {
                continue;
            }

            String compName = (String) compInstance.get('componentName');
            if (compName != 'flexipage:tab') {
                continue;
            }

            TabDefinition tab = new TabDefinition();

            // Extract tab title and body facet reference from component properties
            Map<String, String> tabProps = extractComponentProperties(compInstance);
            tab.title = tabProps.get('title');
            String bodyFacetName = tabProps.get('body');

            if (bodyFacetName != null) {
                // Parse sections within this tab's body facet
                tab.sections = parseSections(facetMap, bodyFacetName);
            }

            tabs.add(tab);
        }

        return tabs;
    }

    /**
     * Builds a map of facet name → region data from all flexiPageRegions.
     */
    private static Map<String, Object> buildFacetMap(Map<String, Object> metadata) {
        Map<String, Object> facetMap = new Map<String, Object>();
        List<Object> regions = (List<Object>) metadata.get('flexiPageRegions');
        if (regions == null) {
            return facetMap;
        }
        for (Object regionObj : regions) {
            Map<String, Object> region = (Map<String, Object>) regionObj;
            String regionName = (String) region.get('name');
            if (regionName != null) {
                facetMap.put(regionName, region);
            }
        }
        return facetMap;
    }

    /**
     * Finds the facet name that holds the tab components by looking for the
     * flexipage:tabset component in the main region.
     */
    private static String findTabsFacetName(List<Object> regions) {
        for (Object regionObj : regions) {
            Map<String, Object> region = (Map<String, Object>) regionObj;
            // The main region or any region containing a tabset
            List<Object> items = (List<Object>) region.get('itemInstances');
            if (items == null) {
                continue;
            }
            for (Object itemObj : items) {
                Map<String, Object> item = (Map<String, Object>) itemObj;
                Map<String, Object> compInstance = (Map<String, Object>) item.get('componentInstance');
                if (compInstance == null) {
                    continue;
                }
                String compName = (String) compInstance.get('componentName');
                if (compName == 'flexipage:tabset') {
                    Map<String, String> props = extractComponentProperties(compInstance);
                    return props.get('tabs');
                }
            }
        }
        return null;
    }

    /**
     * Gets the itemInstances list from a facet by name.
     */
    private static List<Object> getFacetItems(Map<String, Object> facetMap, String facetName) {
        Map<String, Object> facet = (Map<String, Object>) facetMap.get(facetName);
        if (facet == null) {
            return null;
        }
        return (List<Object>) facet.get('itemInstances');
    }

    /**
     * Extracts name→value pairs from a componentInstance's componentInstanceProperties.
     */
    private static Map<String, String> extractComponentProperties(Map<String, Object> compInstance) {
        Map<String, String> props = new Map<String, String>();
        List<Object> propsList = (List<Object>) compInstance.get('componentInstanceProperties');
        if (propsList == null) {
            return props;
        }
        for (Object propObj : propsList) {
            Map<String, Object> prop = (Map<String, Object>) propObj;
            String name = (String) prop.get('name');
            String value = (String) prop.get('value');
            if (name != null) {
                props.put(name, value);
            }
        }
        return props;
    }

    /**
     * Parses field sections from a tab's body facet.
     * The body facet contains fieldSection components, each referencing column facets.
     */
    private static List<SectionDefinition> parseSections(Map<String, Object> facetMap, String bodyFacetName) {
        List<SectionDefinition> sections = new List<SectionDefinition>();
        List<Object> bodyItems = getFacetItems(facetMap, bodyFacetName);
        if (bodyItems == null) {
            return sections;
        }

        for (Object itemObj : bodyItems) {
            Map<String, Object> item = (Map<String, Object>) itemObj;
            Map<String, Object> compInstance = (Map<String, Object>) item.get('componentInstance');
            if (compInstance == null) {
                continue;
            }
            String compName = (String) compInstance.get('componentName');
            if (compName != 'flexipage:fieldSection') {
                continue;
            }

            SectionDefinition section = new SectionDefinition();
            Map<String, String> sectionProps = extractComponentProperties(compInstance);
            section.label = sectionProps.get('label');
            section.isHorizontal = 'true'.equals(sectionProps.get('horizontalAlignment'));

            // The 'columns' property references a facet containing flexipage:column components
            String columnsFacetName = sectionProps.get('columns');
            if (columnsFacetName != null) {
                section.columns = parseColumns(facetMap, columnsFacetName);
            }

            sections.add(section);
        }

        return sections;
    }

    /**
     * Parses columns from a section's columns facet.
     * Each column references another facet containing the actual field instances.
     */
    private static List<ColumnDefinition> parseColumns(Map<String, Object> facetMap, String columnsFacetName) {
        List<ColumnDefinition> columns = new List<ColumnDefinition>();
        List<Object> columnItems = getFacetItems(facetMap, columnsFacetName);
        if (columnItems == null) {
            return columns;
        }

        for (Object colItemObj : columnItems) {
            Map<String, Object> colItem = (Map<String, Object>) colItemObj;
            Map<String, Object> compInstance = (Map<String, Object>) colItem.get('componentInstance');
            if (compInstance == null) {
                continue;
            }
            String compName = (String) compInstance.get('componentName');
            if (compName != 'flexipage:column') {
                continue;
            }

            Map<String, String> colProps = extractComponentProperties(compInstance);
            String bodyFacetName = colProps.get('body');

            ColumnDefinition column = new ColumnDefinition();
            if (bodyFacetName != null) {
                column.fields = parseFields(facetMap, bodyFacetName);
            }
            columns.add(column);
        }

        return columns;
    }

    /**
     * Parses field instances from a column's body facet.
     * Each field instance has a fieldItem (e.g., "Record.Dealership_Staffing__c")
     * and optionally a visibilityRule with a criteria array.
     */
    private static List<FieldDefinition> parseFields(Map<String, Object> facetMap, String fieldsFacetName) {
        List<FieldDefinition> fields = new List<FieldDefinition>();
        List<Object> fieldItems = getFacetItems(facetMap, fieldsFacetName);
        if (fieldItems == null) {
            return fields;
        }

        for (Object fieldItemObj : fieldItems) {
            Map<String, Object> fieldItem = (Map<String, Object>) fieldItemObj;
            Map<String, Object> fieldInstance = (Map<String, Object>) fieldItem.get('fieldInstance');
            if (fieldInstance == null) {
                continue;
            }

            // Extract the field API name from "Record.FieldName__c" format
            String fieldItemValue = (String) fieldInstance.get('fieldItem');
            if (fieldItemValue == null || !fieldItemValue.startsWith('Record.')) {
                continue;
            }
            // Normalize to lowercase for consistent matching with Schema.fields.getMap()
            String fieldApiName = fieldItemValue.substringAfter('Record.').toLowerCase();

            FieldDefinition field = new FieldDefinition();
            field.fieldName = fieldApiName;
            field.label = fieldApiName; // Will be overridden with describe label later
            field.visible = true; // Default visible; overridden if visibility rule exists

            // Parse visibility rule if present
            Map<String, Object> visRule = (Map<String, Object>) fieldInstance.get('visibilityRule');
            if (visRule != null) {
                // The Tooling API returns criteria as an array; use the first criterion
                List<Object> criteriaList = (List<Object>) visRule.get('criteria');
                if (criteriaList != null && !criteriaList.isEmpty()) {
                    Map<String, Object> criteria = (Map<String, Object>) criteriaList[0];
                    String leftValue = (String) criteria.get('leftValue');
                    // leftValue format: "{!Record.FieldName__c}"
                    if (leftValue != null && leftValue.contains('Record.')) {
                        // Also normalize visibility field name to lowercase
                        field.visibilityField = leftValue.substringBetween('Record.', '}').toLowerCase();
                    }
                    field.visibilityOperator = (String) criteria.get('operator');
                    field.visibilityValue = String.valueOf(criteria.get('rightValue'));
                }
            }

            fields.add(field);
        }

        return fields;
    }

    /**
     * Returns all tabs — all users can see every tab in this LWC regardless of
     * profile or permission set. Tab-level permission filtering was removed per
     * requirements; the custom permissions and permission sets remain in the org
     * for potential use elsewhere.
     */
    private static List<TabDefinition> filterTabsByPermission(List<TabDefinition> tabs) {
        return tabs;
    }

    /**
     * Collects all unique field API names from the layout structure.
     * Includes both regular fields and fields referenced in visibility rules.
     */
    private static Set<String> collectFieldNames(List<TabDefinition> tabs) {
        Set<String> fieldNames = new Set<String>();
        for (TabDefinition tab : tabs) {
            for (SectionDefinition section : tab.sections) {
                for (ColumnDefinition col : section.columns) {
                    for (FieldDefinition field : col.fields) {
                        fieldNames.add(field.fieldName);
                        // Also collect fields referenced in visibility rules
                        if (field.visibilityField != null) {
                            fieldNames.add(field.visibilityField);
                        }
                    }
                }
            }
        }
        return fieldNames;
    }

    /**
     * Returns DescribeFieldResult for each field that is accessible to the current
     * user and is NOT a lookup/reference field. Lookup fields are excluded per requirements.
     */
    private static Map<String, Schema.DescribeFieldResult> getAccessibleFieldDescribes(Set<String> fieldNames) {
        Map<String, Schema.DescribeFieldResult> result = new Map<String, Schema.DescribeFieldResult>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Visit.fields.getMap();

        for (String fieldName : fieldNames) {
            Schema.SObjectField sField = fieldMap.get(fieldName);
            if (sField == null) {
                continue;
            }
            Schema.DescribeFieldResult dfr = sField.getDescribe();
            // Skip fields the user cannot read
            if (!dfr.isAccessible()) {
                continue;
            }
            // Skip lookup/reference fields per requirements
            if (dfr.getType() == Schema.DisplayType.REFERENCE) {
                continue;
            }
            result.put(fieldName, dfr);
        }

        return result;
    }

    /**
     * Queries the most recent Visit record for the given Account, selecting only
     * the fields that the user has access to.
     */
    private static SObject queryMostRecentVisit(Id accountId, Set<String> accessibleFields) {
        if (accountId == null || accessibleFields.isEmpty()) {
            return null;
        }

        // Build the field list for the SOQL query
        List<String> fieldList = new List<String>(accessibleFields);
        String fieldString = String.join(fieldList, ', ');

        // Include the Visitor relationship name for the card header display
        String soql = 'SELECT ' + fieldString + ', Visitor__r.Name'
                     + ' FROM Visit'
                     + ' WHERE AccountId = :accountId'
                     + ' ORDER BY Visit_Date__c DESC NULLS LAST'
                     + ' LIMIT 1';

        List<SObject> results = Database.query(soql);
        return results.isEmpty() ? null : results[0];
    }

    /**
     * Evaluates a field's visibility rule against the visit record values.
     * If no visibility rule exists, the field is always visible.
     * If the referenced visibility field is not accessible, the field is hidden.
     */
    private static Boolean evaluateVisibility(FieldDefinition field, SObject visit, Set<String> accessibleFields) {
        // No visibility rule means always visible
        if (field.visibilityField == null) {
            return true;
        }

        // If the controlling field is not accessible, hide this field
        if (!accessibleFields.contains(field.visibilityField)) {
            return false;
        }

        // If there is no visit record, nothing to evaluate against
        if (visit == null) {
            return false;
        }

        // Get the value of the controlling field from the visit record
        Object controllingValue = visit.get(field.visibilityField);

        // Evaluate based on the operator
        if (field.visibilityOperator == 'EQUAL') {
            String expectedValue = field.visibilityValue;
            if (expectedValue == 'true') {
                return controllingValue != null && Boolean.valueOf(controllingValue) == true;
            } else if (expectedValue == 'false') {
                return controllingValue == null || Boolean.valueOf(controllingValue) == false;
            }
            return String.valueOf(controllingValue) == expectedValue;
        }

        // Default to visible for unrecognized operators
        return true;
    }
}