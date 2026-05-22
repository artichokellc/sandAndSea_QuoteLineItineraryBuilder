import { LightningElement, api } from 'lwc';
import searchRecords from '@salesforce/apex/ItineraryBuilderController.searchRecords';

export default class LookupInput extends LightningElement {
    @api value          = '';
    @api objectApiName  = '';
    @api recordTypeName = '';
    @api pricebook2Id   = '';
    @api placeholder    = 'Search...';
    @api hasError       = false;

    _results  = [];
    _showDrop = false;
    _dropStyle = '';

    _searchTimer = null;
    _blurTimer   = null;

    get _inputClass() {
        return this.hasError ? 'lup-input lup-input-error' : 'lup-input';
    }

    get _dropEmpty() {
        return this._results.length === 0;
    }

    disconnectedCallback() {
        clearTimeout(this._searchTimer);
        clearTimeout(this._blurTimer);
    }

    handleInput(event) {
        const term = event.currentTarget.value;
        this.dispatchEvent(new CustomEvent('inputchange', { detail: { value: term } }));
        clearTimeout(this._searchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimer = setTimeout(() => {
            this._doSearch(term);
        }, 250);
    }

    handleBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._blurTimer = setTimeout(() => {
            this._blurTimer = null;
            this._showDrop  = false;
        }, 200);
    }

    handleBtnMouseDown(event) {
        // Prevents the input from blurring when the search button is pressed,
        // eliminating the blur-timer race that would close the dropdown before it opens.
        event.preventDefault();
    }

    handleBtnClick() {
        clearTimeout(this._blurTimer);
        this._blurTimer = null;
        const input = this.template.querySelector('input');
        const term  = input ? input.value : '';
        if (input) input.focus();
        this._doSearch(term);
    }

    handleSelectResult(event) {
        clearTimeout(this._blurTimer);
        this._blurTimer = null;
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this._showDrop = false;
        this._results  = [];
        this.dispatchEvent(new CustomEvent('lookupselect', { detail: { id, name } }));
    }

    async _doSearch(term) {
        try {
            const results = await searchRecords({
                objectApiName:  this.objectApiName,
                searchTerm:     term,
                recordTypeName: this.recordTypeName || '',
                pricebook2Id:   this.pricebook2Id   || ''
            });
            this._results   = results;
            this._showDrop  = true;
            this._dropStyle = this._computeDropStyle();
        } catch (e) {
            console.error('LookupInput search error for', this.objectApiName, ':', e);
        }
    }

    _computeDropStyle() {
        const input = this.template.querySelector('input');
        if (!input) return '';
        const rect = input.getBoundingClientRect();
        const w    = Math.round(rect.width) + 28;
        const left = Math.round(rect.left);
        if ((window.innerHeight - rect.bottom) < 220) {
            const bottom = Math.round(window.innerHeight - rect.top) + 2;
            return `left:${left}px;bottom:${bottom}px;width:${w}px;top:auto`;
        }
        return `left:${left}px;top:${Math.round(rect.bottom) + 2}px;width:${w}px`;
    }
}
