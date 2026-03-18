public without sharing class VisitSharingResyncService {

    public static void resyncByAccountIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }

        List<Visit> visits = [
            SELECT Id, AccountId
            FROM Visit
            WHERE AccountId IN :accountIds
        ];

        if (visits.isEmpty()) {
            return;
        }

        VisitSharingService.syncVisitSharing(visits, null);
    }
}