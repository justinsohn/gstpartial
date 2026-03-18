public without sharing class VisitSharingService {

    public static void syncVisitSharing(List<Visit> newVisits, Map<Id, Visit> oldMap) {
        if (newVisits == null || newVisits.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        Set<Id> visitIdsToProcess = new Set<Id>();

        for (Visit v : newVisits) {
            if (v.AccountId == null) {
                continue;
            }

            if (oldMap == null) {
                // Insert path, or explicit resync path
                accountIds.add(v.AccountId);
                visitIdsToProcess.add(v.Id);
            } else {
                Visit oldVisit = oldMap.get(v.Id);

                // Reprocess only when Account changes
                if (oldVisit != null && v.AccountId != oldVisit.AccountId) {
                    accountIds.add(v.AccountId);
                    visitIdsToProcess.add(v.Id);
                }
            }
        }

        if (visitIdsToProcess.isEmpty() || accountIds.isEmpty()) {
            return;
        }

        Map<Id, Account> accountsById = new Map<Id, Account>([
            SELECT Id, District__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        Set<String> districtNames = new Set<String>();
        for (Account acct : accountsById.values()) {
            if (String.isNotBlank(acct.District__c)) {
                districtNames.add(getDistrictGroupName(acct.District__c));
            }
        }

        if (districtNames.isEmpty()) {
            return;
        }

        Map<String, Group> groupsByName = new Map<String, Group>();
        for (Group g : [
            SELECT Id, Name
            FROM Group
            WHERE Type = 'Regular'
            AND Name IN :districtNames
        ]) {
            groupsByName.put(g.Name, g);
        }

        // Delete all existing manual shares for visits being reprocessed before inserting new ones.
        List<VisitShare> sharesToDelete = [
            SELECT Id
            FROM VisitShare
            WHERE ParentId IN :visitIdsToProcess
            AND RowCause = 'Manual'
        ];
        if (!sharesToDelete.isEmpty()) {
            delete sharesToDelete;
        }

        List<VisitShare> sharesToInsert = new List<VisitShare>();

        for (Visit v : newVisits) {
            if (!visitIdsToProcess.contains(v.Id) || v.AccountId == null) {
                continue;
            }

            Account acct = accountsById.get(v.AccountId);
            if (acct == null || String.isBlank(acct.District__c)) {
                continue;
            }

            Group districtGroup = groupsByName.get(getDistrictGroupName(acct.District__c));
            if (districtGroup == null) {
                continue;
            }

            VisitShare vs = new VisitShare();
            vs.ParentId = v.Id;
            vs.UserOrGroupId = districtGroup.Id;
            vs.AccessLevel = 'Edit';
            vs.RowCause = Schema.VisitShare.RowCause.Manual;

            sharesToInsert.add(vs);
        }

        if (!sharesToInsert.isEmpty()) {
            Database.insert(sharesToInsert, false);
        }
    }

    private static String getDistrictGroupName(String districtValue) {
        if (String.isBlank(districtValue)) {
            return null;
        }
        return 'District ' + districtValue.trim();
    }
}