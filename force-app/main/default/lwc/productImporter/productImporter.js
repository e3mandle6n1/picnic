/**
 * @name ProductImporter
 * @version 0.1
 * @author Emandleni M
 * @description Main component, fetches the list of products, handles filtering, manages selections, and controls when the modal is shown.
 */

import { LightningElement, track } from 'lwc';
import getProducts from '@salesforce/apex/ProductImporterController.getProducts';
import importProducts from '@salesforce/apex/ProductImporterController.importProducts';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const DEBOUNCE_DELAY = 350;

export default class ProductImporter extends LightningElement {
    @track allProducts = [];
    @track filteredProducts = [];
    
    selectedProductIds = new Set();
    
    error;
    debounceTimeout;
    isLoading = true;

    isModalOpen = false;
    selectedProductId = null;

    connectedCallback() {
        this.loadProducts();
    }

    loadProducts() {
        this.isLoading = true;
        getProducts()
            .then(data => {
                this.allProducts = data;
                this.filteredProducts = data;
                this.error = undefined;
            })
            .catch(error => {
                this.error = error;
                this.allProducts = [];
                this.filteredProducts = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    get isImportDisabled() {
        return this.selectedProductIds.size === 0 || this.isLoading;
    }

    get importButtonLabel() {
        const count = this.selectedProductIds.size;
        return count > 0 ? `Import (${count}) Selected` : 'Import Selected';
    }

    get errorText() {
        return this.error && this.error.body ? this.error.body.message : 'An unknown error occurred.';
    }

    handleSearchChange(event) {
        // Debounce to prevent filtering on every keystroke
        window.clearTimeout(this.debounceTimeout);
        const searchQuery = event.target.value;

        this.debounceTimeout = setTimeout(() => {
            if (searchQuery.length > 2 || searchQuery.length === 0) {
                this.filterProducts(searchQuery);
            }
        }, DEBOUNCE_DELAY);
    }

    handleProductSelected(event) {
        const { productId, isSelected } = event.detail;
        if (isSelected) {
            this.selectedProductIds.add(productId);
        } else {
            this.selectedProductIds.delete(productId);
        }
        // Force a re-render by creating a new Set object
        this.selectedProductIds = new Set(this.selectedProductIds);
    }

    handleImportClick() {
        this.isLoading = true;
        
        const productsToImport = this.allProducts.filter(prod => 
            this.selectedProductIds.has(prod.product_id)
        );

        importProducts({ productsToImportJson: JSON.stringify(productsToImport) })
            .then(result => {
                this.showToast('Success', `${result} products imported successfully.`, 'success');
                this.selectedProductIds.clear();
                // Uncheck all checkboxes after successful import by re-filtering
                this.filterProducts(this.template.querySelector('lightning-input').value);
            })
            .catch(error => {
                this.showToast('Error Importing Products', error.body.message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleViewDetail(event) {
        this.selectedProductId = event.detail;
        this.isModalOpen = true;
    }

    handleCloseModal() {
        this.isModalOpen = false;
        this.selectedProductId = null;
    }

    filterProducts(searchQuery) {
        if (!searchQuery) {
            this.filteredProducts = [...this.allProducts];
            return;
        }
        
        const lowerCaseQuery = searchQuery.toLowerCase();
        this.filteredProducts = this.allProducts.filter(product =>
            product.name.toLowerCase().includes(lowerCaseQuery)
        );
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}