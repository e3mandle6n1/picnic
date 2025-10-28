/**
 * @name ProductTile
 * @version 0.1
 * @author Emandleni M
 * @description A component for displaying a single product with its image, name, and price. Fires events when the user selects it or requests to view its details.
 */

import { LightningElement, api } from 'lwc';

export default class ProductTile extends LightningElement {
    @api product;

    handleSelect(event) {
        event.stopPropagation();

        const selectedEvent = new CustomEvent('productselected', {
            bubbles: true, 
            composed: true,
            detail: {
                productId: this.product.product_id,
                isSelected: event.target.checked
            }
        });
        this.dispatchEvent(selectedEvent);
    }

    handleTileClick() {
        const viewEvent = new CustomEvent('viewdetail', {
            detail: this.product.product_id
        });
        this.dispatchEvent(viewEvent);
    }
}