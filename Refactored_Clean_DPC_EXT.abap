" ===== CLASS DEFINITION (in DPC class) =====

PRIVATE SECTION.
  " Constants for validation
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

  " Type definitions
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

  " Helper methods
  METHODS: validate_payload_structure
    IMPORTING is_deep_entity TYPE ty_deep_headerdummy
    RETURNING VALUE(rv_valid) TYPE abap_bool,

  validate_header
    IMPORTING is_header TYPE ty_header
              it_processed_slips TYPE string_table
    RETURNING VALUE(rv_error_msg) TYPE string,

  process_items
    IMPORTING it_items TYPE ty_items
    EXPORTING et_gm_items TYPE bapi2017_gm_item_create_tab
              ev_processed_items TYPE i
    RETURNING VALUE(rv_error_msg) TYPE string,

  validate_single_item
    IMPORTING is_item TYPE ty_item
    RETURNING VALUE(rv_error_msg) TYPE string,

  map_item_to_bapi
    IMPORTING is_item TYPE ty_item
    RETURNING VALUE(rs_gm_item) TYPE bapi2017_gm_item_create,

  append_error_message
    IMPORTING iv_new_error TYPE string
    CHANGING cv_error_msg TYPE string,

  add_error_result
    IMPORTING iv_grgislipno TYPE string
              iv_error_msg TYPE string
    CHANGING ct_results TYPE STANDARD TABLE
             cv_error_count TYPE i,

  prepare_bapi_header
    IMPORTING is_header TYPE ty_header
    EXPORTING es_gm_header TYPE bapi2017_gm_head_01
              es_gm_code TYPE bapi2017_gm_code,

  execute_goods_movement
    IMPORTING is_gm_header TYPE bapi2017_gm_head_01
              is_gm_code TYPE bapi2017_gm_code
              it_gm_items TYPE bapi2017_gm_item_create_tab
              iv_grgislipno TYPE string
    CHANGING ct_results TYPE STANDARD TABLE
             cv_success_count TYPE i
             cv_error_count TYPE i,

  collect_bapi_errors
    IMPORTING it_return TYPE bapiret2_tab
    RETURNING VALUE(rv_error_msg) TYPE string,

  determine_overall_status
    IMPORTING iv_success_count TYPE i
              iv_error_count TYPE i
    RETURNING VALUE(rv_status) TYPE string,

  generate_json_response
    IMPORTING is_response TYPE ty_response,

  set_http_response
    IMPORTING iv_json TYPE string
              iv_status_code TYPE i,

  get_http_status_code
    IMPORTING is_response TYPE ty_response
    RETURNING VALUE(rv_status_code) TYPE i,

  raise_business_exception
    IMPORTING iv_message TYPE string.

" ===== CLASS IMPLEMENTATION =====

METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  DATA: ls_deep_entity TYPE ty_deep_headerdummy,
        ls_response TYPE ty_response,
        lv_success_count TYPE i,
        lv_error_count TYPE i,
        lv_total_headers TYPE i,
        lt_processed_slips TYPE string_table,
        lv_response_json TYPE string.

  " Step 2: Read full deep structure with enhanced error handling
  TRY.
      io_data_provider->read_entry_data(
        IMPORTING
          es_data = ls_deep_entity
      ).
    CATCH /iwbep/cx_mgw_tech_exception INTO DATA(lx_tech_error).
      lv_response_json = |Technical Error: { lx_tech_error->get_text( ) }|.
      me->raise_business_exception( lv_response_json ).
    CATCH cx_root INTO DATA(lx_read_error).
      lv_response_json = |Error reading payload: { lx_read_error->get_text( ) }|.
      me->raise_business_exception( lv_response_json ).
  ENDTRY.

  " Initialize response
  ls_response-grgislipno = ls_deep_entity-grgislipno.
  lv_total_headers = lines( ls_deep_entity-torealheaders ).

  " Enhanced data validation
  IF me->validate_payload_structure( ls_deep_entity ) = abap_false.
    me->raise_business_exception( 'Invalid payload structure' ).
  ENDIF.

  " Step 3: Process each real header with enhanced validation
  LOOP AT ls_deep_entity-torealheaders INTO DATA(ls_header).

    " Enhanced header validation
    DATA(lv_header_errors) = me->validate_header( 
      is_header = ls_header 
      it_processed_slips = lt_processed_slips 
    ).

    IF lv_header_errors IS NOT INITIAL.
      me->add_error_result( 
        EXPORTING
          iv_grgislipno = ls_header-grgislipno
          iv_error_msg = lv_header_errors
        CHANGING
          ct_results = ls_response-results
          cv_error_count = lv_error_count
      ).
      CONTINUE.
    ENDIF.

    " Add to processed slips for uniqueness check
    APPEND ls_header-grgislipno TO lt_processed_slips.

    " Prepare BAPI header with proper date handling
    DATA: ls_gm_header TYPE bapi2017_gm_head_01,
          ls_gm_code TYPE bapi2017_gm_code.
          
    me->prepare_bapi_header( 
      EXPORTING
        is_header = ls_header
      IMPORTING
        es_gm_header = ls_gm_header
        es_gm_code = ls_gm_code
    ).

    " Process items with enhanced validation
    DATA: lt_gm_items TYPE bapi2017_gm_item_create_tab,
          lv_processed_items TYPE i.
          
    DATA(lv_item_errors) = me->process_items( 
      EXPORTING
        it_items = ls_header-headertoitemnav
      IMPORTING
        et_gm_items = lt_gm_items
        ev_processed_items = lv_processed_items
    ).

    IF lv_item_errors IS NOT INITIAL.
      me->add_error_result( 
        EXPORTING
          iv_grgislipno = ls_header-grgislipno
          iv_error_msg = lv_item_errors
        CHANGING
          ct_results = ls_response-results
          cv_error_count = lv_error_count
      ).
      CONTINUE.
    ENDIF.

    " Execute BAPI call with enhanced error handling
    me->execute_goods_movement(
      EXPORTING
        is_gm_header = ls_gm_header
        is_gm_code = ls_gm_code
        it_gm_items = lt_gm_items
        iv_grgislipno = ls_header-grgislipno
      CHANGING
        ct_results = ls_response-results
        cv_success_count = lv_success_count
        cv_error_count = lv_error_count
    ).

  ENDLOOP.

  " Set overall status
  ls_response-overallstatus = me->determine_overall_status( 
    iv_success_count = lv_success_count
    iv_error_count = lv_error_count
  ).

  " Generate and return JSON response
  me->generate_json_response( ls_response ).

  " Return empty entity to avoid OData processing
  DATA: ls_dummy_entity TYPE zcl_zmm_migo_automatio_mpc=>ts_headerdummy.
  copy_data_to_ref(
    EXPORTING
      is_data = ls_dummy_entity
    CHANGING
      cr_data = er_deep_entity
  ).

ENDMETHOD.

" ===== HELPER METHOD IMPLEMENTATIONS =====

METHOD validate_payload_structure.
  rv_valid = abap_true.
  
  IF is_deep_entity-grgislipno IS INITIAL AND 
     lines( is_deep_entity-torealheaders ) = 0.
    rv_valid = abap_false.
  ENDIF.
  
  IF is_deep_entity-grgislipno IS INITIAL.
    rv_valid = abap_false.
  ENDIF.
ENDMETHOD.

