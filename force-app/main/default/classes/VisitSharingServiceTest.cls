@IsTest
private class VisitSharingServiceTest {

    @TestSetup
    static void setupData() {

        insert new List<Schema.Location>{
            new Schema.Location(
                Name = 'Test Store Location A',
                LocationType = 'Store'
            ),
            new Schema.Location(
                Name = 'Test Store Location B',
                LocationType = 'Store'
            )
        };

        insert new List<Account>{
            new Account(
                Name = 'Dealer A',
                Area__c = '1 (East)',
                District__c = 'A'
            ),
            new Account(
                Name = 'Dealer B',
                Area__c = '1 (East)',
                District__c = 'B'
            ),
            new Account(
                Name = 'Dealer No District'
            )
        };
    }

    private static Id getGroupIdByName(String name) {
        List<Group> groups = [
            SELECT Id
            FROM Group
            WHERE Type = 'Regular'
            AND Name = :name
        ];

        System.assertEquals(1, groups.size(), 'Expected exactly one Group named ' + name);
        return groups[0].Id;
    }

    private static Id getLocationIdByName(String name) {
        return [
            SELECT Id
            FROM Location
            WHERE Name = :name
            LIMIT 1
        ].Id;
    }

    private static Id getAccountIdByName(String name) {
        return [
            SELECT Id
            FROM Account
            WHERE Name = :name
            LIMIT 1
        ].Id;
    }

    private static Visit createVisit(Id accountId, Id placeId) {
        Visit v = new Visit(
            AccountId = accountId,
            PlaceId = placeId,
            PlannedVisitStartTime = System.now().addDays(1)
        );
        insert v;
        return v;
    }

    @IsTest
    static void testShareCreatedOnInsert() {
        Id accountId = getAccountIdByName('Dealer A');
        Id placeId = getLocationIdByName('Test Store Location A');
        Id districtAGroupId = getGroupIdByName('District A');

        Test.startTest();
        Visit v = createVisit(accountId, placeId);
        Test.stopTest();

        List<VisitShare> shares = [
            SELECT Id, ParentId, UserOrGroupId, AccessLevel, RowCause
            FROM VisitShare
            WHERE ParentId = :v.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(1, shares.size(), 'Expected one VisitShare row.');
        System.assertEquals(districtAGroupId, shares[0].UserOrGroupId, 'Visit should be shared to District A group.');
        System.assertEquals('Edit', shares[0].AccessLevel, 'Visit should be shared with Edit access.');
    }

    @IsTest
    static void testShareUpdatedWhenAccountChanges() {
        Id accountAId = getAccountIdByName('Dealer A');
        Id accountBId = getAccountIdByName('Dealer B');
        Id placeId = getLocationIdByName('Test Store Location A');
        Id districtBGroupId = getGroupIdByName('District B');

        Visit v = createVisit(accountAId, placeId);

        Test.startTest();
        v.AccountId = accountBId;
        update v;
        Test.stopTest();

        List<VisitShare> shares = [
            SELECT Id, UserOrGroupId, AccessLevel
            FROM VisitShare
            WHERE ParentId = :v.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(1, shares.size(), 'Expected one VisitShare row after Account change.');
        System.assertEquals(districtBGroupId, shares[0].UserOrGroupId, 'Visit should now be shared to District B group.');
        System.assertEquals('Edit', shares[0].AccessLevel, 'Visit should still be shared with Edit access.');
    }

    @IsTest
    static void testNoShareWhenDistrictBlank() {
        Id accountId = getAccountIdByName('Dealer No District');
        Id placeId = getLocationIdByName('Test Store Location A');

        Test.startTest();
        Visit v = createVisit(accountId, placeId);
        Test.stopTest();

        Integer shareCount = [
            SELECT COUNT()
            FROM VisitShare
            WHERE ParentId = :v.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(0, shareCount, 'No share should be created when district is blank.');
    }

    @IsTest
    static void testResyncWhenAccountDistrictChanges() {
        Id accountId = getAccountIdByName('Dealer A');
        Id placeId = getLocationIdByName('Test Store Location A');
        Id districtBGroupId = getGroupIdByName('District B');

        Visit v = createVisit(accountId, placeId);

        Account acct = [
            SELECT Id, District__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        Test.startTest();
        acct.District__c = 'B';
        update acct;
        Test.stopTest();

        List<VisitShare> shares = [
            SELECT Id, UserOrGroupId, AccessLevel
            FROM VisitShare
            WHERE ParentId = :v.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(1, shares.size(), 'Expected one VisitShare row after district resync.');
        System.assertEquals(districtBGroupId, shares[0].UserOrGroupId, 'Visit should now be shared to District B group.');
        System.assertEquals('Edit', shares[0].AccessLevel, 'Visit should still be shared with Edit access.');
    }
}