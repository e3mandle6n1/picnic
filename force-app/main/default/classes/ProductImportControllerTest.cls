/**
 * @name ProductImportControllerTest
 * @version 0.4
 * @author Emandleni M (with Gemini updates)
 * @description Test class for ProductImportController. Covers mock callouts and all DML operations, including create, update, and mixed upsert scenarios. 
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

    /**
     * @description Set up the Standard Pricebook to be active.
     */
    @isTest(SeeAllData=true) // Needs to see the Standard Pricebook
    static void setupTestData() {
        Pricebook2 standardPb = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        
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

    // --- Tests for getProductDetail ---

    @isTest
    static void getProductDetail_Success() {
        // Arrange
        String productId = '3';
        String detailEndpoint = 'https://s3-eu-west-1.amazonaws.com/developer-application-test/cart/3/detail';
        String mockBody = '{"product_id": "3", "name": "Detail Prod", "price": 99.99, "image": "img3.png", "description": "Full description."}';
        
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
    static void getProductDetail_BlankId() {
        // Act
        Test.startTest();
        ProductImportController.ExternalProductDetail detail = ProductImportController.getProductDetail('');
        Test.stopTest();

        // Assert
        System.assertEquals(null, detail, 'Should return null when product ID is blank.');
    }

    // --- Tests for importProducts ---

    @isTest(SeeAllData=true) // Needs to see Standard Pricebook
    static void importProducts_CreateNew_Success() {
        // Arrange
        ProductImportController.ExternalProduct prodA = new ProductImportController.ExternalProduct();
        prodA.product_id = 'P001';
        prodA.name = 'Import Prod A';
        prodA.price = 50.00;

        ProductImportController.ExternalProduct prodB = new ProductImportController.ExternalProduct();
        prodB.product_id = 'P002';
        prodB.name = 'Import Prod B';
        prodB.price = 100.00;

        List<ProductImportController.ExternalProduct> products = new List<ProductImportController.ExternalProduct>{prodA, prodB};
        String productsJson = JSON.serialize(products);

        // Act
        Test.startTest();
        ProductImportController.ImportResult result = ProductImportController.importProducts(productsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(2, result.createdCount, 'Should create 2 new products.');
        System.assertEquals(0, result.updatedCount, 'Should update 0 products.');

        // Verify Product2 records
        List<Product2> insertedProducts = [SELECT Id, Name FROM Product2 WHERE External_Product_ID__c IN ('P001', 'P002')];
        System.assertEquals(2, insertedProducts.size(), 'Two Product2 records should be created.');
        
        // Verify PricebookEntry records
        List<PricebookEntry> entries = [SELECT UnitPrice FROM PricebookEntry WHERE Product2.External_Product_ID__c IN ('P001', 'P002') AND Pricebook2.IsStandard = true];
        System.assertEquals(2, entries.size(), 'Two PricebookEntry records should be created.');
    }

    @isTest(SeeAllData=true) // Needs to see Standard Pricebook
    static void importProducts_Update_Success() {
        // Arrange: Create an existing product 'P001'
        Id standardPbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
        
        Product2 existingProd = new Product2(
            Name = 'Old Name',
            External_Product_ID__c = 'P001',
            IsActive = true
        );
        insert existingProd;
        insert new PricebookEntry(
            Pricebook2Id = standardPbId,
            Product2Id = existingProd.Id,
            UnitPrice = 10.00,
            IsActive = true
        );

        // Arrange: New payload to update 'P001'
        ProductImportController.ExternalProduct prodUpdate = new ProductImportController.ExternalProduct();
        prodUpdate.product_id = 'P001';
        prodUpdate.name = 'New Name';
        prodUpdate.price = 99.00;

        String productsJson = JSON.serialize(new List<ProductImportController.ExternalProduct>{prodUpdate});

        // Act
        Test.startTest();
        ProductImportController.ImportResult result = ProductImportController.importProducts(productsJson);
        Test.stopTest();

        // Assert: Check the counts
        System.assertEquals(0, result.createdCount, 'Should create 0 products.');
        System.assertEquals(1, result.updatedCount, 'Should update 1 product.');

        // Assert: Verify DB state
        Integer prodCount = [SELECT count() FROM Product2 WHERE External_Product_ID__c = 'P001'];
        System.assertEquals(1, prodCount, 'Should only be one product with this external ID.');
        
        Product2 updatedProd = [SELECT Name FROM Product2 WHERE External_Product_ID__c = 'P001'];
        System.assertEquals('New Name', updatedProd.Name, 'Product name should be updated.');
        
        PricebookEntry updatedPBE = [SELECT UnitPrice FROM PricebookEntry WHERE Product2Id = :existingProd.Id AND Pricebook2Id = :standardPbId];
        System.assertEquals(99.00, updatedPBE.UnitPrice, 'Price should be updated.');
    }
    
    @isTest(SeeAllData=true)
    static void importProducts_MixedCreateAndUpdate_Success() {
        // Arrange: Create existing product ('P001')
        Id standardPbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
        
        Product2 existingProd = new Product2(
            Name = 'Old Name',
            External_Product_ID__c = 'P001',
            IsActive = true
        );
        insert existingProd;
        insert new PricebookEntry(
            Pricebook2Id = standardPbId,
            Product2Id = existingProd.Id,
            UnitPrice = 10.00,
            IsActive = true
        );

        // Arrange: Setup payload for 'P001' (update) and 'P002' (new)
        ProductImportController.ExternalProduct prodUpdate = new ProductImportController.ExternalProduct();
        prodUpdate.product_id = 'P001';
        prodUpdate.name = 'New Name';
        prodUpdate.price = 99.00;

        ProductImportController.ExternalProduct prodNew = new ProductImportController.ExternalProduct();
        prodNew.product_id = 'P002';
        prodNew.name = 'New Product';
        prodNew.price = 50.00;
        
        String productsJson = JSON.serialize(new List<ProductImportController.ExternalProduct>{prodUpdate, prodNew});

        // Act
        Test.startTest();
        ProductImportController.ImportResult result = ProductImportController.importProducts(productsJson);
        Test.stopTest();

        // Assert: Check the counts
        System.assertEquals(1, result.createdCount, 'Should create 1 new product.');
        System.assertEquals(1, result.updatedCount, 'Should update 1 existing product.');

        // Assert: Verify DB state
        Integer totalProds = [SELECT count() FROM Product2 WHERE External_Product_ID__c IN ('P001', 'P002')];
        System.assertEquals(2, totalProds, 'Should be 2 products in total in the DB.');

        Product2 updatedProd = [SELECT Name FROM Product2 WHERE External_Product_ID__c = 'P001'];
        System.assertEquals('New Name', updatedProd.Name, 'P001 name should be updated.');

        Product2 createdProd = [SELECT Name FROM Product2 WHERE External_Product_ID__c = 'P002'];
        System.assertEquals('New Product', createdProd.Name, 'P002 should be created.');
    }

    @isTest
    static void importProducts_BadJson() {
        // Arrange
        String badJson = '{"products": [ {"name": "Bad Product"} ]}'; // Not a List<ExternalProduct>

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
        Test.startTest();
        ProductImportController.ImportResult result = ProductImportController.importProducts(emptyJson);
        Test.stopTest();

        // Assert
        System.assertEquals(0, result.createdCount, 'Should create 0 products.');
        System.assertEquals(0, result.updatedCount, 'Should update 0 products.');
    }

    @isTest(SeeAllData=true) // Needs to see Standard Pricebook
    static void importProducts_FilteringInvalidData() {
        // Arrange
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

        ProductImportController.ExternalProduct prodNullExtId = new ProductImportController.ExternalProduct();
        prodNullExtId.product_id = null; // Invalid: Null External ID
        prodNullExtId.name = 'No Ext ID';
        prodNullExtId.price = 30.00;
        
        List<ProductImportController.ExternalProduct> products = new List<ProductImportController.ExternalProduct>{
            prodValid,
            prodBlankName, 
            prodNullPrice,
            prodNullExtId
        };
        String productsJson = JSON.serialize(products);

        // Act
        Test.startTest();
        ProductImportController.ImportResult result = ProductImportController.importProducts(productsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(1, result.createdCount, 'Only one product should be valid and created.');
        System.assertEquals(0, result.updatedCount, 'No products should be updated.');

        // Verify only the valid product was inserted
        List<Product2> insertedProducts = [SELECT Id, Name FROM Product2];
        System.assertEquals(1, insertedProducts.size(), 'Only one Product2 record should be created.');
        System.assertEquals('Valid Prod', insertedProducts[0].Name, 'The valid product should be the one inserted.');
    }
}