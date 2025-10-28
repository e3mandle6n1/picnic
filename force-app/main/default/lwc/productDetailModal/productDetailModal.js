/**
 * @name ProductDetailModal
 * @version 0.1
 * @author Emandleni M
 * @description A modal dialog (lightbox) that displays detailed information about a single product by fetching it from the API.
 */

import { LightningElement, api, wire } from 'lwc';
import getProductDetail from '@salesforce/apex/ProductImporterController.getProductDetail';

export default class ProductDetailModal extends LightningElement {
    @api productId;

    @wire(getProductDetail, { productId: '$productId' })
    product;

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}