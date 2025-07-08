" REFINED SOLUTION: Better Exception Handling
" Replace the end of your method with this improved code:

" Prepare final response structure
TYPES: BEGIN OF ty_final_response,
         ZMATSet TYPE ty_items,
       END OF ty_final_response.
DATA: ls_final_response TYPE ty_final_response.
ls_final_response-ZMATSet = lt_result_data.

" ALWAYS set response data FIRST
copy_data_to_ref(
  EXPORTING
    is_data = ls_final_response
  CHANGING
    cr_data = er_deep_entity
).

" IMPROVED ERROR HANDLING for HTTP status
IF lv_any_error_occurred = abap_true.
  
  " Method A: Try with more specific exception details
  TRY.
      DATA(lx_exception) = NEW /iwbep/cx_mgw_busi_exception(
        textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        previous = NEW cx_sy_generic_error( )
      ).
      
      " Set specific error message
      lx_exception->if_message~set_text( 'Business validation errors occurred during material movement processing' ).
      
      RAISE EXCEPTION lx_exception.
      
    CATCH cx_root.
      " If Method A fails, use Method B
  ENDTRY.
  
  " Method B: Simple message-based exception
  MESSAGE e001(z_custom) WITH 'Business errors occurred' INTO DATA(lv_message_text).
  
  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
    EXPORTING
      message = 'Business validation errors occurred during material movement processing. Check response details for specific errors.'
      message_unlimited = 'One or more material movements failed validation or BAPI processing. Detailed error information is provided in the response body.'
      entity_type = 'Zheader'.
      
ENDIF.

ENDMETHOD.

" ALTERNATIVE APPROACH (if above still gives generic error):
" Replace the IF block with this version that doesn't raise exceptions:

" IF lv_any_error_occurred = abap_true.
"   " Don't raise exception - just let it return with the error data
"   " The response will contain Status = 'ERROR' which clients can check
"   " This ensures HTTP 201 but with clear error indication in response body
" ENDIF.