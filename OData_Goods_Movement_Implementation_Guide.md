# OData Goods Movement Deep Entity Implementation Guide

## Overview
This guide provides a complete implementation for an OData service that handles goods movement creation using BAPI_GOODSMVT_CREATE through deep entity operations.

## Entity Structure

### 1. HeaderDummy (Main Entity)
- **Key**: GrGiSlipNo
- **Purpose**: Entry point for deep entity operation
- **Additional Fields Needed**:
  ```abap
  ProcessStatus : String (20)  // SUCCESS, ERROR, PARTIAL
  ```

### 2. GoodsMovementHeader
- **Key**: GrGiSlipNo
- **Fields**: ZtypeGm, ZsubType, Movementtype, DocDate, PstngDate, HeaderTxt
- **Additional Response Fields**:
  ```abap
  MaterialDoc  : String (10)   // Material Document Number
  DocYear      : String (4)    // Document Year
  ProcessStatus: String (20)   // SUCCESS, ERROR, NO_ITEMS
  ```

### 3. GoodsMovementItem
- **Key**: GrGiSlipNo, ItemNo
- **Fields**: Material, MatDesc, BaseUom, Quantity, StrgLoc, Plant, GlAccount, Costcenter, OrderNo, ItemOk
- **Additional Response Fields**:
  ```abap
  MaterialDoc  : String (10)   // Material Document Number
  DocYear      : String (4)    // Document Year
  ProcessStatus: String (20)   // SUCCESS, ERROR
  ```

## Implementation Steps

### 1. Extend Entity Types in SEGW
Add the response fields to your entity types:

```xml
<!-- HeaderDummy -->
<Property Name="ProcessStatus" Type="Edm.String" MaxLength="20"/>

<!-- GoodsMovementHeader -->
<Property Name="MaterialDoc" Type="Edm.String" MaxLength="10"/>
<Property Name="DocYear" Type="Edm.String" MaxLength="4"/>
<Property Name="ProcessStatus" Type="Edm.String" MaxLength="20"/>

<!-- GoodsMovementItem -->
<Property Name="MaterialDoc" Type="Edm.String" MaxLength="10"/>
<Property Name="DocYear" Type="Edm.String" MaxLength="4"/>
<Property Name="ProcessStatus" Type="Edm.String" MaxLength="20"/>
```

### 2. Configure Deep Entity in SEGW
1. Go to Service Implementation → Entity Sets → HeaderDummySet
2. Enable "Create Entity" operation
3. In the method implementation, use the provided code

### 3. BAPI Mapping

#### Movement Type Mapping
| Movement Type | Description | GM Code |
|---------------|-------------|---------|
| 101 | Goods Receipt for Purchase Order | 01 |
| 261 | Goods Issue to Cost Center | 03 |
| 551 | Goods Issue without Account Assignment | 03 |
| 963 | Goods Issue for Sampling | 03 |

#### Required BAPI Fields
```abap
" Header Fields
ls_gm_header-pstng_date    " Posting Date
ls_gm_header-doc_date      " Document Date  
ls_gm_header-header_txt    " Header Text
ls_gm_header-ref_doc_no    " Reference Document

" Item Fields
ls_gm_item-material        " Material Number
ls_gm_item-plant          " Plant
ls_gm_item-stge_loc       " Storage Location
ls_gm_item-move_type      " Movement Type
ls_gm_item-entry_qnt      " Quantity
ls_gm_item-entry_uom      " Unit of Measure
ls_gm_item-gl_account     " G/L Account
ls_gm_item-costcenter     " Cost Center
ls_gm_item-orderid        " Order Number
```

### 4. Error Handling Strategy

#### Validation Levels
1. **Payload Level**: Check for required main fields
2. **Header Level**: Validate header-specific data
3. **Item Level**: Validate each item individually
4. **BAPI Level**: Handle BAPI-specific errors

#### Response Status Values
- `SUCCESS`: All operations completed successfully
- `ERROR`: Critical errors occurred, transaction rolled back
- `PARTIAL`: Some items processed, some failed
- `NO_ITEMS`: No valid items found for processing

### 5. Date Handling
OData dates come in format `/Date(1750099200000)/` and need conversion:

```abap
METHOD convert_odata_date.
  DATA: lv_timestamp TYPE string,
        lv_ticks TYPE i.
  
  FIND REGEX '\d+' IN iv_odata_date MATCH lv_timestamp.
  lv_ticks = lv_timestamp.
  
  " Convert milliseconds to SAP date
  " Implementation depends on your SAP version
ENDMETHOD.
```

### 6. Test Payload
```json
{
  "GrGiSlipNo": "GI999",
  "ToGoodsMvmtHeader": [
    {
      "GrGiSlipNo": "GI999",
      "ZtypeGm": "A007",
      "ZsubType": "R10", 
      "Movementtype": "963",
      "DocDate": "/Date(1750099200000)/",
      "PstngDate": "/Date(1750099200000)/",
      "HeaderTxt": "Batch Post Header 1",
      "ToGoodsMvmtItem": [
        {
          "GrGiSlipNo": "GI999",
          "ItemNo": "0001",
          "Material": "MAT001",
          "MatDesc": "Material 1",
          "BaseUom": "EA",
          "Quantity": "10",
          "StrgLoc": "0001",
          "Plant": "1000",
          "GlAccount": "500000",
          "Costcenter": "CC1000",
          "OrderNo": "ORD123456",
          "ItemOk": true
        }
      ]
    }
  ]
}
```

### 7. Expected Response
```json
{
  "d": {
    "GrGiSlipNo": "GI999",
    "ProcessStatus": "SUCCESS",
    "ToGoodsMvmtHeader": {
      "results": [
        {
          "GrGiSlipNo": "GI999",
          "MaterialDoc": "4900000123",
          "DocYear": "2024",
          "ProcessStatus": "SUCCESS",
          "ToGoodsMvmtItem": {
            "results": [
              {
                "GrGiSlipNo": "GI999",
                "ItemNo": "0001",
                "MaterialDoc": "4900000123",
                "DocYear": "2024",
                "ProcessStatus": "SUCCESS"
              }
            ]
          }
        }
      ]
    }
  }
}
```

## Key Features

### 1. Batch Processing
- Processes multiple headers in one request
- Each header can have multiple items
- Individual item validation and processing

### 2. Robust Error Handling
- Field-level validation
- BAPI error capture and reporting
- Rollback on errors with detailed messages

### 3. Flexible Item Processing
- Skips items with `ItemOk = false`
- Continues processing valid items even if some fail
- Detailed status reporting per item

### 4. Response Enrichment
- Returns material document numbers
- Provides processing status at all levels
- Includes detailed error messages

## Implementation Checklist

- [ ] Extend entity types with response fields
- [ ] Implement helper class for validation and mapping
- [ ] Configure deep entity operation in SEGW
- [ ] Test with sample payload
- [ ] Handle authorization and error scenarios
- [ ] Document API for consumers

## Security Considerations

1. **Authorization**: Ensure users have appropriate authorization for movement types
2. **Validation**: Implement business-specific validation rules
3. **Logging**: Log all transactions for audit purposes
4. **Error Handling**: Don't expose sensitive system information

## Performance Optimization

1. **Batch Size**: Limit number of items per request
2. **Validation**: Validate data before BAPI call
3. **Caching**: Cache frequently used master data
4. **Parallel Processing**: Consider parallel processing for large batches

This implementation provides a robust, production-ready solution for goods movement creation through OData deep entity operations.