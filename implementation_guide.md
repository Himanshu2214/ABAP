# SAP OData Material Movement - HTTP Status Code Implementation Guide

## Overview
This guide shows how to modify your ABAP OData method to return appropriate HTTP status codes (422 instead of 201) when business errors occur, while still providing the structured error response.

## Key Changes Made

### 1. Critical Bug Fix
**Fixed line item field mapping in BAPI call:**
```abap
" BEFORE (INCORRECT):
ls_bapiitem-stck_type = lv_item_counter.

" AFTER (CORRECT):
ls_bapiitem-stge_type = lv_item_counter.
```

### 2. Enhanced Validations
Added missing business validations:
```abap
" Validate quantity
IF ls_check-quantity <= 0.
  lv_return-type = 'E'.
  lv_return-message = |Quantity must be greater than zero for item { ls_check-itemno }|.
  APPEND lv_return TO lt_bapi_error_messages.
  lv_validation_failed = abap_true.
ENDIF.

" Validate movement type
IF ls_check-movementtype IS INITIAL.
  lv_return-type = 'E'.
  lv_return-message = |Movement type is required for item { ls_check-itemno }|.
  APPEND lv_return TO lt_bapi_error_messages.
  lv_validation_failed = abap_true.
ENDIF.
```

### 3. HTTP Status Code Implementation

## Implementation Options

### Option 1: Response Context Method (Recommended)
```abap
" Copy data to exporting parameter FIRST
copy_data_to_ref(
  EXPORTING
    is_data = ls_final_response
  CHANGING
    cr_data = er_deep_entity
).

" THEN set HTTP status code
IF lv_any_error_occurred = abap_true.
  TRY.
      DATA(lo_response_context) = mo_context->get_response_context( ).
      IF lo_response_context IS BOUND.
        lo_response_context->set_status_code( 422 ). " Unprocessable Entity
        lo_response_context->set_header(
          iv_name = 'Content-Type'
          iv_value = 'application/json;charset=utf-8'
        ).
      ENDIF.
    CATCH cx_root.
      " Continue with fallback approach
  ENDTRY.
ENDIF.
```

### Option 2: Business Exception with HTTP Status
```abap
IF lv_any_error_occurred = abap_true.
  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
    EXPORTING
      textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
      message = 'Material movement completed with business errors'
      http_status_code = '422'
      message_unlimited = 'Detailed error information is in the response body'.
ENDIF.
```

### Option 3: DPC_EXT Override (For Complex Cases)
If the above methods don't work, override in your DPC_EXT class:

```abap
METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.
  
  " Call the original method
  super->/iwbep/if_mgw_appl_srv_runtime~create_deep_entity(
    EXPORTING
      io_data_provider = io_data_provider
      io_expand = io_expand
      io_tech_request_context = io_tech_request_context
    IMPORTING
      er_deep_entity = er_deep_entity
  ).
  
  " Parse response to check for errors
  DATA: lv_has_errors TYPE abap_bool.
  
  " Check if response contains error status
  " (Parse er_deep_entity to look for Status = 'ERROR')
  IF er_deep_entity IS BOUND.
    " Your logic to check for errors in the response
    " Set lv_has_errors = abap_true if errors found
  ENDIF.
  
  " Set appropriate HTTP status code
  IF lv_has_errors = abap_true.
    mo_context->get_response_context( )->set_status_code( 422 ).
  ENDIF.
  
ENDMETHOD.
```

## Expected Response Structure

With these changes, when BAPI errors occur, you'll get:

**HTTP Status Code:** 422 Unprocessable Entity

**Response Body:**
```json
{
  "d": {
    "__metadata": {
      "id": "http://devs4.gulbrandsen.com:8000/sap/opu/odata/sap/ZMIGO_MVMT_AUTO_SRV/ZheaderSet('')",
      "uri": "http://devs4.gulbrandsen.com:8000/sap/opu/odata/sap/ZMIGO_MVMT_AUTO_SRV/ZheaderSet('')",
      "type": "ZMIGO_MVMT_AUTO_SRV.Zheader"
    },
    "Header": "",
    "ZMATSet": {
      "results": [
        {
          "__metadata": {
            "id": "http://devs4.gulbrandsen.com:8000/sap/opu/odata/sap/ZMIGO_MVMT_AUTO_SRV/ZMATSet('GI89')",
            "uri": "http://devs4.gulbrandsen.com:8000/sap/opu/odata/sap/ZMIGO_MVMT_AUTO_SRV/ZMATSet('GI89')",
            "type": "ZMIGO_MVMT_AUTO_SRV.ZMAT"
          },
          "GrGiSlipNo": "GI89",
          "MigoDocNo": "",
          "Status": "ERROR",
          "Message": "Deficit of SL Unrestr. prev. 1 EA : 50045454 4001 1080"
        }
      ]
    }
  }
}
```

## HTTP Status Code Guidelines

| Scenario | HTTP Status | Description |
|----------|-------------|-------------|
| All movements successful | 201 Created | Standard creation success |
| Validation errors | 422 Unprocessable Entity | Business validation failed |
| BAPI errors (insufficient stock, etc.) | 422 Unprocessable Entity | Business logic errors |
| System errors | 500 Internal Server Error | Unexpected system failures |
| Authentication issues | 401 Unauthorized | Security violations |

## Implementation Steps

1. **Apply the bug fix** for `stge_type` field mapping
2. **Add enhanced validations** for quantity and movement type
3. **Implement HTTP status code logic** using Option 1 (Response Context)
4. **Test with various scenarios** to ensure proper status codes
5. **If Option 1 doesn't work**, try Option 2 (Business Exception)
6. **As last resort**, implement Option 3 (DPC_EXT Override)

## Testing Scenarios

### Test Case 1: Insufficient Stock
- **Input:** Movement type 963 with quantity exceeding available stock
- **Expected:** HTTP 422 + Error message in response body

### Test Case 2: Missing Required Fields
- **Input:** Empty plant or material fields
- **Expected:** HTTP 422 + Validation error messages

### Test Case 3: Successful Movement
- **Input:** Valid data with sufficient stock
- **Expected:** HTTP 201 + Success message with document number

### Test Case 4: Mixed Results
- **Input:** Multiple slips with some successful, some failed
- **Expected:** HTTP 422 + Mixed success/error status in response

## Troubleshooting

### Issue: Still getting HTTP 201 for errors
**Solution:** Check the order of operations:
1. Set response data FIRST
2. Set HTTP status code SECOND
3. Ensure `lv_any_error_occurred` is properly set

### Issue: Response body is empty with error status
**Solution:** Make sure `copy_data_to_ref` is called BEFORE setting error status

### Issue: Method not available
**Solution:** Check SAP Gateway version and use appropriate alternative method

## Monitoring and Logging

Add logging for production monitoring:
```abap
" Log errors for monitoring
IF lv_any_error_occurred = abap_true.
  TRY.
      DATA(lo_logger) = /iwbep/cl_mgw_logger=>get_logger( ).
      lo_logger->log_error(
        iv_message = |Material movement errors for { lines( lt_result_data ) } items|
        iv_entity_type = 'Zheader'
      ).
    CATCH cx_root.
      " Logger not available, continue
  ENDTRY.
ENDIF.
```

This implementation ensures proper HTTP status codes while maintaining the structured error response format your client applications expect.