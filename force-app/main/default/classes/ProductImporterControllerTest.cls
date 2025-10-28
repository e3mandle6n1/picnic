/**
 * @name ProductImporterControllerTest
 * @version 0.2
 * @author Emandleni M
 * @description Test class for the ProductImporterController. Verifies the behavior of the controller methods.
 */
@isTest
private class ProductImporterControllerTest {

    public class ProductImporterMock implements HttpCalloutMock {
        protected Integer statusCode;
        protected String responseBody;

        public ProductImporterMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            return res;
        }
    }

    @isTest
    static void testGetProducts_Success() {
        String mockProductListJson = '{ "products": [ { "product_id": "1", "name": "Test Product 1", "price": 10.0, "image": "test1.jpg", "description": "Desc 1" } ] }';
        Test.setMock(HttpCalloutMock.class, new ProductImporterMock(200, mockProductListJson));

        Test.startTest();
        List<ProductImporterController.ProductAPIDto> products = ProductImporterController.getProducts();
        Test.stopTest();

        System.assertEquals(1, products.size(), 'Should return one product.');
        System.assertEquals('Test Product 1', products[0].name, 'Product name should match.');
    }

    @isTest
    static void testGetProducts_Error() {
        Test.setMock(HttpCalloutMock.class, new ProductImporterMock(500, 'Internal Server Error'));

        Test.startTest();
        try {
            ProductImporterController.getProducts();
        } catch (Exception e) {
            System.assert(e.getMessage().contains('API call to fetch product list failed'), 'Should throw a callout exception.');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetProductDetail_Success() {
        String mockProductDetailJson = '{ "product_id": "-1", "name": "Test Product Name", "price": 20.0, "image": "detail.jpg", "description": "Detailed Desc" }';
        Test.setMock(HttpCalloutMock.class, new ProductImporterMock(200, mockProductDetailJson));

        Test.startTest();
        ProductImporterController.ProductAPIDto product = ProductImporterController.getProductDetail('1');
        Test.stopTest();

        System.assertNotEquals(null, product, 'Product should not be null.');
        System.assertEquals('Test Product Name', product.name, 'Product name should match.');
    }

    @isTest
    static void testGetProductDetail_Error() {
        Test.setMock(HttpCalloutMock.class, new ProductImporterMock(500, 'Internal Server Error'));

        Test.startTest();
        try {
            ProductImporterController.getProductDetail('1');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('API call to fetch product detail failed'), 'Should throw a callout exception.');
        }
        Test.stopTest();
    }

    @isTest
    static void testImportProducts_Success() {
        List<ProductImporterController.ProductAPIDto> productsToImport = new List<ProductImporterController.ProductAPIDto>();
        ProductImporterController.ProductAPIDto product1 = new ProductImporterController.ProductAPIDto();
        product1.name = 'New Product 1';
        product1.price = 50.0;
        productsToImport.add(product1);

        ProductImporterController.ProductAPIDto product2 = new ProductImporterController.ProductAPIDto();
        product2.name = 'New Product 2';
        product2.price = 75.0;
        productsToImport.add(product2);
        
        String productsToImportJson = JSON.serialize(productsToImport);

        Test.startTest();
        Integer importedCount = ProductImporterController.importProducts(productsToImportJson);
        Test.stopTest();

        System.assertEquals(2, importedCount, 'Should import two products.');

        List<Product2> createdProducts = [SELECT Name FROM Product2 WHERE Name IN ('New Product 1', 'New Product 2')];
        System.assertEquals(2, createdProducts.size(), 'Two Product2 records should be created.');

        List<PricebookEntry> createdPricebookEntries = [SELECT UnitPrice FROM PricebookEntry WHERE Product2.Name IN ('New Product 1', 'New Product 2')];
        System.assertEquals(2, createdPricebookEntries.size(), 'Two PricebookEntry records should be created.');
    }

    @isTest
    static void testImportProducts_EmptyList() {
        Test.startTest();
        Integer importedCount = ProductImporterController.importProducts('[]');
        Test.stopTest();

        System.assertEquals(0, importedCount, 'Should import zero products.');
    }
}