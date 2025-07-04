CLASS ZCL_ZMM_MIGO_AUTOMATIO_DPC_EXT DEFINITION
  PUBLIC
  INHERITING FROM ZCL_ZMM_MIGO_AUTOMATIO_DPC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    " Your existing public methods...

  PROTECTED SECTION.
    " Your existing protected methods...

  PRIVATE SECTION.
    " ===== ADD THIS COMPLETE PRIVATE SECTION =====
    
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

    " ===== METHOD DECLARATIONS (REQUIRED!) =====
    METHODS: validate_payload_structure
      IMPORTING is_deep_entity TYPE ty_deep_headerdummy
      RETURNING VALUE(rv_valid) TYPE abap_bool,

    validate_header
      IMPORTING is_header TYPE ty_header
                it_processed_slips TYPE string_table
      RETURNING VALUE(rv_error_msg) TYPE string,

    process_items
      IMPORTING it_items TYPE ty_items
      EXPORTING et_gm_items TYPE BAPI2017_GM_ITEM_CREATE_T
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
                it_gm_items TYPE BAPI2017_GM_ITEM_CREATE_T
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

    get_http_status_code
      IMPORTING is_response TYPE ty_response
      RETURNING VALUE(rv_status_code) TYPE i,

    raise_business_exception
      IMPORTING iv_message TYPE string.

ENDCLASS.