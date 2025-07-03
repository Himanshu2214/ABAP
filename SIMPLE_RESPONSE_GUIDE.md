# Simple Response Guide

## Simplified Implementation

The optimized code now processes **single records only** and returns **simple JSON responses**.

## Actual JSON Response Structure

Based on your OData model structure, the actual JSON responses will be:

### ✅ SUCCESS Response
```json
{
  "gr_gi_slip_no": "GI602",
  "mat_doc_num": "4900001234",
  "header_txt": "",
  "movementtype": "",
  "doc_date": "",
  "pstng_date": "", 
  "ztype_gm": "",
  "GoodsMvtItemSet": []
}
```

### ❌ ERROR Response  
```json
{
  "gr_gi_slip_no": "GI602", 
  "mat_doc_num": "Error: Material not extended to Plant 4002/Sloc 1081",
  "header_txt": "",
  "movementtype": "",
  "doc_date": "",
  "pstng_date": "",
  "ztype_gm": "",
  "GoodsMvtItemSet": []
}
```

## If You Want Exact Format You Specified

If you need the exact JSON format you mentioned:
```json
// Success
{
  "GrGiSlipNo": "GI602",
  "MatDocNum": "4900001234"
}

// Error
{
  "GrGiSlipNo": "GI602",
  "Error": "Material not extended to Plant 4002/Sloc 1081"
}
```

**You would need to modify your OData model to have:**
- Field names in PascalCase: `GrGiSlipNo`, `MatDocNum`, `Error`
- Only include the fields you want in the response

## Current Implementation Features

✅ **Single Record Processing** - Processes exactly 1 item per call
✅ **Simple Error Handling** - Returns error message in `mat_doc_num` field  
✅ **Clean Success Response** - Returns material document number
✅ **No Complex Batch Logic** - Simplified for single item processing
✅ **Proper BAPI Error Handling** - Captures and returns business errors

## Error Types Handled

1. **Validation Errors**
   - Missing material, plant, or quantity
   - Returns: `"Error: Material is required"`

2. **Business Logic Errors** 
   - Material not extended to plant/storage location
   - Returns: `"Error: Material not extended to Plant 4002/Sloc 1081"`

3. **Technical Errors**
   - BAPI communication failures
   - Returns: `"Error: BAPI Communication Failure"`

## Sample Request Structure

```json
{
  "gr_gi_slip_no": "GI602",
  "header_txt": "Test Movement",
  "movementtype": "101", 
  "doc_date": "2024-01-15",
  "pstng_date": "2024-01-15",
  "ztype_gm": "01",
  "GoodsMvtItemSet": [
    {
      "MATERIAL": "000000000050045456",
      "PLANT": "4002",
      "STRG_LOC": "1081", 
      "QUANTITY": 1,
      "BASE_UOM": "EA",
      "ITEM_NO": "000001"
    }
  ]
}
```

The simplified implementation eliminates the complex batch processing and status tracking, focusing on clean single-record processing with simple success/error responses.