CLASS zcl_zmm01_migo_auto_dpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zmm01_migo_auto_dpc
  CREATE PUBLIC .

  PUBLIC SECTION.
    METHODS goodsmvtflatset_create_entity REDEFINITION.
    
  PRIVATE SECTION.
    METHODS: process_flat_records
               IMPORTING it_flat_records TYPE zcl_zmm01_migo_auto_mpc_ext=>tt_flat_entity
               RETURNING VALUE(rt_results) TYPE zcl_zmm01_migo_auto_mpc_ext=>tt_flat_entity,
               
             group_records_by_header
               IMPORTING it_flat_records TYPE zcl_zmm01_migo_auto_mpc_ext=>tt_flat_entity
               RETURNING VALUE(rt_grouped) TYPE TABLE,
               
             create_goods_movement
               IMPORTING is_header TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_flat_entity
                         it_items TYPE zcl_zmm01_migo_auto_mpc_ext=>tt_flat_entity
               RETURNING VALUE(rv_mat_doc) TYPE string.

ENDCLASS.

CLASS zcl_zmm01_migo_auto_dpc_ext IMPLEMENTATION.

  METHOD goodsmvtflatset_create_entity.
    
    DATA: lt_flat_records TYPE zcl_zmm01_migo_auto_mpc_ext=>tt_flat_entity,
          ls_flat_record  TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_flat_entity,
          lt_results      TYPE zcl_zmm01_migo_auto_mpc_ext=>tt_flat_entity.
    
    TRY.
        " Read the input data - could be single record or multiple records
        io_data_provider->read_entry_data( IMPORTING es_data = ls_flat_record ).
        
        " For now, handle single record (can be extended for batch later)
        APPEND ls_flat_record TO lt_flat_records.
        
        " Process the records
        lt_results = process_flat_records( lt_flat_records ).
        
        " Return the first result (or modify to handle multiple)
        IF lines( lt_results ) > 0.
          DATA(ls_result) = lt_results[ 1 ].
          copy_data_to_ref( EXPORTING is_data = ls_result 
                           CHANGING  cr_data = er_entity ).
        ENDIF.
        
      CATCH cx_root INTO DATA(lx_error).
        " Handle errors
        ls_flat_record-status = 'ERROR'.
        ls_flat_record-message = lx_error->get_text( ).
        ls_flat_record-mat_doc_num = ''.
        
        copy_data_to_ref( EXPORTING is_data = ls_flat_record 
                         CHANGING  cr_data = er_entity ).
    ENDTRY.
    
  ENDMETHOD.

  METHOD process_flat_records.
    
    DATA: lt_results TYPE zcl_zmm01_migo_auto_mpc_ext=>tt_flat_entity,
          ls_result  TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_flat_entity.
    
    " Group records by header information
    DATA: BEGIN OF ls_group,
            gr_gi_slip_no TYPE xabln,
            ztype_gm      TYPE char10,
            zsub_type     TYPE char4,
            movementtype  TYPE bwart,
            doc_date      TYPE string,
            pstng_date    TYPE string,
            header_txt    TYPE bktxt,
            items         TYPE zcl_zmm01_migo_auto_mpc_ext=>tt_flat_entity,
          END OF ls_group,
          lt_groups LIKE TABLE OF ls_group.
    
    " Process each record
    LOOP AT it_flat_records INTO DATA(ls_record).
      
      " Find or create group for this record
      READ TABLE lt_groups INTO ls_group
        WITH KEY gr_gi_slip_no = ls_record-gr_gi_slip_no
                 ztype_gm = ls_record-ztype_gm
                 movementtype = ls_record-movementtype.
                 
      IF sy-subrc <> 0.
        " Create new group
        CLEAR ls_group.
        ls_group-gr_gi_slip_no = ls_record-gr_gi_slip_no.
        ls_group-ztype_gm = ls_record-ztype_gm.
        ls_group-zsub_type = ls_record-zsub_type.
        ls_group-movementtype = ls_record-movementtype.
        ls_group-doc_date = ls_record-doc_date.
        ls_group-pstng_date = ls_record-pstng_date.
        ls_group-header_txt = ls_record-header_txt.
        APPEND ls_record TO ls_group-items.
        APPEND ls_group TO lt_groups.
      ELSE.
        " Add to existing group
        APPEND ls_record TO ls_group-items.
        MODIFY lt_groups FROM ls_group INDEX sy-tabix.
      ENDIF.
      
    ENDLOOP.
    
    " Process each group (goods movement)
    LOOP AT lt_groups INTO ls_group.
      
      DATA(ls_header) = ls_group-items[ 1 ]. " Use first item as header template
      
      TRY.
          " Create goods movement for this group
          DATA(lv_mat_doc) = create_goods_movement( 
            is_header = ls_header
            it_items = ls_group-items ).
          
          " Mark all items in this group as successful
          LOOP AT ls_group-items INTO DATA(ls_item).
            ls_result = ls_item.
            ls_result-status = 'SUCCESS'.
            ls_result-mat_doc_num = lv_mat_doc.
            ls_result-message = |Material Document { lv_mat_doc } created successfully|.
            APPEND ls_result TO lt_results.
          ENDLOOP.
          
        CATCH cx_root INTO DATA(lx_error).
          " Mark all items in this group as failed
          LOOP AT ls_group-items INTO ls_item.
            ls_result = ls_item.
            ls_result-status = 'ERROR'.
            ls_result-mat_doc_num = ''.
            ls_result-message = lx_error->get_text( ).
            APPEND ls_result TO lt_results.
          ENDLOOP.
      ENDTRY.
      
    ENDLOOP.
    
    rt_results = lt_results.
    
  ENDMETHOD.

  METHOD create_goods_movement.
    
    " BAPI variables
    DATA: ls_bapi_header TYPE bapi2017_gm_head_01,
          lv_bapi_gm_code TYPE gm_code,
          lt_bapi_items TYPE TABLE OF bapi2017_gm_item_create,
          ls_bapi_item TYPE bapi2017_gm_item_create,
          ls_bapi_headret TYPE bapi2017_gm_head_ret,
          lt_return TYPE bapiret2_t.
    
    " Validate input
    IF is_header-material IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                  message = 'Material is required'.
    ENDIF.
    
    IF is_header-plant IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                  message = 'Plant is required'.
    ENDIF.
    
    " Map header data
    ls_bapi_header-doc_date = is_header-doc_date.
    ls_bapi_header-pstng_date = is_header-pstng_date.
    ls_bapi_header-header_txt = is_header-header_txt.
    lv_bapi_gm_code = is_header-ztype_gm.
    
    " Map items
    LOOP AT it_items INTO DATA(ls_item).
      
      CLEAR ls_bapi_item.
      ls_bapi_item-material = ls_item-material.
      ls_bapi_item-plant = ls_item-plant.
      ls_bapi_item-stge_loc = ls_item-strg_loc.
      ls_bapi_item-move_type = ls_item-movementtype.
      ls_bapi_item-entry_qnt = ls_item-quantity.
      ls_bapi_item-entry_uom = ls_item-base_uom.
      ls_bapi_item-gl_account = ls_item-gl_account.
      ls_bapi_item-costcenter = ls_item-costcenter.
      ls_bapi_item-orderid = ls_item-order_no.
      
      APPEND ls_bapi_item TO lt_bapi_items.
      
    ENDLOOP.
    
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

ENDCLASS.