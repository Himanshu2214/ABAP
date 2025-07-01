# MIGO Posting API Documentation

## Overview
This API allows you to post MIGO (Material Document) entries using SAP's BAPI_GOODSMVT_CREATE function module. The API is built using ABAP RESTful Application Programming (RAP) model and provides both RAP-based and direct REST endpoints.

## API Components

### 1. Core Classes
- **ZCL_MIGO_POSTING_IMPROVED**: Main business logic class that handles MIGO posting
- **ZCL_MIGO_BATCH_PROCESSOR**: Enhanced batch processor for high-volume processing (50+ records)
- **ZCL_REST_MIGO_POSTING**: REST endpoint handler class
- **ZBP_I_MIGO_POSTING**: RAP behavior implementation class

### 2. RAP Model Components
- **ZI_MIGO_POSTING.ddls**: Interface view for MIGO posting
- **ZC_MIGO_POSTING.ddls**: Consumption view for MIGO posting
- **ZI_MIGO_POSTING.bdef**: Behavior definition for interface view
- **ZC_MIGO_POSTING.bdef**: Behavior definition for consumption view
- **ZUI_MIGO_POSTING_O4.srvd**: Service definition
- **ZUI_MIGO_POSTING_O4.srvb**: Service binding

## Request Format

### JSON Payload Structure
```json
[
  {
    "ZtypeGm": "A007",
    "ZsubType": "R10", 
    "Movementtype": "963",
    "DocDate": "/Date(1750099200000)/",
    "PstngDate": "/Date(1750099200000)/",
    "GrGiSlipNo": "GI407",
    "HeaderTxt": "Text Header 1",
    "HeaderToItemNav": [
      {
        "Material": "50000001",
        "Plant": "1000",
        "StgeLoc": "0001",
        "EntryQnt": "10",
        "EntryUom": "EA"
      },
      {
        "Material": "50000002", 
        "Plant": "1000",
        "StgeLoc": "0001",
        "EntryQnt": "5",
        "EntryUom": "EA"
      }
    ]
  }
]
```

### Field Descriptions

#### Header Fields
- **ZtypeGm**: Movement type classification (custom field)
- **ZsubType**: Movement sub-type (custom field)
- **Movementtype**: SAP standard movement type (e.g., 963, 261, 101, 201)
- **DocDate**: Document date in OData format `/Date(timestamp)/`
- **PstngDate**: Posting date in OData format `/Date(timestamp)/`
- **GrGiSlipNo**: Goods Receipt/Goods Issue slip number (reference)
- **HeaderTxt**: Header text/description

#### Item Fields
- **Material**: Material number
- **Plant**: Plant code
- **StgeLoc**: Storage location
- **EntryQnt**: Quantity 
- **EntryUom**: Unit of measure

## Response Format

### Success Response
```json
[
  {
    "success": true,
    "materialDocument": "5000000123", 
    "message": "Material Document 5000000123 created successfully for GI407",
    "grgiSlipno": "GI407",
    "errors": []
  }
]
```

### Error Response
```json
[
  {
    "success": false,
    "materialDocument": "",
    "message": "Material 50000001 does not exist in plant 1000",
    "grgiSlipno": "GI407", 
    "errors": [
      "Material 50000001 does not exist in plant 1000",
      "Storage location 0001 not found"
    ]
  }
]
```

### Batch Processing Response (For High Volume)
```json
{
  "batchSummary": {
    "totalRecords": 50,
    "successfulCount": 48,
    "failedCount": 2,
    "totalItems": 150,
    "processingTime": "25.450 seconds",
    "startTime": "2024-01-15T10:30:00.000Z",
    "endTime": "2024-01-15T10:30:25.450Z"
  },
  "responses": [
    {
      "success": true,
      "materialDocument": "5000000123",
      "message": "Material Document 5000000123 created successfully for GI407",
      "grgiSlipno": "GI407",
      "processingTime": "0.250 sec",
      "itemCount": 3,
      "errors": []
    }
  ]
}
```

## Movement Type Configuration

The API supports various movement types with appropriate goods movement codes:

- **101**: Goods Receipt (GM Code: 01)
- **201**: Goods Issue for Cost Center (GM Code: 03)  
- **261**: Goods Issue for Production Order (GM Code: 03)
- **963**: Goods Issue (GM Code: 04) - Default

## Date Format Handling

The API handles OData date format `/Date(timestamp)/` where timestamp is milliseconds since Unix epoch (January 1, 1970). The timestamp is automatically converted to SAP internal date format (DATS).

Example: `/Date(1750099200000)/` represents a date in the future.

## Usage Examples

