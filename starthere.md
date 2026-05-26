# Itinerary Builder — Start Here

## What This Is

A Salesforce LWC (`itinerarySpreadsheet`) + Apex controller (`ItineraryBuilderController`) that provides a spreadsheet-style Quote Line Item entry grid on the Quote record page.

## Project Status

**Production deploy is PENDING.** Two change sets have been uploaded to Chris G's Production org — the original 8-component set and a patch. Before Chris deploys, read the sections below.

---

## Action Required Before Production Deploy

The test class (`ItineraryBuilderControllerTest`) was updated to fix a slow-running test and a Production lookup-filter compatibility issue. **A new/updated change set must be created and uploaded to Production** with the latest version of this file:

```
force-app/main/default/classes/ItineraryBuilderControllerTest.cls
```

### What changed and why

1. **Booking_Channel__c fix** — Production's `Supplier__c` lookup filter requires `Account.Booking_Channel__c = 'Yes'`. The original test account didn't set this field, causing all 16 tests to fail with `FIELD_FILTER_VALIDATION_EXCEPTION` during validation. Fixed in `makeData()`.

2. **Slow test fix** — `testSearchRecords_blankTermReturnsRecords` was passing a blank search term, which becomes `LIKE '%'` — a full table scan. Against Production-scale data this ran for ~3 minutes per test. Fixed by passing `'Test Supplier Co'` instead.

### Steps to re-deploy

1. In the SBX org, clone or update the existing change set to include the updated `ItineraryBuilderControllerTest` class
2. Upload the change set to Production
3. Tell Chris G to deploy this updated set (it supersedes the previous patch)

---

## Deployment Guide

See `.claude/DEPLOYMENT.md` for the full pre-deploy checklist, change set component list, and post-deploy manual steps (App Builder drag-and-drop, visibility filter, permission set assignment).

## Code Location

GitHub: https://github.com/artichokellc/sandAndSea_QuoteLineItineraryBuilder

## SBX Org Alias

`sandandsea_sbx`
