import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent }          from 'lightning/platformShowToastEvent';
import { getRecord, refreshApex }  from 'lightning/uiRecordApi';
import PRICEBOOK2ID_FIELD          from '@salesforce/schema/Quote.Pricebook2Id';
import saveItineraryLines          from '@salesforce/apex/ItineraryBuilderController.saveItineraryLines';
import getExistingLines            from '@salesforce/apex/ItineraryBuilderController.getExistingLines';
import getCommissionRate           from '@salesforce/apex/ItineraryBuilderController.getCommissionRate';

function newRow(counter) {
    return {
        id:                counter,
        sfId:              null,
        product2Id:        null,  product2Name:   '',
        supplierId:        null,  supplierName:   '',
        providerId:        null,  providerName:   '',
        quantity:          1,
        salesPrice:        null,  salesPriceDisplay: '',
        commissionRate:    null,
        commissionAmount:  null,  commissionAmountDisplay: '',
        description:       '',
        startDate:         '',
        endDate:           '',
        sortOrder:         null,
        _productError:      false,
        _commAmountManual:  false,
        _rowClass:         rowBaseClass(null),
        _priceInputClass:  'price-input',
        _startDateClass:   'date-input',
        _endDateClass:     'date-input'
    };
}

function rowBaseClass(sfId) {
    return `data-row ${sfId ? 'row-existing' : 'row-new'}`;
}

