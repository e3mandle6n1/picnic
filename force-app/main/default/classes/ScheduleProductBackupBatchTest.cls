/**
 * @name ScheduleProductBackupBatchTest
 * @version 0.1
 * @author Emandleni M
 * @description A test class for the ScheduleProductBackupBatch.
 */
@isTest
private class ScheduleProductBackupBatchTest {

    @isTest
    static void testScheduleExecutesBatch() {
        Test.startTest();

        String cronExpression = '0 0 22 ? * *';
        String jobName = 'Test Product Backup';
        System.schedule(jobName, cronExpression, new ScheduleProductBackupBatch());

        Test.stopTest();

        List<AsyncApexJob> batchJobs = [SELECT Id, Status, ApexClass.Name
                                        FROM AsyncApexJob
                                        WHERE JobType = 'BatchApex'
                                        AND ApexClass.Name = 'ProductBackupBatch'];

        System.assertEquals(1, batchJobs.size(), 'A batch job should have been queued.');
        System.assertEquals('ProductBackupBatch', batchJobs[0].ApexClass.Name, 'The correct batch class should have been queued.');
    }
}