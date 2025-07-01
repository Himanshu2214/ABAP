CLASS zcl_zgm_api_srv_dpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zgm_api_srv_dpc
  CREATE PUBLIC .

  PUBLIC SECTION.
    METHODS /iwbep/if_mgw_appl_srv_runtime~execute_action
        REDEFINITION .
  PROTECTED SECTION.
    METHODS postgoodsmovements_action
      IMPORTING
        !iv_action_name         TYPE /iwbep/if_mgw_appl_types=>ty_action_name
        !io_tech_request_context TYPE REF TO /iwbep/if_mgw_tech_req_context
      EXPORTING
        !er_data                TYPE zst_gma_response " Specific type for the response
      RAISING
        /iwbep/cx_mgw_busi_exception
        /iwbep/cx_mgw_tech_exception .

  PRIVATE SECTION.
    TYPES:
      tt_bapi_items TYPE STANDARD TABLE OF bapi2017_gm_item_create WITH EMPTY KEY.

    CONSTANTS:
      c_mvt_gi_963    TYPE bwart  VALUE '963',
      c_ztype_gm_gi   TYPE char10 VALUE 'A007',
      c_zsub_type_r10 TYPE char4  VALUE 'R10',
      c_gm_code_gi    TYPE gm_code VALUE '03',
      c_action_post_gm TYPE /iwbep/if_mgw_appl_types=>ty_action_name VALUE 'PostGoodsMovements'.


    METHODS map_to_bapi_format
      IMPORTING
        is_header_payload TYPE zstr_goodsmvt_api_header " Using your defined header structure
      EXPORTING
        es_bapi_header    TYPE bapi2017_gm_header_create
        ev_bapi_gm_code   TYPE bapi2017_gm_code-gm_code
        et_bapi_items     TYPE tt_bapi_items
      RAISING
        /iwbep/cx_mgw_busi_exception.

    METHODS validate_input_data " Renamed for clarity
      IMPORTING
        is_header_payload TYPE zstr_goodsmvt_api_header " Using your defined header structure
        iv_header_index   TYPE i
      RAISING
        /iwbep/cx_mgw_busi_exception.

ENDCLASS.



