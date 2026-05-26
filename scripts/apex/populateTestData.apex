// ─── Itinerary Builder — Test Data Population Script ─────────────────────────
// Run via: sf apex run --file scripts/apex/populateTestData.apex --target-org <alias>
//
// Creates: 3 supplier Accounts → 1 Opportunity → 1 Quote → 8 QLIs
// Safe to re-run: checks for existing records by name before inserting.
// ─────────────────────────────────────────────────────────────────────────────

// ── 1. Record type ────────────────────────────────────────────────────────────
Id supplierRtId = Schema.SObjectType.Account
    .getRecordTypeInfosByDeveloperName()
    .get('Business_Supplier')
    .getRecordTypeId();

// ── 2. Supplier accounts ──────────────────────────────────────────────────────
// Always ensure correct RecordType and Booking_Channel__c regardless of whether
// the accounts already exist — existing accounts in SBX may have wrong values.
Map<String, Account> existingAccounts = new Map<String, Account>();
for (Account a : [
    SELECT Id, Name FROM Account
    WHERE Name IN ('Delta Vacations', 'Virgin Voyages', 'Royal Carribean')
]) {
    existingAccounts.put(a.Name, a);
}

List<Account> accountsToUpsert = new List<Account>{
    new Account(
        Id                  = existingAccounts.containsKey('Delta Vacations') ? existingAccounts.get('Delta Vacations').Id : null,
        Name                = 'Delta Vacations',
        RecordTypeId        = supplierRtId,
        Booking_Channel__c  = 'Yes',
        Commission_Rate__c  = 10
    ),
    new Account(
        Id                  = existingAccounts.containsKey('Virgin Voyages') ? existingAccounts.get('Virgin Voyages').Id : null,
        Name                = 'Virgin Voyages',
        RecordTypeId        = supplierRtId,
        Booking_Channel__c  = 'Yes',
        Commission_Rate__c  = 10
    ),
    new Account(
        Id                  = existingAccounts.containsKey('Royal Carribean') ? existingAccounts.get('Royal Carribean').Id : null,
        Name                = 'Royal Carribean',
        RecordTypeId        = supplierRtId,
        Booking_Channel__c  = 'Yes',
        Commission_Rate__c  = 8
    )
};
upsert accountsToUpsert;

Map<String, Id> accountIdByName = new Map<String, Id>();
for (Account a : accountsToUpsert) accountIdByName.put(a.Name, a.Id);
Id deltaId  = accountIdByName.get('Delta Vacations');
Id virginId = accountIdByName.get('Virgin Voyages');
Id royalId  = accountIdByName.get('Royal Carribean');

// ── 3. Pricebook ──────────────────────────────────────────────────────────────
// Use the custom pricebook if it exists; fall back to standard.
List<Pricebook2> customPbs = [
    SELECT Id FROM Pricebook2
    WHERE IsStandard = false AND IsActive = true
    ORDER BY CreatedDate ASC LIMIT 1
];
Id pricebookId = customPbs.isEmpty()
    ? Test.getStandardPricebookId()
    : customPbs[0].Id;

// ── 4. Products + PricebookEntries ────────────────────────────────────────────
List<String> productNames = new List<String>{
    'Hotel Lodging', 'Cruise', 'Transfer - Private Car',
    'Activity / Excursion', 'Flight - Round Trip', 'Signature Service Fee',
    'Car - Rental', 'Package'
};

Map<String, Id> productIdByName = new Map<String, Id>();
for (Product2 p : [
    SELECT Id, Name FROM Product2
    WHERE Name IN :productNames AND IsActive = true
]) {
    productIdByName.put(p.Name, p.Id);
}

// Insert any missing products
List<Product2> newProducts = new List<Product2>();
for (String name : productNames) {
    if (!productIdByName.containsKey(name)) {
        newProducts.add(new Product2(Name = name, IsActive = true));
    }
}
if (!newProducts.isEmpty()) {
    insert newProducts;
    for (Product2 p : newProducts) productIdByName.put(p.Name, p.Id);
}

