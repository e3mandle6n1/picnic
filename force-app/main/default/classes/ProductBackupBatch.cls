/**
 * @name ProductBackupBatch
 * @version 0.1
 * @author Emandleni M
 * @description A batch class for backing up product data.
 */
public class ProductBackupBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, Name, Product_External_ID__c, ' +
            '(SELECT UnitPrice FROM PricebookEntries WHERE IsActive = true AND Pricebook2.IsStandard = true LIMIT 1) ' +
            'FROM Product2 WHERE IsActive = true'
        );
    }

    public void execute(Database.BatchableContext bc, List<Product2> scope) {
        List<ProductBackup__c> productBackupsToUpsert = new List<ProductBackup__c>();

        for (Product2 prod : scope) {
            // Default selling price to 0 if no active standard price book entry is found.
            Decimal sellingPrice = 0;
            if (prod.PricebookEntries != null && !prod.PricebookEntries.isEmpty()) {
                sellingPrice = prod.PricebookEntries[0].UnitPrice;
            }

            productBackupsToUpsert.add(new ProductBackup__c(
                Product_External_ID__c = prod.Product_External_ID__c,
                Name = prod.Name,
                Selling_Price__c = sellingPrice
            ));
        }

        if (!productBackupsToUpsert.isEmpty()) {
            upsert productBackupsToUpsert Product_External_ID__c;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('ProductBackupBatch has completed.');
    }
}