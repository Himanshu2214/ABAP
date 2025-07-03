" ================================================================
" ADD THESE TO YOUR EXISTING ZCL_ZMM01_MIGO_AUTO_DPC_EXT CLASS
" ================================================================

" Add to PUBLIC SECTION:
METHODS goodsmvtflatset_create_entity REDEFINITION.

" Add to PRIVATE SECTION:
METHODS: process_flat_record
           IMPORTING is_flat_record TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_flat_entity
           RETURNING VALUE(rs_result) TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_flat_entity,
         create_goods_movement_flat
           IMPORTING is_flat_record TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_flat_entity
           RETURNING VALUE(rv_mat_doc) TYPE string.

" ================================================================
" METHOD IMPLEMENTATIONS:
" ================================================================

METHOD goodsmvtflatset_create_entity.
  
  DATA: ls_flat_record TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_flat_entity,
        ls_result      TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_flat_entity.
  
  TRY.
      " Read the input data
      io_data_provider->read_entry_data( IMPORTING es_data = ls_flat_record ).
      
      " Process the record
      ls_result = process_flat_record( ls_flat_record ).
      
      " Add success message to context if successful
      IF ls_result-status = 'SUCCESS'.
        mo_context->get_message_container( )->add_message_text_only(
          iv_msg_text = ls_result-message
          iv_msg_type = 'S' ).
      ENDIF.
      
      " Return result
      copy_data_to_ref( EXPORTING is_data = ls_result 
                       CHANGING  cr_data = er_entity ).
      
    CATCH cx_root INTO DATA(lx_error).
      " Handle errors
      ls_result = ls_flat_record.
      ls_result-status = 'ERROR'.
      ls_result-message = lx_error->get_text( ).
      ls_result-mat_doc_num = ''.
      
      " Add error message to context
      mo_context->get_message_container( )->add_message_text_only(
        iv_msg_text = ls_result-message
        iv_msg_type = 'E' ).
      
      copy_data_to_ref( EXPORTING is_data = ls_result 
                       CHANGING  cr_data = er_entity ).
  ENDTRY.
  
ENDMETHOD.

METHOD process_flat_record.
  
  DATA: ls_result TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_flat_entity.
  
  " Copy input to result
  ls_result = is_flat_record.
  
  TRY.
      " Basic validation
      IF is_flat_record-material IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                    message = 'Material is required'.
      ENDIF.
      
      IF is_flat_record-plant IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                    message = 'Plant is required'.
      ENDIF.
      
      IF is_flat_record-quantity IS INITIAL OR is_flat_record-quantity <= 0.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                    message = 'Valid quantity is required'.
      ENDIF.
      
      IF is_flat_record-ztype_gm IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                    message = 'Goods Movement Type (ZtypeGm) is required'.
      ENDIF.
      
      IF is_flat_record-movementtype IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                    message = 'Movement Type is required'.
      ENDIF.
      
      " Create goods movement
      DATA(lv_mat_doc) = create_goods_movement_flat( is_flat_record ).
      
      " Success
      ls_result-status = 'SUCCESS'.
      ls_result-mat_doc_num = lv_mat_doc.
      ls_result-message = |Material Document { lv_mat_doc } created successfully|.
      
    CATCH cx_root INTO DATA(lx_error).
      " Error
      ls_result-status = 'ERROR'.
      ls_result-mat_doc_num = ''.
      ls_result-message = lx_error->get_text( ).
  ENDTRY.
  
  rs_result = ls_result.
  
ENDMETHOD.

METHOD create_goods_movement_flat.
  
  " BAPI variables
  DATA: ls_bapi_header TYPE bapi2017_gm_head_01,
        lv_bapi_gm_code TYPE gm_code,
        lt_bapi_items TYPE TABLE OF bapi2017_gm_item_create,
        ls_bapi_item TYPE bapi2017_gm_item_create,
        ls_bapi_headret TYPE bapi2017_gm_head_ret,
        lt_return TYPE bapiret2_t.
  
  " Map header data
  ls_bapi_header-doc_date = is_flat_record-doc_date.
  ls_bapi_header-pstng_date = is_flat_record-pstng_date.
  ls_bapi_header-header_txt = is_flat_record-header_txt.
  lv_bapi_gm_code = is_flat_record-ztype_gm.
  
  " Map item data
  ls_bapi_item-material = is_flat_record-material.
  ls_bapi_item-plant = is_flat_record-plant.
  ls_bapi_item-stge_loc = is_flat_record-strg_loc.
  ls_bapi_item-move_type = is_flat_record-movementtype.
  ls_bapi_item-entry_qnt = is_flat_record-quantity.
  ls_bapi_item-entry_uom = is_flat_record-base_uom.
  ls_bapi_item-gl_account = is_flat_record-gl_account.
  ls_bapi_item-costcenter = is_flat_record-costcenter.
  ls_bapi_item-orderid = is_flat_record-order_no.
  
  " Set default UOM if not provided
  IF ls_bapi_item-entry_uom IS INITIAL.
    ls_bapi_item-entry_uom = 'EA'. " Default to Each
  ENDIF.
  
  APPEND ls_bapi_item TO lt_bapi_items.
  
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
    DATA(lv_error) = COND string(
      WHEN sy-subrc = 1 THEN 'BAPI Communication Failure'
      WHEN sy-subrc = 2 THEN 'BAPI System Failure'
      ELSE |BAPI Technical Error (subrc: { sy-subrc })| ).
      
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                message = lv_error.
  ENDIF.
  
  " Check for business errors
  DATA(lv_has_errors) = COND abap_bool(
    WHEN line_exists( lt_return[ type = 'E' ] )
      OR line_exists( lt_return[ type = 'A' ] )
      OR line_exists( lt_return[ type = 'X' ] )
    THEN abap_true
    ELSE abap_false ).
  
  IF lv_has_errors = abap_true OR ls_bapi_headret-mat_doc IS INITIAL.
    " Collect error messages
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
    
    " Rollback
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                message = lv_error_details.
  ENDIF.
  
  " Success - commit
  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' EXPORTING wait = 'X'.
  
  rv_mat_doc = ls_bapi_headret-mat_doc.
  
ENDMETHOD.