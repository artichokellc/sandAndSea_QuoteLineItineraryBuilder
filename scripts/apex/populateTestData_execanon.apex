// Itinerary Builder — Execute Anonymous version (fresh sandbox)
Id rtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Business_Supplier').getRecordTypeId();

List<Account> accts = new List<Account>{
    new Account(Name='Delta Vacations', RecordTypeId=rtId, Booking_Channel__c='Yes', Commission_Rate__c=10),
    new Account(Name='Virgin Voyages',  RecordTypeId=rtId, Booking_Channel__c='Yes', Commission_Rate__c=10),
    new Account(Name='Royal Carribean', RecordTypeId=rtId, Booking_Channel__c='Yes', Commission_Rate__c=8)
};
insert accts;
Id deltaId=accts[0].Id; Id virginId=accts[1].Id; Id royalId=accts[2].Id;

Id pbId = [SELECT Id FROM Pricebook2 WHERE IsStandard=false AND IsActive=true ORDER BY CreatedDate ASC LIMIT 1].Id;
Id stdId = [SELECT Id FROM Pricebook2 WHERE IsStandard=true LIMIT 1].Id;

Map<String,Id> pMap = new Map<String,Id>();
for(Product2 p : [SELECT Id,Name FROM Product2 WHERE Name IN ('Hotel Lodging','Cruise','Transfer - Private Car','Activity / Excursion','Flight - Round Trip','Signature Service Fee','Car - Rental','Package') AND IsActive=true]){
    pMap.put(p.Name, p.Id);
}

Map<Id,Id> pbeMap = new Map<Id,Id>();
for(PricebookEntry e : [SELECT Id,Product2Id FROM PricebookEntry WHERE Pricebook2Id=:pbId AND Product2Id IN :pMap.values() AND IsActive=true]){
    pbeMap.put(e.Product2Id, e.Id);
}

Opportunity opp = new Opportunity(Name='TEST Scotland Trip 2027', StageName='Prospecting', CloseDate=Date.newInstance(2027,3,1));
insert opp;

Quote q = new Quote(Name='TEST Scotland Itinerary', OpportunityId=opp.Id, Pricebook2Id=pbId, Status='Draft');
insert q;

insert new List<QuoteLineItem>{
    new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbeMap.get(pMap.get('Flight - Round Trip')),    Quantity=2, UnitPrice=1200, Description='LHR to Edinburgh return',         Supplier__c=virginId, Provider__c=virginId, Start_Date__c=Date.newInstance(2027,6,5),  End_Date__c=Date.newInstance(2027,6,5),  Commission_Amount__c=0,   Commission_Percent__c=0),
    new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbeMap.get(pMap.get('Transfer - Private Car')), Quantity=1, UnitPrice=350,  Description='Airport to hotel transfer',      Supplier__c=deltaId,  Provider__c=deltaId,  Start_Date__c=Date.newInstance(2027,6,5),  End_Date__c=Date.newInstance(2027,6,5),  Commission_Amount__c=35,  Commission_Percent__c=10),
    new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbeMap.get(pMap.get('Hotel Lodging')),          Quantity=5, UnitPrice=280,  Description='The Balmoral Hotel 5 nights',    Supplier__c=royalId,  Provider__c=royalId,  Start_Date__c=Date.newInstance(2027,6,5),  End_Date__c=Date.newInstance(2027,6,10), Commission_Amount__c=112, Commission_Percent__c=8),
    new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbeMap.get(pMap.get('Activity / Excursion')),   Quantity=2, UnitPrice=195,  Description='Loch Ness guided day tour',      Supplier__c=deltaId,  Provider__c=deltaId,  Start_Date__c=Date.newInstance(2027,6,7),  End_Date__c=Date.newInstance(2027,6,7),  Commission_Amount__c=39,  Commission_Percent__c=10),
    new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbeMap.get(pMap.get('Car - Rental')),           Quantity=3, UnitPrice=120,  Description='Economy rental 3 days Edinburgh',Supplier__c=deltaId,  Provider__c=deltaId,  Start_Date__c=Date.newInstance(2027,6,8),  End_Date__c=Date.newInstance(2027,6,10), Commission_Amount__c=36,  Commission_Percent__c=10),
    new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbeMap.get(pMap.get('Cruise')),                 Quantity=2, UnitPrice=4500, Description='Virgin Voyages Scottish Isles',   Supplier__c=virginId, Provider__c=virginId, Start_Date__c=Date.newInstance(2027,6,10), End_Date__c=Date.newInstance(2027,6,15), Commission_Amount__c=900, Commission_Percent__c=10, Commission_Amount_Manual__c=true),
    new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbeMap.get(pMap.get('Package')),                Quantity=1, UnitPrice=800,  Description='Whisky distillery experience',   Supplier__c=royalId,  Provider__c=royalId,  Start_Date__c=Date.newInstance(2027,6,12), End_Date__c=Date.newInstance(2027,6,12), Commission_Amount__c=64,  Commission_Percent__c=8),
    new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbeMap.get(pMap.get('Signature Service Fee')),  Quantity=1, UnitPrice=500,  Description='Artichoke planning fee',         Commission_Amount__c=0, Commission_Percent__c=0)
};
System.debug('Done. Quote ID: ' + q.Id);
