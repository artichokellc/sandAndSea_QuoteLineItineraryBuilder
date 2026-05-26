@IsTest
private class ItineraryBuilderControllerTest {

    // ─── Test Data Setup ──────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        // Account (used as Supplier + Provider)
        // Must be Business_Supplier record type to pass Provider__c lookup filter
        // Must have Booking_Channel__c = true to pass Supplier__c lookup filter
        Id supplierRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Business_Supplier')
            .getRecordTypeId();
        Account acct = new Account(
            Name               = 'Test Supplier Co',
            RecordTypeId       = supplierRtId,
            Booking_Channel__c = 'Yes'
        );
        insert acct;

        // Product
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true);
        insert prod;

        // Standard pricebook entry
        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry stdPbe = new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id   = prod.Id,
            UnitPrice    = 100,
            IsActive     = true
        );
        insert stdPbe;

        // Opportunity (required parent for Quote)
        Opportunity opp = new Opportunity(
            Name        = 'Test Opp',
            StageName   = 'Prospecting',
            CloseDate   = Date.today().addDays(30)
        );
        insert opp;

        // Quote using standard pricebook
        Quote q = new Quote(
            Name         = 'Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id  = stdPbId,
            Status        = 'Draft'
        );
        insert q;

        // One existing QLI on the quote
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId          = q.Id,
            PricebookEntryId = stdPbe.Id,
            Quantity         = 2,
            UnitPrice        = 500,
            Description      = 'Existing line',
            Supplier__c      = acct.Id,
            Provider__c      = acct.Id,
            Start_Date__c    = Date.newInstance(2026, 6, 1),
            End_Date__c      = Date.newInstance(2026, 6, 7)
        );
        insert qli;
    }

    // ─── getExistingLines ─────────────────────────────────────────────────────

    @IsTest
    static void testGetExistingLines_returnsRows() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> rows = ItineraryBuilderController.getExistingLines(q.Id);
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'Should return the one existing QLI');
        Assert.areEqual('Existing line', rows[0].get('Description'));
        Assert.areEqual('Test Product',  rows[0].get('Product2Name'));
        Assert.areEqual('Test Supplier Co', rows[0].get('SupplierName'));
        Assert.areEqual('Test Supplier Co', rows[0].get('ProviderName'));
        Assert.isNotNull(rows[0].get('Start_Date__c'));
        Assert.isNotNull(rows[0].get('End_Date__c'));
    }

    @IsTest
    static void testGetExistingLines_emptyQuote() {
        // New quote with no line items
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Quote emptyQ = new Quote(
            Name          = 'Empty Quote',
            OpportunityId = opp.Id,
            Pricebook2Id  = Test.getStandardPricebookId(),
            Status        = 'Draft'
        );
        insert emptyQ;

        Test.startTest();
        List<Map<String, Object>> rows = ItineraryBuilderController.getExistingLines(emptyQ.Id);
        Test.stopTest();

        Assert.areEqual(0, rows.size(), 'Empty quote should return no rows');
    }

    // ─── saveItineraryLines — insert ──────────────────────────────────────────

    @IsTest
    static void testSaveItineraryLines_insertsNewRow() {
        Quote q       = [SELECT Id, Pricebook2Id FROM Quote LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        Account acct  = [SELECT Id FROM Account LIMIT 1];

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'sfId'        => null,
                'product2Id'  => prod.Id,
                'salesPrice'  => 750,
                'quantity'    => 3,
                'description' => 'New insert row',
                'supplierId'  => acct.Id,
                'providerId'  => acct.Id,
                'startDate'   => '2026-07-01',
                'endDate'     => '2026-07-10'
            }
        };

        Test.startTest();
        ItineraryBuilderController.saveItineraryLines(
            q.Id,
            q.Pricebook2Id,
            JSON.serialize(rows),
            '[]'
        );
        Test.stopTest();

        List<QuoteLineItem> qlis = [
            SELECT Quantity, UnitPrice, Description, Supplier__c, Provider__c,
                   Start_Date__c, End_Date__c
            FROM QuoteLineItem
            WHERE QuoteId = :q.Id
              AND Description = 'New insert row'
        ];
        Assert.areEqual(1, qlis.size(), 'One new QLI should have been inserted');
        Assert.areEqual(3,    qlis[0].Quantity);
        Assert.areEqual(750,  qlis[0].UnitPrice);
        Assert.areEqual(acct.Id, qlis[0].Supplier__c);
        Assert.areEqual(Date.newInstance(2026, 7, 1), qlis[0].Start_Date__c);
    }

    @IsTest
    static void testSaveItineraryLines_skipsRowWithoutProduct() {
        Quote q = [SELECT Id, Pricebook2Id FROM Quote LIMIT 1];
        Integer beforeCount = [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :q.Id];

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'sfId'       => null,
                'product2Id' => '',        // blank — should be skipped
                'salesPrice' => 100,
                'quantity'   => 1
            }
        };

        Test.startTest();
        ItineraryBuilderController.saveItineraryLines(q.Id, q.Pricebook2Id, JSON.serialize(rows), '[]');
        Test.stopTest();

        Integer afterCount = [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :q.Id];
        Assert.areEqual(beforeCount, afterCount, 'Row with no product should be skipped');
    }

    @IsTest
    static void testSaveItineraryLines_skipsRowWithNoPricebookEntry() {
        Quote q = [SELECT Id, Pricebook2Id FROM Quote LIMIT 1];
        Integer beforeCount = [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :q.Id];

        // Product with no pricebook entry
        Product2 unmapped = new Product2(Name = 'Unmapped Product', IsActive = true);
        insert unmapped;

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'sfId'       => null,
                'product2Id' => unmapped.Id,
                'salesPrice' => 100,
                'quantity'   => 1
            }
        };

        Test.startTest();
        ItineraryBuilderController.saveItineraryLines(q.Id, q.Pricebook2Id, JSON.serialize(rows), '[]');
        Test.stopTest();

        Integer afterCount = [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :q.Id];
        Assert.areEqual(beforeCount, afterCount, 'Row with no PBE should be skipped');
    }

    // ─── saveItineraryLines — update ──────────────────────────────────────────

    @IsTest
    static void testSaveItineraryLines_updatesExistingRow() {
        QuoteLineItem existing = [SELECT Id, QuoteId FROM QuoteLineItem LIMIT 1];
        Quote q = [SELECT Id, Pricebook2Id FROM Quote WHERE Id = :existing.QuoteId LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'sfId'        => existing.Id,
                'product2Id'  => prod.Id,
                'salesPrice'  => 999,
                'quantity'    => 5,
                'description' => 'Updated description',
                'startDate'   => '2026-08-01',
                'endDate'     => '2026-08-15'
            }
        };

        Test.startTest();
        ItineraryBuilderController.saveItineraryLines(q.Id, q.Pricebook2Id, JSON.serialize(rows), '[]');
        Test.stopTest();

        QuoteLineItem updated = [
            SELECT Quantity, UnitPrice, Description, Start_Date__c
            FROM QuoteLineItem
            WHERE Id = :existing.Id
        ];
        Assert.areEqual(5,                          updated.Quantity);
        Assert.areEqual(999,                        updated.UnitPrice);
        Assert.areEqual('Updated description',      updated.Description);
        Assert.areEqual(Date.newInstance(2026,8,1), updated.Start_Date__c);
    }

    @IsTest
    static void testSaveItineraryLines_deletesRemovedRows() {
        QuoteLineItem existing = [SELECT Id, QuoteId FROM QuoteLineItem LIMIT 1];
        Quote q = [SELECT Id, Pricebook2Id FROM Quote WHERE Id = :existing.QuoteId LIMIT 1];

        Test.startTest();
        ItineraryBuilderController.saveItineraryLines(
            q.Id,
            q.Pricebook2Id,
            '[]',
            JSON.serialize(new List<Id>{ existing.Id })
        );
        Test.stopTest();

        Integer remaining = [SELECT COUNT() FROM QuoteLineItem WHERE Id = :existing.Id];
        Assert.areEqual(0, remaining, 'Deleted QLI should no longer exist');
    }

    // ─── searchRecords ────────────────────────────────────────────────────────

    @IsTest
    static void testSearchRecords_product2ByName() {
        Test.startTest();
        List<SObject> results = ItineraryBuilderController.searchRecords('Product2', 'Test Product', '', '');
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should find exactly the one test product by name');
    }

    @IsTest
    static void testSearchRecords_blankTermReturnsRecords() {
        Test.startTest();
        List<SObject> results = ItineraryBuilderController.searchRecords('Account', 'Test Supplier Co', '', '');
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return the one test account by name');
    }

    @IsTest
    static void testSearchRecords_invalidObjectThrows() {
        Test.startTest();
        try {
            ItineraryBuilderController.searchRecords('Contact', 'test', '', '');
            Assert.fail('Expected AuraHandledException for disallowed object');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('not permitted') ||
                          e.getMessage().contains('Script-thrown exception'),
                          'Exception message should indicate object not permitted');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchRecords_pricebookFilterIncludesProduct() {
        Id stdPbId = Test.getStandardPricebookId();

        Test.startTest();
        List<SObject> results = ItineraryBuilderController.searchRecords('Product2', 'Test Product', '', stdPbId);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should find product with active PBE in the standard pricebook');
    }

    @IsTest
    static void testSearchRecords_pricebookFilterExcludesProductNotInPricebook() {
        Pricebook2 otherPb = new Pricebook2(Name = 'Other Pricebook', IsActive = true);
        insert otherPb;

        Test.startTest();
        List<SObject> results = ItineraryBuilderController.searchRecords('Product2', 'Test Product', '', otherPb.Id);
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'Product not mapped to this pricebook should be excluded');
    }

    // ─── getCommissionRate ────────────────────────────────────────────────────

    @IsTest
    static void testGetCommissionRate_returnsRate() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        acct.Commission_Rate__c = 12.5;
        update acct;

        Test.startTest();
        Decimal rate = ItineraryBuilderController.getCommissionRate(acct.Id);
        Test.stopTest();

        Assert.areEqual(12.5, rate, 'Should return the account commission rate');
    }

    @IsTest
    static void testGetCommissionRate_blankIdReturnsNull() {
        Test.startTest();
        Decimal rate = ItineraryBuilderController.getCommissionRate('');
        Test.stopTest();

        Assert.isNull(rate, 'Blank account ID should return null');
    }

    // ─── Commission_Amount_Manual__c persistence ──────────────────────────────

    @IsTest
    static void testSaveItineraryLines_commissionManualFlagPersists() {
        Quote q       = [SELECT Id, Pricebook2Id FROM Quote LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        Account acct  = [SELECT Id FROM Account LIMIT 1];

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'sfId'                   => null,
                'product2Id'             => prod.Id,
                'salesPrice'             => 500,
                'quantity'               => 1,
                'supplierId'             => acct.Id,
                'commissionAmount'       => 75,
                'commissionAmountManual' => true
            }
        };

        Test.startTest();
        ItineraryBuilderController.saveItineraryLines(q.Id, q.Pricebook2Id, JSON.serialize(rows), '[]');
        Test.stopTest();

        QuoteLineItem saved = [
            SELECT Commission_Amount__c, Commission_Amount_Manual__c
            FROM QuoteLineItem
            WHERE QuoteId = :q.Id AND Commission_Amount__c = 75
            LIMIT 1
        ];
        Assert.areEqual(75,   saved.Commission_Amount__c,        'Commission amount should be saved');
        Assert.isTrue(saved.Commission_Amount_Manual__c,         'Manual flag should persist to the database');
    }

    @IsTest
    static void testGetExistingLines_commissionManualFlagLoads() {
        QuoteLineItem existing = [SELECT Id, QuoteId FROM QuoteLineItem LIMIT 1];
        existing.Commission_Amount_Manual__c = true;
        update existing;

        Quote q = [SELECT Id FROM Quote WHERE Id = :existing.QuoteId LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> rows = ItineraryBuilderController.getExistingLines(q.Id);
        Test.stopTest();

        Assert.areEqual(true, rows[0].get('CommissionAmountManual'), 'Manual flag should be returned on record load');
    }
}
