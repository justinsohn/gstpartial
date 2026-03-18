trigger AccountTrigger on Account (after update) {
    Set<Id> changedAccountIds = new Set<Id>();

    for (Account a : Trigger.new) {
        Account oldA = Trigger.oldMap.get(a.Id);
        if (a.District__c != oldA.District__c) {
            changedAccountIds.add(a.Id);
        }
    }

    if (!changedAccountIds.isEmpty()) {
        VisitSharingResyncService.resyncByAccountIds(changedAccountIds);
    }
}