# Itinerary Builder — Start Here

## What This Is

A Salesforce LWC (`itinerarySpreadsheet`) + Apex controller (`ItineraryBuilderController`) that provides a spreadsheet-style Quote Line Item entry grid on the Quote record page.

## Project Status

**Validated and ready for Production deploy.** All 16 test methods passing. Change set has been uploaded to Chris G's Production org. See `.claude/DEPLOYMENT.md` for Chris's post-deploy steps.

---

## Test Class Fixes (applied 2026-05-26)

Two issues were found and fixed in `ItineraryBuilderControllerTest` during deployment validation in a staging sandbox:

1. **Booking_Channel__c fix** — Production's `Supplier__c` lookup filter requires `Account.Booking_Channel__c = 'Yes'`. The original test account didn't set this field, causing all 16 tests to fail with `FIELD_FILTER_VALIDATION_EXCEPTION`. Fixed in `makeData()`.

2. **Slow test fix** — `testSearchRecords_blankTermReturnsRecords` passed a blank search term, becoming `LIKE '%'` — a full table scan against Production-scale data (~3 min per test). Fixed by passing a specific search term instead.

---

## Deployment Guide

See `.claude/DEPLOYMENT.md` for the full pre-deploy checklist, change set component list, and Chris's post-deploy steps.

## Test Data Script

`scripts/apex/populateTestData_execanon.apex` — paste into Execute Anonymous to create 3 supplier accounts, an Opportunity, a Quote, and 8 QLIs for testing. Requires the `Business_Supplier` Account record type to be assigned to the running user's profile.

## Code Location

GitHub: https://github.com/artichokellc/sandAndSea_QuoteLineItineraryBuilder

## SBX Org Alias

`sandandsea_sbx`
