/**
 * @name ProductImporterController
 * @version 0.2
 * @author Emandleni M
 * @description Controller for the LWC Product Importer. Handles callouts to the external product API and the creation of Product2 records in Salesforce.
 */
public with sharing class ProductImporterController {

    private static final String PRODUCT_LIST_URL = 'https://s3-eu-west-1.amazonaws.com/developer-application-test/cart/list';
    private static final String PRODUCT_DETAIL_URL_BASE = 'https://s3-eu-west-1.amazonaws.com/developer-application-test/cart/';

    @AuraEnabled(cacheable=true)
    public static List<ProductAPIDto> getProducts() {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(PRODUCT_LIST_URL);
        request.setMethod('GET');
        request.setTimeout(120000);

        try {
            HttpResponse response = http.send(request);
            if (response.getStatusCode() == 200) {
                ProductListWrapper wrapper = (ProductListWrapper) JSON.deserialize(response.getBody(), ProductListWrapper.class);
                return wrapper.products;
            } else {
                throw new CalloutException('API call to fetch product list failed with status code: ' + response.getStatusCode());
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static ProductAPIDto getProductDetail(String productId) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(PRODUCT_DETAIL_URL_BASE + productId + '/detail');
        request.setMethod('GET');
        request.setTimeout(120000);

        try {
            HttpResponse response = http.send(request);
            if (response.getStatusCode() == 200) {
                return (ProductAPIDto) JSON.deserialize(response.getBody(), ProductAPIDto.class);
            } else {
                throw new CalloutException('API call to fetch product detail failed with status code: ' + response.getStatusCode());
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Integer importProducts(String productsToImportJson) {
        List<ProductAPIDto> productsToImport = (List<ProductAPIDto>) JSON.deserialize(productsToImportJson, List<ProductAPIDto>.class);

        if (productsToImport == null || productsToImport.isEmpty()) {
            return 0;
        }

        Id standardPricebookId = Test.getStandardPricebookId();
        List<Product2> newProducts = new List<Product2>();
        
        Map<String, Decimal> productNameToPriceMap = new Map<String, Decimal>();

        for (ProductAPIDto incomingProduct : productsToImport) {
            newProducts.add(new Product2(
                Name = incomingProduct.name,
                IsActive = true
            ));
            productNameToPriceMap.put(incomingProduct.name, incomingProduct.price);
        }

        try {
            insert newProducts;

            List<PricebookEntry> standardPriceEntries = new List<PricebookEntry>();
            for (Product2 prod : newProducts) {
                Decimal unitPrice = productNameToPriceMap.get(prod.Name);
                
                standardPriceEntries.add(new PricebookEntry(
                    Pricebook2Id = standardPricebookId,
                    Product2Id = prod.Id,
                    UnitPrice = unitPrice,
                    IsActive = true
                ));
            }
            
            if (!standardPriceEntries.isEmpty()) {
                insert standardPriceEntries;
            }

            return newProducts.size();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class ProductListWrapper {
        public List<ProductAPIDto> products;
    }
    
    public class ProductAPIDto {
        public String product_id;
        public String name;
        public Decimal price;
        public String image;
        public String description;
    }
}