METHOD validate_header.
  DATA: lv_error_msg TYPE string.
  
  " Validate ZtypeGm
  IF is_header-ztypegm <> gc_ztypegm_required.
    lv_error_msg = |ZtypeGm must be '{ gc_ztypegm_required }', received: '{ is_header-ztypegm }'|.
  ENDIF.

  " Validate ZsubType
  IF is_header-zsubtype <> gc_zsubtype_required.
    me->append_error_message( 
      EXPORTING
        iv_new_error = |ZsubType must be '{ gc_zsubtype_required }', received: '{ is_header-zsubtype }'|
      CHANGING
        cv_error_msg = lv_error_msg
    ).
  ENDIF.

  " Validate Movement type
  IF is_header-movementtype <> gc_movetype_required.
    me->append_error_message( 
      EXPORTING
        iv_new_error = |Movement type must be { gc_movetype_required }|
      CHANGING
        cv_error_msg = lv_error_msg
    ).
  ENDIF.

  " Validate uniqueness
  READ TABLE it_processed_slips TRANSPORTING NO FIELDS 
    WITH KEY table_line = is_header-grgislipno.
  IF sy-subrc = 0.
    me->append_error_message( 
      EXPORTING
        iv_new_error = |GrGiSlipNo '{ is_header-grgislipno }' already processed (must be unique)|
      CHANGING
        cv_error_msg = lv_error_msg
    ).
  ENDIF.

  " Validate required fields
  IF is_header-grgislipno IS INITIAL OR
     is_header-docdate IS INITIAL OR
     is_header-pstngdate IS INITIAL.
    me->append_error_message( 
      EXPORTING
        iv_new_error = 'Missing required header fields'
      CHANGING
        cv_error_msg = lv_error_msg
    ).
  ENDIF.

  rv_error_msg = lv_error_msg.
ENDMETHOD.

METHOD process_items.
  DATA: lv_item_errors TYPE string.
  
  CLEAR: et_gm_items, ev_processed_items.
  
  LOOP AT it_items INTO DATA(ls_item).
    " Validate individual item
    DATA(lv_single_item_error) = me->validate_single_item( ls_item ).
    
    IF lv_single_item_error IS INITIAL.
      " Item is valid - add to BAPI items
      DATA(ls_gm_item) = me->map_item_to_bapi( ls_item ).
      APPEND ls_gm_item TO et_gm_items.
      ev_processed_items = ev_processed_items + 1.
    ELSE.
      " Item has errors
      me->append_error_message( 
        EXPORTING
          iv_new_error = lv_single_item_error
        CHANGING
          cv_error_msg = lv_item_errors
      ).
    ENDIF.
  ENDLOOP.
  
  IF et_gm_items IS INITIAL.
    me->append_error_message( 
      EXPORTING
        iv_new_error = 'No valid items found after validation'
      CHANGING
        cv_error_msg = lv_item_errors
    ).
  ENDIF.
  
  rv_error_msg = lv_item_errors.
ENDMETHOD.

METHOD validate_single_item.
  DATA: lv_error_msg TYPE string.
  
  " ItemOk validation
  IF is_item-itemok <> abap_true.
    lv_error_msg = 'ItemOk must be true'.
  ENDIF.
  
  " Required field validations with specific error messages
  IF is_item-material IS INITIAL.
    me->append_error_message( 
      EXPORTING iv_new_error = 'Material Code is mandatory'
      CHANGING cv_error_msg = lv_error_msg ).
  ENDIF.
  
  IF is_item-matdesc IS INITIAL.
    me->append_error_message( 
      EXPORTING iv_new_error = 'Material Description is mandatory'
      CHANGING cv_error_msg = lv_error_msg ).
  ENDIF.
  
  IF is_item-baseuom IS INITIAL.
    me->append_error_message( 
      EXPORTING iv_new_error = 'UOM is mandatory'
      CHANGING cv_error_msg = lv_error_msg ).
  ENDIF.
  
  IF is_item-strgloc IS INITIAL.
    me->append_error_message( 
      EXPORTING iv_new_error = 'Storage Location is mandatory'
      CHANGING cv_error_msg = lv_error_msg ).
  ENDIF.
  
  IF is_item-plant IS INITIAL.
    me->append_error_message( 
      EXPORTING iv_new_error = 'Plant is mandatory'
      CHANGING cv_error_msg = lv_error_msg ).
  ENDIF.
  
  IF is_item-glaccount IS INITIAL.
    me->append_error_message( 
      EXPORTING iv_new_error = 'General Ledger Account is mandatory'
      CHANGING cv_error_msg = lv_error_msg ).
  ENDIF.
  
  IF is_item-costcenter IS INITIAL.
    me->append_error_message( 
      EXPORTING iv_new_error = 'Cost Center is mandatory'
      CHANGING cv_error_msg = lv_error_msg ).
  ENDIF.
  
  IF is_item-orderno IS INITIAL.
    me->append_error_message( 
      EXPORTING iv_new_error = 'Missing required field: OrderNo'
      CHANGING cv_error_msg = lv_error_msg ).
  ENDIF.
  
  " Quantity validation
  IF is_item-quantity IS INITIAL OR is_item-quantity <= 0.
    me->append_error_message( 
      EXPORTING iv_new_error = 'Quantity must be greater than 0'
      CHANGING cv_error_msg = lv_error_msg ).
  ENDIF.
  
  rv_error_msg = lv_error_msg.
