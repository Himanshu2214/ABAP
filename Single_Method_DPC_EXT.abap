METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  " ===== ALL TYPE DEFINITIONS INLINE =====
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

  TYPES: BEGIN OF ty_result_record,
           grgislipno TYPE string,
           status TYPE string,
           migonumber TYPE string,
           error TYPE string,
         END OF ty_result_record.

  TYPES: BEGIN OF ty_response,
           grgislipno TYPE string,
           overallstatus TYPE string,
           results TYPE STANDARD TABLE OF ty_result_record WITH DEFAULT KEY,
         END OF ty_response.

  TYPES: BEGIN OF ty_deep_headerdummy,
           grgislipno    TYPE zcl_zmm_migo_automatio_mpc=>ts_headerdummy-grgislipno,
           torealheaders TYPE ty_headers,
         END OF ty_deep_headerdummy.

  " Final response types
  TYPES: BEGIN OF ty_final_result,
           grgislipno TYPE string,
           status TYPE string,
           migonumber TYPE string,
           error TYPE string,
         END OF ty_final_result,
         ty_final_results TYPE STANDARD TABLE OF ty_final_result WITH DEFAULT KEY.

  TYPES: BEGIN OF ty_final_response_data,
           grgislipno TYPE string,
           overallstatus TYPE string,
           results TYPE ty_final_results,
         END OF ty_final_response_data.

  TYPES: BEGIN OF ty_final_response,
           response TYPE ty_final_response_data,
         END OF ty_final_response.

  " ===== ALL CONSTANTS INLINE =====
  CONSTANTS: gc_ztypegm_required TYPE string VALUE 'A007',
             gc_zsubtype_required TYPE string VALUE 'R10',
             gc_movetype_required TYPE string VALUE '963',
             gc_gm_code TYPE string VALUE '03',
             gc_status_success TYPE string VALUE 'SUCCESS',
             gc_status_failed TYPE string VALUE 'FAILED',
             gc_status_partial TYPE string VALUE 'PARTIAL SUCCESS',
             gc_http_ok TYPE i VALUE 200,
             gc_http_bad_request TYPE i VALUE 400,
             gc_http_multi_status TYPE i VALUE 207.

  " ===== DATA DECLARATIONS =====
  DATA: ls_deep_entity TYPE ty_deep_headerdummy,
        ls_response TYPE ty_response,
        ls_final_response TYPE ty_final_response,
        lv_success_count TYPE i,
        lv_error_count TYPE i,
        lv_total_headers TYPE i,
        lt_processed_slips TYPE string_table,
        lv_response_json TYPE string.

  " BAPI structures
  DATA: ls_gm_header    TYPE bapi2017_gm_head_01,
        lt_gm_items     TYPE BAPI2017_GM_ITEM_CREATE_T,
        ls_gm_item      TYPE bapi2017_gm_item_create,
        ls_gm_code      TYPE bapi2017_gm_code,
        lv_materialdoc  TYPE bapi2017_gm_head_ret-mat_doc,
        lv_matdocyear   TYPE bapi2017_gm_head_ret-doc_year,
        lt_return       TYPE TABLE OF bapiret2,
        ls_return       TYPE bapiret2.

  " Result tracking
  DATA: ls_result_record TYPE ty_result_record,
        ls_final_result TYPE ty_final_result.

  " ===== STEP 1: READ PAYLOAD =====
  TRY.
      io_data_provider->read_entry_data(
        IMPORTING
          es_data = ls_deep_entity
      ).
    CATCH /iwbep/cx_mgw_tech_exception INTO DATA(lx_tech_error).
      lv_response_json = |Technical Error: { lx_tech_error->get_text( ) }|.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error
          message = lv_response_json
          http_status_code = '400'.
    CATCH cx_root INTO DATA(lx_read_error).
      lv_response_json = |Error reading payload: { lx_read_error->get_text( ) }|.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error
          message = lv_response_json
          http_status_code = '400'.
  ENDTRY.

  " Initialize response
  ls_response-grgislipno = ls_deep_entity-grgislipno.
  lv_total_headers = lines( ls_deep_entity-torealheaders ).

  " Basic validation
  IF ls_deep_entity-grgislipno IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error
        message = 'Main GrGiSlipNo is required'
        http_status_code = '400'.
  ENDIF.

  " ===== STEP 2: PROCESS EACH HEADER =====
  LOOP AT ls_deep_entity-torealheaders INTO DATA(ls_header).

    CLEAR: ls_gm_header, lt_gm_items, ls_gm_code, lt_return,
           lv_materialdoc, lv_matdocyear, ls_result_record.

    " === HEADER VALIDATIONS ===
    DATA: lv_header_valid TYPE abap_bool VALUE abap_true,
          lv_error_msg TYPE string.

    " Validate ZtypeGm must be A007
    IF ls_header-ztypegm <> gc_ztypegm_required.
      lv_header_valid = abap_false.
      lv_error_msg = |ZtypeGm must be '{ gc_ztypegm_required }', received: '{ ls_header-ztypegm }'|.
    ENDIF.

    " Validate ZsubType must be R10
    IF ls_header-zsubtype <> gc_zsubtype_required.
      lv_header_valid = abap_false.
      IF lv_error_msg IS NOT INITIAL.
        lv_error_msg = |{ lv_error_msg }; ZsubType must be '{ gc_zsubtype_required }', received: '{ ls_header-zsubtype }'|.
      ELSE.
        lv_error_msg = |ZsubType must be '{ gc_zsubtype_required }', received: '{ ls_header-zsubtype }'|.
      ENDIF.
    ENDIF.

    " Validate Movement type must be 963
    IF ls_header-movementtype <> gc_movetype_required.
      lv_header_valid = abap_false.
      IF lv_error_msg IS NOT INITIAL.
        lv_error_msg = |{ lv_error_msg }; Movement type must be { gc_movetype_required }|.
      ELSE.
        lv_error_msg = |Movement type must be { gc_movetype_required }|.
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

    " Skip BAPI call if header validation failed
    IF lv_header_valid = abap_false.
      lv_error_count = lv_error_count + 1.
      ls_result_record-grgislipno = ls_header-grgislipno.
      ls_result_record-status = gc_status_failed.
      ls_result_record-error = lv_error_msg.
      APPEND ls_result_record TO ls_response-results.
      CONTINUE.
    ENDIF.

    " === PREPARE BAPI HEADER ===
    ls_gm_header-pstng_date = sy-datum.
    ls_gm_header-doc_date   = sy-datum.
    ls_gm_header-header_txt = ls_header-headertxt.
    ls_gm_header-ref_doc_no = ls_header-grgislipno.
    ls_gm_code-gm_code = gc_gm_code.

    " === PROCESS ITEMS ===
    DATA: lv_item_errors TYPE string,
          lv_processed_items TYPE i.
    CLEAR: lt_gm_items, lv_processed_items.

    LOOP AT ls_header-headertoitemnav INTO DATA(ls_item).
      DATA: lv_item_valid TYPE abap_bool VALUE abap_true,
            lv_single_item_error TYPE string.

      " ItemOk validation
      IF ls_item-itemok <> abap_true.
        lv_item_valid = abap_false.
        lv_single_item_error = 'ItemOk must be true'.
      ENDIF.

      " Required field validations
      IF ls_item-material IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_single_item_error IS NOT INITIAL.
          lv_single_item_error = |{ lv_single_item_error }; Material Code is mandatory|.
        ELSE.
          lv_single_item_error = 'Material Code is mandatory'.
        ENDIF.
      ENDIF.

      IF ls_item-matdesc IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_single_item_error IS NOT INITIAL.
          lv_single_item_error = |{ lv_single_item_error }; Material Description is mandatory|.
        ELSE.
          lv_single_item_error = 'Material Description is mandatory'.
        ENDIF.
      ENDIF.

      IF ls_item-baseuom IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_single_item_error IS NOT INITIAL.
          lv_single_item_error = |{ lv_single_item_error }; UOM is mandatory|.
        ELSE.
          lv_single_item_error = 'UOM is mandatory'.
        ENDIF.
      ENDIF.

      IF ls_item-quantity IS INITIAL OR ls_item-quantity <= 0.
        lv_item_valid = abap_false.
        IF lv_single_item_error IS NOT INITIAL.
          lv_single_item_error = |{ lv_single_item_error }; Quantity must be greater than 0|.
        ELSE.
          lv_single_item_error = 'Quantity must be greater than 0'.
        ENDIF.
      ENDIF.

      IF ls_item-strgloc IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_single_item_error IS NOT INITIAL.
          lv_single_item_error = |{ lv_single_item_error }; Storage Location is mandatory|.
        ELSE.
          lv_single_item_error = 'Storage Location is mandatory'.
        ENDIF.
      ENDIF.

      IF ls_item-plant IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_single_item_error IS NOT INITIAL.
          lv_single_item_error = |{ lv_single_item_error }; Plant is mandatory|.
        ELSE.
          lv_single_item_error = 'Plant is mandatory'.
        ENDIF.
      ENDIF.

      IF ls_item-glaccount IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_single_item_error IS NOT INITIAL.
          lv_single_item_error = |{ lv_single_item_error }; General Ledger Account is mandatory|.
        ELSE.
          lv_single_item_error = 'General Ledger Account is mandatory'.
        ENDIF.
      ENDIF.

      IF ls_item-costcenter IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_single_item_error IS NOT INITIAL.
          lv_single_item_error = |{ lv_single_item_error }; Cost Center is mandatory|.
        ELSE.
          lv_single_item_error = 'Cost Center is mandatory'.
        ENDIF.
      ENDIF.

      IF ls_item-orderno IS INITIAL.
        lv_item_valid = abap_false.
        IF lv_single_item_error IS NOT INITIAL.
          lv_single_item_error = |{ lv_single_item_error }; Missing required field: OrderNo|.
        ELSE.
          lv_single_item_error = 'Missing required field: OrderNo'.
        ENDIF.
      ENDIF.

      " Add valid items to BAPI
      IF lv_item_valid = abap_true.
        CLEAR: ls_gm_item.
        ls_gm_item-material     = ls_item-material.
        ls_gm_item-plant        = ls_item-plant.
        ls_gm_item-stge_loc     = ls_item-strgloc.
        ls_gm_item-move_type    = gc_movetype_required.
        ls_gm_item-entry_qnt    = ls_item-quantity.
        ls_gm_item-entry_uom    = ls_item-baseuom.
        ls_gm_item-move_mat     = ls_item-material.
        ls_gm_item-gl_account   = ls_item-glaccount.
        ls_gm_item-costcenter   = ls_item-costcenter.
        ls_gm_item-orderid      = ls_item-orderno.
        APPEND ls_gm_item TO lt_gm_items.
        lv_processed_items = lv_processed_items + 1.
      ELSE.
        " Collect item errors
        IF lv_item_errors IS NOT INITIAL.
          lv_item_errors = |{ lv_item_errors }; { lv_single_item_error }|.
        ELSE.
          lv_item_errors = lv_single_item_error.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " Check if we have valid items for BAPI call
    IF lt_gm_items IS INITIAL.
      lv_error_count = lv_error_count + 1.
      ls_result_record-grgislipno = ls_header-grgislipno.
      ls_result_record-status = gc_status_failed.
      IF lv_item_errors IS NOT INITIAL.
        ls_result_record-error = lv_item_errors.
      ELSE.
        ls_result_record-error = 'No valid items found after validation'.
      ENDIF.
      APPEND ls_result_record TO ls_response-results.
      CONTINUE.
    ENDIF.

    " === CALL BAPI ===
    CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
      EXPORTING
        goodsmvt_header       = ls_gm_header
        goodsmvt_code         = ls_gm_code
        testrun              = ''
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
      ls_result_record-status = gc_status_failed.
      ls_result_record-error = lv_error_msg.
      APPEND ls_result_record TO ls_response-results.

    ELSE.
      " No errors in LT_RETURN - commit
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait = 'X'.

      lv_success_count = lv_success_count + 1.
      ls_result_record-grgislipno = ls_header-grgislipno.
      ls_result_record-status = gc_status_success.
      ls_result_record-migonumber = lv_materialdoc.
      APPEND ls_result_record TO ls_response-results.
    ENDIF.

  ENDLOOP.

  " === SET OVERALL STATUS ===
  IF lv_success_count = 0.
    ls_response-overallstatus = gc_status_failed.
  ELSEIF lv_error_count = 0.
    ls_response-overallstatus = gc_status_success.
  ELSE.
    ls_response-overallstatus = gc_status_partial.
  ENDIF.

  " === GENERATE FINAL JSON RESPONSE ===
  ls_final_response-response-grgislipno = ls_response-grgislipno.
  ls_final_response-response-overallstatus = ls_response-overallstatus.

  " Map results array
  LOOP AT ls_response-results INTO ls_result_record.
    CLEAR: ls_final_result.
    ls_final_result-grgislipno = ls_result_record-grgislipno.
    ls_final_result-status = ls_result_record-status.
    ls_final_result-migonumber = ls_result_record-migonumber.
    ls_final_result-error = ls_result_record-error.
    APPEND ls_final_result TO ls_final_response-response-results.
  ENDLOOP.

  " Generate JSON with uppercase field names
  lv_response_json = /ui2/cl_json=>serialize(
    data = ls_final_response
    compress = abap_false
    pretty_name = /ui2/cl_json=>pretty_mode-upper_case
  ).

  " Determine HTTP status code
  DATA: lv_http_status TYPE string.
  IF lv_success_count = 0.
    lv_http_status = '400'.  " Bad Request - all failed
  ELSEIF lv_error_count = 0.
    lv_http_status = '200'.  " OK - all success
  ELSE.
    lv_http_status = '207'.  " Multi-Status - partial success
  ENDIF.

  " Return clean JSON via exception
  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
    EXPORTING
      textid = /iwbep/cx_mgw_busi_exception=>business_error
      message = lv_response_json
      http_status_code = lv_http_status.

ENDMETHOD.