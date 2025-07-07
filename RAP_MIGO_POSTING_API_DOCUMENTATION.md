# RAP MIGO Posting API Documentation

## Overview

This document describes the RAP (RESTful ABAP Programming) service for MIGO (Material Movement) batch posting. This service replaces the traditional OData DPC_EXT approach with a modern RAP-based implementation while maintaining the same functionality and payload structure.

## Service Components

### 1. Data Definitions (CDS Views)

#### Interface Views
- **ZI_MIGO_BATCH_POSTING**: Root entity for batch posting requests
- **ZI_MIGO_ITEM**: Child entity for individual material movement items

#### Consumption Views  
- **ZC_MIGO_BATCH_POSTING**: Projection for external consumption
- **ZC_MIGO_ITEM**: Projection for material items

### 2. Behavior Definitions

#### ZI_MIGO_BATCH_POSTING.bdef
- Defines the `processMigoPosting` action for batch processing
- Manages composition relationship with items
- Handles deep entity operations

#### ZC_MIGO_BATCH_POSTING.bdef
- Projection behavior exposing actions to consumers
- Inherits operations from interface behavior

### 3. Service Definition & Binding

- **ZUI_MIGO_BATCH_POSTING_O4.srvd**: Service definition
- **ZUI_MIGO_BATCH_POSTING_O4.srvb**: OData V4 service binding

## API Structure

### Request Payload

The API accepts the same payload structure as the original DPC_EXT implementation:

```json
{
  "Header": "",
  "ZMATSet": [
    {
      "GrGiSlipNo": "A1",
      "ZtypeGm": "A07",
      "ZsubType": "R10",
      "Movementtype": "963",
      "DocDate": "/Date(1750099200000)/",
      "PstngDate": "/Date(1750099200000)/",
      "HeaderTxt": "Header GI999",
      "ItemNo": "01",
      "Material": "000000000050045454",
      "MatDesc": "HOSE, HIGH PRESSURE",
      "BaseUom": "EA",
      "Quantity": "1",
      "StrgLoc": "1080",
      "Plant": "4001",
      "GlAccount": "0043601400",
      "Costcenter": "0040010202",
      "OrderNo": "000000100736",
      "ItemOk": true
    }
  ]
}
```

### Response Structure

```json
{
  "Header": "",
  "ZMATSet": [
    {
      "GrGiSlipNo": "A1",
      "Status": "SUCCESS",
      "Message": "Document 5000000123 posted successfully.",
      "MigoDocNo": "5000000123",
      "ProcessedDate": "2024-12-19",
      "ProcessedTime": "14:30:25"
    }
  ]
}
```

## Business Logic Features

### 1. Grouping by GrGiSlipNo
- Items with the same `GrGiSlipNo` are processed together
- Each group creates one material document
- Validation is performed at group level

### 2. Validation Rules
- **Plant**: Must not be blank
- **GrGiSlipNo**: Must not be blank  
- **DocDate**: Must not be blank
- **PstngDate**: Must not be blank
- **Material**: Must not be blank
- **ItemOk**: Must be true

### 3. Date Conversion
- Supports JSON date format: `/Date(1750099200000)/`
- Converts Unix timestamps to ABAP dates
- Handles regular date formats as fallback

### 4. BAPI Integration
- Uses `BAPI_GOODSMVT_CREATE` for material movements
- Applies proper conversion exits (MATN1, ALPHA)
- Handles transaction commit/rollback

## Usage Examples

### 1. OData V4 Action Call

```http
POST /sap/opu/odata4/sap/zui_migo_batch_posting_o4/srvd_a2x/sap/migobatchposting/0001/MigoBatchPosting/processMigoPosting
Content-Type: application/json

{
  "Header": "",
  "_Items": [
    {
      "GrGiSlipNo": "A1",
      "ZtypeGm": "A07",
      "ZsubType": "R10",
      "Movementtype": "963",
      "DocDate": "/Date(1750099200000)/",
      "PstngDate": "/Date(1750099200000)/",
      "HeaderTxt": "Header GI999",
      "ItemNo": "01",
      "Material": "000000000050045454",
      "MatDesc": "HOSE, HIGH PRESSURE", 
      "BaseUom": "EA",
      "Quantity": "1",
      "StrgLoc": "1080",
      "Plant": "4001",
      "GlAccount": "0043601400",
      "Costcenter": "0040010202",
      "OrderNo": "000000100736",
      "ItemOk": true
    }
  ]
}
```

