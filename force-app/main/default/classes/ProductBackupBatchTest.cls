/**
 * @name ProductBackupBatchTest
 * @version 0.1
 * @author Emandleni M
 * @description A test class for the ProductBackupBatch.
 */
@isTest
private class ProductBackupBatchTest {

    @isTest
    static void testBatchCreatesAndUpdatesBackups() {
        Test.loadData(Product2.sObjectType, 'TestProducts');
        
        Product2 product1 = [SELECT Id FROM Product2 WHERE Name = 'Organic Apples' LIMIT 1];
        Product2 product2 = [SELECT Id FROM Product2 WHERE Name = 'Carrots' LIMIT 1];

        Id standardPbId = Test.getStandardPricebookId();
        
        List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
        pbesToInsert.add(new PricebookEntry(
            Pricebook2Id = standardPbId, Product2Id = product1.Id, UnitPrice = 150.00, IsActive = true
        ));
        pbesToInsert.add(new PricebookEntry(
            Pricebook2Id = standardPbId, Product2Id = product2.Id, UnitPrice = 250.00, IsActive = true
        ));
        insert pbesToInsert;

        String idFilter = '(\'' + product1.Id + '\',\'' + product2.Id + '\')';
        
        Test.startTest();
        Database.executeBatch(new ProductBackupBatch(idFilter));
        Test.stopTest();

        Map<Id, ProductBackup__c> initialBackups = new Map<Id, ProductBackup__c>([
            SELECT Product_External_ID__c, Selling_Price__c FROM ProductBackup__c
        ]);
        
        System.assertEquals(2, initialBackups.size());
        System.assertEquals(150.00, initialBackups.get(product1.Id).Selling_Price__c);
        System.assertEquals(250.00, initialBackups.get(product2.Id).Selling_Price__c);

        PricebookEntry pbeToUpdate = [SELECT Id FROM PricebookEntry WHERE Product2Id = :product1.Id LIMIT 1];
        pbeToUpdate.UnitPrice = 999.00;
        update pbeToUpdate;
        
        Test.startTest();
        Database.executeBatch(new ProductBackupBatch(idFilter));
        Test.stopTest();
        
        System.assertEquals(2, [SELECT count() FROM ProductBackup__c]);
        
        ProductBackup__c updatedRecord = [SELECT Selling_Price__c FROM ProductBackup__c WHERE Product_External_ID__c = :product1.Id];
        
        System.assertEquals(999.00, updatedRecord.Selling_Price__c);
    }
}