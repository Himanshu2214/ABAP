METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  " Data declarations
  DATA(ls_header_payload) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity( ).
  DATA: lt_items TYPE zcl_zmm01_migo_auto_mpc_ext=>tt_goodsmvtitem.
  
  " BAPI related variables
  DATA(ls_bapi_header)    = VALUE bapi2017_gm_head_01( ).
  DATA(lv_bapi_gm_code)   = VALUE gm_code( ).
  DATA(lt_bapi_items)     = VALUE tt_bapi_items( ).
  DATA(ls_bapi_headret)   = VALUE bapi2017_gm_head_ret( ).
  DATA(lt_return)         = VALUE bapiret2_t( ).
  
  " Response variables
  DATA: lv_error_message TYPE string.

  TRY.
      " Read input data
      io_data_provider->read_entry_data( IMPORTING es_data = ls_header_payload ).
      
      " Get items from the request
      lt_items = ls_header_payload-GoodsMvtItemSet.
      
      " Validate that we have exactly one item (since you mentioned it's always 1 record)
      IF lines( lt_items ) = 0.
        " Return error response
        DATA(ls_error_response) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity(
          gr_gi_slip_no = ls_header_payload-gr_gi_slip_no
          mat_doc_num = |Error: No items provided for processing| ).
          
        copy_data_to_ref(
          EXPORTING is_data = ls_error_response
          CHANGING  cr_data = er_deep_entity ).
        RETURN.
      ENDIF.

      " Process the item (taking first item from the set)
      DATA(ls_current_item) = lt_items[ 1 ].
      
      " Basic validation for required fields
      IF ls_current_item-material IS INITIAL.
        lv_error_message = 'Material is required'.
      ELSEIF ls_current_item-plant IS INITIAL.
        lv_error_message = 'Plant is required'.
      ELSEIF ls_current_item-quantity IS INITIAL OR ls_current_item-quantity <= 0.
        lv_error_message = 'Valid quantity is required'.
      ENDIF.
      
      " If validation failed, return error response
      IF lv_error_message IS NOT INITIAL.
        DATA(ls_validation_error_response) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity(
          gr_gi_slip_no = ls_header_payload-gr_gi_slip_no
          mat_doc_num = |Error: { lv_error_message }| ).
          
        copy_data_to_ref(
          EXPORTING is_data = ls_validation_error_response
          CHANGING  cr_data = er_deep_entity ).
        RETURN.
      ENDIF.

      " Validate using existing method (if needed, or skip if causing issues)
      TRY.
          validate_input_data( is_header_payload = ls_header_payload ).
        CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_validation).
          DATA(ls_custom_validation_error) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity(
            gr_gi_slip_no = ls_header_payload-gr_gi_slip_no
            mat_doc_num = |Error: { lx_validation->get_text( ) }| ).
            
          copy_data_to_ref(
            EXPORTING is_data = ls_custom_validation_error
            CHANGING  cr_data = er_deep_entity ).
          RETURN.
      ENDTRY.

      " Map to BAPI format
      map_to_bapi_format(
        EXPORTING is_header_payload = ls_header_payload
        IMPORTING es_bapi_header    = ls_bapi_header
                  ev_bapi_gm_code   = lv_bapi_gm_code
                  et_bapi_items     = lt_bapi_items ).

      " Override BAPI item with actual item data
      IF lines( lt_bapi_items ) > 0.
        DATA(ls_bapi_item) = lt_bapi_items[ 1 ].
        ls_bapi_item-material     = ls_current_item-material.
        ls_bapi_item-plant        = ls_current_item-plant.
        ls_bapi_item-stge_loc     = ls_current_item-strg_loc.
        ls_bapi_item-entry_qnt    = ls_current_item-quantity.
        ls_bapi_item-entry_uom    = ls_current_item-base_uom.
        ls_bapi_item-gl_account   = ls_current_item-gl_account.
        ls_bapi_item-costcenter   = ls_current_item-costcenter.
        ls_bapi_item-orderid      = ls_current_item-order_no.
        ls_bapi_item-move_type    = ls_header_payload-movementtype.
        
        " Update the BAPI item table
        MODIFY lt_bapi_items FROM ls_bapi_item INDEX 1.
      ENDIF.

      " Set BAPI header fields
      lv_bapi_gm_code = ls_header_payload-ztype_gm.
      ls_bapi_header-doc_date = ls_header_payload-doc_date.
      ls_bapi_header-pstng_date = ls_header_payload-pstng_date.
      ls_bapi_header-header_txt = ls_header_payload-header_txt.

      " Call BAPI
      CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
        EXPORTING
          goodsmvt_header  = ls_bapi_header
          goodsmvt_code    = VALUE bapi2017_gm_code( gm_code = lv_bapi_gm_code )
        IMPORTING
          goodsmvt_headret = ls_bapi_headret
        TABLES
          goodsmvt_item    = lt_bapi_items
          return           = lt_return
        EXCEPTIONS
          communication_failure = 1
          system_failure        = 2
          OTHERS                = 3.

      " Check BAPI result
      IF sy-subrc <> 0.
        " Technical error
        DATA(lv_technical_error) = COND string(
          WHEN sy-subrc = 1 THEN 'BAPI Communication Failure'
          WHEN sy-subrc = 2 THEN 'BAPI System Failure'
          ELSE |BAPI Technical Error (subrc: { sy-subrc })| ).
          
        DATA(ls_tech_error_response) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity(
          gr_gi_slip_no = ls_header_payload-gr_gi_slip_no
          mat_doc_num = |Error: { lv_technical_error }| ).
          
        copy_data_to_ref(
          EXPORTING is_data = ls_tech_error_response
          CHANGING  cr_data = er_deep_entity ).
        RETURN.
      ENDIF.

      " Check for business errors
      DATA(lv_has_errors) = COND abap_bool(
        WHEN line_exists( lt_return[ type = 'E' ] )
          OR line_exists( lt_return[ type = 'A' ] )
          OR line_exists( lt_return[ type = 'X' ] )
        THEN abap_true
        ELSE abap_false ).

      IF lv_has_errors = abap_true OR ls_bapi_headret-mat_doc IS INITIAL.
        " Business error - collect error messages
        DATA(lv_error_details) = VALUE string( ).
        LOOP AT lt_return INTO DATA(ls_return_msg) WHERE type CA 'AEX'.
          IF lv_error_details IS NOT INITIAL.
            lv_error_details = |{ lv_error_details }; { ls_return_msg-message }|.
          ELSE.
            lv_error_details = ls_return_msg-message.
          ENDIF.
        ENDLOOP.
        
        IF lv_error_details IS INITIAL.
          lv_error_details = 'BAPI indicated success but no Material Document was created'.
        ENDIF.
        
        " Return error response
        DATA(ls_bapi_error_response) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity(
          gr_gi_slip_no = ls_header_payload-gr_gi_slip_no
          mat_doc_num = |Error: { lv_error_details }| ).
          
        copy_data_to_ref(
          EXPORTING is_data = ls_bapi_error_response
          CHANGING  cr_data = er_deep_entity ).
          
        " Rollback transaction
        CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
        RETURN.
      ENDIF.

      " SUCCESS CASE - Commit and return success response
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' EXPORTING wait = 'X'.
      
      " Return simple success response
      DATA(ls_success_response) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity(
        gr_gi_slip_no = ls_header_payload-gr_gi_slip_no
        mat_doc_num = ls_bapi_headret-mat_doc ).

      " Add success message to container
      mo_context->get_message_container( )->add_message_text_only(
        iv_msg_text = |Material Document { ls_bapi_headret-mat_doc } created successfully|
        iv_msg_type = 'S' ).

      " Set response
      copy_data_to_ref(
        EXPORTING is_data = ls_success_response
        CHANGING  cr_data = er_deep_entity ).

    CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_busi_exception).
      " Handle business exceptions
      DATA(ls_exception_response) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity(
        gr_gi_slip_no = ls_header_payload-gr_gi_slip_no
        mat_doc_num = |Error: { lx_busi_exception->get_text( ) }| ).
        
      copy_data_to_ref(
        EXPORTING is_data = ls_exception_response
        CHANGING  cr_data = er_deep_entity ).

    CATCH cx_root INTO DATA(lx_root).
      " Handle unexpected technical errors
      DATA(ls_root_exception_response) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity(
        gr_gi_slip_no = ls_header_payload-gr_gi_slip_no
        mat_doc_num = |Error: Technical error - { lx_root->get_text( ) }| ).
        
      copy_data_to_ref(
        EXPORTING is_data = ls_root_exception_response
        CHANGING  cr_data = er_deep_entity ).

  ENDTRY.

ENDMETHOD.