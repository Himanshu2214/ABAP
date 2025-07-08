" SOLUTION 1: SIMPLEST - No Exceptions (Recommended)
" Replace the end of your method with this:

" Prepare final response structure
TYPES: BEGIN OF ty_final_response,
         ZMATSet TYPE ty_items,
       END OF ty_final_response.
DATA: ls_final_response TYPE ty_final_response.
ls_final_response-ZMATSet = lt_result_data.

" Set response data
copy_data_to_ref(
  EXPORTING
    is_data = ls_final_response
  CHANGING
    cr_data = er_deep_entity
).

" NO EXCEPTIONS - Let client check Status field in response
" This gives HTTP 201 but with clear error indication in response body
" Your client can check if any items have Status = 'ERROR'

ENDMETHOD.

" =================================================================
" SOLUTION 2: Minimal Exception (if you must have non-201 status)
" Replace the end of your method with this:

" Prepare final response structure  
TYPES: BEGIN OF ty_final_response,
         ZMATSet TYPE ty_items,
       END OF ty_final_response.
DATA: ls_final_response TYPE ty_final_response.
ls_final_response-ZMATSet = lt_result_data.

" Set response data FIRST
copy_data_to_ref(
  EXPORTING
    is_data = ls_final_response
  CHANGING
    cr_data = er_deep_entity
).

" Simple exception for HTTP status (minimal approach)
IF lv_any_error_occurred = abap_true.
  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
    EXPORTING
      message = 'Errors occurred'.
ENDIF.

ENDMETHOD.

" =================================================================
" SOLUTION 3: Using Standard Message Class
" First create message class ZMIGO_MSG with message 001: "Business errors occurred"
" Then replace the end of your method with this:

" Prepare final response structure
TYPES: BEGIN OF ty_final_response,
         ZMATSet TYPE ty_items,
       END OF ty_final_response.
DATA: ls_final_response TYPE ty_final_response.
ls_final_response-ZMATSet = lt_result_data.

" Set response data FIRST
copy_data_to_ref(
  EXPORTING
    is_data = ls_final_response
  CHANGING
    cr_data = er_deep_entity
).

" Use message class for exception
IF lv_any_error_occurred = abap_true.
  MESSAGE e001(zmigo_msg) INTO DATA(lv_dummy).
  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception.
ENDIF.

ENDMETHOD.