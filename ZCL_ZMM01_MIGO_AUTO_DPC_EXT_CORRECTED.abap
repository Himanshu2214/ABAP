class ZCL_ZMM01_MIGO_AUTO_DPC_EXT definition
  public
  inheriting from ZCL_ZMM01_MIGO_AUTO_DPC
  create public .

public section.

  methods /IWBEP/IF_MGW_APPL_SRV_RUNTIME~CREATE_DEEP_ENTITY
    redefinition .

  " Add the new flat structure method
  methods goodsmvtflatset_create_entity redefinition.

protected section.
private section.

  CONSTANTS:
    c_mvt_gi_963        TYPE bapi2017_gm_item_create-move_type VALUE '963',
    c_gm_code_for_963   TYPE bapi2017_gm_code-gm_code VALUE '03',
    c_ztype_gm_gi       TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity-ztype_gm VALUE 'A007'.  " or whatever constant you expect

 TYPES:
    tt_bapi_items TYPE STANDARD TABLE OF bapi2017_gm_item_create WITH EMPTY KEY.

METHODS:
      " Existing methods
      validate_input_data
        IMPORTING is_header_payload TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity
                RAISING
        /iwbep/cx_mgw_busi_exception,

       map_to_bapi_format
         IMPORTING
           is_header_payload TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity
         EXPORTING
           es_bapi_header TYPE bapi2017_gm_head_01
           ev_bapi_gm_code TYPE gm_code
           et_bapi_items TYPE tt_bapi_items
         RAISING /iwbep/cx_mgw_busi_exception,

      " New methods for flat structure
      process_flat_record
        IMPORTING is_flat_record TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_flat_entity
        RETURNING VALUE(rs_result) TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_flat_entity,
        
      create_goods_movement_flat
        IMPORTING is_flat_record TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_flat_entity
        RETURNING VALUE(rv_mat_doc) TYPE string.

ENDCLASS.

CLASS ZCL_ZMM01_MIGO_AUTO_DPC_EXT IMPLEMENTATION.

METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  DATA(ls_header_payload) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity( ).
  DATA(ls_bapi_header)    = VALUE bapi2017_gm_head_01( ).
  DATA(lv_bapi_gm_code)   = VALUE gm_code( ).
  DATA(lt_bapi_items)     = VALUE tt_bapi_items( ).
  DATA(ls_bapi_headret)   = VALUE bapi2017_gm_head_ret( ).
  DATA(lt_return)         = VALUE bapiret2_t( ).
  DATA lo_message_container TYPE REF TO /iwbep/if_message_container.

  io_data_provider->read_entry_data( IMPORTING es_data = ls_header_payload ).

  TRY.
      " Validate input payload
      validate_input_data( is_header_payload = ls_header_payload ).

      " Map input to BAPI format
      map_to_bapi_format(
        EXPORTING is_header_payload = ls_header_payload
        IMPORTING es_bapi_header    = ls_bapi_header
                  ev_bapi_gm_code   = lv_bapi_gm_code
                  et_bapi_items     = lt_bapi_items ).

      " Call BAPI to create goods movement
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

      IF sy-subrc <> 0.
        " Raise exception for BAPI failures
        RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
          textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = COND #(
                      WHEN sy-subrc = 1 THEN |BAPI Communication Failure (sy-subrc: { sy-subrc })|
                      WHEN sy-subrc = 2 THEN |BAPI System Failure (sy-subrc: { sy-subrc })|
                      ELSE                   |BAPI Error (OTHERS) - sy-subrc: { sy-subrc }| ) ).
      ENDIF.

      " Check for error messages returned by BAPI
      DATA(lv_has_errors) = COND abap_bool(
        WHEN line_exists( lt_return[ type = 'E' ] )
          OR line_exists( lt_return[ type = 'A' ] )
          OR line_exists( lt_return[ type = 'X' ] )
        THEN abap_true
        ELSE abap_false ).

      IF lv_has_errors = abap_true OR ls_bapi_headret-mat_doc IS INITIAL.
        DATA(lo_busi_exception) = NEW /iwbep/cx_mgw_busi_exception(
                                          textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                                          message = 'Goods movement posting failed; see details.' ).

        lo_message_container = lo_busi_exception->get_msg_container( ).

        LOOP AT lt_return INTO DATA(ls_return_msg).
          lo_message_container->add_message_from_bapi(
            is_bapi_message   = ls_return_msg
            iv_message_target = COND string(
                                  WHEN ls_return_msg-type CA 'AEX'
                                  THEN |{ ls_return_msg-field }|
                                  ELSE || ) ).
        ENDLOOP.

        " If no error messages but no material doc created, add error message
        IF lv_has_errors = abap_false AND ls_bapi_headret-mat_doc IS INITIAL.
          lo_message_container->add_message_text_only(
            iv_msg_text = 'BAPI indicated success but no Material Document was created. Check messages.'
            iv_msg_type = 'E' ).
        ENDIF.

        RAISE EXCEPTION lo_busi_exception.

      ELSE. " SUCCESS CASE

        " Commit the transaction
        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING
            wait = 'X'.

        " Prepare response structure with additional details
        DATA(ls_response) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_goodsmvtheader1(
            mat_doc_num   = ls_bapi_headret-mat_doc
            response_msg  = |Goods Movement created successfully: { ls_bapi_headret-mat_doc }|
            gr_gi_slip_no = ls_header_payload-gr_gi_slip_no
            success_flag  = 'X' ).

        " Set response format to JSON (ensure proper content type)
        mo_context->get_message_container( )->add_message_text_only(
          iv_msg_text = 'Success'
          iv_msg_type = 'S' ).

        " Populate deep entity with response data
        copy_data_to_ref(
          EXPORTING is_data = ls_response
          CHANGING  cr_data = er_deep_entity ).

      ENDIF.

    CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_busi_exception).
      RAISE EXCEPTION lx_busi_exception.

    CATCH cx_root INTO DATA(lx_root).
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message = |An unexpected technical error occurred. Details: { lx_root->get_text( ) }| ).

  ENDTRY.