ENDMETHOD.

METHOD map_item_to_bapi.
  rs_gm_item-material     = is_item-material.
  rs_gm_item-plant        = is_item-plant.
  rs_gm_item-stge_loc     = is_item-strgloc.
  rs_gm_item-move_type    = gc_movetype_required.
  rs_gm_item-entry_qnt    = is_item-quantity.
  rs_gm_item-entry_uom    = is_item-baseuom.
  rs_gm_item-move_mat     = is_item-material.
  rs_gm_item-gl_account   = is_item-glaccount.
  rs_gm_item-costcenter   = is_item-costcenter.
  rs_gm_item-orderid      = is_item-orderno.
ENDMETHOD.

METHOD append_error_message.
  IF cv_error_msg IS NOT INITIAL.
    cv_error_msg = |{ cv_error_msg }; { iv_new_error }|.
  ELSE.
    cv_error_msg = iv_new_error.
  ENDIF.
ENDMETHOD.

METHOD add_error_result.
  DATA: ls_result_record TYPE ty_result_record.
  
  ls_result_record-grgislipno = iv_grgislipno.
  ls_result_record-status = gc_status_failed.
  ls_result_record-error = iv_error_msg.
  
  APPEND ls_result_record TO ct_results.
  cv_error_count = cv_error_count + 1.
ENDMETHOD.

METHOD prepare_bapi_header.
  es_gm_header-pstng_date = sy-datum.
  es_gm_header-doc_date   = sy-datum.
  es_gm_header-header_txt = is_header-headertxt.
  es_gm_header-ref_doc_no = is_header-grgislipno.
  
  es_gm_code-gm_code = gc_gm_code.
ENDMETHOD.

METHOD execute_goods_movement.
  DATA: lv_materialdoc TYPE bapi2017_gm_head_ret-mat_doc,
        lv_matdocyear TYPE bapi2017_gm_head_ret-doc_year,
        lt_return TYPE TABLE OF bapiret2,
        ls_return TYPE bapiret2,
        ls_result_record TYPE ty_result_record.

  IF it_gm_items IS INITIAL.
    me->add_error_result( 
      EXPORTING
        iv_grgislipno = iv_grgislipno
        iv_error_msg = 'No valid items for BAPI call'
      CHANGING
        ct_results = ct_results
        cv_error_count = cv_error_count
    ).
    RETURN.
  ENDIF.

  CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
    EXPORTING
      goodsmvt_header       = is_gm_header
      goodsmvt_code         = is_gm_code
      testrun              = ''
    IMPORTING
      materialdocument     = lv_materialdoc
      matdocumentyear      = lv_matdocyear
    TABLES
      goodsmvt_item        = it_gm_items
      return               = lt_return.

  " Enhanced error checking - BAPI SY-SUBRC is always 0, check LT_RETURN
  READ TABLE lt_return INTO ls_return WITH KEY type = 'E'.
  IF sy-subrc = 0.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    
    " Collect all error messages
    DATA(lv_error_msg) = me->collect_bapi_errors( lt_return ).
    
    me->add_error_result( 
      EXPORTING
        iv_grgislipno = iv_grgislipno
        iv_error_msg = lv_error_msg
      CHANGING
        ct_results = ct_results
        cv_error_count = cv_error_count
    ).
  ELSE.
    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = 'X'.

    " Add success result
    ls_result_record-grgislipno = iv_grgislipno.
    ls_result_record-status = gc_status_success.
    ls_result_record-migonumber = lv_materialdoc.
    
    APPEND ls_result_record TO ct_results.
    cv_success_count = cv_success_count + 1.
  ENDIF.