CLASS ZCL_ZGM_API_SRV_DPC_EXT IMPLEMENTATION.


  METHOD /iwbep/if_mgw_appl_srv_runtime~execute_action.
    IF iv_action_name = c_action_post_gm.
      postgoodsmovements_action(
        EXPORTING
          iv_action_name         = iv_action_name
          io_tech_request_context = io_tech_request_context
        IMPORTING
          er_data                = er_data
      ).
    ELSE.
      super->/iwbep/if_mgw_appl_srv_runtime~execute_action(
        EXPORTING
          iv_action_name         = iv_action_name
          iv_operation_type      = iv_operation_type
          it_key                 = it_key
          it_parameter           = it_parameter
          io_message_container   = io_message_container
          io_tech_request_context = io_tech_request_context
          io_dp_context          = io_dp_context
       ).
    ENDIF.
  ENDMETHOD.


  METHOD postgoodsmovements_action.

    DATA lt_headers_from_payload TYPE ztt_goodsmvt_api_headers_in. " Table of your ZSTR_GOODSMVT_API_HEADER
    DATA ls_header_for_loop    TYPE zstr_goodsmvt_api_header.

    DATA lt_bapi_items         TYPE tt_bapi_items.
    DATA ls_bapi_header        TYPE bapi2017_gm_header_create.
    DATA ls_bapi_headret       TYPE bapi2017_gm_head_ret.
    DATA lt_return             TYPE bapiret2_t.
    DATA lv_bapi_gm_code       TYPE gm_code.
    DATA lv_mblnr              TYPE mblnr.

    DATA lt_individual_results TYPE ztt_gma_result_items.
    DATA ls_individual_result  TYPE zst_gma_result_item.
    DATA ls_final_response     TYPE zst_gma_response.


    DATA lv_all_records_success TYPE abap_bool VALUE abap_true.
    DATA lv_any_record_succeeded TYPE abap_bool VALUE abap_false.
    DATA lv_json_xstring TYPE xstring.
    DATA lv_json_string TYPE string.

    FIELD-SYMBOLS: <ls_header_in> LIKE LINE OF lt_headers_from_payload.


    TRY.
        lv_json_xstring = io_tech_request_context->get_request_payload( ).
        IF lv_json_xstring IS INITIAL.
          RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
            EXPORTING
              textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
              message = 'Request payload is empty.'.
        ENDIF.

        lv_json_string = cl_abap_codepage=>convert_from( lv_json_xstring ).

        TRY.
            /ui2/cl_json=>deserialize(
              EXPORTING
                json = lv_json_string
              CHANGING
                data = lt_headers_from_payload ).
          CATCH /ui2/cx_json INTO DATA(lx_json).
            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                message = lx_json->get_text( ).
        ENDTRY.

      CATCH cx_sy_codepage_converter_error INTO DATA(lx_codepage).
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
            EXPORTING
              textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
              message = lx_codepage->get_text( ).
    ENDTRY.


    IF lt_headers_from_payload IS INITIAL.
      ls_final_response-overall_status = 'NO RECORDS TO PROCESS'.
      er_data = ls_final_response.
      RETURN.
    ENDIF.

    LOOP AT lt_headers_from_payload ASSIGNING <ls_header_in>.
      DATA(lv_current_header_index) = sy-tabix.
      CLEAR: ls_individual_result, ls_bapi_header, lv_bapi_gm_code, lt_bapi_items, lt_return, ls_bapi_headret, lv_mblnr.

      ls_individual_result-gr_gi_slip_no = <ls_header_in>-gr_gi_slip_no.
      ls_individual_result-success = abap_false. " Default to false

      TRY.
          validate_input_data( is_header_payload = <ls_header_in>
                               iv_header_index = lv_current_header_index ).

          map_to_bapi_format(
            EXPORTING
              is_header_payload = <ls_header_in>
            IMPORTING
              es_bapi_header    = ls_bapi_header
              ev_bapi_gm_code   = lv_bapi_gm_code
              et_bapi_items     = lt_bapi_items
          ).

          CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
            EXPORTING
              goodsmvt_header  = ls_bapi_header
              goodsmvt_code    = VALUE #( gm_code = lv_bapi_gm_code )
            IMPORTING
              goodsmvt_headret = ls_bapi_headret
              materialdocument = lv_mblnr
            TABLES
              goodsmvt_item    = lt_bapi_items
              return           = lt_return
            EXCEPTIONS
              OTHERS           = 1.

          IF sy-subrc <> 0.
            ls_individual_result-message = |BAPI System/Communication Error (SY-SUBRC: { sy-subrc })|.
            lv_all_records_success = abap_false.
            CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
            APPEND ls_individual_result TO lt_individual_results.
            CONTINUE.
          ENDIF.

          DATA(lv_bapi_error_found) = abap_false.
          LOOP AT lt_return INTO DATA(ls_return_msg) WHERE type = 'E' OR type = 'A' OR type = 'X'.
            lv_bapi_error_found = abap_true.
            ls_individual_result-message = ls_return_msg-message.
            EXIT. " Take first error message
          ENDLOOP.

          IF lv_bapi_error_found = abap_true OR lv_mblnr IS INITIAL.
            ls_individual_result-success = abap_false.
            lv_all_records_success = abap_false.
            IF ls_individual_result-message IS INITIAL.
                ls_individual_result-message = 'BAPI processing failed or no document created.'.
            ENDIF.
            CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
          ELSE.
            CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' EXPORTING wait = 'X'.
            IF sy-subrc = 0.
              ls_individual_result-success = abap_true;
              ls_individual_result-migo_number = lv_mblnr.
              ls_individual_result-message = |Goods Movement Posted: { ls_individual_result-migo_number }|.
              lv_any_record_succeeded = abap_true.
            ELSE.
              ls_individual_result-success = abap_false.
              ls_individual_result-message = 'Error during COMMIT WORK after BAPI success.'.
              lv_all_records_success = abap_false.
              " BAPI_TRANSACTION_ROLLBACK might be needed here if commit fails after BAPI was seemingly OK
              " but BAPI_GOODSMVT_CREATE should ideally handle its own LUW or BAPI_TRANSACTION_COMMIT handles it.
              " For safety, a rollback might be considered if commit fails.
            ENDIF.
          ENDIF.
        CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_busi).
          ls_individual_result-message = lx_busi->get_text( ).
          lv_all_records_success = abap_false.
        CATCH cx_root INTO DATA(lx_root_err). " Catch any other unexpected error
          ls_individual_result-message = lx_root_err->get_text( ).
          lv_all_records_success = abap_false.
      ENDTRY.
      APPEND ls_individual_result TO lt_individual_results.
    ENDLOOP.

    ls_final_response-results = lt_individual_results.
    IF lv_all_records_success = abap_true AND lt_headers_from_payload IS NOT INITIAL.
      ls_final_response-overall_status = 'ALL RECORDS : SUCCESS'.
    ELSEIF lv_any_record_succeeded = abap_true.
      ls_final_response-overall_status = 'PARTIAL SUCCESS'.
    ELSEIF lt_headers_from_payload IS NOT INITIAL.
      ls_final_response-overall_status = 'ALL FAILED'.
    ELSE. " Should be caught by the initial check if lt_headers_from_payload is initial
      ls_final_response-overall_status = 'NO RECORDS PROCESSED'.
    ENDIF.

    er_data = ls_final_response.

  ENDMETHOD.


  METHOD map_to_bapi_format.
    es_bapi_header = VALUE #(
        pstng_date = is_header_payload-pstng_date
        doc_date   = is_header_payload-doc_date
        ref_doc_no = is_header_payload-gr_gi_slip_no " BAPI field is CHAR16, input XABLN is CHAR10
        header_txt = is_header_payload-header_txt
    ).

    IF is_header_payload-movementtype = me->c_mvt_gi_963 AND
       is_header_payload-ztype_gm   = me->c_ztype_gm_gi AND
       is_header_payload-zsub_type  = me->c_zsub_type_r10.
      ev_bapi_gm_code = me->c_gm_code_gi.
    ELSE.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |Unsupported MvtType ({ is_header_payload-movementtype }), ZtypeGm ({ is_header_payload-ztype_gm }), or ZsubType ({ is_header_payload-zsub_type }) for Slip { is_header_payload-gr_gi_slip_no }.|.
    ENDIF.

    CLEAR et_bapi_items.
    IF is_header_payload-headertoitemnav IS NOT INITIAL.
      et_bapi_items = VALUE #( FOR ls_item_in IN is_header_payload-headertoitemnav
                               ( VALUE bapi2017_gm_item_create(
                                   material   = ls_item_in-material
                                   plant      = ls_item_in-plant
                                   stge_loc   = ls_item_in-strg_loc
                                   move_type  = is_header_payload-movementtype " '963'
                                   entry_qnt  = ls_item_in-quantity
                                   entry_uom  = ls_item_in-base_uom
                                   gl_account = ls_item_in-gl_account
                                   costcenter = ls_item_in-costcenter
                                   orderid    = ls_item_in-order_no
                                   line_id    = ls_item_in-item_no  " Mapped to CHAR6 BAPI field LINE_ID
                               ) ) ).
    ENDIF.
  ENDMETHOD.


  METHOD validate_input_data.
    " Basic mandatory field checks for header
    IF is_header_payload-ztype_gm IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}): ZTYPE_GM is mandatory.|.
    ENDIF.
    IF is_header_payload-zsub_type IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}): ZSUB_TYPE is mandatory.|.
    ENDIF.
    IF is_header_payload-movementtype IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}): MOVEMENTTYPE is mandatory.|.
    ENDIF.
    IF is_header_payload-doc_date IS INITIAL OR is_header_payload-doc_date = '00000000'.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}): DOC_DATE is mandatory and must be valid.|.
    ENDIF.
    IF is_header_payload-pstng_date IS INITIAL OR is_header_payload-pstng_date = '00000000'.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}): PSTNG_DATE is mandatory and must be valid.|.
    ENDIF.

    " Item checks
    IF is_header_payload-headertoitemnav IS INITIAL.
        " Depending on business logic, no items might be an error or allowed for some movement types.
        " For 963 GI, items are typically mandatory.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}): At least one item is required for movement type { is_header_payload-movementtype }.|.
    ENDIF.

    LOOP AT is_header_payload-headertoitemnav INTO DATA(ls_item).
      DATA(lv_current_item_index) = sy-tabix.
      IF ls_item-material IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}), Item { lv_current_item_index }: MATERIAL is mandatory.|.
      ENDIF.
      IF ls_item-item_no IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}), Item { lv_current_item_index }: ITEM_NO is mandatory.|.
      ENDIF.
      IF ls_item-mat_desc IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}), Item { lv_current_item_index }: MAT_DESC is mandatory.|.
      ENDIF.
      IF ls_item-base_uom IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}), Item { lv_current_item_index }: BASE_UOM is mandatory.|.
      ENDIF.
      IF ls_item-quantity IS INITIAL OR ls_item-quantity <= 0.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}), Item { lv_current_item_index }: QUANTITY must be positive and is mandatory.|.
      ENDIF.
      IF ls_item-strg_loc IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}), Item { lv_current_item_index }: STRG_LOC is mandatory.|.
      ENDIF.
      IF ls_item-plant IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}), Item { lv_current_item_index }: PLANT is mandatory.|.
      ENDIF.
      IF ls_item-gl_account IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}), Item { lv_current_item_index }: GL_ACCOUNT is mandatory.|.
      ENDIF.
      IF ls_item-costcenter IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}), Item { lv_current_item_index }: COSTCENTER is mandatory.|.
      ENDIF.
       IF ls_item-order_no IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}), Item { lv_current_item_index }: ORDER_NO is mandatory.|.
      ENDIF.
      IF ls_item-item_ok IS INITIAL OR ls_item-item_ok = abap_false.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception MESSAGE |Header { iv_header_index } ({is_header_payload-gr_gi_slip_no}), Item { lv_current_item_index } ({ls_item-material}): ITEM_OK must be true.|.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