ENDMETHOD.

" ================================================================
" NEW FLAT STRUCTURE METHODS
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
  ls_bapi_header-ref_doc_no = is_flat_record-gr_gi_slip_no.
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

" ================================================================
" EXISTING METHODS (UNCHANGED)
" ================================================================

METHOD validate_input_data.
  " --- Header Validations ---

  " Validate ZtypeGm - must be Goods Issue type
  IF is_header_payload-ztype_gm <> c_ztype_gm_gi.
    RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
      textid            = /iwbep/cx_mgw_busi_exception=>business_error
      message_unlimited = |Invalid ZtypeGm: '{ is_header_payload-ztype_gm }'. Only '{ c_ztype_gm_gi }' (Goods Issue) is supported.| ).
  ENDIF.

  " Validate Movementtype - must be 963 for Goods Issue
  IF is_header_payload-movementtype <> c_mvt_gi_963.
    RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
      textid            = /iwbep/cx_mgw_busi_exception=>business_error
      message_unlimited = |Invalid Movementtype: '{ is_header_payload-movementtype }'. Only '{ c_mvt_gi_963 }' is supported for ZtypeGm '{ c_ztype_gm_gi }'.| ).
  ENDIF.

  " GR/GI Slip Number is mandatory and must be unique
  IF is_header_payload-gr_gi_slip_no IS INITIAL.
    RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
      textid            = /iwbep/cx_mgw_busi_exception=>business_error
      message_unlimited = 'Material Slip Number (GR_GI_SLIP_NO) is mandatory.' ).
  ELSE.
    SELECT COUNT(*) FROM mkpf INTO @DATA(lv_slip_count_mkpf) WHERE xblnr = @is_header_payload-gr_gi_slip_no.
    IF sy-subrc = 0 AND lv_slip_count_mkpf > 0.
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid            = /iwbep/cx_mgw_busi_exception=>business_error
        message_unlimited = |Duplicate Slip Number: { is_header_payload-gr_gi_slip_no } already exists in system.| ).
    ENDIF.
  ENDIF.

  " Document Date must be present
  IF is_header_payload-doc_date IS INITIAL.
    RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
      textid            = /iwbep/cx_mgw_busi_exception=>business_error
      message_unlimited = |Document Date (DocDate) is mandatory for Slip No { is_header_payload-gr_gi_slip_no }.| ).
  ENDIF.

  " Posting Date must be present
  IF is_header_payload-pstng_date IS INITIAL.
    RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
      textid            = /iwbep/cx_mgw_busi_exception=>business_error
      message_unlimited = |Posting Date (PstngDate) is mandatory for Slip No { is_header_payload-gr_gi_slip_no }.| ).
  ENDIF.

  " --- Item Level Validations ---

  " Ensure item set is not empty
  IF is_header_payload-goodsmvtitemset IS INITIAL.
    RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
      textid            = /iwbep/cx_mgw_busi_exception=>business_error
      message_unlimited = |No items found for Slip No { is_header_payload-gr_gi_slip_no }.| ).
  ENDIF.

  " Check for duplicate item numbers in payload
  DATA lt_item_numbers TYPE STANDARD TABLE OF zcl_zmm01_migo_auto_mpc_ext=>ts_goodsmvtitem1-item_no WITH EMPTY KEY.
  LOOP AT is_header_payload-goodsmvtitemset ASSIGNING FIELD-SYMBOL(<fs_item_check_dup>).
    IF <fs_item_check_dup>-item_no IS NOT INITIAL.
      IF line_exists( lt_item_numbers[ table_line = <fs_item_check_dup>-item_no ] ).
        RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
          textid            = /iwbep/cx_mgw_busi_exception=>business_error
          message_unlimited = |Duplicate Item No ({ <fs_item_check_dup>-item_no }) in payload for Slip No { is_header_payload-gr_gi_slip_no }.| ).
      ENDIF.
      INSERT <fs_item_check_dup>-item_no INTO TABLE lt_item_numbers.
    ELSE.
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid            = /iwbep/cx_mgw_busi_exception=>business_error
        message_unlimited = |Item No is mandatory for Material { <fs_item_check_dup>-material } in Slip No { is_header_payload-gr_gi_slip_no }.| ).
    ENDIF.
  ENDLOOP.

  " Validate mandatory fields on each item
  LOOP AT is_header_payload-goodsmvtitemset ASSIGNING FIELD-SYMBOL(<fs_item>).
    DATA(lv_item_id_for_msg) = |Mat '{ <fs_item>-material }' Item '{ <fs_item>-item_no }' in Slip '{ is_header_payload-gr_gi_slip_no }'|.

    IF <fs_item>-material IS INITIAL.
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid            = /iwbep/cx_mgw_busi_exception=>business_error
        message_unlimited = |Material Code is mandatory. { lv_item_id_for_msg }| ).
    ENDIF.

    IF <fs_item>-base_uom IS INITIAL.
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid            = /iwbep/cx_mgw_busi_exception=>business_error
        message_unlimited = |UOM (BaseUom) is mandatory. { lv_item_id_for_msg }| ).
    ENDIF.

    IF <fs_item>-quantity IS INITIAL OR <fs_item>-quantity <= 0.
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid            = /iwbep/cx_mgw_busi_exception=>business_error
        message_unlimited = |Quantity must be > 0. { lv_item_id_for_msg }| ).
    ENDIF.

    IF <fs_item>-plant IS INITIAL.
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid            = /iwbep/cx_mgw_busi_exception=>business_error
        message_unlimited = |Plant is mandatory. { lv_item_id_for_msg }| ).
    ENDIF.

    IF <fs_item>-strg_loc IS INITIAL.
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid            = /iwbep/cx_mgw_busi_exception=>business_error
        message_unlimited = |Storage Location (StrgLoc) is mandatory. { lv_item_id_for_msg }| ).
    ENDIF.

    " Check if Plant + Storage Location combo exists in T001L
    IF <fs_item>-plant IS NOT INITIAL AND <fs_item>-strg_loc IS NOT INITIAL.
      SELECT SINGLE @abap_true FROM t001l INTO @DATA(lv_found_sloc)
        WHERE werks = @<fs_item>-plant AND lgort = @<fs_item>-strg_loc.
      IF sy-subrc <> 0.
        RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
          textid            = /iwbep/cx_mgw_busi_exception=>business_error
          message_unlimited = |Invalid Plant/SLoc. { lv_item_id_for_msg }| ).
      ENDIF.
    ENDIF.

    IF <fs_item>-gl_account IS INITIAL.
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid            = /iwbep/cx_mgw_busi_exception=>business_error
        message_unlimited = |GL Account is mandatory. { lv_item_id_for_msg }| ).
    ENDIF.

    IF <fs_item>-costcenter IS INITIAL.
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid            = /iwbep/cx_mgw_busi_exception=>business_error
        message_unlimited = |Cost Center is mandatory. { lv_item_id_for_msg }| ).
    ENDIF.

    IF <fs_item>-order_no IS INITIAL.
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid            = /iwbep/cx_mgw_busi_exception=>business_error
        message_unlimited = |Order No is mandatory. { lv_item_id_for_msg }| ).
    ENDIF.

    IF <fs_item>-item_ok IS INITIAL.
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid            = /iwbep/cx_mgw_busi_exception=>business_error
        message_unlimited = |Item OK flag is mandatory. { lv_item_id_for_msg }| ).
    ENDIF.

  ENDLOOP.
