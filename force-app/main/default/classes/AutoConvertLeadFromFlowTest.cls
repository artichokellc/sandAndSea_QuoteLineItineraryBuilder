@isTest
public class AutoConvertLeadFromFlowTest {
    Static TestMethod void AutoConvert()
    {
        test.StartTest();
        
        
        
        Account acc = new Account(Name='Test Account');
        insert acc;
        
        
        
        Contact c = new Contact(LastName='Contant Test',AccountId=acc.Id);
        insert c;
        
        Opportunity opp = new Opportunity(Name='Test Opp', StageName='Qualification', CloseDate= System.Today(),AccountId=acc.Id);
        insert opp;
        
        Lead testLead = new Lead(
            FirstName='Demo 100800',
            LastName = 'Demo 100800 UnitTest',
            Status='Qualified',
            company='Lacosta',
            street='1211 E I-40 Service Rd',
            city=' Oklahoma City',
            state='OK'
        );
        insert  testLead;
        
        
        AutoConvertLeadFromFlow.convertDetails cd = new AutoConvertLeadFromFlow.convertDetails();
        cd.LeadIdToConvert=testLead.Id;
        //cd.oppId=opp.Id;
        cd.AccountId=acc.Id;
        cd.ContactId =c.Id;
        
        List<AutoConvertLeadFromFlow.convertDetails> convertDetails = new List<AutoConvertLeadFromFlow.convertDetails>();
        convertDetails.add(cd);
        
        AutoConvertLeadFromFlow.convert(convertDetails);

        test.stopTest();
        
    }
      
   
}