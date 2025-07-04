METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  " Step 1: Define the structure matching the deep entity
  TYPES: ty_item  TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementitem,
         ty_items TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY.

  TYPES: BEGIN OF ty_header,
           grgislipno     TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-grgislipno,
           ztypegm        TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-ztypegm,
           zsubtype       TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-zsubtype,
           movementtype   TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-movementtype,
           docdate        TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-docdate,
           pstngdate      TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-pstngdate,
           headertxt      TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-headertxt,
           headertoitemnav TYPE ty_items,
         END OF ty_header.

  TYPES: ty_headers TYPE STANDARD TABLE OF ty_header WITH DEFAULT KEY.

  " Result record structure (unified for success and failure)
  TYPES: BEGIN OF ty_result_record,
           grgislipno TYPE string,
           status TYPE string,
           migonumber TYPE string,
           error TYPE string,
         END OF ty_result_record.

  " Expected response structure
  TYPES: BEGIN OF ty_response,
           grgislipno TYPE string,
           overallstatus TYPE string,
           results TYPE STANDARD TABLE OF ty_result_record WITH DEFAULT KEY,
         END OF ty_response.

  TYPES: BEGIN OF ty_deep_headerdummy,
           grgislipno    TYPE zcl_zmm_migo_automatio_mpc=>ts_headerdummy-grgislipno,
           torealheaders TYPE ty_headers,
         END OF ty_deep_headerdummy.

  DATA: ls_deep_entity TYPE ty_deep_headerdummy,
        ls_response TYPE ty_response.

  " BAPI structures
  DATA: ls_gm_header    TYPE bapi2017_gm_head_01,
        lt_gm_items     TYPE TABLE OF bapi2017_gm_item_create,
        ls_gm_item      TYPE bapi2017_gm_item_create,
        ls_gm_code      TYPE bapi2017_gm_code,
        lv_materialdoc  TYPE bapi2017_gm_head_ret-mat_doc,
        lv_matdocyear   TYPE bapi2017_gm_head_ret-doc_year,
        lt_return       TYPE TABLE OF bapiret2,
        ls_return       TYPE bapiret2.

  " Processing variables
  DATA: lv_success_count TYPE i,
        lv_error_count   TYPE i,
        lv_total_headers TYPE i,
        lv_processed_items TYPE i.

  " Result tracking
  DATA: ls_result_record TYPE ty_result_record.

  " Validation table for unique GrGiSlipNo
  DATA: lt_processed_slips TYPE TABLE OF string.

  " Error response message for exception
  DATA: lv_exception_message TYPE string,
        lv_response_json TYPE string.

  " Step 2: Read full deep structure
  TRY.
      io_data_provider->read_entry_data(
        IMPORTING
          es_data = ls_deep_entity
      ).
    CATCH cx_root INTO DATA(lx_read_error).
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
        EXPORTING
          textid = /iwbep/cx_mgw_tech_exception=>internal_error.
  ENDTRY.

  " Initialize response
  ls_response-grgislipno = ls_deep_entity-grgislipno.

  " Count total headers
  lv_total_headers = lines( ls_deep_entity-torealheaders ).

  " Validate main payload
  IF ls_deep_entity-grgislipno IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error
        message = 'Main GrGiSlipNo is required'.
  ENDIF.

  " Step 3: Process each real header with validation
  LOOP AT ls_deep_entity-torealheaders INTO DATA(ls_header).

    CLEAR: ls_gm_header, lt_gm_items, ls_gm_code, lt_return,
           lv_materialdoc, lv_matdocyear, lv_processed_items,
           ls_result_record.

    " === HEADER VALIDATIONS ===
    DATA: lv_header_valid TYPE abap_bool VALUE abap_true,
          lv_error_msg TYPE string.

    " Validate ZtypeGm must be A007
    IF ls_header-ztypegm <> 'A007'.
      lv_header_valid = abap_false.
      lv_error_msg = |ZtypeGm must be 'A007', received: '{ ls_header-ztypegm }'|.
    ENDIF.

    " Validate ZsubType must be R10
    IF ls_header-zsubtype <> 'R10'.
      lv_header_valid = abap_false.
      IF lv_error_msg IS NOT INITIAL.
        lv_error_msg = |{ lv_error_msg }; ZsubType must be 'R10', received: '{ ls_header-zsubtype }'|.
      ELSE.
        lv_error_msg = |ZsubType must be 'R10', received: '{ ls_header-zsubtype }'|.
      ENDIF.
    ENDIF.

    " Validate Movementtype must be 963
    IF ls_header-movementtype <> '963'.
      lv_header_valid = abap_false.
      IF lv_error_msg IS NOT INITIAL.
        lv_error_msg = |{ lv_error_msg }; Movement type must be 963|.
      ELSE.
        lv_error_msg = |Movement type must be 963|.
      ENDIF.
    ENDIF.

    " Validate GrGiSlipNo uniqueness
    READ TABLE lt_processed_slips TRANSPORTING NO FIELDS WITH KEY table_line = ls_header-grgislipno.
    IF sy-subrc = 0.
      lv_header_valid = abap_false.
      IF lv_error_msg IS NOT INITIAL.
        lv_error_msg = |{ lv_error_msg }; GrGiSlipNo '{ ls_header-grgislipno }' already processed (must be unique)|.
      ELSE.
        lv_error_msg = |GrGiSlipNo '{ ls_header-grgislipno }' already processed (must be unique)|.
      ENDIF.
    ELSE.
      APPEND ls_header-grgislipno TO lt_processed_slips.
    ENDIF.

    " Validate required header fields
    IF ls_header-grgislipno IS INITIAL OR
       ls_header-docdate IS INITIAL OR
       ls_header-pstngdate IS INITIAL.
      lv_header_valid = abap_false.
      IF lv_error_msg IS NOT INITIAL.
        lv_error_msg = |{ lv_error_msg }; Missing required header fields|.
      ELSE.
        lv_error_msg = |Missing required header fields|.
      ENDIF.
    ENDIF.

    " Skip BAPI call if header validation failed, but continue processing other headers
    IF lv_header_valid = abap_false.
      lv_error_count = lv_error_count + 1.
      ls_result_record-grgislipno = ls_header-grgislipno.
      ls_result_record-status = 'FAILED'.
      ls_result_record-error = lv_error_msg.
      APPEND ls_result_record TO ls_response-results.
      CONTINUE.
    ENDIF.

    " Fill BAPI header (no date conversion needed)
    ls_gm_header-pstng_date = sy-datum.
    ls_gm_header-doc_date   = sy-datum.
    ls_gm_header-header_txt = ls_header-headertxt.
    ls_gm_header-ref_doc_no = ls_header-grgislipno.

    " Set GM Code for movement type 963 (Goods Issue for Sampling)
    ls_gm_code-gm_code = '03'.

    " Step 5: Process items with mandatory field validation
    LOOP AT ls_header-headertoitemnav INTO DATA(ls_item).

      " === ITEM VALIDATIONS ===
      DATA: lv_item_valid TYPE abap_bool VALUE abap_true,
            lv_item_errors TYPE string.

      " ItemOk must be true (mandatory and fixed)
      IF ls_item-itemok <> abap_true.
        lv_item_valid = abap_false.
        lv_item_errors = |ItemOk must be true|.
      ENDIF.

      " Material Code - Mandatory
      IF ls_item-material IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_item_errors IS NOT INITIAL.
          lv_item_errors = |{ lv_item_errors }; Material Code is mandatory|.
        ELSE.
          lv_item_errors = |Material Code is mandatory|.
        ENDIF.
      ENDIF.

      " Material Description - Mandatory
      IF ls_item-matdesc IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_item_errors IS NOT INITIAL.
          lv_item_errors = |{ lv_item_errors }; Material Description is mandatory|.
        ELSE.
          lv_item_errors = |Material Description is mandatory|.
        ENDIF.
      ENDIF.

      " UOM - Mandatory
      IF ls_item-baseuom IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_item_errors IS NOT INITIAL.
          lv_item_errors = |{ lv_item_errors }; UOM is mandatory|.
        ELSE.
          lv_item_errors = |UOM is mandatory|.
        ENDIF.
      ENDIF.

      " Quantity - Mandatory
      IF ls_item-quantity IS INITIAL OR ls_item-quantity <= 0.
        lv_item_valid = abap_false.
        IF lv_item_errors IS NOT INITIAL.
          lv_item_errors = |{ lv_item_errors }; Quantity must be greater than 0|.
        ELSE.
          lv_item_errors = |Quantity must be greater than 0|.
        ENDIF.
      ENDIF.

      " Storage Location - Mandatory
      IF ls_item-strgloc IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_item_errors IS NOT INITIAL.
          lv_item_errors = |{ lv_item_errors }; Storage Location is mandatory|.
        ELSE.
          lv_item_errors = |Storage Location is mandatory|.
        ENDIF.
      ENDIF.

      " Plant - Mandatory
      IF ls_item-plant IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_item_errors IS NOT INITIAL.
          lv_item_errors = |{ lv_item_errors }; Plant is mandatory|.
        ELSE.
          lv_item_errors = |Plant is mandatory|.
        ENDIF.
      ENDIF.

      " General Ledger - Mandatory
      IF ls_item-glaccount IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_item_errors IS NOT INITIAL.
          lv_item_errors = |{ lv_item_errors }; General Ledger Account is mandatory|.
        ELSE.
          lv_item_errors = |General Ledger Account is mandatory|.
        ENDIF.
      ENDIF.

      " Cost Center - Mandatory
      IF ls_item-costcenter IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_item_errors IS NOT INITIAL.
          lv_item_errors = |{ lv_item_errors }; Cost Center is mandatory|.
        ELSE.
          lv_item_errors = |Cost Center is mandatory|.
        ENDIF.
      ENDIF.

      " Order No (Internal Order) - Mandatory
      IF ls_item-orderno IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_item_errors IS NOT INITIAL.
          lv_item_errors = |{ lv_item_errors }; Missing required field: OrderNo|.
        ELSE.
          lv_item_errors = |Missing required field: OrderNo|.
        ENDIF.
      ENDIF.

      " Only add valid items to BAPI call
      IF lv_item_valid = abap_true.
        " Map validated item to BAPI structure
        CLEAR: ls_gm_item.

        ls_gm_item-material     = ls_item-material.
        ls_gm_item-plant        = ls_item-plant.
        ls_gm_item-stge_loc     = ls_item-strgloc.
        ls_gm_item-move_type    = '963'.
        ls_gm_item-entry_qnt    = ls_item-quantity.
        ls_gm_item-entry_uom    = ls_item-baseuom.
        ls_gm_item-move_mat     = ls_item-material.
        ls_gm_item-gl_account   = ls_item-glaccount.
        ls_gm_item-costcenter   = ls_item-costcenter.
        ls_gm_item-orderid      = ls_item-orderno.

        APPEND ls_gm_item TO lt_gm_items.
        lv_processed_items = lv_processed_items + 1.
      ELSE.
        " Add item error to header error message
        IF lv_error_msg IS NOT INITIAL.
          lv_error_msg = |{ lv_error_msg }; { lv_item_errors }|.
        ELSE.
          lv_error_msg = lv_item_errors.
        ENDIF.
      ENDIF.

    ENDLOOP.

    " If there were item validation errors, record them
    IF lv_error_msg IS NOT INITIAL AND lv_header_valid = abap_true.
      lv_error_count = lv_error_count + 1.
      ls_result_record-grgislipno = ls_header-grgislipno.
      ls_result_record-status = 'FAILED'.
      ls_result_record-error = lv_error_msg.
      APPEND ls_result_record TO ls_response-results.
      CONTINUE.
    ENDIF.

    " Step 6: Call BAPI if we have valid items
    IF lt_gm_items IS NOT INITIAL.

      CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
        EXPORTING
          goodsmvt_header       = ls_gm_header
          goodsmvt_code         = ls_gm_code
          testrun              = ''  " Set to 'X' for test mode
        IMPORTING
          materialdocument     = lv_materialdoc
          matdocumentyear      = lv_matdocyear
        TABLES
          goodsmvt_item        = lt_gm_items
          return               = lt_return.

      " Check for BAPI errors in LT_RETURN (SY-SUBRC is always 0)
      READ TABLE lt_return INTO ls_return WITH KEY type = 'E'.
      IF sy-subrc = 0.
        " Error occurred in BAPI - rollback
        CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
        lv_error_count = lv_error_count + 1.

        " Collect BAPI error messages
        CLEAR: lv_error_msg.
        LOOP AT lt_return INTO ls_return WHERE type = 'E' OR type = 'A'.
          IF lv_error_msg IS NOT INITIAL.
            lv_error_msg = |{ lv_error_msg }; { ls_return-message }|.
          ELSE.
            lv_error_msg = ls_return-message.
          ENDIF.
        ENDLOOP.

        ls_result_record-grgislipno = ls_header-grgislipno.
        ls_result_record-status = 'FAILED'.
        ls_result_record-error = lv_error_msg.
        APPEND ls_result_record TO ls_response-results.

      ELSE.
        " No errors in LT_RETURN - check for warnings and commit
        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING
            wait = 'X'.

        lv_success_count = lv_success_count + 1.

        " Add to success records
        ls_result_record-grgislipno = ls_header-grgislipno.
        ls_result_record-status = 'SUCCESS'.
        ls_result_record-migonumber = lv_materialdoc.
        APPEND ls_result_record TO ls_response-results.

      ENDIF.

    ELSE.
      lv_error_count = lv_error_count + 1.
      
      ls_result_record-grgislipno = ls_header-grgislipno.
      ls_result_record-status = 'FAILED'.
      ls_result_record-error = 'No valid items found after validation'.
      APPEND ls_result_record TO ls_response-results.
    ENDIF.

  ENDLOOP.

  " Step 7: Set overall status based on results
  IF lv_success_count = 0.
    ls_response-overallstatus = 'FAILED'.
  ELSEIF lv_error_count = 0.
    ls_response-overallstatus = 'SUCCESS'.
  ELSE.
    ls_response-overallstatus = 'PARTIAL SUCCESS'.
  ENDIF.

  " Step 8: Handle HTTP status codes based on results
  IF lv_success_count = 0.
    " All records failed - return HTTP 400 with error details
    " Convert response to JSON using /UI2/CL_JSON (more reliable for string output)
    lv_response_json = /ui2/cl_json=>serialize( data = ls_response compress = abap_false pretty_name = /ui2/cl_json=>pretty_mode-camel_case ).
    
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error
        message = lv_response_json
        http_status_code = /iwbep/cx_mgw_busi_exception=>gcs_http_status_codes-bad_request.

  ELSEIF lv_error_count > 0.
    " Partial success - return HTTP 207 Multi-Status with mixed results
    " Convert response to JSON using /UI2/CL_JSON
    lv_response_json = /ui2/cl_json=>serialize( data = ls_response compress = abap_false pretty_name = /ui2/cl_json=>pretty_mode-camel_case ).
    
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error
        message = lv_response_json
        http_status_code = '207'.  " Multi-Status
        
  ELSE.
    " All records successful - return HTTP 201 with success response
    copy_data_to_ref(
      EXPORTING
        is_data = ls_response
      CHANGING
        cr_data = er_deep_entity
    ).
  ENDIF.

ENDMETHOD.