ENDMETHOD.

METHOD map_to_bapi_format.
  es_bapi_header = VALUE #( pstng_date = is_header_payload-pstng_date
                            doc_date   = is_header_payload-doc_date
                            ref_doc_no = is_header_payload-gr_gi_slip_no
                            header_txt = is_header_payload-header_txt ).

  IF is_header_payload-movementtype = c_mvt_gi_963 AND is_header_payload-ztype_gm = c_ztype_gm_gi.
    ev_bapi_gm_code = c_gm_code_for_963. " Should be '03'
  ELSE.
    " This case should ideally be caught by validate_input_data already
    RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception( textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                                                      message = |Unsupported MvtType ({ is_header_payload-movementtype }) or ZtypeGm ({ is_header_payload-ztype_gm }) for Slip { is_header_payload-gr_gi_slip_no }.| ).

  ENDIF.

  et_bapi_items = VALUE #( FOR <fs_item> IN is_header_payload-goodsmvtitemset
                           ( VALUE
                             bapi2017_gm_item_create( material   = <fs_item>-material
                                                      plant      = <fs_item>-plant
                                                      stge_loc   = <fs_item>-strg_loc
                                                      move_type  = is_header_payload-movementtype
                                                      entry_qnt  = <fs_item>-quantity
                                                      entry_uom  = <fs_item>-base_uom
                                                      gl_account = <fs_item>-gl_account
                                                      costcenter = <fs_item>-costcenter
                                                      orderid    = <fs_item>-order_no    ) ) ).
ENDMETHOD.

ENDCLASS.