/** Format a number to always show 2 decimal places with comma separators, or return '' for null/undefined */
function fmtPrice(val) {
    if (val === null || val === undefined || val === '') return '';
    const n = parseFloat(String(val).replace(/,/g, ''));
    return isNaN(n) ? '' : n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export default class ItinerarySpreadsheet extends LightningElement {
    @api recordId;
    @api pricebook2Id;          // set by Flow; stays null on record page

    rows        = [];
    errorMessage = null;
    isSaving    = false;
    isLoading   = true;

    _rowCounter           = 0;    // instance-level so multiple component instances don't share state
    _resolvedPricebook2Id = null; // set by wiredQuote when on record page
    _rowsLoaded           = false;
    _deletedIds           = [];
    _wiredLines           = null; // held for refreshApex after save
    _boundKeyDown         = null;
    _dragSourceId         = null; // row.id of the row currently being dragged
    _dragOverId           = null; // row.id of the current drop-target row

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    connectedCallback() {
        // Shift+Enter: add a new row
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._boundKeyDown = (e) => {
            if (e.shiftKey && e.key === 'Enter') {
                e.preventDefault();
                this.handleAddRow();
            }
        };
        this.template.addEventListener('keydown', this._boundKeyDown);
    }

    disconnectedCallback() {
        this.template.removeEventListener('keydown', this._boundKeyDown);
    }

    // ─── Wire: read Quote.Pricebook2Id when on the record page ───────────────

    @wire(getRecord, { recordId: '$recordId', fields: [PRICEBOOK2ID_FIELD] })
    wiredQuote({ data }) {
        if (data) {
            this._resolvedPricebook2Id = data.fields.Pricebook2Id.value;
        }
    }

    // ─── Pricebook ID — resolved from Flow prop or wire ───────────────────────

    get effectivePricebook2Id() {
        return this.pricebook2Id || this._resolvedPricebook2Id || '';
    }

    // ─── Wire: load existing QLIs ─────────────────────────────────────────────

    @wire(getExistingLines, { quoteId: '$recordId' })
    wiredLines(result) {
        this._wiredLines      = result;
        const { data, error } = result;
        if (data) {
            if (data.length > 0) {
                this.rows = data.map(qli => ({
                    id:                       ++this._rowCounter,
                    sfId:                     qli.Id,
                    product2Id:               qli.Product2Id      || null,
                    product2Name:             qli.Product2Name    || '',
                    supplierId:               qli.Supplier__c     || null,
                    supplierName:             qli.SupplierName    || '',
                    providerId:               qli.Provider__c     || null,
                    providerName:             qli.ProviderName    || '',
                    quantity:                 qli.Quantity        || 1,
                    salesPrice:               qli.UnitPrice       != null ? qli.UnitPrice  : null,
                    salesPriceDisplay:        fmtPrice(qli.UnitPrice),
                    commissionRate:           qli.CommissionPercent != null ? qli.CommissionPercent : null,
                    commissionAmount:         qli.CommissionAmount != null ? qli.CommissionAmount : null,
                    commissionAmountDisplay:  fmtPrice(qli.CommissionAmount),
                    description:              qli.Description     || '',
                    startDate:                qli.Start_Date__c ? this._toDisplayDate(qli.Start_Date__c) : '',
                    endDate:                  qli.End_Date__c   ? this._toDisplayDate(qli.End_Date__c)   : '',
                    sortOrder:                qli.SortOrder != null ? qli.SortOrder : null,
                    _productError:            false,
                    _commAmountManual:        qli.CommissionAmountManual === true,
                    _rowClass:                rowBaseClass(qli.Id),
                    _priceInputClass:         'price-input',
                    _startDateClass:          'date-input',
                    _endDateClass:            'date-input'
                }));
            } else if (!this._rowsLoaded) {
                this.rows = [newRow(++this._rowCounter)];
            }
            this._rowsLoaded = true;
            this.isLoading   = false;
        } else if (error) {
            console.error('Failed to load existing line items:', error);
            this.rows      = [newRow(++this._rowCounter)];
            this.isLoading = false;
        }
    }

    // ─── Row count label ──────────────────────────────────────────────────────

    get rowCountLabel() {
        const existing = this.rows.filter(r => r.sfId).length;
        const added    = this.rows.filter(r => !r.sfId).length;
        const parts    = [];
        if (existing > 0) parts.push(`${existing} existing`);
        if (added    > 0) parts.push(`${added} new`);
        return parts.join(' · ');
    }

    // ─── Row management ───────────────────────────────────────────────────────

    handleAddRow() {
        this.rows = [...this.rows, newRow(++this._rowCounter)];
    }

    handleDeleteRow(event) {
        const rowId = +event.currentTarget.dataset.rowId;
        if (this.rows.length === 1) return;
        const row = this.rows.find(r => r.id === rowId);
        if (row && row.sfId) {
            this._deletedIds = [...this._deletedIds, row.sfId];
        }
        this.rows = this.rows.filter(r => r.id !== rowId);
    }

    // ─── Standard field changes ───────────────────────────────────────────────

    handleFieldChange(event) {
        const rowId = +event.currentTarget.dataset.rowId;
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;
        this._patch(rowId, { [field]: value });
    }

    handlePriceChange(event) {
        const rowId = +event.currentTarget.dataset.rowId;
        const raw   = event.currentTarget.value;
        const value = raw !== '' ? parseFloat(String(raw).replace(/,/g, '')) : null;
        const row   = this.rows.find(r => r.id === rowId);

        // Recompute commission $ whenever price and rate are both present, unless user has locked it manually
        let commissionAmount        = row ? row.commissionAmount : null;
        let commissionAmountDisplay = row ? row.commissionAmountDisplay : '';
        if (!row._commAmountManual && value !== null && row && row.commissionRate !== null) {
            commissionAmount        = parseFloat((value * row.commissionRate / 100).toFixed(2));
            commissionAmountDisplay = fmtPrice(commissionAmount);
        }

        this._patch(rowId, {
            salesPrice:               value,
            salesPriceDisplay:        fmtPrice(value),
            commissionAmount,
            commissionAmountDisplay,
            _priceInputClass:         value === null ? 'price-input price-input-error' : 'price-input'
        });
    }

    handlePriceBlur(event) {
        // Reformat to 2 decimal places with commas on blur
        const rowId = +event.currentTarget.dataset.rowId;
        const raw   = event.currentTarget.value;
        const value = raw !== '' ? parseFloat(String(raw).replace(/,/g, '')) : null;
        this._patch(rowId, {
            salesPrice:        value,
            salesPriceDisplay: fmtPrice(value)
        });
    }

    // Commission % — manual override; recomputes Comm $ when price is present
    handleCommissionChange(event) {
        const rowId = +event.currentTarget.dataset.rowId;
        const raw   = event.currentTarget.value;
        const value = raw !== '' ? parseFloat(raw) : null;
        const row   = this.rows.find(r => r.id === rowId);

        let commissionAmount        = row ? row.commissionAmount : null;
        let commissionAmountDisplay = row ? row.commissionAmountDisplay : '';
        if (!row._commAmountManual && value !== null && row && row.salesPrice !== null) {
            commissionAmount        = parseFloat((row.salesPrice * value / 100).toFixed(2));
            commissionAmountDisplay = fmtPrice(commissionAmount);
        }

        this._patch(rowId, { commissionRate: value, commissionAmount, commissionAmountDisplay });
    }

    // Commission $ — manual entry locks auto-calc; clearing the field releases the lock
    handleCommissionAmountChange(event) {
        const rowId = +event.currentTarget.dataset.rowId;
        const raw   = event.currentTarget.value;
        const value = raw !== '' ? parseFloat(String(raw).replace(/,/g, '')) : null;
        this._patch(rowId, {
            commissionAmount:        value,
            commissionAmountDisplay: fmtPrice(value),
            _commAmountManual:       value !== null  // lock when value is set; release when cleared
        });
    }

    handleCommissionAmountBlur(event) {
        const rowId     = +event.currentTarget.dataset.rowId;
        const raw       = event.currentTarget.value;
        const isCleared = raw === '' || raw === null || raw === undefined;
        const value     = !isCleared ? parseFloat(String(raw).replace(/,/g, '')) : null;
        const changes   = {
            commissionAmount:        value,
            commissionAmountDisplay: fmtPrice(value)
        };
        // Blur only releases the lock when the field is cleared.
        // It must NOT set _commAmountManual = true — tabbing through the field
        // without typing would otherwise lock auto-calc incorrectly.
        if (isCleared) changes._commAmountManual = false;
        this._patch(rowId, changes);
    }

    handleDateBlur(event) {
        const rowId      = +event.currentTarget.dataset.rowId;
        const field      = event.currentTarget.dataset.field;
        const raw        = event.currentTarget.value;
        const formatted  = this._toDisplayDate(raw);
        const isInvalid  = raw !== '' && this._parseDateParts(raw) === null;
        const classField = field === 'startDate' ? '_startDateClass' : '_endDateClass';
        this._patch(rowId, {
            [field]:      formatted,
            [classField]: isInvalid ? 'date-input date-input-error' : 'date-input'
        });
    }

    // ─── Lookup: child component events ──────────────────────────────────────

    handleLookupSelect(event) {
        const rowId     = +event.currentTarget.dataset.rowId;
        const field     = event.currentTarget.dataset.field;
        const nameField = event.currentTarget.dataset.nameField;
        const { id, name } = event.detail;
        const changes = { [field]: id, [nameField]: name };
        if (field === 'product2Id') changes._productError = false;
        this._patch(rowId, changes);
        if (field === 'supplierId' && id) {
            this._fetchCommissionRate(rowId, id);
        }
    }

    handleLookupInputChange(event) {
        const rowId     = +event.currentTarget.dataset.rowId;
        const field     = event.currentTarget.dataset.field;
        const nameField = event.currentTarget.dataset.nameField;
        const { value } = event.detail;
        this._patch(rowId, { [field]: null, [nameField]: value });
    }

    async _fetchCommissionRate(rowId, accountId) {
        try {
            const rate         = await getCommissionRate({ accountId });
            const resolvedRate = rate != null ? rate : 0; // null Commission_Rate__c on Account = 0%
            const row          = this.rows.find(r => r.id === rowId);

            let commissionAmount        = row ? row.commissionAmount : null;
            let commissionAmountDisplay = row ? row.commissionAmountDisplay : '';

            // Only recalculate Commission $ if the user has not manually locked it
            if (row && !row._commAmountManual) {
                if (row.salesPrice !== null) {
                    commissionAmount        = parseFloat((row.salesPrice * resolvedRate / 100).toFixed(2));
                    commissionAmountDisplay = fmtPrice(commissionAmount);
                } else {
                    commissionAmount        = null;
                    commissionAmountDisplay = '';
                }
            }

            this._patch(rowId, { commissionRate: resolvedRate, commissionAmount, commissionAmountDisplay });
        } catch (e) {
            console.error('Failed to fetch commission rate for account', accountId, e);
        }
    }

    // ─── Drag-to-reorder ─────────────────────────────────────────────────────

    handleDragStart(event) {
        const rowId = +event.currentTarget.dataset.rowId;
        this._dragSourceId = rowId;
        event.dataTransfer.effectAllowed = 'move';
        // setData is required by the HTML5 spec — some browsers silently abort the drag without it
        event.dataTransfer.setData('text/plain', String(rowId));
        const row = this.rows.find(r => r.id === rowId);
        if (row) this._patch(rowId, { _rowClass: rowBaseClass(row.sfId) + ' row-dragging' });
    }

    handleDragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        const rowId = +event.currentTarget.dataset.rowId;
        if (rowId === this._dragOverId) return; // no change — skip re-render

        // Clear the previous drag-over indicator
        if (this._dragOverId != null) {
            const prev = this.rows.find(r => r.id === this._dragOverId);
            if (prev) {
                const extra = prev.id === this._dragSourceId ? ' row-dragging' : '';
                this._patch(this._dragOverId, { _rowClass: rowBaseClass(prev.sfId) + extra });
            }
        }

        this._dragOverId = rowId;

        // Apply drag-over indicator — but not on the source row itself
        if (rowId !== this._dragSourceId) {
            const row = this.rows.find(r => r.id === rowId);
            if (row) this._patch(rowId, { _rowClass: rowBaseClass(row.sfId) + ' row-drag-over' });
        }
    }

    handleDrop(event) {
        event.preventDefault();
        const targetId = +event.currentTarget.dataset.rowId;
        const sourceId = this._dragSourceId;

        this._dragSourceId = null;
        this._dragOverId   = null;

        if (sourceId == null || sourceId === targetId) {
            this.rows = this.rows.map(r => ({ ...r, _rowClass: rowBaseClass(r.sfId) }));
            return;
        }

        const arr      = [...this.rows];
        const fromIdx  = arr.findIndex(r => r.id === sourceId);
        const toIdx    = arr.findIndex(r => r.id === targetId);
        const [moved]  = arr.splice(fromIdx, 1);
        arr.splice(toIdx, 0, moved);

        // Persist new order in sortOrder; clear all drag-state classes
        this.rows = arr.map((r, i) => ({
            ...r,
            sortOrder: i + 1,
            _rowClass: rowBaseClass(r.sfId)
        }));
    }

    handleDragEnd() {
        // Fires after drop (success) or cancel (Escape). After a successful drop,
        // _dragSourceId is already null — return early to avoid a redundant re-render.
        if (this._dragSourceId == null) return;
        this._dragSourceId = null;
        this._dragOverId   = null;
        this.rows = this.rows.map(r => ({ ...r, _rowClass: rowBaseClass(r.sfId) }));
    }

    // ─── Utility ─────────────────────────────────────────────────────────────

    _patch(rowId, changes) {
        this.rows = this.rows.map(r => r.id === rowId ? { ...r, ...changes } : r);
    }

    // ─── Date helpers ─────────────────────────────────────────────────────────

    _toDisplayDate(str) {
        const parsed = this._parseDateParts(str);
        if (!parsed) return str || '';
        const { m, d, y } = parsed;
        return `${String(m).padStart(2, '0')}/${String(d).padStart(2, '0')}/${y}`;
    }

    _toIsoDate(str) {
        const parsed = this._parseDateParts(str);
        if (!parsed) return null;
        const { m, d, y } = parsed;
        return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
    }

    _parseDateParts(str) {
        if (!str || String(str).trim() === '') return null;
        const s = String(str).trim();

        if (/^\d{4}-\d{2}-\d{2}$/.test(s)) {
            const [y, m, d] = s.split('-').map(Number);
            return { m, d, y };
        }

        const parts = s.split('/');
        if (parts.length === 3) {
            const m = parseInt(parts[0], 10);
            const d = parseInt(parts[1], 10);
            let   y = parseInt(parts[2], 10);
            if (!isNaN(m) && !isNaN(d) && !isNaN(y)) {
                if (y < 100) y += (y < 30 ? 2000 : 1900);
                return { m, d, y };
            }
        }

        return null;
    }

    // ─── Save ─────────────────────────────────────────────────────────────────

    async handleSave() {
        this.errorMessage = null;

        // 1. Mark product errors on all rows missing a selection
        this.rows = this.rows.map(r => ({
            ...r,
            _productError: !r.product2Id
        }));

        const filledRows = this.rows.filter(r => r.product2Id);

        if (filledRows.length === 0) {
            this.errorMessage = 'Please select a product on at least one row before saving.';
            console.error('Validation failed: no product selected on any row');
            return;
        }

        // 2. Warn if text was typed in a product field but no selection was made
        const typedNotSelected = this.rows.some(r => !r.product2Id && r.product2Name.trim() !== '');
        if (typedNotSelected) {
            this.errorMessage = 'One or more product fields have text but no item was selected. Please pick from the list or clear the field.';
            console.error('Validation failed: product text entered without dropdown selection');
            return;
        }

        // Ensure salesPrice is a clean number (strip any comma formatting before serialize)
        this.rows = this.rows.map(r => {
            if (r.salesPrice === null) return r;
            const clean = parseFloat(String(r.salesPrice).replace(/,/g, ''));
            return isNaN(clean) ? r : { ...r, salesPrice: clean };
        });

        // 3. Validate sales price present
        const missingPrice = filledRows.some(r => r.salesPrice === null || r.salesPrice === '');
        if (missingPrice) {
            this.rows = this.rows.map(r => ({
                ...r,
                _priceInputClass: (r.product2Id && (r.salesPrice === null || r.salesPrice === ''))
                    ? 'price-input price-input-error'
                    : r._priceInputClass
            }));
            this.errorMessage = 'Sales Price is required on every row that has a product selected.';
            console.error('Validation failed: missing sales price on one or more rows');
            return;
        }

        // Assign sort order based on current display position — always re-numbered on save
        const rowPositions = new Map(this.rows.map((r, i) => [r.id, i + 1]));

        const serializedRows = filledRows.map(r => ({
            id:                     r.id,
            sfId:                   r.sfId,
            product2Id:             r.product2Id,
            salesPrice:             r.salesPrice,
            quantity:               r.quantity,
            description:            r.description,
            startDate:              this._toIsoDate(r.startDate),
            endDate:                this._toIsoDate(r.endDate),
            supplierId:             r.supplierId,
            providerId:             r.providerId,
            commissionAmount:       r.commissionAmount,
            commissionRate:         r.commissionRate,
            commissionAmountManual: r._commAmountManual,
            sortOrder:              rowPositions.get(r.id)
        }));

        const effectivePricebook2Id = this.pricebook2Id || this._resolvedPricebook2Id;

        this.isSaving = true;
        try {
            const savedIds = await saveItineraryLines({
                quoteId:        this.recordId,
                pricebook2Id:   effectivePricebook2Id,
                rowsJson:       JSON.stringify(serializedRows),
                deletedIdsJson: JSON.stringify(this._deletedIds)
            });

            // Immediately update sfId on newly inserted rows — prevents duplicate inserts on re-save
            if (savedIds && savedIds.length > 0) {
                const idMap = {};
                savedIds.forEach(entry => { idMap[entry.clientId] = entry.sfId; });
                this.rows = this.rows.map(r =>
                    idMap[r.id]
                        ? { ...r, sfId: idMap[r.id], _rowClass: rowBaseClass(idMap[r.id]) }
                        : r
                );
            }

            this._deletedIds = [];

            this.dispatchEvent(new ShowToastEvent({
                title:   'Saved',
                message: 'Itinerary line items saved successfully.',
                variant: 'success'
            }));

            // Only refresh the wire when new rows were inserted — the wire needs to
            // pick up server-assigned Ids and field defaults. On pure updates, local
            // state already reflects the saved values so a round-trip is unnecessary.
            if (savedIds && savedIds.length > 0) {
                try {
                    this._rowsLoaded = false;
                    await refreshApex(this._wiredLines);
                } catch (refreshError) {
                    console.error('Wire refresh failed after save (non-fatal):', refreshError);
                }
            }
        } catch (error) {
            let msg = 'An unexpected error occurred while saving. Please try again.';
            if (error && error.body) {
                if (typeof error.body === 'string' && error.body.length > 0) {
                    msg = error.body;
                } else if (error.body.message) {
                    msg = error.body.message;
                } else if (Array.isArray(error.body) && error.body.length > 0 && error.body[0].message) {
                    msg = error.body[0].message;
                }
            }
            console.error('Save failed:', error);
            this.errorMessage = msg;
        } finally {
            this.isSaving = false;
        }
    }
}
