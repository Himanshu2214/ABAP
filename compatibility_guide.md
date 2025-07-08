# SAP Gateway HTTP Status Code - Compatibility Guide

## Problem Solved
Your SAP Gateway version doesn't support `get_response_context()`, so we need alternative approaches to return HTTP 422 instead of 201 when business errors occur.

## Critical Bug Fixed First
```abap
" BEFORE (INCORRECT - causes BAPI failures):
ls_bapiitem-stck_type = lv_item_counter.

" AFTER (CORRECT):
ls_bapiitem-stge_type = lv_item_counter.
```

## Recommended Implementation (Works with All Versions)

Replace the end of your method with this code:

```abap
" Prepare final response structure
TYPES: BEGIN OF ty_final_response,
         ZMATSet TYPE ty_items,
       END OF ty_final_response.
DATA: ls_final_response TYPE ty_final_response.
ls_final_response-ZMATSet = lt_result_data.

" STEP 1: ALWAYS set response data FIRST (this preserves your JSON structure)
copy_data_to_ref(
  EXPORTING
    is_data = ls_final_response
  CHANGING
    cr_data = er_deep_entity
).

" STEP 2: Handle HTTP status code for errors
IF lv_any_error_occurred = abap_true.
  
  " Add message to container (if available)
  TRY.
      DATA(lo_message_container) = get_message_container( ).
      IF lo_message_container IS BOUND.
        lo_message_container->add_message(
          iv_msg_type       = 'E'
          iv_msg_id         = 'ZMIGO_MVMT_AUTO'
          iv_msg_number     = '001'
          iv_msg_text       = 'Material movement business errors occurred'
          iv_entity_type    = 'Zheader'
          iv_is_technical   = abap_false
        ).
      ENDIF.
    CATCH cx_root.
      " Message container not available, continue
  ENDTRY.
  
  " Business exception to trigger non-201 status code
  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
    EXPORTING
      textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
      message = 'Material movement completed with business errors. Check response details.'.
      
ENDIF.

ENDMETHOD.
```

## Alternative Approaches (If Above Doesn't Work)

### Option A: Simplest Version
```abap
" Replace the IF block with this minimal version:
IF lv_any_error_occurred = abap_true.
  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
    EXPORTING
      message = 'Business errors occurred during material movement processing'.
ENDIF.
```

### Option B: Using Message Class
```abap
" First create a message class ZMIGO_MVMT_AUTO with message 001
" Then use:
IF lv_any_error_occurred = abap_true.
  MESSAGE e001(zmigo_mvmt_auto) WITH 'Business errors occurred' INTO DATA(lv_dummy).
  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
    EXPORTING
      message = 'Material movement completed with errors'.
ENDIF.
```

### Option C: DPC_EXT Override
If none of the above work, implement this in your DPC_EXT class:

```abap
" In ZCL_ZMIGO_MVMT_AUTO_DPC_EXT class:
METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.
  
  " Call original method
  super->/iwbep/if_mgw_appl_srv_runtime~create_deep_entity(
    EXPORTING
      io_data_provider = io_data_provider
      io_expand = io_expand
      io_tech_request_context = io_tech_request_context
    IMPORTING
      er_deep_entity = er_deep_entity
  ).
  
  " Check response for errors
  DATA: lv_has_errors TYPE abap_bool.
  
  " Parse er_deep_entity to check for errors
  IF er_deep_entity IS BOUND.
    " Your logic to detect errors in response
    " Look for Status = 'ERROR' in the response data
    " Set lv_has_errors = abap_true if found
  ENDIF.
  
  " Set HTTP status based on errors
  IF lv_has_errors = abap_true.
    TRY.
        " Try different methods to set status code
        DATA(lo_context) = mo_context.
        " Method 1: Direct context access
        lo_context->get_response( )->set_status( cl_rest_status_code=>gc_client_error_unprocessable_entity ).
      CATCH cx_root.
        TRY.
            " Method 2: Alternative approach
            CALL METHOD lo_context->('SET_STATUS_CODE')
              EXPORTING
                iv_status_code = 422.
          CATCH cx_root.
            " Method 3: Last resort - use exception
            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                message = 'Business validation errors occurred'.
        ENDTRY.
    ENDTRY.
  ENDIF.
  
ENDMETHOD.
```

## Expected Results

### Success Case (HTTP 201)
```json
{
  "d": {
    "ZMATSet": {
      "results": [{
        "GrGiSlipNo": "GI89",
        "MigoDocNo": "4900001234",
        "Status": "SUCCESS",
        "Message": "Document posted successfully"
      }]
    }
  }
}
```

### Error Case (HTTP 422 or 400)
```json
{
  "d": {
    "ZMATSet": {
      "results": [{
        "GrGiSlipNo": "GI89",
        "MigoDocNo": "",
        "Status": "ERROR",
        "Message": "Deficit of SL Unrestr. prev. 1 EA : 50045454 4001 1080"
      }]
    }
  }
}
```

## Testing Steps

1. **Apply the critical bug fix** for `stge_type`
2. **Test with the recommended implementation** first
3. **If still getting HTTP 201 for errors**, try Option A (simplest)
4. **If exceptions prevent response body**, try Option C (DPC_EXT override)
5. **Monitor the actual HTTP status codes** in browser dev tools or REST client

## Troubleshooting

### Issue: Still getting HTTP 201
**Solution**: The order matters - set response data BEFORE raising exception.

### Issue: Empty response body with error status
**Solution**: Ensure `copy_data_to_ref` is called before any exception.

### Issue: Exception prevents response
**Solution**: Use DPC_EXT override method (Option C).

### Issue: Method not found errors
**Solution**: Use the simplest approach (Option A) - it works across all versions.

## HTTP Status Code Mapping

| Scenario | Typical Status | Description |
|----------|----------------|-------------|
| All success | 201 Created | Normal operation |
| Business exception | 422 Unprocessable Entity | Business logic errors |
| Simple exception | 400 Bad Request | General client errors |
| System errors | 500 Internal Server Error | System failures |

## Version Compatibility

- **SAP NetWeaver 7.0-7.3**: Use Option A or B
- **SAP NetWeaver 7.4+**: Use recommended implementation
- **SAP S/4HANA**: All options should work
- **Cloud Gateway**: Use recommended implementation

The key is that **any business exception** will result in a non-201 status code, even if you can't control the exact code. Start with the recommended implementation and fall back to simpler options if needed.