// Ensure every product has a PricebookEntry in the target pricebook
// First, always ensure entries exist in the Standard Pricebook (required by Salesforce)
Id stdPbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

Set<Id> prodIdsWithStdPbe = new Set<Id>();
for (PricebookEntry pbe : [
    SELECT Product2Id FROM PricebookEntry
    WHERE Pricebook2Id = :stdPbId AND Product2Id IN :productIdByName.values() AND IsActive = true
]) {
    prodIdsWithStdPbe.add(pbe.Product2Id);
}
List<PricebookEntry> stdPbes = new List<PricebookEntry>();
for (Id prodId : productIdByName.values()) {
    if (!prodIdsWithStdPbe.contains(prodId)) {
        stdPbes.add(new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id   = prodId,
            UnitPrice    = 0,
            IsActive     = true
        ));
    }
}
if (!stdPbes.isEmpty()) insert stdPbes;

// Now ensure entries in the target pricebook (if different from standard)
Map<Id, Id> pbeIdByProductId = new Map<Id, Id>();
if (pricebookId != stdPbId) {
    Set<Id> prodIdsWithCustomPbe = new Set<Id>();
    for (PricebookEntry pbe : [
        SELECT Id, Product2Id FROM PricebookEntry
        WHERE Pricebook2Id = :pricebookId AND Product2Id IN :productIdByName.values() AND IsActive = true
    ]) {
        prodIdsWithCustomPbe.add(pbe.Product2Id);
        pbeIdByProductId.put(pbe.Product2Id, pbe.Id);
    }
    List<PricebookEntry> customPbes = new List<PricebookEntry>();
    for (Id prodId : productIdByName.values()) {
        if (!prodIdsWithCustomPbe.contains(prodId)) {
            customPbes.add(new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id   = prodId,
                UnitPrice    = 0,
                IsActive     = true
            ));
        }
    }
    if (!customPbes.isEmpty()) insert customPbes;
    // Re-query to get all IDs
    for (PricebookEntry pbe : [
        SELECT Id, Product2Id FROM PricebookEntry
        WHERE Pricebook2Id = :pricebookId AND Product2Id IN :productIdByName.values() AND IsActive = true
    ]) {
        pbeIdByProductId.put(pbe.Product2Id, pbe.Id);
    }
} else {
    for (PricebookEntry pbe : [
        SELECT Id, Product2Id FROM PricebookEntry
        WHERE Pricebook2Id = :stdPbId AND Product2Id IN :productIdByName.values() AND IsActive = true
    ]) {
        pbeIdByProductId.put(pbe.Product2Id, pbe.Id);
    }
}

// ── 5. Opportunity ────────────────────────────────────────────────────────────
List<Opportunity> existingOpps = [
    SELECT Id FROM Opportunity WHERE Name = 'TEST — Scotland Trip 2027' LIMIT 1
];
Opportunity opp;
if (existingOpps.isEmpty()) {
    opp = new Opportunity(
        Name      = 'TEST — Scotland Trip 2027',
        StageName = 'Prospecting',
        CloseDate = Date.newInstance(2027, 3, 1)
    );
    insert opp;
} else {
    opp = existingOpps[0];
}

// ── 6. Quote ──────────────────────────────────────────────────────────────────
List<Quote> existingQuotes = [
    SELECT Id FROM Quote WHERE Name = 'TEST — Scotland Itinerary' AND OpportunityId = :opp.Id LIMIT 1
];
Quote q;
if (existingQuotes.isEmpty()) {
    q = new Quote(
        Name          = 'TEST — Scotland Itinerary',
        OpportunityId = opp.Id,
        Pricebook2Id  = pricebookId,
        Status        = 'Draft'
    );
    insert q;
} else {
    q = existingQuotes[0];
}

// ── 7. Quote Line Items ───────────────────────────────────────────────────────
// Delete any existing test QLIs on this quote to start clean
List<QuoteLineItem> existing = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id];
if (!existing.isEmpty()) delete existing;