ENDMETHOD.

METHOD collect_bapi_errors.
  DATA: lv_error_msg TYPE string.
  
  LOOP AT it_return INTO DATA(ls_return) WHERE type = 'E' OR type = 'A'.
    me->append_error_message( 
      EXPORTING
        iv_new_error = ls_return-message
      CHANGING
        cv_error_msg = lv_error_msg
    ).
  ENDLOOP.
  
  rv_error_msg = lv_error_msg.
ENDMETHOD.

METHOD determine_overall_status.
  IF iv_success_count = 0.
    rv_status = gc_status_failed.
  ELSEIF iv_error_count = 0.
    rv_status = gc_status_success.
  ELSE.
    rv_status = gc_status_partial.
  ENDIF.
ENDMETHOD.

METHOD generate_json_response.
  " Final response structure with proper field mapping
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
         
  DATA: ls_final_response TYPE ty_final_response.
        
  " Map response data
  ls_final_response-response-grgislipno = is_response-grgislipno.
  ls_final_response-response-overallstatus = is_response-overallstatus.
  
  " Map results array
  LOOP AT is_response-results INTO DATA(ls_result).
    DATA(ls_final_result) = VALUE ty_final_result(
      grgislipno = ls_result-grgislipno
      status = ls_result-status
      migonumber = ls_result-migonumber
      error = ls_result-error
    ).
    APPEND ls_final_result TO ls_final_response-response-results.
  ENDLOOP.
  
  " Generate JSON with uppercase field names
  DATA(lv_response_json) = /ui2/cl_json=>serialize( 
    data = ls_final_response 
    compress = abap_false 
    pretty_name = /ui2/cl_json=>pretty_mode-upper_case 
  ).
  
  " Set response headers and content
  me->set_http_response( 
    iv_json = lv_response_json
    iv_status_code = me->get_http_status_code( is_response )
  ).
ENDMETHOD.

METHOD set_http_response.
  DATA: lo_response TYPE REF TO /iwbep/if_mgw_core_srv_runtime.
  
  lo_response = mo_context.
  
  lo_response->get_response( )->set_header( 
    name = 'Content-Type' 
    value = 'application/json; charset=utf-8' 
  ).
  
  lo_response->get_response( )->set_status( iv_status_code ).
  lo_response->get_response( )->set_text( iv_json ).
ENDMETHOD.

METHOD get_http_status_code.
  CASE is_response-overallstatus.
    WHEN gc_status_success.
      rv_status_code = gc_http_ok.
    WHEN gc_status_failed.
      rv_status_code = gc_http_bad_request.
    WHEN gc_status_partial.
      rv_status_code = gc_http_multi_status.
    WHEN OTHERS.
      rv_status_code = gc_http_bad_request.
  ENDCASE.
ENDMETHOD.

METHOD raise_business_exception.
  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
    EXPORTING
      textid = /iwbep/cx_mgw_busi_exception=>business_error
      message = iv_message
      http_status_code = '400'.
ENDMETHOD.