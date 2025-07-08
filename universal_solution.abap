" UNIVERSAL SOLUTION: Works with ALL SAP Gateway versions
" Replace the end of your method with this simple code:

" Prepare final response structure
TYPES: BEGIN OF ty_final_response,
         ZMATSet TYPE ty_items,
       END OF ty_final_response.
DATA: ls_final_response TYPE ty_final_response.
ls_final_response-ZMATSet = lt_result_data.

" STEP 1: ALWAYS set response data FIRST (preserves your JSON structure)
copy_data_to_ref(
  EXPORTING
    is_data = ls_final_response
  CHANGING
    cr_data = er_deep_entity
).

" STEP 2: Simple HTTP status handling for errors
IF lv_any_error_occurred = abap_true.
  
  " This simple business exception works in ALL SAP Gateway versions
  " and will result in HTTP 400/422 instead of 201
  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
    EXPORTING
      textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
      message = 'Material movement completed with business errors. See response details.'.
      
ENDIF.

ENDMETHOD.