### 2. REST Handler Usage

Use the `ZCL_REST_MIGO_RAP_HANDLER` class for custom REST endpoints:

```http
POST /sap/bc/rest/zmigo_rap_posting
Content-Type: application/json

{
  "Header": "",
  "ZMATSet": [
    {
      "GrGiSlipNo": "A1",
      "ZtypeGm": "A07",
      "ZsubType": "R10",
      "Movementtype": "963",
      "DocDate": "/Date(1750099200000)/",
      "PstngDate": "/Date(1750099200000)/",
      "HeaderTxt": "Header GI999",
      "ItemNo": "01", 
      "Material": "000000000050045454",
      "MatDesc": "HOSE, HIGH PRESSURE",
      "BaseUom": "EA",
      "Quantity": "1",
      "StrgLoc": "1080",
      "Plant": "4001",
      "GlAccount": "0043601400",
      "Costcenter": "0040010202", 
      "OrderNo": "000000100736",
      "ItemOk": true
    }
  ]
}
```

### 3. Direct RAP Entity Usage

```abap
" Create deep entity
MODIFY ENTITIES OF ZI_MIGO_BATCH_POSTING
  ENTITY MigoBatchPosting
  CREATE FIELDS ( RequestId Header )
  WITH VALUE #( ( %cid = 'ROOT'
                  RequestId = lv_request_id
                  Header = lv_header ) )
  CREATE BY \_Items
  FIELDS ( RequestId ItemSequence GrGiSlipNo ZtypeGm ZsubType 
           Movementtype DocDate PstngDate HeaderTxt ItemNo Material 
           MatDesc BaseUom Quantity StrgLoc Plant GlAccount 
           Costcenter OrderNo ItemOk )
  WITH VALUE #( ( %cid_ref = 'ROOT'
                  %target = lt_items_create ) ).

" Execute processing action
MODIFY ENTITIES OF ZI_MIGO_BATCH_POSTING
  ENTITY MigoBatchPosting
  EXECUTE processMigoPosting
  FROM VALUE #( ( %cid_ref = 'ROOT' ) ).
```

## Error Handling

### 1. Validation Errors
- Returns detailed validation messages
- Groups all validation errors for a slip number
- Status: 'ERROR'

### 2. BAPI Errors  
- Captures BAPI return messages
- Performs automatic rollback on errors
- Returns BAPI error details

### 3. System Errors
- Handles date conversion errors
- Manages entity creation failures
- Provides meaningful error messages

## Migration from DPC_EXT

### Similarities
- **Same payload structure**: No changes to request/response format
- **Same business logic**: Identical validation and processing rules
- **Same BAPI calls**: Uses the same BAPI_GOODSMVT_CREATE
- **Same grouping logic**: Processes items by GrGiSlipNo

### Advantages of RAP
- **Modern framework**: Built on latest SAP technologies
- **Better performance**: Optimized entity processing
- **Type safety**: Strong typing with CDS views
- **Easier testing**: RAP framework provides testing capabilities
- **Standard patterns**: Follows SAP recommended practices

### Migration Steps
1. Deploy the RAP objects
2. Test with existing payloads
3. Update client applications to use new service endpoint
4. Retire old DPC_EXT service

## Technical Notes

### 1. Entity Keys
- RequestId: Unique identifier for each request
- ItemSequence: Sequential numbering for items

### 2. Dummy Tables
- Uses DUMMY_TABLE for development/testing
- Replace with actual persistence tables in production

### 3. Authorization
- Currently set to #NOT_REQUIRED for development
- Implement proper authorization in production

### 4. Conversion Exits
- MATN1: Material number conversion
- ALPHA: Leading zeros for accounts, cost centers, orders

## Support and Troubleshooting

### Common Issues
1. **Date format errors**: Ensure proper JSON date format
2. **Material not found**: Verify material exists in plant
3. **Movement type errors**: Check movement type configuration
4. **Authorization issues**: Verify BAPI authorization

### Debugging
- Use RAP development tools in ADT
- Enable BAPI logging for detailed error analysis
- Check entity creation in debugger

## Conclusion

The RAP MIGO Posting API provides a modern, robust alternative to traditional OData services while maintaining full compatibility with existing integrations. The service offers improved performance, better error handling, and follows SAP's recommended development patterns.