CLASS zcl_zgm_dpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zgm_dpc
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS: /iwbep/if_mgw_appl_srv_runtime~create_deep_entity REDEFINITION.

  PRIVATE SECTION.
    METHODS: process_goods_movement_deep
               IMPORTING
                 io_data_provider TYPE REF TO /iwbep/if_mgw_req_entity_c
                 iv_entity_set_name TYPE string
               RETURNING
                 VALUE(er_deep_entity) TYPE REF TO data
               RAISING
                 /iwbep/cx_mgw_busi_exception
                 /iwbep/cx_mgw_tech_exception.

ENDCLASS.

CLASS zcl_zgm_dpc_ext IMPLEMENTATION.

  METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

    DATA: lv_entity_set_name TYPE string,
          lv_entity_name     TYPE string.

    " Get entity information
    lv_entity_set_name = io_data_provider->get_entity_set_name( ).
    lv_entity_name = io_data_provider->get_entity_type_name( ).

    TRY.
        " Route to appropriate deep entity processor
        CASE lv_entity_set_name.
          WHEN 'HeaderDummySet'.
            er_deep_entity = process_goods_movement_deep(
              io_data_provider = io_data_provider
              iv_entity_set_name = lv_entity_set_name
            ).

          WHEN OTHERS.
            " Call parent implementation for other entity sets
            CALL METHOD super->/iwbep/if_mgw_appl_srv_runtime~create_deep_entity
              EXPORTING
                io_data_provider        = io_data_provider
                it_key_tab              = it_key_tab
                it_navigation_path      = it_navigation_path
                io_expand               = io_expand
                io_tech_request_context = io_tech_request_context
              IMPORTING
                er_deep_entity          = er_deep_entity.

        ENDCASE.

      CATCH /iwbep/cx_mgw_busi_exception.
        RAISE.
      CATCH /iwbep/cx_mgw_tech_exception.
        RAISE.
      CATCH OTHERS.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
          EXPORTING
            textid = /iwbep/cx_mgw_tech_exception=>internal_error.

    ENDTRY.

  ENDMETHOD.

  METHOD process_goods_movement_deep.

    DATA: lo_message_container TYPE REF TO /iwbep/if_message_container,
          lv_deep_entity        TYPE zcl_zgm_mpc=>ts_headerdummy,
          ls_header_data        TYPE zcl_zgm_mpc=>ts_goodsmovementheader,
          ls_item_data          TYPE zcl_zgm_mpc=>ts_goodsmovementitem.

    " BAPI structures
    DATA: ls_gm_header    TYPE bapi2017_gm_head_01,
          lt_gm_items     TYPE TABLE OF bapi2017_gm_item_create,
          ls_gm_item      TYPE bapi2017_gm_item_create,
          ls_gm_code      TYPE bapi2017_gm_code,
          lv_materialdoc  TYPE bapi2017_gm_head_ret-mat_doc,
          lv_matdocyear   TYPE bapi2017_gm_head_ret-doc_year,
          lt_return       TYPE TABLE OF bapiret2,
          ls_return       TYPE bapiret2.

    " Response structures
    DATA: lt_header_response TYPE TABLE OF zcl_zgm_mpc=>ts_goodsmovementheader,
          ls_header_response TYPE zcl_zgm_mpc=>ts_goodsmovementheader,
          lt_item_response   TYPE TABLE OF zcl_zgm_mpc=>ts_goodsmovementitem,
          ls_item_response   TYPE zcl_zgm_mpc=>ts_goodsmovementitem.

    " Error handling
    DATA: lv_error_occurred TYPE abap_bool,
          lv_batch_success  TYPE abap_bool,
          lv_processed_items TYPE i,
          lv_total_items    TYPE i.

    " Date conversion variables
    DATA: lv_timestamp TYPE string,
          lv_ticks     TYPE i,
          lv_doc_date  TYPE sy-datum,
          lv_post_date TYPE sy-datum.

    " Get message container
    lo_message_container = mo_context->get_message_container( ).

    " Read the deep entity from request
    io_data_provider->read_entry_data( IMPORTING es_data = lv_deep_entity ).

    " Validate main payload
    IF lv_deep_entity-gr_gi_slip_no IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid  = /iwbep/cx_mgw_busi_exception=>business_error
          message = 'GrGiSlipNo is required in payload'.
    ENDIF.

    " Validate that we have headers
    IF lv_deep_entity-to_goods_mvmt_header IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid  = /iwbep/cx_mgw_busi_exception=>business_error
          message = 'At least one header is required'.
    ENDIF.

    " Process each header
    LOOP AT lv_deep_entity-to_goods_mvmt_header INTO ls_header_data.

      CLEAR: ls_gm_header, lt_gm_items, ls_gm_code, lt_return,
             lv_error_occurred, lv_materialdoc, lv_matdocyear.

      " Validate header data
      IF ls_header_data-gr_gi_slip_no IS INITIAL OR
         ls_header_data-movementtype IS INITIAL OR
         ls_header_data-doc_date IS INITIAL OR
         ls_header_data-pstng_date IS INITIAL.
        
        lo_message_container->add_message(
          iv_msg_type = /iwbep/cl_mgw_med_provider=>gcs_message_type-error
          iv_msg_text = |Invalid header data for slip: { ls_header_data-gr_gi_slip_no }|
        ).
        CONTINUE.
      ENDIF.

      " Convert OData dates to SAP dates
      " Extract timestamp from /Date(1750099200000)/ format
      FIND REGEX '\d+' IN ls_header_data-doc_date MATCH lv_timestamp.
      IF sy-subrc = 0.
        lv_ticks = lv_timestamp.
        lv_doc_date = lv_ticks / 86400000 + 25567. " Convert to SAP date
      ELSE.
        lv_doc_date = sy-datum.
      ENDIF.

      FIND REGEX '\d+' IN ls_header_data-pstng_date MATCH lv_timestamp.
      IF sy-subrc = 0.
        lv_ticks = lv_timestamp.
        lv_post_date = lv_ticks / 86400000 + 25567. " Convert to SAP date
      ELSE.
        lv_post_date = sy-datum.
      ENDIF.

      " Fill GM Header
      ls_gm_header-pstng_date = lv_post_date.
      ls_gm_header-doc_date   = lv_doc_date.
      ls_gm_header-header_txt = ls_header_data-header_txt.
      ls_gm_header-ref_doc_no = ls_header_data-gr_gi_slip_no.

      " Determine GM Code based on movement type
      CASE ls_header_data-movementtype.
        WHEN '101' OR '561' OR '563'. " Goods Receipt
          ls_gm_code-gm_code = '01'.
        WHEN '261' OR '551' OR '963'. " Goods Issue
          ls_gm_code-gm_code = '03'.
        WHEN OTHERS.
          ls_gm_code-gm_code = '03'. " Default to goods issue
      ENDCASE.

      " Count total items for this header
      DESCRIBE TABLE ls_header_data-to_goods_mvmt_item LINES lv_total_items.
      lv_processed_items = 0.

      " Process items for this header
      LOOP AT ls_header_data-to_goods_mvmt_item INTO ls_item_data.

        " Skip if ItemOk is false
        IF ls_item_data-item_ok = abap_false.
          lo_message_container->add_message(
            iv_msg_type = /iwbep/cl_mgw_med_provider=>gcs_message_type-warning
            iv_msg_text = |Item { ls_item_data-item_no } skipped as ItemOk = false|
          ).
          CONTINUE.
        ENDIF.

        " Validate item data
        IF ls_item_data-material IS INITIAL OR
           ls_item_data-plant IS INITIAL OR
           ls_item_data-quantity IS INITIAL OR
           ls_item_data-base_uom IS INITIAL.
          
          lo_message_container->add_message(
            iv_msg_type = /iwbep/cl_mgw_med_provider=>gcs_message_type-error
            iv_msg_text = |Invalid item data for item: { ls_item_data-item_no }|
          ).
          CONTINUE.
        ENDIF.

        " Validate quantity is positive
        IF ls_item_data-quantity <= 0.
          lo_message_container->add_message(
            iv_msg_type = /iwbep/cl_mgw_med_provider=>gcs_message_type-error
            iv_msg_text = |Invalid quantity for item: { ls_item_data-item_no }|
          ).
          CONTINUE.
        ENDIF.

        CLEAR: ls_gm_item.

        " Fill GM Item
        ls_gm_item-material     = ls_item_data-material.
        ls_gm_item-plant        = ls_item_data-plant.
        ls_gm_item-stge_loc     = ls_item_data-strg_loc.
        ls_gm_item-move_type    = ls_header_data-movementtype.
        ls_gm_item-entry_qnt    = ls_item_data-quantity.
        ls_gm_item-entry_uom    = ls_item_data-base_uom.
        ls_gm_item-gl_account   = ls_item_data-gl_account.
        ls_gm_item-costcenter   = ls_item_data-costcenter.
        ls_gm_item-orderid      = ls_item_data-order_no.
        ls_gm_item-move_mat     = ls_item_data-material.

        APPEND ls_gm_item TO lt_gm_items.
        lv_processed_items = lv_processed_items + 1.

      ENDLOOP.

      " Call BAPI only if we have valid items
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

        " Check for errors
        READ TABLE lt_return INTO ls_return WITH KEY type = 'E'.
        IF sy-subrc = 0.
          " Error occurred - rollback
          CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
          lv_error_occurred = abap_true.

          " Collect all error messages
          LOOP AT lt_return INTO ls_return WHERE type = 'E' OR type = 'A'.
            lo_message_container->add_message(
              iv_msg_type = /iwbep/cl_mgw_med_provider=>gcs_message_type-error
              iv_msg_text = |{ ls_return-message } (Header: { ls_header_data-gr_gi_slip_no })|
            ).
          ENDLOOP.

          " Update header response with error
          ls_header_response = ls_header_data.
          ls_header_response-material_doc = ''.
          ls_header_response-doc_year = ''.
          ls_header_response-process_status = 'ERROR'.

        ELSE.
          " Success - commit
          CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
            EXPORTING
              wait = 'X'.

          lv_batch_success = abap_true.

          " Update header response with success
          ls_header_response = ls_header_data.
          ls_header_response-material_doc = lv_materialdoc.
          ls_header_response-doc_year = lv_matdocyear.
          ls_header_response-process_status = 'SUCCESS'.

          " Add success message
          lo_message_container->add_message(
            iv_msg_type = /iwbep/cl_mgw_med_provider=>gcs_message_type-success
            iv_msg_text = |Material document { lv_materialdoc } created for { lv_processed_items } items|
          ).

          " Process any warning messages
          LOOP AT lt_return INTO ls_return WHERE type = 'W'.
            lo_message_container->add_message(
              iv_msg_type = /iwbep/cl_mgw_med_provider=>gcs_message_type-warning
              iv_msg_text = ls_return-message
            ).
          ENDLOOP.

        ENDIF.

        " Update item responses
        LOOP AT ls_header_data-to_goods_mvmt_item INTO ls_item_data.
          ls_item_response = ls_item_data.
          IF lv_materialdoc IS NOT INITIAL AND ls_item_data-item_ok = abap_true.
            ls_item_response-material_doc = lv_materialdoc.
            ls_item_response-doc_year = lv_matdocyear.
            ls_item_response-process_status = 'SUCCESS'.
          ELSE.
            ls_item_response-process_status = 'ERROR'.
          ENDIF.
          APPEND ls_item_response TO lt_item_response.
        ENDLOOP.

      ELSE.
        " No valid items found
        lo_message_container->add_message(
          iv_msg_type = /iwbep/cl_mgw_med_provider=>gcs_message_type-warning
          iv_msg_text = |No valid items found for header { ls_header_data-gr_gi_slip_no }|
        ).

        ls_header_response = ls_header_data.
        ls_header_response-process_status = 'NO_ITEMS'.

      ENDIF.

      APPEND ls_header_response TO lt_header_response.

    ENDLOOP.

    " Prepare final response
    lv_deep_entity-to_goods_mvmt_header = lt_header_response.

    " Update item associations in response
    LOOP AT lv_deep_entity-to_goods_mvmt_header INTO ls_header_response.
      CLEAR: ls_header_response-to_goods_mvmt_item.
      LOOP AT lt_item_response INTO ls_item_response
           WHERE gr_gi_slip_no = ls_header_response-gr_gi_slip_no.
        APPEND ls_item_response TO ls_header_response-to_goods_mvmt_item.
      ENDLOOP.
      MODIFY lv_deep_entity-to_goods_mvmt_header FROM ls_header_response.
    ENDLOOP.

    " Set overall processing status
    IF lv_batch_success = abap_true.
      lv_deep_entity-process_status = 'SUCCESS'.
    ELSEIF lv_error_occurred = abap_true.
      lv_deep_entity-process_status = 'ERROR'.
    ELSE.
      lv_deep_entity-process_status = 'PARTIAL'.
    ENDIF.

    " Create reference for return
    CREATE DATA er_deep_entity TYPE zcl_zgm_mpc=>ts_headerdummy.
    ASSIGN er_deep_entity->* TO FIELD-SYMBOL(<ls_deep_entity>).
    <ls_deep_entity> = lv_deep_entity.

  ENDMETHOD.

ENDCLASS.