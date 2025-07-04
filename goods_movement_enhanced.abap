*&---------------------------------------------------------------------*
*& Enhanced Deep Entity Implementation for Goods Movement
*& Includes validation, error handling, and helper methods
*&---------------------------------------------------------------------*

CLASS zcl_goods_movement_helper DEFINITION.
  PUBLIC SECTION.
    " Constants for movement types
    CONSTANTS: BEGIN OF c_mvmt_type,
                 goods_issue   TYPE bapi2017_gm_code VALUE '03',
                 goods_receipt TYPE bapi2017_gm_code VALUE '01',
               END OF c_mvmt_type.
    
    " Helper methods
    CLASS-METHODS: validate_header_data
                     IMPORTING
                       is_header TYPE zcl_zgm_mpc=>ts_goodsmovementheader
                     RETURNING
                       VALUE(rv_valid) TYPE abap_bool,
                   
                   validate_item_data
                     IMPORTING
                       is_item TYPE zcl_zgm_mpc=>ts_goodsmovementitem
                     RETURNING
                       VALUE(rv_valid) TYPE abap_bool,
                   
                   convert_odata_date
                     IMPORTING
                       iv_odata_date TYPE string
                     RETURNING
                       VALUE(rv_date) TYPE sy-datum,
                   
                   map_to_bapi_header
                     IMPORTING
                       is_header TYPE zcl_zgm_mpc=>ts_goodsmovementheader
                     RETURNING
                       VALUE(rs_bapi_header) TYPE bapi2017_gm_head_01,
                   
                   map_to_bapi_item
                     IMPORTING
                       is_item TYPE zcl_zgm_mpc=>ts_goodsmovementitem
                       iv_move_type TYPE bapi2017_gm_item_create-move_type
                     RETURNING
                       VALUE(rs_bapi_item) TYPE bapi2017_gm_item_create.

ENDCLASS.

CLASS zcl_goods_movement_helper IMPLEMENTATION.

  METHOD validate_header_data.
    rv_valid = abap_true.
    
    " Validate required fields
    IF is_header-gr_gi_slip_no IS INITIAL OR
       is_header-movementtype IS INITIAL OR
       is_header-doc_date IS INITIAL OR
       is_header-pstng_date IS INITIAL.
      rv_valid = abap_false.
    ENDIF.
    
    " Validate movement type
    IF is_header-movementtype NOT IN ('101', '102', '261', '262', '551', '552', '963').
      rv_valid = abap_false.
    ENDIF.
    
  ENDMETHOD.

  METHOD validate_item_data.
    rv_valid = abap_true.
    
    " Validate required fields
    IF is_item-material IS INITIAL OR
       is_item-plant IS INITIAL OR
       is_item-quantity IS INITIAL OR
       is_item-base_uom IS INITIAL.
      rv_valid = abap_false.
    ENDIF.
    
    " Validate quantity is positive
    IF is_item-quantity <= 0.
      rv_valid = abap_false.
    ENDIF.
    
  ENDMETHOD.

  METHOD convert_odata_date.
    DATA: lv_timestamp TYPE string,
          lv_ticks TYPE i,
          lv_seconds TYPE i.
    
    " Extract timestamp from OData date format /Date(1750099200000)/
    FIND REGEX '\d+' IN iv_odata_date MATCH lv_timestamp.
    
    IF sy-subrc = 0.
      lv_ticks = lv_timestamp.
      lv_seconds = lv_ticks / 1000. " Convert milliseconds to seconds
      
      " Convert Unix timestamp to SAP date
      CALL FUNCTION 'CONVERT_DATE_TO_EXTERNAL'
        EXPORTING
          date_internal = lv_seconds
        IMPORTING
          date_external = rv_date
        EXCEPTIONS
          OTHERS = 1.
      
      IF sy-subrc <> 0.
        rv_date = sy-datum. " Use current date as fallback
      ENDIF.
    ELSE.
      rv_date = sy-datum.
    ENDIF.
    
  ENDMETHOD.

  METHOD map_to_bapi_header.
    rs_bapi_header-pstng_date = convert_odata_date( is_header-pstng_date ).
    rs_bapi_header-doc_date = convert_odata_date( is_header-doc_date ).
    rs_bapi_header-header_txt = is_header-header_txt.
    rs_bapi_header-ref_doc_no = is_header-gr_gi_slip_no.
  ENDMETHOD.

  METHOD map_to_bapi_item.
    rs_bapi_item-material = is_item-material.
    rs_bapi_item-plant = is_item-plant.
    rs_bapi_item-stge_loc = is_item-strg_loc.
    rs_bapi_item-move_type = iv_move_type.
    rs_bapi_item-entry_qnt = is_item-quantity.
    rs_bapi_item-entry_uom = is_item-base_uom.
    rs_bapi_item-gl_account = is_item-gl_account.
    rs_bapi_item-costcenter = is_item-costcenter.
    rs_bapi_item-orderid = is_item-order_no.
    rs_bapi_item-move_mat = is_item-material.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Main Deep Entity Method
