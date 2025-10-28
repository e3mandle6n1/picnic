/**
 * @name ProductImporterControllerTest
 * @version 0.2
 * @author Emandleni M
 * @description Controller test class for the LWC Product Importer. Handles callouts to the external product API and the creation of Product2 records in Salesforce.
 */
@isTest
private class ProductImportControllerTest {
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        private String endpoint;
        private Integer statusCode;
        private String body;

        public MockHttpResponseGenerator(String endpoint, Integer statusCode, String body) {
            this.endpoint = endpoint;
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            System.assertEquals(this.endpoint, req.getEndpoint(), 'Endpoint mismatch in mock.');
            
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(this.body);
            res.setStatusCode(this.statusCode);
            return res;
        }
    }

    @TestSetup
    static void setupTestData() {
        Pricebook2 standardPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        if (!standardPb.IsActive) {
            standardPb.IsActive = true;
            update standardPb;
        }
    }

    // --- Tests for getProductsList ---

    @isTest
    static void getProductsList_Success() {
        // Arrange
        String listEndpoint = 'https://s3-eu-west-1.amazonaws.com/developer-application-test/cart/list';
        String mockBody = '{"products": [ {"product_id": "1", "name": "Test Prod 1", "price": 10.0, "image": "img1.png"}, {"product_id": "2", "name": "Test Prod 2", "price": 20.0, "image": "img2.png"} ]}';
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(listEndpoint, 200, mockBody));

        // Act
        Test.startTest();
        List<ProductImportController.ExternalProduct> products = ProductImportController.getProductsList();
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, products, 'Product list should not be null.');
        System.assertEquals(2, products.size(), 'Should return 2 products.');
        System.assertEquals('Test Prod 1', products[0].name, 'First product name should match mock data.');
        System.assertEquals(10.0, products[0].price, 'First product price should match mock data.');
    }

    @isTest
    static void getProductsList_HttpError() {
        // Arrange
        String listEndpoint = 'https://s3-eu-west-1.amazonaws.com/developer-application-test/cart/list';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(listEndpoint, 404, 'Not Found'));

        // Act
        Test.startTest();
        List<ProductImportController.ExternalProduct> products = ProductImportController.getProductsList();
        Test.stopTest();

        // Assert
        System.assertEquals(0, products.size(), 'Should return an empty list on HTTP error.');
    }

    @isTest
    static void getProductsList_BadJson() {
        // Arrange
        String listEndpoint = 'https://s3-eu-west-1.amazonaws.com/developer-application-test/cart/list';
        // Missing "products" key, leading to null wrapper.products
        String mockBody = '{"items": [ {"product_id": "1", "name": "Test Prod 1"} ]}'; 
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(listEndpoint, 200, mockBody));

        // Act
        Test.startTest();
        List<ProductImportController.ExternalProduct> products = ProductImportController.getProductsList();
        Test.stopTest();

        // Assert
        System.assertEquals(0, products.size(), 'Should return an empty list if JSON format is incorrect.');
    }

    // --- Tests for getProductDetail ---

    @isTest
    static void getProductDetail_Success() {
        // Arrange
        String productId = '3';
        String detailEndpoint = 'https://s3-eu-west-1.amazonaws.com/developer-application-test/cart/3/detail';
        String mockBody = '{"product_id": "3", "name": "Detail Prod", "price": 99.99, "image": "img3.png", "description": "Full description."}';
        
        // Note: EncodingUtil.urlEncode('3', 'UTF-8') is '3', so the endpoint will be exactly as defined.
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(detailEndpoint, 200, mockBody));

        // Act
        Test.startTest();
        ProductImportController.ExternalProductDetail detail = ProductImportController.getProductDetail(productId);
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, detail, 'Product detail should not be null.');
        System.assertEquals('Detail Prod', detail.name, 'Product name should match mock data.');
        System.assertEquals('Full description.', detail.description, 'Product description should match mock data.');
    }

    @isTest
    static void getProductDetail_NotFound() {
        // Arrange
        String productId = '404';
        String detailEndpoint = 'https://s3-eu-west-1.amazonaws.com/developer-application-test/cart/404/detail';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(detailEndpoint, 404, 'Not Found'));

        // Act
        Test.startTest();
        ProductImportController.ExternalProductDetail detail = ProductImportController.getProductDetail(productId);
        Test.stopTest();

        // Assert
        System.assertEquals(null, detail, 'Should return null on HTTP 404 error.');
    }

    @isTest
    static void getProductDetail_BlankId() {
        // Act
        Test.startTest();
        ProductImportController.ExternalProductDetail detail = ProductImportController.getProductDetail('');
        Test.stopTest();

        // Assert
        System.assertEquals(null, detail, 'Should return null when product ID is blank.');
    }

    // --- Tests for importProducts ---

    @isTest
    static void importProducts_Success() {
        ProductImportController.ExternalProduct prodA = new ProductImportController.ExternalProduct();
        prodA.product_id = 'P001';
        prodA.name = 'Import Prod A';
        prodA.price = 50.00;
        prodA.image = 'a.png';

        ProductImportController.ExternalProduct prodB = new ProductImportController.ExternalProduct();
        prodB.product_id = 'P002';
        prodB.name = 'Import Prod B';
        prodB.price = 100.00;
        prodB.image = 'b.png';

        List<ProductImportController.ExternalProduct> products = new List<ProductImportController.ExternalProduct>{prodA, prodB};
        String productsJson = JSON.serialize(products);

        // Act
        Integer count;
        Test.startTest();
        count = ProductImportController.importProducts(productsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(2, count, 'Two products should be successfully imported.');

        // Verify Product2 records
        List<Product2> insertedProducts = [SELECT Id, Name FROM Product2 WHERE Name IN ('Import Prod A', 'Import Prod B')];
        System.assertEquals(2, insertedProducts.size(), 'Two Product2 records should be created.');
    }

    @isTest
    static void importProducts_BadJson() {
        // Arrange
        String badJson = '{"products": [ {"name": "Bad Product"} ]}';

        // Act & Assert
        Test.startTest();
        try {
            ProductImportController.importProducts(badJson);
            System.assert(false, 'Expected an AuraHandledException to be thrown for bad JSON.');
        } catch (AuraHandledException e) {
            System.assertEquals('Payload could not be processed. Invalid JSON.', e.getMessage(), 'Should throw exception for bad JSON.');
        }
        Test.stopTest();
    }

    @isTest
    static void importProducts_EmptyList() {
        // Arrange
        String emptyJson = '[]';

        // Act
        Integer count;
        Test.startTest();
        count = ProductImportController.importProducts(emptyJson);
        Test.stopTest();

        // Assert
        System.assertEquals(0, count, 'Should return 0 for an empty product list.');
    }

    @isTest
    static void importProducts_FilteringInvalidData() {
        ProductImportController.ExternalProduct prodValid = new ProductImportController.ExternalProduct();
        prodValid.product_id = 'P001';
        prodValid.name = 'Valid Prod';
        prodValid.price = 10.00;
        
        ProductImportController.ExternalProduct prodBlankName = new ProductImportController.ExternalProduct();
        prodBlankName.product_id = 'P002';
        prodBlankName.name = ''; // Invalid: Blank Name
        prodBlankName.price = 20.00;

        ProductImportController.ExternalProduct prodNullPrice = new ProductImportController.ExternalProduct();
        prodNullPrice.product_id = 'P003';
        prodNullPrice.name = 'No Price';
        prodNullPrice.price = null; // Invalid: Null Price


        List<ProductImportController.ExternalProduct> products = new List<ProductImportController.ExternalProduct>{
            prodValid,
            prodBlankName, 
            prodNullPrice
        };
        String productsJson = JSON.serialize(products);

        // Act
        Integer count;
        Test.startTest();
        count = ProductImportController.importProducts(productsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(1, count, 'Only one product should be valid and imported.');
    }
}