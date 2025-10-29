/**
 * @name ProductImporterController
 * @version 0.4
 * @author Emandleni M
 * @description Controller for the LWC Product Importer. Handles callouts, and UPSERTS Product2 records to prevent duplicates. Returns a detailed count of created vs. updated records.
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
     * @description Wrapper class to hold the counts of inserted and updated records.
     */
    public class ImportResult {
        @AuraEnabled public Integer createdCount { get; set; }
        @AuraEnabled public Integer updatedCount { get; set; }

        public ImportResult() {
            this.createdCount = 0;
            this.updatedCount = 0;
        }
    }

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
     * @description Creates or updates Product2 records and returns detailed counts.
     * @param productsToImportJson A JSON string of the products to import.
     * @return ImportResult The count of new vs. updated products.
     */
    @AuraEnabled
    public static ImportResult importProducts(String productsToImportJson) {
        ImportResult result = new ImportResult();

        List<ExternalProduct> productsToImport;
        try {
            productsToImport = (List<ExternalProduct>) JSON.deserialize(productsToImportJson, List<ExternalProduct>.class);
        } catch (Exception e) {
            System.debug('FATAL: JSON Deserialization failed. Error: ' + e.getMessage());
            throw new AuraHandledException('Payload could not be processed. Invalid JSON.');
        }

        if (productsToImport == null || productsToImport.isEmpty()) {
            System.debug('Payload was null or empty. Returning 0.');
            return result;
        }
        System.debug('Deserialized ' + productsToImport.size() + ' products.');

        Id standardPricebookId;
        try {
            Pricebook2 standardPricebook = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
            standardPricebookId = standardPricebook.Id;
        } catch (Exception e) {
            System.debug('FATAL: Could not find Standard Pricebook. Error: ' + e.getMessage());
            throw new AuraHandledException('Could not find Standard Pricebook. Please ensure one is active.');
        }

        List<Product2> productsToUpsert = new List<Product2>();
        Map<String, Decimal> externalIdToPriceMap = new Map<String, Decimal>();
        // Add a set to hold incoming external IDs for pre-query
        Set<String> incomingExternalIds = new Set<String>();

        for (ExternalProduct incomingProduct : productsToImport) {
            if (String.isNotBlank(incomingProduct.name) && incomingProduct.price != null && String.isNotBlank(incomingProduct.product_id)) {
                
                productsToUpsert.add(new Product2(
                    External_Product_ID__c = incomingProduct.product_id, // Use the custom external Id field on Product2 and NOT the standard external Id field
                    Name = incomingProduct.name,
                    IsActive = true
                ));
                externalIdToPriceMap.put(incomingProduct.product_id, incomingProduct.price);
                incomingExternalIds.add(incomingProduct.product_id);
            } else {
                System.debug('Skipping product with null name, price, or external ID: ' + incomingProduct.product_id);
            }
        }

        if (productsToUpsert.isEmpty()) {
            System.debug('No valid products to upsert after filtering. Returning 0.');
            return result;
        }

        // --- Query for existing products BEFORE upsert ---
        Set<String> existingExternalIds = new Set<String>();
        for (Product2 existingProd : [SELECT Id, External_Product_ID__c 
                                      FROM Product2 
                                      WHERE External_Product_ID__c IN :incomingExternalIds]) {
            existingExternalIds.add(existingProd.External_Product_ID__c);
        }
        System.debug('Found ' + existingExternalIds.size() + ' existing products out of ' + incomingExternalIds.size() + ' incoming.');
        // --- End of pre-query ---

        try {
            System.debug('Attempting to UPSERT ' + productsToUpsert.size() + ' Product2 records.');
            upsert productsToUpsert External_Product_ID__c; // Use the custom Product2 External ID field
            System.debug('Successfully upserted Product2 records.');

            for (Product2 upsertedProd : productsToUpsert) {
                if (existingExternalIds.contains(upsertedProd.External_Product_ID__c)) {
                    result.updatedCount++;
                } else {
                    result.createdCount++;
                }
            }
            System.debug('Result: ' + result.createdCount + ' created, ' + result.updatedCount + ' updated.');

            // --- PricebookEntry upsert logic ---
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
            // --- End of PricebookEntry logic ---

            System.debug('Import complete. Returning results.');
            return result;

        } catch (Exception e) {
            System.debug('DML Exception during import: ' + e.getMessage() + ' at line: ' + e.getLineNumber());
            throw new AuraHandledException('Error during import: ' + e.getMessage());
        }
    }    
}