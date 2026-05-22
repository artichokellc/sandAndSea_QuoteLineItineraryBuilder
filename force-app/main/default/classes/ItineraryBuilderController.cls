public with sharing class ItineraryBuilderController {

    /**
     * Returns existing QuoteLineItems for a Quote, with supplier/provider names
     * and Commission_Amount__c resolved for display in the LWC.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getExistingLines(String quoteId) {
        List<QuoteLineItem> qlis = [
            SELECT Id, Product2Id, Product2.Name,
                   Quantity, UnitPrice, Description,
                   Start_Date__c, End_Date__c,
                   Supplier__c, Supplier__r.Name,
                   Provider__c, Provider__r.Name,
                   Commission_Amount__c, Commission_Percent__c,
                   Commission_Amount_Manual__c,
                   Sort_Order__c
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            ORDER BY Sort_Order__c ASC NULLS LAST, CreatedDate ASC
        ];

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (QuoteLineItem q : qlis) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('Id',               q.Id);
            row.put('Product2Id',       q.Product2Id);
            row.put('Product2Name',     q.Product2 != null ? q.Product2.Name : '');
            row.put('Quantity',         q.Quantity);
            row.put('UnitPrice',        q.UnitPrice);
            row.put('Description',      q.Description);
            row.put('Start_Date__c',    q.Start_Date__c != null ? String.valueOf(q.Start_Date__c) : null);
            row.put('End_Date__c',      q.End_Date__c   != null ? String.valueOf(q.End_Date__c)   : null);
            row.put('Supplier__c',      q.Supplier__c);
            row.put('SupplierName',     q.Supplier__r != null ? q.Supplier__r.Name : '');
            row.put('Provider__c',      q.Provider__c);
            row.put('ProviderName',     q.Provider__r != null ? q.Provider__r.Name : '');
            row.put('CommissionAmount',       q.Commission_Amount__c);
            row.put('CommissionPercent',      q.Commission_Percent__c);
            row.put('CommissionAmountManual', q.Commission_Amount_Manual__c == true);
            row.put('SortOrder',              q.Sort_Order__c);
            result.add(row);
        }
        return result;
    }

    /**
     * Returns the Commission_Rate__c from a single Account record.
     * Called imperatively when the user selects a Supplier in the LWC.
     * Returns null if the field is blank or the account is not found.
     */
    @AuraEnabled(cacheable=true)
    public static Decimal getCommissionRate(String accountId) {
        if (String.isBlank(accountId)) return null;
        try {
            List<Account> accs = [
                SELECT Commission_Rate__c
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];
            return accs.isEmpty() ? null : accs[0].Commission_Rate__c;
        } catch (QueryException ex) {
            // Commission_Rate__c may not exist in all orgs — fail silently
            return null;
        }
    }

    /**
     * Bulk-upserts QuoteLineItems from a JSON array of row objects.
     * Rows with sfId are updated; rows without sfId are inserted.
     * Returns a list of {clientId, sfId} maps for newly inserted rows so the
     * LWC can immediately update local state and prevent duplicate inserts.
     *
     * Each row object must contain:
     *   id               (Number)           — local client-side row counter
     *   product2Id       (String Id)        — required
     *   salesPrice       (Number)           — required
     *   sfId             (String Id|null)   — present for existing records
     *   quantity         (Number)           — defaults to 1
     *   description      (String)           — optional
     *   startDate        (String YYYY-MM-DD) — optional
     *   endDate          (String YYYY-MM-DD) — optional
     *   supplierId       (String Id)        — optional
     *   providerId       (String Id)        — optional
     *   commissionAmount (Number|null)      — pre-computed by LWC; sets Commission_Amount__c
     */
    @AuraEnabled
    public static List<Map<String, Object>> saveItineraryLines(
        String quoteId,
        String pricebook2Id,
        String rowsJson,
        String deletedIdsJson
    ) {
        // Delete rows the user removed — safety filter ensures only QLIs on this Quote are deleted
        if (String.isNotBlank(deletedIdsJson)) {
            List<Object> rawIds = (List<Object>) JSON.deserializeUntyped(deletedIdsJson);
            Set<Id> toDeleteIds = new Set<Id>();
            for (Object o : rawIds) {
                toDeleteIds.add((Id) String.valueOf(o));
            }
            if (!toDeleteIds.isEmpty()) {
                delete [SELECT Id FROM QuoteLineItem WHERE Id IN :toDeleteIds AND QuoteId = :quoteId];
            }
        }

        List<Object> rawRows = (List<Object>) JSON.deserializeUntyped(rowsJson);

        // Collect product IDs from new rows only (existing rows already have a PBE)
        Set<Id> newProductIds = new Set<Id>();
        for (Object o : rawRows) {
            Map<String, Object> row = (Map<String, Object>) o;
            if (row.get('sfId') == null && String.isNotBlank((String) row.get('product2Id'))) {
                newProductIds.add((Id) row.get('product2Id'));
            }
        }

        Map<Id, Id> pbeByProduct = new Map<Id, Id>();
        if (!newProductIds.isEmpty()) {
            for (PricebookEntry pbe : [
                SELECT Id, Product2Id
                FROM PricebookEntry
                WHERE Pricebook2Id = :pricebook2Id
                  AND Product2Id IN :newProductIds
                  AND IsActive = true
            ]) {
                pbeByProduct.put(pbe.Product2Id, pbe.Id);
            }
        }

        List<QuoteLineItem> toInsert  = new List<QuoteLineItem>();
        List<QuoteLineItem> toUpdate  = new List<QuoteLineItem>();
        List<Long>          clientIds = new List<Long>(); // parallel to toInsert — for return mapping

        for (Object o : rawRows) {
            Map<String, Object> row = (Map<String, Object>) o;
            String pid  = (String) row.get('product2Id');
            String sfId = (String) row.get('sfId');

            if (String.isBlank(pid)) continue;

            QuoteLineItem qli = new QuoteLineItem();
            qli.Quantity    = row.get('quantity') != null
                                ? Decimal.valueOf(String.valueOf(row.get('quantity')))
                                : 1;
            qli.UnitPrice   = Decimal.valueOf(String.valueOf(row.get('salesPrice')));
            qli.Description = (String) row.get('description');

            String supplierId = (String) row.get('supplierId');
            String providerId = (String) row.get('providerId');
            String startDate  = (String) row.get('startDate');
            String endDate    = (String) row.get('endDate');

            if (String.isNotBlank(supplierId)) qli.Supplier__c   = (Id) supplierId;
            if (String.isNotBlank(providerId)) qli.Provider__c   = (Id) providerId;
            if (String.isNotBlank(startDate))  qli.Start_Date__c = Date.valueOf(startDate);
            if (String.isNotBlank(endDate))    qli.End_Date__c   = Date.valueOf(endDate);

            // Commission fields are computed by the LWC and passed in directly
            Object commAmountObj   = row.get('commissionAmount');
            Object commPercentObj  = row.get('commissionRate');
            Object commManualObj   = row.get('commissionAmountManual');
            Object sortOrderObj    = row.get('sortOrder');
            if (commAmountObj  != null) qli.Commission_Amount__c         = Decimal.valueOf(String.valueOf(commAmountObj));
            if (commPercentObj != null) qli.Commission_Percent__c        = Decimal.valueOf(String.valueOf(commPercentObj));
            qli.Commission_Amount_Manual__c = commManualObj == true;
            if (sortOrderObj   != null) qli.Sort_Order__c                = Integer.valueOf(String.valueOf(sortOrderObj));

            if (String.isNotBlank(sfId)) {
                // Existing record — update only editable fields (not QuoteId/PBE)
                qli.Id = (Id) sfId;
                toUpdate.add(qli);
            } else {
                // New record — requires QuoteId + PricebookEntryId
                if (!pbeByProduct.containsKey((Id) pid)) continue;
                qli.QuoteId          = (Id) quoteId;
                qli.PricebookEntryId = pbeByProduct.get((Id) pid);
                toInsert.add(qli);
                Object clientIdObj = row.get('id');
                clientIds.add(clientIdObj != null ? Long.valueOf(String.valueOf(clientIdObj)) : null);
            }
        }

        if (!toUpdate.isEmpty()) update toUpdate;
        if (!toInsert.isEmpty()) insert toInsert;

        // Return inserted record IDs mapped back to client-side row IDs
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Integer i = 0; i < toInsert.size(); i++) {
            Map<String, Object> m = new Map<String, Object>();
            m.put('clientId', clientIds[i]);
            m.put('sfId',     String.valueOf(toInsert[i].Id));
            result.add(m);
        }
        return result;
    }

    /**
     * Live record search for Product2 / Account lookups.
     * objectApiName is whitelisted to prevent SOQL injection.
     * recordTypeName, when provided, restricts Account results to a specific record type.
     * pricebook2Id, when provided for Product2 searches, restricts results to products
     * that have an active PricebookEntry in the given pricebook.
     */
    private static final Set<String> SEARCHABLE_OBJECTS = new Set<String>{ 'Product2', 'Account' };

    @AuraEnabled(cacheable=true)
    public static List<SObject> searchRecords(String objectApiName, String searchTerm, String recordTypeName, String pricebook2Id) {
        if (!SEARCHABLE_OBJECTS.contains(objectApiName)) {
            throw new AuraHandledException('Object not permitted: ' + objectApiName);
        }
        String term = String.isBlank(searchTerm) ? '%' : '%' + searchTerm.trim() + '%';
        String q = 'SELECT Id, Name FROM ' + objectApiName
                 + ' WHERE Name LIKE :term';
        if (String.isNotBlank(recordTypeName)) {
            q += ' AND RecordType.DeveloperName = :recordTypeName';
        }
        if (objectApiName == 'Product2' && String.isNotBlank(pricebook2Id)) {
            q += ' AND Id IN (SELECT Product2Id FROM PricebookEntry WHERE Pricebook2Id = :pricebook2Id AND IsActive = true)';
        }
        q += ' ORDER BY Name LIMIT 10';
        return Database.query(q);
    }
}
