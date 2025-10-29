/**
 * @name ProductImporterController
 * @version 0.3
 * @author Emandleni M
 * @description Controller for the LWC Product Importer. Handles callouts, and UPSERTS Product2 records to prevent duplicates.
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
     * @description Imports products into Salesforce by upserting Product2 records and their PricebookEntries to prevent duplicates.
     * @param productsToImportJson A JSON string of the products to import.
     * @return Integer The count of successfully imported products.
     */
    @AuraEnabled
    public static Integer importProducts(String productsToImportJson) {
        System.debug('importProducts started. Payload: ' + productsToImportJson);

        List<ExternalProduct> productsToImport;
        try {
            productsToImport = (List<ExternalProduct>) JSON.deserialize(productsToImportJson, List<ExternalProduct>.class);
        } catch (Exception e) {
            System.debug('FATAL: JSON Deserialization failed. Error: ' + e.getMessage());
            throw new AuraHandledException('Payload could not be processed. Invalid JSON.');
        }

        if (productsToImport == null || productsToImport.isEmpty()) {
            System.debug('Payload was null or empty. Returning 0.');
            return 0;
        }
        System.debug('Deserialized ' + productsToImport.size() + ' products.');

        Id standardPricebookId;
        try {
            Pricebook2 standardPricebook = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
            standardPricebookId = standardPricebook.Id;
            System.debug('Found Standard Pricebook ID: ' + standardPricebookId);
        } catch (Exception e) {
            System.debug('FATAL: Could not find Standard Pricebook. Error: ' + e.getMessage());
            throw new AuraHandledException('Could not find Standard Pricebook. Please ensure one is active.');
        }

        List<Product2> productsToUpsert = new List<Product2>();
        Map<String, Decimal> externalIdToPriceMap = new Map<String, Decimal>();

        for (ExternalProduct incomingProduct : productsToImport) {
            if (String.isNotBlank(incomingProduct.name) && incomingProduct.price != null && String.isNotBlank(incomingProduct.product_id)) {
                
                productsToUpsert.add(new Product2(
                    External_Product_ID__c = incomingProduct.product_id, 
                    Name = incomingProduct.name,
                    IsActive = true
                ));
                externalIdToPriceMap.put(incomingProduct.product_id, incomingProduct.price);
            } else {
                System.debug('Skipping product with null name, price, or external ID: ' + incomingProduct.product_id);
            }
        }

        if (productsToUpsert.isEmpty()) {
            System.debug('No valid products to upsert after filtering. Returning 0.');
            return 0;
        }

        try {
            System.debug('Attempting to UPSERT ' + productsToUpsert.size() + ' Product2 records.');
            upsert productsToUpsert External_Product_ID__c;
            System.debug('Successfully upserted Product2 records.');
            
            Set<Id> productIds = (new Map<Id, SObject>(productsToUpsert)).keySet();

            Map<Id, PricebookEntry> existingPbeMap = new Map<Id, PricebookEntry>();
            for (PricebookEntry pbe : [SELECT Id, Product2Id, UnitPrice, IsActive 
                                       FROM PricebookEntry 
                                       WHERE Product2Id IN :productIds 
                                       AND Pricebook2Id = :standardPricebookId]) {
                existingPbeMap.put(pbe.Product2Id, pbe);
            }

            List<PricebookEntry> pbesToUpsert = new List<PricebookEntry>();
            for (Product2 prod : productsToUpsert) {
                Decimal unitPrice = externalIdToPriceMap.get(prod.External_Product_ID__c);
                
                if (unitPrice != null) {
                    PricebookEntry pbe = existingPbeMap.get(prod.Id);
                    
                    if (pbe == null) {
                        pbe = new PricebookEntry(
                            Pricebook2Id = standardPricebookId,
                            Product2Id = prod.Id,
                            UnitPrice = unitPrice,
                            IsActive = true
                        );
                    } else {
                        pbe.UnitPrice = unitPrice;
                        pbe.IsActive = true;
                    }
                    pbesToUpsert.add(pbe);
                } else {
                     System.debug('WARN: Could not find price in map for upserted product: ' + prod.Name);
                }
            }
            
            if (!pbesToUpsert.isEmpty()) {
                System.debug('Attempting to UPSERT ' + pbesToUpsert.size() + ' PricebookEntry records.');
                upsert pbesToUpsert; 
                System.debug('Successfully upserted PricebookEntry records.');
            }

            System.debug('Import complete. Returning success count: ' + productsToUpsert.size());
            return productsToUpsert.size(); 

        } catch (Exception e) {
            System.debug('DML Exception during import: ' + e.getMessage() + ' at line: ' + e.getLineNumber());
            throw new AuraHandledException('Error during import: ' + e.getMessage());
        }
    }    
}