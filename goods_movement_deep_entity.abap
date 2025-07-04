METHOD headerdummyset_create_entity.

  DATA: lo_message_container TYPE REF TO /iwbep/if_message_container,
        lv_grgi_slip_no       TYPE string,
        lt_header_data        TYPE TABLE OF zcl_zgm_mpc=>ts_goodsmovementheader,
        ls_header_data        TYPE zcl_zgm_mpc=>ts_goodsmovementheader,
        lt_item_data          TYPE TABLE OF zcl_zgm_mpc=>ts_goodsmovementitem,
        ls_item_data          TYPE zcl_zgm_mpc=>ts_goodsmovementitem,
        lv_deep_entity        TYPE zcl_zgm_mpc=>ts_headerdummy.

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

  " Get message container
  lo_message_container = mo_context->get_message_container( ).

  " Read the deep entity from request
  io_data_provider->read_entry_data( IMPORTING es_data = lv_deep_entity ).

  " Get the slip number
  lv_grgi_slip_no = lv_deep_entity-gr_gi_slip_no.

  " Process each header
  LOOP AT lv_deep_entity-to_goods_mvmt_header INTO ls_header_data.
    
    CLEAR: ls_gm_header, lt_gm_items, ls_gm_code, lt_return.
    
    " Fill GM Header
    ls_gm_header-pstng_date = ls_header_data-pstng_date.
    ls_gm_header-doc_date   = ls_header_data-doc_date.
    ls_gm_header-header_txt = ls_header_data-header_txt.
    
    " Set GM Code based on movement type
    ls_gm_code-gm_code = ls_header_data-movementtype.
    
    " Process items for this header
    LOOP AT ls_header_data-to_goods_mvmt_item INTO ls_item_data.
      
      " Skip if ItemOk is false
      IF ls_item_data-item_ok = abap_false.
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
      
      APPEND ls_gm_item TO lt_gm_items.
      
    ENDLOOP.
    
    " Call BAPI only if we have valid items
    IF lt_gm_items IS NOT INITIAL.
      
      CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
        EXPORTING
          goodsmvt_header  = ls_gm_header
          goodsmvt_code    = ls_gm_code
        IMPORTING
          materialdocument = lv_materialdoc
          matdocumentyear  = lv_matdocyear
        TABLES
          goodsmvt_item    = lt_gm_items
          return           = lt_return.
      
      " Check for errors
      READ TABLE lt_return INTO ls_return WITH KEY type = 'E'.
      IF sy-subrc = 0.
        " Error occurred - rollback
        CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
        
        " Add error message
        lo_message_container->add_message(
          iv_msg_type = 'E'
          iv_msg_text = |Error in goods movement: { ls_return-message }|
        ).
        
        " Update header response with error
        ls_header_response = ls_header_data.
        ls_header_response-material_doc = ''.
        ls_header_response-doc_year = ''.
        
      ELSE.
        " Success - commit
        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING
            wait = 'X'.
        
        " Update header response with success
        ls_header_response = ls_header_data.
        ls_header_response-material_doc = lv_materialdoc.
        ls_header_response-doc_year = lv_matdocyear.
        
        " Add success message
        lo_message_container->add_message(
          iv_msg_type = 'S'
          iv_msg_text = |Material document { lv_materialdoc } created successfully|
        ).
        
      ENDIF.
      
      " Update item responses
      LOOP AT ls_header_data-to_goods_mvmt_item INTO ls_item_data.
        ls_item_response = ls_item_data.
        IF lv_materialdoc IS NOT INITIAL.
          ls_item_response-material_doc = lv_materialdoc.
          ls_item_response-doc_year = lv_matdocyear.
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
      
    ENDIF.
    
    APPEND ls_header_response TO lt_header_response.
    
  ENDLOOP.

  " Prepare response deep entity
  lv_deep_entity-to_goods_mvmt_header = lt_header_response.
  
  " Update item associations in headers
  LOOP AT lv_deep_entity-to_goods_mvmt_header INTO ls_header_response.
    CLEAR: lt_item_response.
    LOOP AT lt_item_response INTO ls_item_response 
         WHERE gr_gi_slip_no = ls_header_response-gr_gi_slip_no.
      APPEND ls_item_response TO ls_header_response-to_goods_mvmt_item.
    ENDLOOP.
    MODIFY lv_deep_entity-to_goods_mvmt_header FROM ls_header_response.
  ENDLOOP.

  " Copy to output parameter
  copy_data_to_ref(
    EXPORTING
      is_data = lv_deep_entity
    CHANGING
      cr_data = er_entity
  ).

ENDMETHOD.