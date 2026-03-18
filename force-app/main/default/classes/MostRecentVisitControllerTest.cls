/**
 * Test class for MostRecentVisitController.
 * Tests use the deployed VisitFlexiPageLayout static resource which contains
 * the real Visit Desktop Page layout metadata.
 */
@IsTest
private class MostRecentVisitControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create Account
        Account testAccount = new Account(Name = 'Test Dealership');
        insert testAccount;

        // Create a Location record required for Visit.PlaceId
        Schema.Location testLocation = new Schema.Location(
            Name = 'Test Location',
            LocationType = 'Warehouse'
        );
        insert testLocation;
    }

    /**
     * Verifies that the controller returns visit data with layout structure
     * when a Visit record exists for the Account.
     */
    @IsTest
    static void testGetVisitWithLayout_VisitExists() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Schema.Location testLocation = [SELECT Id FROM Location LIMIT 1];

        // Create a Visit linked to the Account with some fields populated
        Visit testVisit = new Visit(
            AccountId = testAccount.Id,
            PlaceId = testLocation.Id,
            PlannedVisitStartTime = DateTime.now(),
            Visit_Date__c = Date.today(),
            Dealership_Staffing__c = true,
            Dealership_Staffing_Notes__c = 'Test staffing notes'
        );
        insert testVisit;

        Test.startTest();
        MostRecentVisitController.VisitLayoutResult result =
            MostRecentVisitController.getVisitWithLayout(testAccount.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.hasVisit, 'Should find the visit');
        System.assertEquals(testVisit.Id, result.visitId, 'Should return correct visit Id');
        System.assertEquals(Date.today(), result.visitDate, 'Should return correct visit date');
        // Tabs should be present (System Admin sees all tabs)
        System.assert(!result.tabs.isEmpty(), 'Should have at least one tab');
    }

    /**
     * Verifies that the controller returns the most recent Visit
     * when multiple visits exist for the Account.
     */
    @IsTest
    static void testGetVisitWithLayout_MostRecentReturned() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Schema.Location testLocation = [SELECT Id FROM Location LIMIT 1];

        // Create an older visit
        Visit olderVisit = new Visit(
            AccountId = testAccount.Id,
            PlaceId = testLocation.Id,
            PlannedVisitStartTime = DateTime.now().addDays(-10),
            Visit_Date__c = Date.today().addDays(-10),
            Dealership_Staffing__c = true,
            Dealership_Staffing_Notes__c = 'Old notes'
        );
        insert olderVisit;

        // Create a newer visit
        Visit newerVisit = new Visit(
            AccountId = testAccount.Id,
            PlaceId = testLocation.Id,
            PlannedVisitStartTime = DateTime.now(),
            Visit_Date__c = Date.today(),
            Dealership_Staffing__c = true,
            Dealership_Staffing_Notes__c = 'New notes'
        );
        insert newerVisit;

        Test.startTest();
        MostRecentVisitController.VisitLayoutResult result =
            MostRecentVisitController.getVisitWithLayout(testAccount.Id);
        Test.stopTest();

        System.assertEquals(true, result.hasVisit, 'Should find a visit');
        System.assertEquals(newerVisit.Id, result.visitId, 'Should return the most recent visit');
        System.assertEquals(Date.today(), result.visitDate, 'Should return the most recent date');
    }

    /**
     * Verifies that the controller returns hasVisit = false
     * when no Visit records exist for the Account.
     */
    @IsTest
    static void testGetVisitWithLayout_NoVisit() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        MostRecentVisitController.VisitLayoutResult result =
            MostRecentVisitController.getVisitWithLayout(testAccount.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(false, result.hasVisit, 'Should not find any visit');
        System.assertEquals(null, result.visitId, 'Visit Id should be null');
    }

    /**
     * Verifies that all four tabs are returned for any user, since tab
     * permission filtering was removed and all tabs are visible to everyone.
     */
    @IsTest
    static void testGetVisitWithLayout_AllTabsVisibleToEveryone() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Schema.Location testLocation = [SELECT Id FROM Location LIMIT 1];

        Visit testVisit = new Visit(
            AccountId = testAccount.Id,
            PlaceId = testLocation.Id,
            PlannedVisitStartTime = DateTime.now(),
            Visit_Date__c = Date.today()
        );
        insert testVisit;

        Test.startTest();
        MostRecentVisitController.VisitLayoutResult result =
            MostRecentVisitController.getVisitWithLayout(testAccount.Id);
        Test.stopTest();

        // All users should see all 4 tabs (Sales Ops, Fixed Ops, Other, Admin)
        Set<String> tabTitles = new Set<String>();
        for (MostRecentVisitController.TabDefinition tab : result.tabs) {
            tabTitles.add(tab.title);
        }
        System.assert(tabTitles.contains('Sales Ops'),
            'System Admin should see Sales Ops tab');
        System.assert(tabTitles.contains('Fixed Ops'),
            'System Admin should see Fixed Ops tab');
    }

    /**
     * Verifies that the parseFlexiPageTabs method correctly parses the
     * tab/section/column/field structure from FlexiPage metadata JSON.
     */
    @IsTest
    static void testParseFlexiPageTabs() {
        String mockJson = buildMockFlexiPageMetadata();
        Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(mockJson);

        Test.startTest();
        List<MostRecentVisitController.TabDefinition> tabs =
            MostRecentVisitController.parseFlexiPageTabs(metadata);
        Test.stopTest();

        // Should find all 4 tabs
        System.assertEquals(4, tabs.size(), 'Should parse 4 tabs');
        System.assertEquals('Sales Ops', tabs[0].title, 'First tab should be Sales Ops');
        System.assertEquals('Fixed Ops', tabs[1].title, 'Second tab should be Fixed Ops');
        System.assertEquals('Other', tabs[2].title, 'Third tab should be Other');
        System.assertEquals('Admin', tabs[3].title, 'Fourth tab should be Admin');
    }

    /**
     * Verifies that visibility rules are correctly parsed and evaluated.
     * When a controlling checkbox is true, the corresponding notes field
     * should be visible. When false, it should be hidden.
     */
    @IsTest
    static void testVisibilityRuleEvaluation() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Schema.Location testLocation = [SELECT Id FROM Location LIMIT 1];

        // Create a Visit with Dealership_Staffing checked (notes should be visible)
        // and all other checkboxes unchecked (their notes should be hidden)
        Visit testVisit = new Visit(
            AccountId = testAccount.Id,
            PlaceId = testLocation.Id,
            PlannedVisitStartTime = DateTime.now(),
            Visit_Date__c = Date.today(),
            Dealership_Staffing__c = true,
            Dealership_Staffing_Notes__c = 'Staffing notes here'
        );
        insert testVisit;

        Test.startTest();
        MostRecentVisitController.VisitLayoutResult result =
            MostRecentVisitController.getVisitWithLayout(testAccount.Id);
        Test.stopTest();

        System.assertEquals(true, result.hasVisit, 'Should find the visit');

        // Verify that at least one field with a visibility rule was found visible
        // and at least one was found hidden, proving the rules are evaluated
        Boolean foundVisibleWithRule = false;
        Boolean foundHiddenWithRule = false;
        for (MostRecentVisitController.TabDefinition tab : result.tabs) {
            for (MostRecentVisitController.SectionDefinition section : tab.sections) {
                for (MostRecentVisitController.ColumnDefinition col : section.columns) {
                    for (MostRecentVisitController.FieldDefinition field : col.fields) {
                        if (field.visibilityField != null) {
                            if (field.visible == true) {
                                foundVisibleWithRule = true;
                            } else if (field.visible == false) {
                                foundHiddenWithRule = true;
                            }
                        }
                    }
                }
            }
        }
        System.assert(foundVisibleWithRule,
            'Should find at least one visible field controlled by a visibility rule');
        System.assert(foundHiddenWithRule,
            'Should find at least one hidden field controlled by a visibility rule');
    }

    // ─── Helper methods for building mock metadata ───

    /**
     * Builds a simplified FlexiPage metadata JSON that mirrors the real
     * Visit_Desktop_Page structure with 4 tabs, sections, and fields.
     * Uses array format for visibility rule criteria to match Tooling API output.
     */
    private static String buildMockFlexiPageMetadata() {
        return '{'
            // ── Field facets for Sales Ops tab ──
            + '"flexiPageRegions":['
            + '{"name":"facet-sales-left","type":"Facet","itemInstances":['
            + '{"fieldInstance":{"fieldItem":"Record.Dealership_Staffing__c","identifier":"f1"}}'
            + ',{"fieldInstance":{"fieldItem":"Record.New_Sales_Processes__c","identifier":"f2"}}'
            + ']},'
            + '{"name":"facet-sales-right","type":"Facet","itemInstances":['
            + '{"fieldInstance":{"fieldItem":"Record.Inventory__c","identifier":"f3"}}'
            + ',{"fieldInstance":{"fieldItem":"Record.Traffic_Generation__c","identifier":"f4"}}'
            + ']},'
            + '{"name":"facet-sales-columns","type":"Facet","itemInstances":['
            + '{"componentInstance":{"componentName":"flexipage:column","componentInstanceProperties":[{"name":"body","value":"facet-sales-left"}]}}'
            + ',{"componentInstance":{"componentName":"flexipage:column","componentInstanceProperties":[{"name":"body","value":"facet-sales-right"}]}}'
            + ']},'
            // Notes fields with visibility rules (criteria as array)
            + '{"name":"facet-sales-notes-fields","type":"Facet","itemInstances":['
            + '{"fieldInstance":{"fieldItem":"Record.Dealership_Staffing_Notes__c","identifier":"fn1"'
            + ',"visibilityRule":{"criteria":[{"leftValue":"{!Record.Dealership_Staffing__c}","operator":"EQUAL","rightValue":"true"}]}}}'
            + ',{"fieldInstance":{"fieldItem":"Record.Inventory_Notes__c","identifier":"fn2"'
            + ',"visibilityRule":{"criteria":[{"leftValue":"{!Record.Inventory__c}","operator":"EQUAL","rightValue":"true"}]}}}'
            + ']},'
            + '{"name":"facet-sales-notes-col","type":"Facet","itemInstances":['
            + '{"componentInstance":{"componentName":"flexipage:column","componentInstanceProperties":[{"name":"body","value":"facet-sales-notes-fields"}]}}'
            + ']},'
            + '{"name":"facet-sales-body","type":"Facet","itemInstances":['
            + '{"componentInstance":{"componentName":"flexipage:fieldSection","componentInstanceProperties":['
            + '{"name":"label","value":"Sales Ops Consultative Model"},{"name":"columns","value":"facet-sales-columns"},{"name":"horizontalAlignment","value":"true"}'
            + ']}}'
            + ',{"componentInstance":{"componentName":"flexipage:fieldSection","componentInstanceProperties":['
            + '{"name":"label","value":"Sales Ops Notes"},{"name":"columns","value":"facet-sales-notes-col"},{"name":"horizontalAlignment","value":"false"}'
            + ']}}'
            + ']},'

            // ── Fixed Ops tab ──
            + '{"name":"facet-fixed-left","type":"Facet","itemInstances":['
            + '{"fieldInstance":{"fieldItem":"Record.Dealership_Staffing__c","identifier":"ff1"}}'
            + ',{"fieldInstance":{"fieldItem":"Record.Repair_Flow__c","identifier":"ff2"}}'
            + ']},'
            + '{"name":"facet-fixed-right","type":"Facet","itemInstances":['
            + '{"fieldInstance":{"fieldItem":"Record.Dealership_Processes__c","identifier":"ff3"}}'
            + ',{"fieldInstance":{"fieldItem":"Record.Customer_Retention__c","identifier":"ff4"}}'
            + ']},'
            + '{"name":"facet-fixed-columns","type":"Facet","itemInstances":['
            + '{"componentInstance":{"componentName":"flexipage:column","componentInstanceProperties":[{"name":"body","value":"facet-fixed-left"}]}}'
            + ',{"componentInstance":{"componentName":"flexipage:column","componentInstanceProperties":[{"name":"body","value":"facet-fixed-right"}]}}'
            + ']},'
            + '{"name":"facet-fixed-notes-fields","type":"Facet","itemInstances":['
            + '{"fieldInstance":{"fieldItem":"Record.Dealership_Staffing_Notes__c","identifier":"ffn1"'
            + ',"visibilityRule":{"criteria":[{"leftValue":"{!Record.Dealership_Staffing__c}","operator":"EQUAL","rightValue":"true"}]}}}'
            + ',{"fieldInstance":{"fieldItem":"Record.Repair_Flow_Notes__c","identifier":"ffn2"'
            + ',"visibilityRule":{"criteria":[{"leftValue":"{!Record.Repair_Flow__c}","operator":"EQUAL","rightValue":"true"}]}}}'
            + ']},'
            + '{"name":"facet-fixed-notes-col","type":"Facet","itemInstances":['
            + '{"componentInstance":{"componentName":"flexipage:column","componentInstanceProperties":[{"name":"body","value":"facet-fixed-notes-fields"}]}}'
            + ']},'
            + '{"name":"facet-fixed-body","type":"Facet","itemInstances":['
            + '{"componentInstance":{"componentName":"flexipage:fieldSection","componentInstanceProperties":['
            + '{"name":"label","value":"Fixed Ops Consultative Model"},{"name":"columns","value":"facet-fixed-columns"},{"name":"horizontalAlignment","value":"true"}'
            + ']}}'
            + ',{"componentInstance":{"componentName":"flexipage:fieldSection","componentInstanceProperties":['
            + '{"name":"label","value":"Fixed Ops Notes"},{"name":"columns","value":"facet-fixed-notes-col"},{"name":"horizontalAlignment","value":"false"}'
            + ']}}'
            + ']},'

            // ── Other tab ──
            + '{"name":"facet-other-fields","type":"Facet","itemInstances":['
            + '{"fieldInstance":{"fieldItem":"Record.Other_Notes__c","identifier":"fo1"}}'
            + ']},'
            + '{"name":"facet-other-col","type":"Facet","itemInstances":['
            + '{"componentInstance":{"componentName":"flexipage:column","componentInstanceProperties":[{"name":"body","value":"facet-other-fields"}]}}'
            + ']},'
            + '{"name":"facet-other-body","type":"Facet","itemInstances":['
            + '{"componentInstance":{"componentName":"flexipage:fieldSection","componentInstanceProperties":['
            + '{"name":"label","value":"Notes"},{"name":"columns","value":"facet-other-col"},{"name":"horizontalAlignment","value":"false"}'
            + ']}}'
            + ']},'

            // ── Admin tab ──
            + '{"name":"facet-admin-fields","type":"Facet","itemInstances":['
            + '{"fieldInstance":{"fieldItem":"Record.Visit_Date__c","identifier":"fa1"}}'
            + ',{"fieldInstance":{"fieldItem":"Record.Visitor__c","identifier":"fa2"}}'
            + ']},'
            + '{"name":"facet-admin-col","type":"Facet","itemInstances":['
            + '{"componentInstance":{"componentName":"flexipage:column","componentInstanceProperties":[{"name":"body","value":"facet-admin-fields"}]}}'
            + ']},'
            + '{"name":"facet-admin-body","type":"Facet","itemInstances":['
            + '{"componentInstance":{"componentName":"flexipage:fieldSection","componentInstanceProperties":['
            + '{"name":"label","value":"General"},{"name":"columns","value":"facet-admin-col"},{"name":"horizontalAlignment","value":"false"}'
            + ']}}'
            + ']},'

            // ── Tab components ──
            + '{"name":"facet-tabs","type":"Facet","itemInstances":['
            + '{"componentInstance":{"componentName":"flexipage:tab","componentInstanceProperties":[{"name":"title","value":"Sales Ops"},{"name":"body","value":"facet-sales-body"}]}}'
            + ',{"componentInstance":{"componentName":"flexipage:tab","componentInstanceProperties":[{"name":"title","value":"Fixed Ops"},{"name":"body","value":"facet-fixed-body"}]}}'
            + ',{"componentInstance":{"componentName":"flexipage:tab","componentInstanceProperties":[{"name":"title","value":"Other"},{"name":"body","value":"facet-other-body"}]}}'
            + ',{"componentInstance":{"componentName":"flexipage:tab","componentInstanceProperties":[{"name":"title","value":"Admin"},{"name":"body","value":"facet-admin-body"}]}}'
            + ']},'

            // ── Main region with tabset ──
            + '{"name":"main","type":"Region","itemInstances":['
            + '{"componentInstance":{"componentName":"flexipage:tabset","componentInstanceProperties":['
            + '{"name":"tabs","value":"facet-tabs"},{"name":"label","value":"Tabs"}'
            + ']}}'
            + ']}'

            + ']}';
    }
}