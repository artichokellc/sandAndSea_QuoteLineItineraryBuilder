# Deployment Checklist — Itinerary Builder

---

## 1. Pre-Deployment Manual Steps

These items must exist in the **production org** before deploying. They are not in source and will not be created by the deploy.

- [ ] `QuoteLineItem.Supplier__c` — Lookup to Account. A validation rule ("A booking channel is required") must exist requiring this field on insert — the test class depends on it.
- [ ] `QuoteLineItem.Provider__c` — Lookup to Account, with a lookup filter restricting values to `Business_Supplier` record type accounts. The test class creates `Business_Supplier` accounts to satisfy this filter; if the record type or filter is absent the test will fail and the deploy will be rejected.
- [ ] `QuoteLineItem.Start_Date__c` — Date field
- [ ] `QuoteLineItem.End_Date__c` — Date field
- [ ] `QuoteLineItem.Commission_Amount__c` — Currency field
- [ ] `QuoteLineItem.Commission_Percent__c` — Percent field
- [ ] `QuoteLineItem.Booking_Channel_Commission_Percent__c` — Formula (Percent)
- [ ] `Account.Commission_Rate__c` — Percent or Number field (auto-populates Commission % when a Supplier is selected)
- [ ] `Account.Booking_Channel__c` — Required by the `Supplier__c` lookup filter on QuoteLineItem. Test class sets this to `'Yes'` on the test account; if the field is absent the test will fail and the deploy will be rejected.
- [ ] Account Record Type `Business_Supplier` exists — DeveloperName must match exactly. Verify:
      `SELECT DeveloperName FROM RecordType WHERE SobjectType = 'Account' AND DeveloperName = 'Business_Supplier'`
- [ ] Flow `QLI_Set_Default_Commission` is **deactivated** in production and must stay that way. Its commission formula (`UnitPrice × Commission_Rate__c`) does not divide by 100, producing values 100× too large. The Itinerary Builder LWC owns commission calculation. Do not activate this flow.

---

## 2. Change Set Components

| Component | Type |
|---|---|
| `classes/ItineraryBuilderController.cls` | Apex Class |
| `classes/ItineraryBuilderControllerTest.cls` | Apex Class (required for 75% code coverage) |
| `lwc/itinerarySpreadsheet/` | LWC — spreadsheet bulk entry component |
| `lwc/lookupInput/` | LWC — reusable typeahead lookup child component |
| `objects/QuoteLineItem/fields/Commission_Amount_Manual__c.field-meta.xml` | Custom Field — Checkbox |
| `objects/QuoteLineItem/fields/Sort_Order__c.field-meta.xml` | Custom Field — Number |
| `customPermissions/Itinerary_Builder_Access.customPermission-meta.xml` | Custom Permission |
| `permissionsets/Itinerary_Builder.permissionset-meta.xml` | Permission Set |

```bash
# Authenticate to prod (first time only)
sf org login web --alias sandandsea_prod --instance-url https://login.salesforce.com

# Deploy using scoped manifest
sf project deploy start \
  --manifest manifest/deployment-package.xml \
  --target-org sandandsea_prod

# Dry run (validate without deploying)
sf project deploy validate \
  --manifest manifest/deployment-package.xml \
  --target-org sandandsea_prod
```

> **When validating via change set UI:** use **Run Specified Tests** and enter `ItineraryBuilderControllerTest`. This avoids running all org-wide tests and keeps validation fast.

---

## 3. Post-Deployment Manual Steps

- [ ] **Add the Itinerary Builder component to the Quote record page**
      Setup → Lightning App Builder → open the Quote record page → drag the `Itinerary Builder (Spreadsheet)` component onto the page → Save & Activate.
      The component is embedded directly on the page (not a modal/Quick Action). No flow or Quick Action is required.

- [ ] **Set component visibility filter on the Quote record page**
      In Lightning App Builder → select the `Itinerary Builder` component → Set Component Visibility → Add Filter → Permission / Custom Permission / `Itinerary Builder Access` / Equal / True → Save & Activate.
      This hides the component from users who have not been assigned the `Itinerary Builder` permission set.

- [ ] Assign the **Itinerary Builder** permission set to all users who use the Itinerary Builder
      Setup → Permission Sets → Itinerary Builder → Manage Assignments → Add Assignments
      (Grants field access to `Commission_Amount_Manual__c` and `Sort_Order__c`, and controls component visibility via the `Itinerary Builder Access` custom permission.)
