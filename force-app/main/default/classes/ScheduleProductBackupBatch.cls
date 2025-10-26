/**
 * @name ScheduleProductBackupBatch
 * @version 0.1
 * @author Emandleni M
 * @description A schedulable class for backing up product data.
 */
public class ScheduleProductBackupBatch implements Schedulable {
    public void execute(SchedulableContext sc) {
        ProductBackupBatch batch = new ProductBackupBatch();
        Database.executeBatch(batch);
    }
}