" SIMPLE ALTERNATIVE: Replace the end of your method with this

" Prepare final response structure
TYPES: BEGIN OF ty_final_response,
         ZMATSet TYPE ty_items,
       END OF ty_final_response.
DATA: ls_final_response TYPE ty_final_response.
ls_final_response-ZMATSet = lt_result_data.

" ALWAYS set the response data first
copy_data_to_ref(
  EXPORTING
    is_data = ls_final_response
  CHANGING
    cr_data = er_deep_entity
).

" SIMPLE APPROACH: Use message container to set HTTP status
IF lv_any_error_occurred = abap_true.
  
  " Method 1: Add error message to message container
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
      " Message container not available, continue with fallback
  ENDTRY.
  
  " Method 2: Fallback using simple business exception
  " This will typically result in HTTP 400 or 422 depending on Gateway version
  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
    EXPORTING
      textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
      message = 'Material movement processing completed with business errors. See response details.'.
      
ENDIF.

" ALTERNATIVE SIMPLE METHOD (if above doesn't work):
" Replace the entire IF block above with this even simpler version:

" IF lv_any_error_occurred = abap_true.
"   
"   " Add application error to message container
"   MESSAGE e001(zmigo_mvmt_auto) WITH 'Business errors occurred' INTO DATA(lv_dummy).
"   
"   " Simple business exception - will result in non-201 status code
"   RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
"     EXPORTING
"       message = 'Material movement completed with errors'.
"       
" ENDIF.

ENDMETHOD.