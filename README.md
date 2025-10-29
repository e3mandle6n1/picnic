# Product Import & Backup System

A comprehensive Salesforce solution for importing products from external APIs and managing automated product data backups. This system features a modern Lightning Web Component frontend and robust batch processing backend.

[![Salesforce Platform](https://img.shields.io/badge/Platform-Salesforce%20Winter%20'26-blue.svg?logo=salesforce&logoColor=white)](https://www.salesforce.com/platform/)
[![Apex](https://img.shields.io/badge/Apex-v64.0-blue.svg?logo=salesforce&logoColor=white)](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/)
[![Salesforce DX](https://img.shields.io/badge/CLI-v2.108.6-blue.svg?logo=salesforce&logoColor=white)](https://developer.salesforce.com/tools/sfdxcli)
[![JSON](https://img.shields.io/badge/JSON-000?logo=json&logoColor=fff)](#)
[![Node.js](https://img.shields.io/badge/Node.js-6DA55F?logo=node.js&logoColor=white)](#)

## 📋 Overview

This project implements a complete product lifecycle management system that:
- Imports products from an external AWS S3-hosted API
- Provides an intuitive user interface for product browsing and selection
- Implements smart duplicate prevention using external ID matching
- Maintains automated product data backups via scheduled batch processing
- Ensures data integrity with comprehensive validation and error handling

## 🏗️ Architecture

### Frontend Components (Lightning Web Components)
- **Product Importer**: Main interface for browsing, selecting, and importing products
- **Inline Modal**: Product detail viewing with rich information display
- **Real-time Feedback**: Dynamic import results with created/updated counts

### Backend Processing (Apex)
- **Product Import Controller**: Handles API integration and product upsert operations
- **Batch Processing**: Automated product backup system with scheduling
- **Data Models**: Custom objects and fields for external system integration

### External Integration
- **AWS S3 API**: Product data source with list and detail endpoints
- **Remote Site Settings**: Secure external API communication
- **HTTP Callout Framework**: Robust error handling and timeout management

## 🚀 Key Features

### Smart Product Import
- **Duplicate Prevention**: Upsert functionality using `External_Product_ID__c`
- **Batch Processing**: Efficient handling of multiple product selections
- **Price Synchronization**: Automatic PricebookEntry management
- **Input Validation**: Comprehensive data sanitization and null checking

### User Experience
- **Debounced Search**: Performance-optimised filtering (3+ character requirement)
- **Multi-select Interface**: Intuitive checkbox-based product selection
- **Loading States**: Visual feedback during API operations
- **Toast Notifications**: Detailed success/error messaging with specific counts

### Automated Backup System
- **Scheduled Processing**: Twice-daily batch execution (09:41 and 23:43)
- **Data Snapshots**: ProductBackup__c records with current product state
- **Unique Constraints**: Exactly one backup record per product guarantee
- **Price Tracking**: Historical selling price preservation

## 📁 Project Structure

```
force-app/main/default/
├── classes/
│   ├── ProductImportController.cls              # Main API integration controller
│   ├── ProductImportControllerTest.cls          # Comprehensive test coverage
│   ├── ProductBackupBatch.cls                   # Automated backup processing
│   ├── ProductBackupBatchTest.cls               # Batch processing tests
│   ├── ScheduleProductBackupBatch.cls           # Scheduler implementation
│   └── ScheduleProductBackupBatchTest.cls       # Scheduler tests
├── lwc/
│   └── productImporter/                         # Main LWC component
│       ├── productImporter.html                 # Template with modal
│       ├── productImporter.js                   # Controller logic
│       ├── productImporter.css                  # Responsive styling
│       └── __tests__/                           # Jest test framework
├── objects/
│   ├── Product2/                                # Enhanced standard object
│   │   └── fields/External_Product_ID__c        # Custom external ID field
│   └── ProductBackup__c/                        # Custom backup object
│       └── fields/                              # Backup-specific fields
├── layouts/
│   ├── Product2-Product Layout.layout-meta.xml  # Product record layout
│   └── ProductBackup__c-Product Backup Layout   # Backup record layout
└── remoteSiteSettings/
    └── PicnicDeveloperApplicationTest.remoteSite # AWS S3 API access
```

## 🛠️ Installation & Setup

### Prerequisites
- Salesforce org with API access
- Standard Pricebook activated
- Custom object deployment permissions

### Deployment Steps

1. **Clone and Deploy**
   ```bash
   git clone https://github.com/e3mandle6n1/picnic.git
   sf project deploy start --source-dir force-app/
   ```

2. **Configure Remote Site Settings**
   - Verify `PicnicDeveloperApplicationTest` remote site is active
   - URL: `https://s3-eu-west-1.amazonaws.com`

3. **Set Up Scheduled Jobs**
   ```apex
   // Execute in Developer Console
   String cronExp09 = '0 41 9 * * ?';  // 09:41 daily
   String cronExp23 = '0 43 23 * * ?'; // 23:43 daily
   
   System.schedule('Product Backup Morning', cronExp09, new ScheduleProductBackupBatch());
   System.schedule('Product Backup Evening', cronExp23, new ScheduleProductBackupBatch());
   ```

4. **Add Component to Lightning Pages**
   - Navigate to Lightning App Builder
   - Add `productImporter` component to desired pages
   - Available targets: App Pages, Record Pages, Home Pages

## 🔧 Configuration

### API Endpoints
```apex
// ProductImportController.cls
private static final String LIST_ENDPOINT = 
    'https://s3-eu-west-1.amazonaws.com/developer-application-test/cart/list';
private static final String DETAIL_BASE_ENDPOINT = 
    'https://s3-eu-west-1.amazonaws.com/developer-application-test/cart/';
```

### Custom Fields

#### Product2.External_Product_ID__c
- **Type**: Text(18)
- **Properties**: External ID, Unique
- **Purpose**: Links imported products with external system

#### ProductBackup__c Fields
- **Product_External_ID__c**: External ID for product linking
- **Name__c**: Product name snapshot
- **Selling_Price__c**: Price at backup time

## 🧪 Testing

### Apex Test Coverage
- **ProductImportControllerTest**: HTTP mocking and upsert scenarios
- **ProductBackupBatchTest**: Batch processing validation
- **ScheduleProductBackupBatchTest**: Scheduler functionality

### Running Tests
```bash
# Run all tests
sf apex run test --test-level RunAllTestsInOrg --synchronous

# Run specific test class
sf apex run test --tests ProductImportControllerTest --synchronous

# Generate coverage report
sf apex run test --code-coverage --result-format human
```

<img width="957" height="381" alt="Screenshot 2025-10-29 at 08 00 50" src="https://github.com/user-attachments/assets/b90dcce6-8537-41d9-86ae-83561d910bdb" />


## 📊 Data Flow

### Import Process
1. **Product Discovery**: User browses external API products
2. **Selection**: Multi-select interface for bulk operations  
3. **Validation**: Input sanitization and duplicate checking
4. **Upsert**: Create new or update existing Product2 records
5. **Price Management**: Automatic PricebookEntry synchronization
6. **Feedback**: Detailed success/error reporting

### Backup Process
1. **Schedule Trigger**: Automated execution twice daily
2. **Product Query**: All active Product2 records with prices
3. **Data Mapping**: External ID to ProductBackup__c relationship
4. **Upsert Operation**: Maintain exactly one backup per product
5. **Completion**: Debug logging and error handling

## 🔍 API Integration

### External Product API
- **List Endpoint**: Returns paginated product catalog
- **Detail Endpoint**: Provides comprehensive product information
- **Authentication**: Open API (no authentication required)
- **Rate Limiting**: Handled via 60-second timeouts
- **Error Handling**: Comprehensive HTTP status code management

### Response Format
```json
{
  "products": [
    {
      "product_id": "unique_identifier",
      "name": "Product Name",
      "price": 29.99,
      "image": "https://example.com/image.jpg",
      "description": "Detailed product description"
    }
  ]
}
```

### Advanced JSON Handling
For more complex or verbose JSON payloads, this solution can benefit from the [Apex JPath](https://github.com/e3mandle6n1/apex-jpath) unlocked package - a comprehensive library for handling dynamic JSON data within the Salesforce Apex environment. This library provides powerful JSON traversal capabilities for scenarios requiring advanced data extraction and manipulation.

## 🚦 Error Handling

### Frontend
- **Network Errors**: Toast notifications with retry guidance
- **Validation Errors**: Real-time field-level feedback
- **Loading States**: Spinner indicators during operations
- **Empty States**: Graceful handling of no-data scenarios

### Backend  
- **HTTP Failures**: Comprehensive status code handling
- **JSON Parsing**: Malformed response validation
- **DML Exceptions**: Database operation error recovery
- **Batch Failures**: Individual record error isolation

## 📈 Performance Optimisation

### Caching Strategy
- **@AuraEnabled(cacheable=true)**: Product list caching
- **Wire Service**: Automatic LWC data management
- **Debounced Search**: Reduced API call frequency

### Bulk Operations
- **Batch Processing**: Efficient large dataset handling
- **Upsert Operations**: Minimize database round trips
- **Set-based Queries**: Avoid SOQL in loops

## 🔒 Security Considerations

### Data Protection
- **Input Sanitization**: EncodingUtil.urlEncode for API parameters
- **SOQL Injection Prevention**: Parameterized queries
- **Cross-Site Scripting**: Lightning platform built-in protection

### API Security
- **Remote Site Settings**: Whitelist external endpoints
- **HTTPS Enforcement**: Secure communication protocols
- **Timeout Management**: Prevent indefinite hanging requests

## 📋 Maintenance

### Monitoring
- **Debug Logs**: Comprehensive logging throughout application
- **Batch Job Monitoring**: AsyncApexJob status tracking
- **Error Reporting**: Centralized exception handling

### Regular Tasks
- **Backup Verification**: Periodic ProductBackup__c data validation
- **API Health Checks**: External endpoint availability monitoring
- **Performance Review**: Query optimization and bulk limits

## 🖥️ Screenshots

<img width="1656" height="791" alt="Screenshot 2025-10-29 at 08 16 55" src="https://github.com/user-attachments/assets/e27fe509-b98c-4c22-aa72-dedea56f1d56" />

</br>

<img width="726" height="414" alt="Screenshot 2025-10-29 at 08 17 19" src="https://github.com/user-attachments/assets/32354d84-cbf0-4bad-9326-78c397137b32" />

### Development Setup
```bash
# Install dependencies
npm install

# Run linting
npm run lint

# Format code  
npm run prettier

# Pre-commit hooks
npm run precommit
```

### Code Standards
- **Apex**: Salesforce naming conventions and best practices
- **LWC**: Lightning Web Components style guide
- **Testing**: Minimum 90% code coverage 
- **Documentation**: Comprehensive inline comments

## 📝 License

None

## 👥 Support

For technical support or questions:
- Review debug logs in Developer Console
- Check batch job execution history
- Validate remote site settings configuration
- Verify standard pricebook activation

---

**Version**: 1.0.0  
**Last Updated**: October 2025  
**Salesforce API Version**: 65.0