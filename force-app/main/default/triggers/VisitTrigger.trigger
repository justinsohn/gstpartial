trigger VisitTrigger on Visit (
    after insert,
    after update
) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            VisitSharingService.syncVisitSharing(Trigger.new, null);
        } else if (Trigger.isUpdate) {
            VisitSharingService.syncVisitSharing(Trigger.new, Trigger.oldMap);
        }
    }
}