List<QuoteLineItem> qlis = new List<QuoteLineItem>{
    new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbeIdByProductId.get(productIdByName.get('Flight - Round Trip')),
        Quantity         = 2,
        UnitPrice        = 1200,
        Description      = 'London Heathrow → Edinburgh return',
        Supplier__c      = virginId,
        Provider__c      = virginId,
        Start_Date__c    = Date.newInstance(2027, 6, 5),
        End_Date__c      = Date.newInstance(2027, 6, 5),
        Commission_Amount__c = 0,
        Commission_Percent__c = 0
    ),
    new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbeIdByProductId.get(productIdByName.get('Transfer - Private Car')),
        Quantity         = 1,
        UnitPrice        = 350,
        Description      = 'Airport → Hotel private transfer',
        Supplier__c      = deltaId,
        Provider__c      = deltaId,
        Start_Date__c    = Date.newInstance(2027, 6, 5),
        End_Date__c      = Date.newInstance(2027, 6, 5),
        Commission_Amount__c = 35,
        Commission_Percent__c = 10
    ),
    new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbeIdByProductId.get(productIdByName.get('Hotel Lodging')),
        Quantity         = 5,
        UnitPrice        = 280,
        Description      = 'The Balmoral Hotel — 5 nights',
        Supplier__c      = royalId,
        Provider__c      = royalId,
        Start_Date__c    = Date.newInstance(2027, 6, 5),
        End_Date__c      = Date.newInstance(2027, 6, 10),
        Commission_Amount__c = 112,
        Commission_Percent__c = 8
    ),
    new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbeIdByProductId.get(productIdByName.get('Activity / Excursion')),
        Quantity         = 2,
        UnitPrice        = 195,
        Description      = 'Loch Ness guided day tour',
        Supplier__c      = deltaId,
        Provider__c      = deltaId,
        Start_Date__c    = Date.newInstance(2027, 6, 7),
        End_Date__c      = Date.newInstance(2027, 6, 7),
        Commission_Amount__c = 39,
        Commission_Percent__c = 10
    ),
    new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbeIdByProductId.get(productIdByName.get('Car - Rental')),
        Quantity         = 3,
        UnitPrice        = 120,
        Description      = 'Economy rental — 3 days Edinburgh',
        Supplier__c      = deltaId,
        Provider__c      = deltaId,
        Start_Date__c    = Date.newInstance(2027, 6, 8),
        End_Date__c      = Date.newInstance(2027, 6, 10),
        Commission_Amount__c = 36,
        Commission_Percent__c = 10
    ),
    new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbeIdByProductId.get(productIdByName.get('Cruise')),
        Quantity         = 2,
        UnitPrice        = 4500,
        Description      = 'Virgin Voyages — Scottish Isles 5-night',
        Supplier__c      = virginId,
        Provider__c      = virginId,
        Start_Date__c    = Date.newInstance(2027, 6, 10),
        End_Date__c      = Date.newInstance(2027, 6, 15),
        Commission_Amount__c = 900,
        Commission_Percent__c = 10,
        Commission_Amount_Manual__c = true
    ),
    new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbeIdByProductId.get(productIdByName.get('Package')),
        Quantity         = 1,
        UnitPrice        = 800,
        Description      = 'Whisky distillery experience package',
        Supplier__c      = royalId,
        Provider__c      = royalId,
        Start_Date__c    = Date.newInstance(2027, 6, 12),
        End_Date__c      = Date.newInstance(2027, 6, 12),
        Commission_Amount__c = 64,
        Commission_Percent__c = 8
    ),
    new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbeIdByProductId.get(productIdByName.get('Signature Service Fee')),
        Quantity         = 1,
        UnitPrice        = 500,
        Description      = 'Artichoke planning & coordination fee',
        Start_Date__c    = null,
        End_Date__c      = null,
        Commission_Amount__c = 0,
        Commission_Percent__c = 0
    )
};
insert qlis;

System.debug('✓ Created ' + qlis.size() + ' QLIs on Quote: ' + q.Id + ' (' + q.Name + ')');
System.debug('✓ Open this Quote in Salesforce to test the Itinerary Builder component.');
