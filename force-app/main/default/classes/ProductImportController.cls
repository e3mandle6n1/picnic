/**
 * @name ProductImporterController
 * @version 0.2
 * @author Emandleni M
 * @description Controller for the LWC Product Importer. Handles callouts to the external product API and the creation of Product2 records in Salesforce.
 */
public class ProductImportController {
    private static final String LIST_ENDPOINT = 'https://s3-eu-west-1.amazonaws.com/developer-application-test/cart/list';
    private static final String DETAIL_BASE_ENDPOINT = 'https://s3-eu-west-1.amazonaws.com/developer-application-test/cart/';

    public virtual class ExternalProduct {
        @AuraEnabled public String product_id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal price;
        @AuraEnabled public String image;
    }

    public class ExternalProductDetail extends ExternalProduct {
        @AuraEnabled public String description;
    }

    private class ProductListWrapper {
        public List<ExternalProduct> products;
    }

    /**
     * @description Retrieves the list of products from the external REST endpoint.
     * @return List<ExternalProduct> The list of products, or an empty list on error.
     */
    @AuraEnabled(cacheable=true)
    public static List<ExternalProduct> getProductsList() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(LIST_ENDPOINT);
        req.setMethod('GET');
        req.setTimeout(60000);

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                ProductListWrapper wrapper = (ProductListWrapper) System.JSON.deserialize(res.getBody(), ProductListWrapper.class);
                
                if (wrapper != null && wrapper.products != null) {
                    return wrapper.products;
                }
            } else {
                System.debug('Error calling list endpoint. Status: ' + res.getStatusCode() + ' Body: ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug('Exception in getProductsList: ' + e.getMessage());
        }

        return new List<ExternalProduct>();
    }

    /**
     * @description Retrieves the detailed product information.
     * @param productId The ID of the product to retrieve.
     * @return ExternalProductDetail The product details, or null on error.
     */
    @AuraEnabled
    public static ExternalProductDetail getProductDetail(String productId) {
        if (String.isBlank(productId)) return null;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(DETAIL_BASE_ENDPOINT + EncodingUtil.urlEncode(productId, 'UTF-8') + '/detail');
        req.setMethod('GET');
        req.setTimeout(60000);

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                ExternalProductDetail detail = (ExternalProductDetail) System.JSON.deserialize(res.getBody(), ExternalProductDetail.class);
                return detail;
            } else {
                System.debug('Error calling detail endpoint. Status: ' + res.getStatusCode() + ' Body: ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug('Exception in getProductDetail: ' + e.getMessage());
        }

        return null;
    }
    
    /**
     * @description Creates Product2 records and Standard PricebookEntries from a list of selected products.
     * @param productsToImportJson A JSON string of the products to import.
     * @return Integer The count of successfully imported products.
     */
    @AuraEnabled
    public static Integer importProducts(String productsToImportJson) {
        System.debug('importProducts started. Received payload string length: ' + (productsToImportJson != null ? productsToImportJson.length() : 0));

        List<ExternalProduct> productsToImport;
        try {
            productsToImport = (List<ExternalProduct>) JSON.deserialize(productsToImportJson, List<ExternalProduct>.class);
        } catch (Exception e) {
            System.debug('FATAL: JSON Deserialization failed. Payload may be malformed. Error: ' + e.getMessage());
            throw new AuraHandledException('Payload could not be processed. Invalid JSON.');
        }

        if (productsToImport == null || productsToImport.isEmpty()) {
            System.debug('Payload was null or empty after deserialization. Returning 0.');
            return 0;
        }
        System.debug('Deserialized ' + productsToImport.size() + ' products from payload.');

        Id standardPricebookId;
        try {
            Pricebook2 standardPricebook = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
            standardPricebookId = standardPricebook.Id;
            System.debug('Found Standard Pricebook ID: ' + standardPricebookId);
        } catch (Exception e) {
            System.debug('FATAL: Could not find Standard Pricebook. Error: ' + e.getMessage());
            throw new AuraHandledException('Could not find Standard Pricebook. Please ensure one is active.');
        }

        List<Product2> newProducts = new List<Product2>();
        Map<String, Decimal> productNameToPriceMap = new Map<String, Decimal>();

        for (ExternalProduct incomingProduct : productsToImport) {
            if (String.isNotBlank(incomingProduct.name) && incomingProduct.price != null) {
                newProducts.add(new Product2(
                    Name = incomingProduct.name,
                    IsActive = true
                ));
                productNameToPriceMap.put(incomingProduct.name, incomingProduct.price);
            } else {
                System.debug('Skipping product with null name or price. ID: ' + incomingProduct.product_id);
            }
        }

        if (newProducts.isEmpty()) {
            System.debug('No valid products to insert after filtering for nulls. Returning 0.');
            return 0;
        }

        try {
            System.debug('Attempting to insert ' + newProducts.size() + ' new Product2 records.');
            insert newProducts;
            System.debug('Successfully inserted Product2 records.');

            List<PricebookEntry> standardPriceEntries = new List<PricebookEntry>();
            for (Product2 prod : newProducts) {
                Decimal unitPrice = productNameToPriceMap.get(prod.Name);
                
                if (unitPrice != null) {
                    standardPriceEntries.add(new PricebookEntry(
                        Pricebook2Id = standardPricebookId,
                        Product2Id = prod.Id,
                        UnitPrice = unitPrice,
                        IsActive = true
                    ));
                } else {
                     System.debug('WARN: Could not find price in map for inserted product: ' + prod.Name);
                }
            }
            
            if (!standardPriceEntries.isEmpty()) {
                System.debug('Attempting to insert ' + standardPriceEntries.size() + ' new PricebookEntry records.');
                insert standardPriceEntries;
                System.debug('Successfully inserted PricebookEntry records.');
            } else {
                 System.debug('No PricebookEntry records were created (all prices might have been null).');
            }

            System.debug('Import complete. Returning success count: ' + newProducts.size());
            return newProducts.size();

        } catch (Exception e) {
            System.debug('DML Exception during import: ' + e.getMessage() + ' at line: ' + e.getLineNumber());
            throw new AuraHandledException('Error during import: ' + e.getDmlMessage(0));
        }
    }    
}