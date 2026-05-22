## Testing Protocol — Itinerary Builder

After every flow deployment, run these validation steps before reporting back:

1. Run: `sf data query --query "SELECT Id, Quantity, Description, Supplier__c, Provider__c, Commission_Amount__c, Start_Date__c, End_Date__c FROM QuoteLineItem ORDER BY CreatedDate DESC LIMIT 10" --target-org sandandseatravel--artichoke`

2. Verify against test criteria:
   - Quantity = 1 on all new records ✓
   - Commission_Amount__c is NOT null if Supplier__c is set ✓
   - Description field is populated ✓
   - Start_Date__c and End_Date__c are populated ✓
   - Provider__c is populated ✓

3. If any field is null when it shouldn't be, report the gap and fix before returning.

4. Use SLDS Standards for front-end design