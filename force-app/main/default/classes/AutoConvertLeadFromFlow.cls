public class AutoConvertLeadFromFlow {
    @InvocableMethod
    public static void convert(List<convertDetails> convertDetails) {
        Id leadId = convertDetails[0].leadIdToConvert;
        String oppName = convertDetails[0].oppName;
        Id contactId = convertDetails[0].contactId;
        Id accountId = convertDetails[0].accountId;
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(leadId);
        
        LeadStatus convertStatus = [SELECT Id, ApiName FROM LeadStatus WHERE IsConverted=true LIMIT 1];
        lc.setConvertedStatus(convertStatus.ApiName);
     
        lc.setAccountId(accountId);
        lc.setContactId(contactId);
        lc.setOpportunityName(oppName);
        
        Database.LeadConvertResult lcr = Database.convertLead(lc);
        System.debug(lcr);
        
        String oppId = lcr.getOpportunityId();
        Opportunity toBeUpdatedOpp = new Opportunity(Id=oppId);
        toBeUpdatedOpp.StageName = 'Needs Analysis';
        Update toBeUpdatedOpp;
        
        List<OpportunityContactRole> oppContactRoleList = [select Id from OpportunityContactRole where opportunityId=:oppId LIMIT 1];
        OpportunityContactRole oppContactRole = new OpportunityContactRole();
        if(oppContactRoleList.size() >= 1){
            oppContactRole = oppContactRoleList[0];
        }else{
            oppContactRole.ContactId = lcr.getContactId(); 
        }
        oppContactRole.IsPrimary = true;
        oppContactRole.Role = 'Primary Traveler';
        upsert oppContactRole;


    }
    
    public class convertDetails {
        @InvocableVariable(label='Lead' description='Id' required=true)
        public String leadIdToConvert;
        @InvocableVariable(label='opportunity name' description='String' required=true)
        public String oppName;
        @InvocableVariable(label='contact' description='Id' required=true)
        public String contactId;
        @InvocableVariable(label='account' description='Id' required=true)
        public String accountId;
    }
    
    

}