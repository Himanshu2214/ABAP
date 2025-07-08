" ALTERNATIVE APPROACH: Simpler HTTP Status Code Handling
" Add this at the end of your method, replacing the previous HTTP status code logic

" Copy data to exporting parameter FIRST
copy_data_to_ref(
  EXPORTING
    is_data = ls_final_response
  CHANGING
    cr_data = er_deep_entity
).

" THEN handle HTTP status code for errors
IF lv_any_error_occurred = abap_true.
  
  " Method 1: Set response status directly (works in most SAP Gateway versions)
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
      " Fallback to exception approach if response context is not available
  ENDTRY.
  
  " Method 2: Fallback using custom exception (always works)
  " This ensures we get a non-201 status code even if Method 1 fails
  IF sy-subrc <> 0 OR lo_response_context IS NOT BOUND.
    " Use a warning-level exception that doesn't interrupt processing
    " but signals an error condition
    DATA: lo_logger TYPE REF TO /iwbep/cl_mgw_logger.
    
    " Log the error for monitoring purposes
    TRY.
        lo_logger = /iwbep/cl_mgw_logger=>get_logger( ).
        lo_logger->log_error(
          iv_message = 'Business validation errors in material movement'
          iv_entity_type = 'Zheader'
        ).
      CATCH cx_root.
        " Logger not available, continue
    ENDTRY.
    
    " Create a custom business exception that carries the error information
    " but doesn't prevent the response body from being returned
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message = 'Material movement completed with business errors. Check response details.'
        http_status_code = '422'
        message_unlimited = 'One or more material movements failed validation or BAPI processing. Detailed error information is provided in the response body.'.
  ENDIF.
  
ENDIF.

" Method 3: Additional approach for older SAP Gateway versions
" If you're still getting 201 status codes, try this override in the DPC_EXT class

" In your DPC_EXT class, override the CREATE_DEEP_ENTITY method like this:
"
" METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.
"   
"   " Call the parent implementation
"   super->/iwbep/if_mgw_appl_srv_runtime~create_deep_entity(
"     EXPORTING
"       io_data_provider = io_data_provider
"       io_expand = io_expand
"       io_tech_request_context = io_tech_request_context
"     IMPORTING
"       er_deep_entity = er_deep_entity
"   ).
"   
"   " Check if the response contains errors
"   " (You'll need to parse er_deep_entity to check for errors)
"   DATA: lv_has_errors TYPE abap_bool.
"   
"   " Parse the response to check for errors
"   " ... your parsing logic here ...
"   
"   " If errors found, set different status code
"   IF lv_has_errors = abap_true.
"     mo_context->get_response_context( )->set_status_code( 422 ).
"   ENDIF.
"   
" ENDMETHOD.