
/**
 * @name ProductImporter
 * @version 0.4
 * @author Emandleni M
 * @description Main component, fetches the list of products, handles filtering, manages selections, and controls when and how the details modal is shown. Now with detailed import/update feedback.
 */

import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProductsList from '@salesforce/apex/ProductImportController.getProductsList';
import getProductDetail from '@salesforce/apex/ProductImportController.getProductDetail';
import importProducts from '@salesforce/apex/ProductImportController.importProducts';

// Debounce timer
const DEBOUNCE_DELAY = 300;

export default class ProductImporter extends LightningElement {
    @track products = []; // Full product list from the API
    @track filteredProducts = []; // List displayed in the UI
    @track filterTerm = '';
    @track isLoading = true;
    
    // Modal State
    @track isModalOpen = false;
    @track selectedProductDetail = {};
    @track isDetailLoading = false;
    
    timerId; // for debouncing

    @wire(getProductsList)
    wiredProducts({ error, data }) {
        this.isLoading = false;
        if (data) {
            // Map the product list to add a 'selected' flag for the checkbox
            this.products = data.map(product => ({
                ...product,
                selected: false
            }));
            this.filteredProducts = this.products;
        } else if (error) {
            console.error('Error retrieving products: ', error);
            this.showToast('Error', 'Could not load products. Check Apex logs.', 'error');
        }
    }

    get hasProducts() {
        return this.filteredProducts && this.filteredProducts.length > 0;
    }

    get isImportDisabled() {
        // Disable if no products are selected
        return !this.products.some(p => p.selected);
    }

    handleFilterChange(event) {
        this.filterTerm = event.target.value.toLowerCase();
        
        clearTimeout(this.timerId);

        // Check for the minimum two characters requirement
        if (this.filterTerm.length > 2 || this.filterTerm.length === 0) {
            this.timerId = setTimeout(() => {
                this.applyFilter();
            }, DEBOUNCE_DELAY);
        } else {
            // If they delete chars to be < 3 (and not 0), show full list.
            if (this.filterTerm.length === 0) {
                 this.timerId = setTimeout(() => {
                    this.applyFilter();
                }, DEBOUNCE_DELAY);
            } else {
                 this.filteredProducts = this.products;
            }
        }
    }

    applyFilter() {
        if (!this.filterTerm || this.filterTerm.length === 0) {
            this.filteredProducts = this.products;
            return;
        }

        this.filteredProducts = this.products.filter(product => 
            product.name.toLowerCase().includes(this.filterTerm)
        );
    }
    
    handleProductSelection(event) {
        const productId = event.target.dataset.id;
        const isChecked = event.target.checked;

        // Update the 'selected' flag on the main product list
        this.products = this.products.map(p => 
            p.product_id === productId ? { ...p, selected: isChecked } : p
        );

        // Update the 'selected' flag on the filtered list to refresh the UI
        this.filteredProducts = this.filteredProducts.map(p => 
            p.product_id === productId ? { ...p, selected: isChecked } : p
        );
    }
    
    async handleImport() {
        const selectedProducts = this.products.filter(p => p.selected);

        if (selectedProducts.length === 0) {
            this.showToast('Warning', 'Please select at least one product to import.', 'warning');
            return;
        }

        this.isLoading = true;
        
        const jsonPayload = JSON.stringify(selectedProducts);
        
        try {
            // Expect the new ImportResult wrapper object
            const result = await importProducts({ productsToImportJson: jsonPayload });
            
            const createdCount = result.createdCount;
            const updatedCount = result.updatedCount;

            // Build a dynamic, detailed success message that shows correct plurals and counts
            let messageParts = [];
            if (createdCount > 0) {
                let part = `${createdCount} new product${createdCount > 1 ? 's' : ''} imported`;
                messageParts.push(part);
            }
            if (updatedCount > 0) {
                let part = `${updatedCount} existing product${updatedCount > 1 ? 's' : ''} updated`;
                messageParts.push(part);
            }

            if (messageParts.length > 0) {
                // This will create messages like:
                // "5 new products imported."
                // "3 existing products updated."
                // "5 new products imported and 3 existing products updated."
                const message = messageParts.join(' and ') + '.';
                
                this.showToast('Import Complete', message, 'success');
                
                // Clear selections after successful import
                this.products = this.products.map(p => ({ ...p, selected: false }));
                this.applyFilter(); // Re-render filtered list with cleared selections
            } else {
                this.showToast('Info', 'No products were imported or updated.', 'info');
            }
            
        } catch (error) {
            console.error('Error importing products: ', JSON.stringify(error));
            let errorMessage = 'An unexpected error occurred during import.';
            
            if (error && error.body && error.body.message) {
                errorMessage = error.body.message;
            }
            
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleProductClick(event) {
        const productId = event.currentTarget.dataset.id;
        if (!productId) return;
        
        this.openModal();
        this.isDetailLoading = true;
        
        try {
            const detail = await getProductDetail({ productId });

            if (detail) {
                // Rigorous null check on the payload from detail endpoint
                this.selectedProductDetail = {
                    name: detail.name || 'N/A',
                    price: detail.price || 0,
                    image: detail.image || '',
                    description: detail.description || 'No description available.'
                };
            } else {
                 this.showToast('Error', 'Could not retrieve product details.', 'error');
                 this.closeModal();
            }
        } catch (error) {
            console.error('Error fetching product detail: ', error);
            this.showToast('Error', 'Failed to fetch product details.', 'error');
            this.closeModal();
        } finally {
            this.isDetailLoading = false;
        }
    }

    openModal() {
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
        this.selectedProductDetail = {};
    }
    
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}