### 1. Direct Class Usage (Standard Processing)
```abap
DATA: lo_migo_api TYPE REF TO zcl_migo_posting_improved,
      lv_payload  TYPE string,
      lv_response TYPE string.

CREATE OBJECT lo_migo_api.
lv_response = lo_migo_api->post_migo( lv_payload ).
```

### 1b. High-Volume Batch Processing (50+ Records)
```abap
DATA: lo_batch_processor TYPE REF TO zcl_migo_batch_processor,
      lv_payload         TYPE string,
      lv_response        TYPE string,
      lv_batch_size      TYPE i VALUE 10.

CREATE OBJECT lo_batch_processor.
lv_response = lo_batch_processor->post_migo_batch( 
  iv_payload = lv_payload 
  iv_batch_size = lv_batch_size 
).
```

### 2. REST Endpoint Usage
```http
POST /sap/bc/rest/zcl_rest_migo_posting
Content-Type: application/json

[
  {
    "ZtypeGm": "A007",
    "ZsubType": "R10",
    "Movementtype": "963",
    "DocDate": "/Date(1750099200000)/",
    "PstngDate": "/Date(1750099200000)/", 
    "GrGiSlipNo": "GI407",
    "HeaderTxt": "Test Header",
    "HeaderToItemNav": [
      {
        "Material": "50000001",
        "Plant": "1000", 
        "StgeLoc": "0001",
        "EntryQnt": "10",
        "EntryUom": "EA"
      }
    ]
  }
]
```

### 3. RAP OData Service Usage
```http
POST /sap/opu/odata4/sap/zui_migo_posting_o4/srvd/sap/zui_migo_posting_o4/0001/MigoPosting/post_migo
Content-Type: application/json

{
  "payload": "[JSON_PAYLOAD_HERE]"
}
```

## Batch Processing for High Volume (50+ Records)

### Performance Optimizations
- **Chunked Processing**: Processes records in configurable batches (default: 10, max: 100)
- **Memory Management**: Commits after each chunk to prevent memory issues
- **Payload Validation**: Pre-validates payload size (max 50MB)
- **Individual Timing**: Tracks processing time per record and overall batch
- **Progress Logging**: Logs chunk completion for monitoring

### Batch Size Guidelines
- **1-10 records**: Use standard processing (`ZCL_MIGO_POSTING_IMPROVED`)
- **11-50 records**: Use batch processor with batch size 5-10
- **51-100 records**: Use batch processor with batch size 10-15
- **100+ records**: Split into multiple API calls or increase batch size to 20-25

### Response Structure for Batches
```json
{
  "batchSummary": {
    "totalRecords": 50,        // Total number of headers
    "successfulCount": 48,     // Successfully processed
    "failedCount": 2,          // Failed to process
    "totalItems": 150,         // Total line items across all headers
    "processingTime": "25.450 seconds",
    "startTime": "2024-01-15T10:30:00.000Z",
    "endTime": "2024-01-15T10:30:25.450Z"
  },
  "responses": [
    // Individual responses for each header
  ]
}
```

## Error Handling

The API implements comprehensive error handling:

1. **JSON Parsing Errors**: Invalid JSON format
2. **Validation Errors**: Missing required fields, invalid data types
3. **BAPI Errors**: Business logic errors from SAP
4. **System Errors**: Database, connectivity issues
5. **Batch Processing Errors**: Payload size, chunk processing failures

All errors are captured and returned in the response with descriptive messages.

## Security Considerations

1. **Authorization**: Implement proper authorization checks for movement types
2. **Validation**: Validate all input data before processing
3. **Logging**: Log all API calls for audit purposes
4. **Error Handling**: Don't expose internal system details in error messages

## Implementation Steps

1. **Create Classes**: Deploy all ABAP classes
2. **Create RAP Objects**: Deploy CDS views, behavior definitions
3. **Activate Service**: Activate service definition and binding
4. **Configure ICF**: Set up ICF node for REST endpoint (if needed)
5. **Test**: Test with sample payloads
6. **Monitor**: Set up monitoring and logging

## Testing

### Test Payload
Use the provided sample JSON with valid material numbers, plants, and storage locations from your SAP system.

### Validation Points
1. Material numbers exist and are active
2. Plants are configured and accessible
3. Storage locations exist in the specified plants  
4. Movement types are configured
5. User has proper authorizations

## Troubleshooting

### Common Issues
1. **Material not found**: Verify material number exists and is active
2. **Plant not found**: Check plant configuration 
3. **Storage location not found**: Verify storage location exists in plant
4. **Authorization missing**: Check user has MM02, MIGO authorizations
5. **Date conversion errors**: Verify OData date format

### Debug Points
1. Check BAPI return messages in `lt_return` table
2. Verify JSON deserialization in debugger
3. Check date conversion logic
4. Validate BAPI input parameters