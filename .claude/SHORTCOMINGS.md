# Known Shortcomings & Backlog — Itinerary Builder

---

---

## Open Issues — Active

### #19 — Supplier lookup does not respect platform lookup filter (shows all accounts)

**What:** The `lookupInput` component's `searchRecords` Apex call queries Account freely. The platform-configured lookup filter on `Supplier__c` (Booking Channel = Yes) is not enforced at search time — users see all accounts in the dropdown. The filter IS enforced at DML save (Salesforce rejects records that don't match), so saves will error if the user picks a non-qualifying account.

**Current behavior:** Bad UX — user can select a supplier that will fail on save with a cryptic error.

**Desired behavior:** Supplier search only surfaces accounts where `Booking_Channel__c = 'Yes'`, matching the platform filter. Chris's preference: do NOT hard-code the rule in Apex — instead, find a way to read and respect the platform-configured lookup filter dynamically so admin changes to the filter are automatically honored.

**Options to explore:**
- Read the lookup filter definition via Metadata API or `FieldDefinition` at runtime and apply dynamically (complex, but honors the "no code duplication" principle)
- Add `Booking_Channel__c = 'Yes'` as a SOQL WHERE clause in `searchRecords` for the Account object (simpler, but duplicates the platform rule in code — Chris explicitly does not want this)
- Use the standard Salesforce lookup component (`lightning-record-picker`, GA Spring '24) which natively respects lookup filters configured in Setup

**Why we didn't use `lightning-record-picker` for all three lookups:**
The custom `lookupInput` was built because the Product column needs a pricebook filter (only show products active in the quote's pricebook) — a dynamic SOQL condition that `lightning-record-picker` does not support natively. The component also needs to render inline inside a table cell without standard field chrome. For those reasons, the custom component was the right call for Product and Provider.

For the **Supplier field specifically**, `lightning-record-picker` is a viable drop-in — it doesn't need the pricebook filter, and it would honor the `Booking Channel = Yes` lookup filter natively with no code duplication. Worth evaluating as a targeted swap for Supplier only, leaving the custom `lookupInput` in place for Product and Provider.

**Recommended approach:** Evaluate `lightning-record-picker` as a replacement for the custom `lookupInput` on the Supplier column only.

**Status:** Open. For now, users will hit a save error if they select a non-qualifying account. Acceptable short-term per Chris.

---

### #20 — No "+ Add Supplier" shortcut in the Supplier lookup

**What:** When users search for a supplier and it doesn't exist yet, there is no way to create one without leaving the Itinerary Builder. Standard Salesforce lookup fields show a "+ New [Object]" option at the bottom of the dropdown that launches a quick action modal.

**Desired behavior:** The Supplier lookup dropdown should show an "+ Add Supplier" option at the bottom of the results list. Clicking it launches the existing **New Supplier** global action (already configured in the org's global action menu) as a modal. On save, the new account populates the Supplier field on the row.

**Implementation notes:** The global action can be launched via `NavigationMixin.Navigate` with `type: 'standard__quickAction'` and `actionName: 'NewAccount'` (or whatever the org's New Supplier global action API name is). To open it as a modal without leaving the page, consider `lightning/modal` wrapping a `lightning-flow` or `force:createRecord` event. The `lookupInput` child LWC would need to emit an event up to the parent, which owns the navigation context.

**Status:** Open. Enhancement for next sprint.

---

### #21 — "Promote to Trip Components" action on Quote

**What:** A new action button on the Quote record page (only visible when Quote Status = Accepted) that lets users select which QLIs to promote to Opportunity Line Items (Trip Components / OLIs). This is the handoff from quoting to booking.

**Full flow:**
1. Button appears on Quote only when `Status = 'Accepted'`
2. User clicks → multi-select list of QLIs on the quote (checkboxes, show Description + Product + Price)
3. User selects one or more rows → clicks "Promote"
4. Each selected QLI is cloned to an OLI on the parent Opportunity, copying all relevant fields (Product, Price, Quantity, Description, Supplier, Provider, Start/End Date, Commission fields)
5. New OLIs are created with `Status = 'Pending'` (overriding the org default of 'Confirmed')

**Dependencies:**
- Custom fields (`Supplier__c`, `Provider__c`, `Start_Date__c`, `End_Date__c`, `Commission_Amount__c`, `Commission_Percent__c`) must exist on OpportunityLineItem (they currently exist on QuoteLineItem only) — see #16
- The parent Opportunity must have a Pricebook assigned (same pricebook as the Quote, typically)

**Related:** See #16 (Lift to OLI) for the broader OLI data model work this depends on.

**Status:** Open. Requires #16 field creation as a prerequisite.

---

### #22 — Grid column set is hardcoded; should be admin-configurable

**What:** The columns displayed in the Itinerary Builder grid are defined in the LWC JavaScript and HTML. Adding, removing, or reordering a column requires a code change and redeployment. Chris wants to be able to adjust the displayed fields as an admin without opening the code.

**Desired behavior:** The set of columns (and their order) rendered in the grid should be driven by a configuration source that an admin can modify — without developer involvement.

**Options to explore:**
- Custom Metadata Type (e.g., `Itinerary_Column__mdt`) with rows for each column (API name, label, type, order, visible) — queried at component load via Apex
- Custom Settings or a JSON field on a Custom Setting record
- `lightning-datatable` column definition stored as a JSON blob on a Custom Metadata record

**Relationship to #17:** This is the admin-facing half of the reusability work described in #17. #17 covers code-level reusability; this issue covers runtime configurability by admins.

**Status:** Open. Medium complexity. Recommended to design alongside #21 (Promote to Trip Components) since that feature will likely require a different column set than the Quote grid.

---

### #23 — Remove branding header; condense subtitle; reduce top/bottom padding

**What:** The component currently renders the Sand & Sea Travel logo/branding block at the top, followed by "Add Itinerary Line Items" and a subtitle on separate lines with generous padding. In production this wastes vertical space.

**Requested changes:**
1. Remove the company branding block entirely (logo, company name, tagline)
2. Condense the two subtitle lines into a single line
3. Reduce top and bottom margin/padding on the header area

**Status:** In testing in SBX (2026-05-27).

---

### #24 — "Add Itinerary Line Items" header should be renamed and get a help icon

**What:** "Add Itinerary Line Items" implies the component is only for adding new rows. In practice it is also used for editing and viewing existing rows. The word "Add" is misleading.

**Requested changes:**
1. Remove "Add" from the heading — use "Itinerary Line Items" or similar
2. Add a help text hover icon (`lightning-helptext`) next to the heading that explains what the component does (e.g., "Use this grid to add, edit, or remove line items on this quote. Click Save All Line Items to persist your changes.")

**Status:** In testing in SBX (2026-05-27).

---

### #18 — Rows with manually overridden Commission $ are not visually highlighted

**What:** When a user manually enters a Commission $ value (`_commAmountManual = true` / `Commission_Amount_Manual__c = true`), the row looks identical to rows where commission was auto-calculated. There is no visual indicator distinguishing "user-locked" commission rows from auto-computed ones.

**Tracking field:** `Commission_Amount_Manual__c` (Checkbox on QuoteLineItem) already exists and persists the flag across sessions. The per-row `_commAmountManual` boolean is already maintained in component state. The missing piece is surfacing this state visually in the grid.

**Recommended approach:** Apply a CSS class (e.g., a subtle background tint or accent border on the Commission $ cell) when `_commAmountManual === true`. This mirrors the pattern already used for existing vs. new rows (existing rows show a left border accent).

**Status:** Not implemented. Tracked here for future scoping.

---

### #13 — Supplier cleared after Commission $ was auto-calculated — behavior undefined

**What:** If the user selects a Supplier (auto-populating Commission % and Commission $), then clears the Supplier field, the expected behavior is ambiguous. Current behavior: Commission % and Commission $ remain at their auto-populated values. The Supplier lookup clears the name display but does not zero out Commission % or Commission $.

**Options:**
- *Clear both commission fields when Supplier is cleared* — cleanest, but discards values the user may want to keep
- *Keep commission values, show a warning* — less disruptive but confusing
- *Prompt the user* — adds friction to a common action

**Status:** Undefined. Needs a product decision before implementing. Tracked here for future scoping.

---

### #14 — Row cloned/duplicated — manual override flag behavior undefined

**What:** There is currently no row-duplication feature in the Itinerary Builder. If one is added in the future (e.g., a "Duplicate row" button), the question is whether the cloned row should inherit `_commAmountManual = true` from its source (preserving the locked Comm $) or reset to `false` (allowing auto-calc on the new row).

**Recommended behavior:** Clone should inherit `_commAmountManual` from the source row, since the user deliberately copied the row and likely wants the same commission values preserved.

**Status:** N/A until row duplication is implemented. Tracked here to inform that future feature.

---

## Future Scope (Not In Current Build)

### #6 — Sub-reservation / hierarchical package data model

**What:** A data model to represent parent-child relationships between Quote Line Items — e.g., a "Delta Vacations package" parent line with $0-price sub-components (air, hotel, car transfer) carrying their own supplier/provider attribution.

**Options evaluated:**

*Self-referential lookup on QuoteLineItem* — ruled out. QuoteLineItem is already the detail side of a Master-Detail with Quote; Salesforce does not reliably support self-referential custom lookups on standard objects in that position.

*Custom `Package__c` object* — a lightweight custom object with a Lookup to Quote, and a `Package__c` lookup field added to QuoteLineItem. Cleaner data model, but the price-bearing parent row would live on a separate object rather than as a QLI, which breaks native Quote subtotal reporting and complicates the Itinerary Builder UI.

*Text grouping field (recommended)* — add two fields to QuoteLineItem:
- `Package_Group__c` (Text) — a system-assigned key (e.g., UUID or sequential number) shared by all rows in the same package. The Itinerary Builder assigns this programmatically; users see a human-readable label, not the raw key.
- `Is_Package_Header__c` (Checkbox) — marks the price-bearing parent row.

Child rows carry `UnitPrice = 0` and the same `Package_Group__c` as their parent. This approach is simple to build, carries naturally to OpportunityLineItem without trigger logic, and the integrity risk of key mismatch is eliminated by code-assigning the group key rather than allowing user input.

**UI work required in Itinerary Builder:** render child rows indented under their parent, support $0 sales price on sub-components, and provide a mechanism to create a package group and attach rows to it.

---

### #7 — Quote comparison UI

**What:** A side-by-side visual comparison interface for multiple quotes on the same Opportunity, to support complex multi-option quoting scenarios.

**Status:** Conceptual — not scoped or designed yet.

---

### #15 — Smart commission field tracking with conflict-resolution modal

**What:** Today, the three related commission fields (Sales Price, Comm %, Comm $) auto-calculate forward from left to right: entering Sales Price + Comm % auto-fills Comm $; entering Comm $ overrides without recalculating the others. There is no awareness of which fields the user has manually touched vs. which were computed. The proposed enhancement adds per-field dirty tracking and a conflict-resolution modal when all three have been manually set and the user edits one of them.

**How it would work:**

Each row gains three boolean flags: `_salesPriceManual`, `_commRateManual`, `_commAmountManual`. These default to `false`. They flip to `true` only on direct user input (not on auto-population from supplier selection, which stays non-manual). Auto-population from `getCommissionRate` when a supplier is selected never sets a manual flag.

*While any field is still non-manual:* the existing auto-calculate behavior runs silently — no prompt, no friction.

*Once all three flags are `true`:* editing any one field opens a `lightning-modal` (the SLDS-standard modal pattern introduced in API 54, fully supported in the current build's API 66 target) presenting three choices plus cancel:

| User edited | Option A | Option B | Skip |
|---|---|---|---|
| Sales Price | Recalculate Comm % (keep Comm $) | Recalculate Comm $ (keep Comm %) | Revert / do nothing |
| Comm % | Recalculate Sales Price (keep Comm $) | Recalculate Comm $ (keep Sales Price) | Revert / do nothing |
| Comm $ | Recalculate Sales Price (keep Comm %) | Recalculate Comm % (keep Sales Price) | Revert / do nothing |

The math in all cases is exact: `Comm $ = Sales Price × Comm % / 100`. Divide-by-zero edge cases (Comm % = 0 or Sales Price = 0) disable the dependent option in the modal and show a tooltip explaining why.

**Implementation scope:**

- Three new boolean flags per row object in `newRow()` and the `wiredLines` mapper.
- Modified `handlePriceChange`, `handleCommissionChange`, `handleCommissionAmountChange` to set their respective manual flag and check the "all three dirty" condition before deciding whether to auto-calc or open a modal.
- A new child LWC (`commissionConflictModal`) that extends `LightningModal`, accepts the edited field name and all three current values as `@api` properties, and dispatches the user's choice back to the parent.
- The modal result handler in the parent patches the appropriate row fields.

**Complexity:** Medium. The math is trivial. The non-trivial parts are: (1) keeping dirty flags synchronized when a row is reset (product change, supplier change, row delete/re-add), and (2) the `lightning-modal` is a separate LWC bundle — it adds a second deployable file and must be declared in `js-meta.xml` as `isExposed: false`. The modal itself is ~30 lines of HTML and ~20 lines of JS.

**Risk / edge cases:**
- Auto-population from supplier (`getCommissionRate`) must NOT set `_commRateManual`. If it did, selecting a supplier on a row where the user had already typed a price and commission amount would immediately arm the conflict logic, which is wrong.
- "Skip / Cancel" should revert the input to its previous value, not silently leave the three fields in a mathematically inconsistent state. This requires holding the pre-edit value in a temp variable before the modal opens.
- The modal is per-row, not per-table — multiple rows can have independent dirty states simultaneously with no interaction.

---

### #16 — Lift to Opportunity / OpportunityLineItem

**What:** The entire Itinerary Builder experience (LWC, Apex controller, Flow, Quick Action) currently targets Quote + QuoteLineItem. The same UX could serve Opportunity + OpportunityLineItem for cases where a line-item-level itinerary is needed before a formal quote is created.

**What is identical and carries over at zero cost:**
- All UI logic: row management, lookup dropdowns, commission calculation, date formatting, validation, error handling.
- `searchRecords` Apex method — already generic, already used for both Product and Account lookups.
- `getCommissionRate` Apex method — reads `Account.Commission_Rate__c`, has no Quote/QLI dependency.
- The Flow shell — only the record type of the Quick Action target changes.

**What requires changes:**

*Apex (`ItineraryBuilderController.cls`):*
- `getExistingLines`: SOQL changes from `QuoteLineItem` to `OpportunityLineItem`. Column aliases stay the same; the custom field API names (`Supplier__c`, `Provider__c`, etc.) would also exist on OLI once created (see below).
- `saveItineraryLines`: DML target changes from `QuoteLineItem` to `OpportunityLineItem`. The `pricebook2Id` lookup for PricebookEntry stays exactly the same — OLI uses `Opportunity.Pricebook2Id` identically.
- The cleanest implementation is a shared private method `_buildLineItem(row, pricebookEntryId)` called by both the QLI and OLI save paths, rather than duplicating the field-mapping logic.

*LWC:*
- `PRICEBOOK2ID_FIELD` import changes from `@salesforce/schema/Quote.Pricebook2Id` to `@salesforce/schema/Opportunity.Pricebook2Id`.
- `getExistingLines` and `saveItineraryLines` wire/imperative calls stay the same if the Apex methods are overloaded or accept a `targetObject` param.
- Alternatively, add a single `@api targetObject` string prop (`'Quote'` | `'Opportunity'`) and branch within the component.

*Org configuration:*
- The six custom fields (`Supplier__c`, `Provider__c`, `Start_Date__c`, `End_Date__c`, `Commission_Amount__c`, `Commission_Percent__c`) currently exist on **QuoteLineItem**. They need to be created identically on **OpportunityLineItem**. This is pure admin work — no code change.
- `Booking_Channel_Commission_Percent__c` formula field would also need to be re-created on OLI if commission rollup visibility is desired.
- A new Quick Action on the Opportunity object and a corresponding Flow.

**Effort estimate:** Small-to-medium. The Apex changes are ~30 lines; the LWC changes are ~10 lines. The field creation on OLI is the largest single task but is admin work, not development. The main architectural decision is whether to build a single parameterized LWC or maintain two thin wrapper components sharing a core utility — the latter is slightly more deployable in Salesforce's component model.

**Dependency:** The pricebook-active product filter fix (resolved in #3) followed the same pattern; the OLI lift inherits the fix automatically.

---

### #17 — Reusability of the spreadsheet component for other PricebookEntry-backed child objects

**What:** The Itinerary Builder is a spreadsheet-style data entry component for line items that are backed by a PricebookEntry relationship. Other Salesforce standard line item objects share this structural pattern: QuoteLineItem, OpportunityLineItem, OrderItem, and Contract Line Items all require a Product2 → PricebookEntry → parent-object chain. The question is whether this component can be generalized into a reusable primitive.

**What is genuinely shared across all PricebookEntry-backed objects:**
- The product lookup pattern: search Product2 by name, require an active PricebookEntry for the parent's pricebook, resolve `PricebookEntry.Id` at save time.
- The pricebook resolution pattern: read `{ParentObject}.Pricebook2Id` via `@wire(getRecord)`.
- Row state management: add, delete, validate, save as a bulk list.
- The column that can be generalized: any "currency amount" column with a `$` prefix and 2-decimal formatting is reusable as a sub-component.

**What is domain-specific to Sand & Sea and cannot be generalized without significant configuration overhead:**
- Commission fields and their three-way calculation logic — these are custom travel-industry fields that don't exist on standard OLI/OrderItem.
- Supplier and Provider lookup columns — these are custom account lookups specific to this org's data model.
- Start/End Date columns — custom fields, not present on OrderItem.
- The `getCommissionRate` auto-population behavior — specific to `Account.Commission_Rate__c`.

**True generalization approach (and why it's probably not worth it):**

A fully configurable component would accept a column-definition array as a metadata-driven `@api` prop, something like:
```json
[
  { "field": "supplierId", "label": "Supplier", "type": "lookup", "object": "Account" },
  { "field": "commissionRate", "label": "Comm %", "type": "percent" }
]
```
This would require a generic Apex controller that accepts field mappings at runtime, which means dynamic SOQL for both reads and writes, and no compile-time field validation. Dynamic DML on standard objects in Salesforce is possible but adds governor limit complexity and eliminates static analysis tooling (the Salesforce CLI's source deploy validation catches field-name typos on strongly-typed Apex; dynamic SOQL does not).

Salesforce's own answer to this problem is the `lightning-datatable` with inline editing — for generic tabular data entry, that is the platform primitive. The Itinerary Builder already exceeds what `lightning-datatable` can do natively (custom lookup inputs, commission auto-calculation, position:fixed dropdown positioning).

**Pragmatic middle ground (recommended if OLI support is added):**

Rather than a single configurable component, extract the two genuinely reusable pieces into their own LWC bundles:
- `lookupInput` — a standalone lookup input with typeahead dropdown (**already extracted and in use**).
- A shared JS utility module (`commissionCalc.js`) for the three-way commission math, importable by both the Quote and OLI variants.

The parent components (one per object context) stay thin and domain-specific. This is the Salesforce-idiomatic pattern: reuse at the sub-component and utility level, not at the full-table level.

**Conclusion:** Full generalization is over-engineering for a single org. `lookupInput` has already been extracted. The next reusability step, if OLI support is added, is extracting commission math into a shared utility module.

---

## Resolved

### ~~#1 — Commission field mapping~~ ✓ RESOLVED

**Resolution:** Confirmed 2026-05-22. Commission fields map correctly — `Commission_Amount__c` ← LWC-computed value, `Commission_Percent__c` ← supplier rate. Validated by Apex test class and Smartsheet items 2.1–2.4 all Dev Complete.

---

### ~~#2 — Magnifying glasses do not re-open after first use~~ ✓ RESOLVED

**Resolution:** Extracted `lookupInput` as a dedicated child LWC. The child component owns its own focus/blur cycle within a clean shadow DOM boundary, eliminating the race condition that caused the dropdown to not re-open. Magnifying glass now opens reliably on every click, on all three lookup columns (Product, Supplier, Provider).

---

### ~~#4 — Drag-to-reorder rows is not implemented~~ ✓ RESOLVED

**Resolution:** Added `Sort_Order__c` (Number) custom field to QuoteLineItem. `getExistingLines` now orders by `Sort_Order__c ASC NULLS LAST, CreatedDate ASC`. `saveItineraryLines` writes the current display position (1-based index) to `Sort_Order__c` on every save. In the LWC, HTML5 drag-and-drop is implemented on `<tr>` elements (`dragstart`/`dragover`/`drop`/`dragend`). Rows show a grab-cursor handle column; the dragged row fades, and the drop target shows a blue top border indicating "insert before." Row order persists across sessions via `Sort_Order__c`.

---

### ~~#3 — Product dropdown does not filter to pricebook-active products~~ ✓ RESOLVED

**Resolution:** `searchRecords` in `ItineraryBuilderController.cls` now accepts a `pricebook2Id` parameter and appends a PricebookEntry subquery (`AND Id IN (SELECT Product2Id FROM PricebookEntry WHERE Pricebook2Id = :pricebook2Id AND IsActive = true)`) when searching Product2. The parent LWC passes `effectivePricebook2Id` down to the `lookupInput` child via the `pricebook2-id` prop.

---

### ~~#5 — Sequential DML in Apex (update then insert)~~ ✓ WON'T FIX

**Resolution:** Intentional design. Bulk DML is already used (list-based). Sequential ordering (update before insert) avoids duplication. No real-world performance concern at expected row counts.

---

### ~~#8 — PDF quote ingestion~~ ✓ OUT OF SCOPE

Explicitly out of scope for the current engagement.

---

### ~~#9 — Commission Rollup to Quote or Opportunity~~ ✓ OUT OF SCOPE

Explicitly out of scope for the current engagement.

---

### ~~#10 — Commission $ manual override does not persist across save/reload sessions~~ ✓ RESOLVED

**Resolution:** Added `Commission_Amount_Manual__c` (Checkbox) to QuoteLineItem (`objects/QuoteLineItem/fields/`). `getExistingLines` now returns the field; `saveItineraryLines` writes it. The LWC initializes `_commAmountManual` from the loaded value on record open. Permission set `Itinerary_Builder` grants FLS on the field.

---

### ~~#11 / #12 — Extract `lookupInput` child LWC~~ ✓ RESOLVED

**Resolution:** `lookupInput` extracted into its own LWC bundle (`force-app/main/default/lwc/lookupInput/`). All three lookup columns (Product, Supplier, Provider) now use `<c-lookup-input>`. The parent component no longer owns any search, dropdown, or blur logic.