*&---------------------------------------------------------------------*

METHOD headerdummyset_create_entity.

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

  " Get message container
  lo_message_container = mo_context->get_message_container( ).

  " Read the deep entity from request
  io_data_provider->read_entry_data( IMPORTING es_data = lv_deep_entity ).

  " Validate main payload
  IF lv_deep_entity-gr_gi_slip_no IS INITIAL.
    lo_message_container->add_message(
      iv_msg_type = 'E'
      iv_msg_text = 'GrGiSlipNo is required'
    ).
    RETURN.
  ENDIF.

  " Process each header
  LOOP AT lv_deep_entity-to_goods_mvmt_header INTO ls_header_data.
    
    CLEAR: ls_gm_header, lt_gm_items, ls_gm_code, lt_return,
           lv_error_occurred, lv_materialdoc, lv_matdocyear.
    
    " Validate header data
    IF zcl_goods_movement_helper=>validate_header_data( ls_header_data ) = abap_false.
      lo_message_container->add_message(
        iv_msg_type = 'E'
        iv_msg_text = |Invalid header data for slip: { ls_header_data-gr_gi_slip_no }|
      ).
      CONTINUE.
    ENDIF.
    
    " Map header to BAPI structure
    ls_gm_header = zcl_goods_movement_helper=>map_to_bapi_header( ls_header_data ).
    
    " Determine GM Code based on movement type
    CASE ls_header_data-movementtype.
      WHEN '101' OR '561' OR '563'. " Goods Receipt
        ls_gm_code-gm_code = zcl_goods_movement_helper=>c_mvmt_type-goods_receipt.
      WHEN '261' OR '551' OR '963'. " Goods Issue
        ls_gm_code-gm_code = zcl_goods_movement_helper=>c_mvmt_type-goods_issue.
      WHEN OTHERS.
        ls_gm_code-gm_code = zcl_goods_movement_helper=>c_mvmt_type-goods_issue.
    ENDCASE.
    
    " Count total items for this header
    DESCRIBE TABLE ls_header_data-to_goods_mvmt_item LINES lv_total_items.
    lv_processed_items = 0.
    
    " Process items for this header
    LOOP AT ls_header_data-to_goods_mvmt_item INTO ls_item_data.
      
      " Skip if ItemOk is false
      IF ls_item_data-item_ok = abap_false.
        lo_message_container->add_message(
          iv_msg_type = 'W'
          iv_msg_text = |Item { ls_item_data-item_no } skipped as ItemOk = false|
        ).
        CONTINUE.
      ENDIF.
      
      " Validate item data
      IF zcl_goods_movement_helper=>validate_item_data( ls_item_data ) = abap_false.
        lo_message_container->add_message(
          iv_msg_type = 'E'
          iv_msg_text = |Invalid item data for item: { ls_item_data-item_no }|
        ).
        CONTINUE.
      ENDIF.
      
      " Map item to BAPI structure
      ls_gm_item = zcl_goods_movement_helper=>map_to_bapi_item( 
        is_item = ls_item_data 
        iv_move_type = ls_header_data-movementtype 
      ).
      
      APPEND ls_gm_item TO lt_gm_items.
      lv_processed_items = lv_processed_items + 1.
      
    ENDLOOP.
    
    " Call BAPI only if we have valid items
    IF lt_gm_items IS NOT INITIAL.
      
      " Check material availability if required
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
            iv_msg_type = ls_return-type
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
          iv_msg_type = 'S'
          iv_msg_text = |Material document { lv_materialdoc } created for { lv_processed_items } items|
        ).
        
        " Process any warning messages
        LOOP AT lt_return INTO ls_return WHERE type = 'W'.
          lo_message_container->add_message(
            iv_msg_type = 'W'
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
        iv_msg_type = 'W'
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

  " Copy to output parameter
  copy_data_to_ref(
    EXPORTING
      is_data = lv_deep_entity
    CHANGING
      cr_data = er_entity
  ).

ENDMETHOD.