METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  " Type definitions following reference pattern
  TYPES: ty_items TYPE STANDARD TABLE OF zcl_zmm_migo_automation_mpc_ext=>ts_goodsmovementitem WITH DEFAULT KEY.

  TYPES: BEGIN OF ty_header.
           INCLUDE TYPE zcl_zmm_migo_automation_mpc_ext=>ts_headerdummy.
  TYPES:   headertogoodsmovementheader TYPE zcl_zmm_migo_automation_mpc_ext=>ts_goodsmovementheader,
           headertogoodsmovementitem TYPE ty_items,
         END OF ty_header.

  " Data declarations
  DATA: iw_data TYPE ty_header,
        it_item TYPE TABLE OF zcl_zmm_migo_automation_mpc_ext=>ts_goodsmovementitem,
        wa_item TYPE zcl_zmm_migo_automation_mpc_ext=>ts_goodsmovementitem,
        wa_header TYPE zcl_zmm_migo_automation_mpc_ext=>ts_goodsmovementheader,
        lt_errors TYPE STANDARD TABLE OF bapiret2,
        wa_errors TYPE bapiret2.

  " BAPI structures for goods movement
  DATA: wa_goodsmvt_header TYPE bapi2017_gm_head_01,
        it_goodsmvt_item TYPE TABLE OF bapi2017_gm_item_create,
        wa_goodsmvt_item TYPE bapi2017_gm_item_create,
        it_return TYPE TABLE OF bapiret2,
        wa_return TYPE bapiret2,
        lv_materialdocument TYPE bapi2017_gm_head_ret-mat_doc,
        lv_matdocumentyear TYPE bapi2017_gm_head_ret-doc_year.

  " Response tracking variables
  DATA: lv_overall_status TYPE string,
        lv_created_count TYPE i,
        lv_failed_count TYPE i,
        lv_current_header TYPE string.

  " JSON response building
  DATA: lv_json_response TYPE string,
        lv_temp_string TYPE string,
        lv_results_json TYPE string.

  " Constants for validation
  CONSTANTS: lc_ztype_gm TYPE string VALUE 'A007',
             lc_zsub_type TYPE string VALUE 'R10',
             lc_movement_type TYPE string VALUE '963',
             lc_gm_code TYPE string VALUE '03'.

  " Get posted data following reference pattern
  io_data_provider->read_entry_data( IMPORTING es_data = iw_data ).

  " Extract header and items
  wa_header = iw_data-headertogoodsmovementheader.
  MOVE-CORRESPONDING iw_data-headertogoodsmovementitem TO it_item.

  " Initialize response tracking
  lv_created_count = 0.
  lv_failed_count = 0.
  lv_current_header = iw_data-GrGiSlipNo.

  " Build JSON response start
  lv_json_response = '{"GrGiSlipNo":"' && lv_current_header && '","Results":['.

  " Process each item (following reference loop pattern)
  LOOP AT it_item INTO wa_item.
    DATA(lv_tabix) = sy-tabix.
    CLEAR: wa_goodsmvt_header, it_goodsmvt_item, it_return, wa_return.
    CLEAR: lv_materialdocument, lv_matdocumentyear.

    " Validation following business rules
    IF wa_header-ZtypeGm <> lc_ztype_gm.
      wa_errors-type = 'E'.
      wa_errors-message = 'ZtypeGm must be A007'.
      APPEND wa_errors TO lt_errors.
      lv_failed_count = lv_failed_count + 1.
      " Add to JSON results
      IF lv_results_json IS NOT INITIAL.
        lv_results_json = lv_results_json && ','.
      ENDIF.
      lv_results_json = lv_results_json && '{"GrGiSlipNo":"' && wa_item-GrGiSlipNo && 
                        '","Status":"FAILED","Error":"ZtypeGm must be A007"}'.
      CONTINUE.
    ENDIF.

    IF wa_header-ZsubType <> lc_zsub_type.
      wa_errors-type = 'E'.
      wa_errors-message = 'ZsubType must be R10'.
      APPEND wa_errors TO lt_errors.
      lv_failed_count = lv_failed_count + 1.
      " Add to JSON results
      IF lv_results_json IS NOT INITIAL.
        lv_results_json = lv_results_json && ','.
      ENDIF.
      lv_results_json = lv_results_json && '{"GrGiSlipNo":"' && wa_item-GrGiSlipNo && 
                        '","Status":"FAILED","Error":"ZsubType must be R10"}'.
      CONTINUE.
    ENDIF.

    IF wa_header-Movementtype <> lc_movement_type.
      wa_errors-type = 'E'.
      wa_errors-message = 'Movement type must be 963'.
      APPEND wa_errors TO lt_errors.
      lv_failed_count = lv_failed_count + 1.
      " Add to JSON results
      IF lv_results_json IS NOT INITIAL.
        lv_results_json = lv_results_json && ','.
      ENDIF.
      lv_results_json = lv_results_json && '{"GrGiSlipNo":"' && wa_item-GrGiSlipNo && 
                        '","Status":"FAILED","Error":"Movement type must be 963"}'.
      CONTINUE.
    ENDIF.

    " Validate mandatory item fields
    IF wa_item-Material IS INITIAL OR wa_item-Plant IS INITIAL OR 
       wa_item-StrgLoc IS INITIAL OR wa_item-Quantity IS INITIAL.
      wa_errors-type = 'E'.
      wa_errors-message = 'Mandatory fields missing: Material, Plant, Storage Location, or Quantity'.
      APPEND wa_errors TO lt_errors.
      lv_failed_count = lv_failed_count + 1.
      " Add to JSON results
      IF lv_results_json IS NOT INITIAL.
        lv_results_json = lv_results_json && ','.
      ENDIF.
      lv_results_json = lv_results_json && '{"GrGiSlipNo":"' && wa_item-GrGiSlipNo && 
                        '","Status":"FAILED","Error":"Mandatory fields missing"}'.
      CONTINUE.
    ENDIF.

    " Prepare BAPI header data
    wa_goodsmvt_header-pstng_date = sy-datum.
    wa_goodsmvt_header-doc_date = sy-datum.
    wa_goodsmvt_header-header_txt = wa_header-HeaderTxt.

    " Prepare BAPI item data
    wa_goodsmvt_item-material = wa_item-Material.
    wa_goodsmvt_item-plant = wa_item-Plant.
    wa_goodsmvt_item-stge_loc = wa_item-StrgLoc.
    wa_goodsmvt_item-move_type = wa_header-Movementtype.
    wa_goodsmvt_item-entry_qnt = wa_item-Quantity.
    wa_goodsmvt_item-entry_uom = wa_item-BaseUom.
    wa_goodsmvt_item-gl_account = wa_item-GlAccount.
    wa_goodsmvt_item-costcenter = wa_item-Costcenter.
    wa_goodsmvt_item-orderid = wa_item-OrderNo.
    APPEND wa_goodsmvt_item TO it_goodsmvt_item.

    " Call BAPI for goods movement creation
    CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
      EXPORTING
        goodsmvt_header  = wa_goodsmvt_header
        goodsmvt_code    = lc_gm_code
      IMPORTING
        materialdocument = lv_materialdocument
        matdocumentyear  = lv_matdocumentyear
      TABLES
        goodsmvt_item    = it_goodsmvt_item
        return           = it_return.

    " Check for BAPI errors (critical: BAPI returns sy-subrc = 0 even with errors)
    READ TABLE it_return INTO wa_return WITH KEY type = 'E'.
    IF sy-subrc = 0.
      " Error occurred
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      lv_failed_count = lv_failed_count + 1.
      " Add to JSON results
      IF lv_results_json IS NOT INITIAL.
        lv_results_json = lv_results_json && ','.
      ENDIF.
      " Clean error message for JSON
      REPLACE ALL OCCURRENCES OF '"' IN wa_return-message WITH '\"'.
      lv_results_json = lv_results_json && '{"GrGiSlipNo":"' && wa_item-GrGiSlipNo && 
                        '","Status":"FAILED","Error":"' && wa_return-message && '"}'.
      
      " Update item with error info
      LOOP AT iw_data-headertogoodsmovementitem INTO DATA(ls_item).
        IF lv_tabix EQ sy-tabix.
          ls_item-ItemOk = abap_false.
          MODIFY iw_data-headertogoodsmovementitem FROM ls_item INDEX lv_tabix.
          EXIT.
        ENDIF.
      ENDLOOP.
      
    ELSE.
      " Success - commit transaction
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait = abap_true.
      
      lv_created_count = lv_created_count + 1.
      " Add to JSON results
      IF lv_results_json IS NOT INITIAL.
        lv_results_json = lv_results_json && ','.
      ENDIF.
      lv_results_json = lv_results_json && '{"GrGiSlipNo":"' && wa_item-GrGiSlipNo && 
                        '","Status":"SUCCESS","MIGONumber":"' && lv_materialdocument && '"}'.
      
      " Update item with success info
      LOOP AT iw_data-headertogoodsmovementitem INTO ls_item.
        IF lv_tabix EQ sy-tabix.
          ls_item-ItemOk = abap_true.
          MODIFY iw_data-headertogoodsmovementitem FROM ls_item INDEX lv_tabix.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " Collect all return messages for logging
    LOOP AT it_return INTO wa_return.
      APPEND wa_return TO lt_errors.
    ENDLOOP.

  ENDLOOP.

  " Determine overall status
  IF lv_failed_count = 0.
    lv_overall_status = 'SUCCESS'.
  ELSEIF lv_created_count = 0.
    lv_overall_status = 'FAILED'.
  ELSE.
    lv_overall_status = 'PARTIAL SUCCESS'.
  ENDIF.

  " Complete JSON response
  lv_json_response = lv_json_response && lv_results_json && '],"OverallStatus":"' && 
                     lv_overall_status && '"}'.

  " Set response following reference pattern
  CALL METHOD io_data_provider->read_entry_data
    IMPORTING
      es_data = er_deep_entity.

  copy_data_to_ref( EXPORTING is_data = iw_data
                    CHANGING  cr_data = er_deep_entity ).

  " Handle response status and message container
  DATA: lo_msg TYPE REF TO /iwbep/if_message_container.
  CALL METHOD me->/iwbep/if_mgw_conv_srv_runtime~get_message_container
    RECEIVING
      ro_message_container = lo_msg.

  " Add JSON response as custom message
  IF lo_msg IS BOUND.
    wa_return-type = 'I'.
    wa_return-message = lv_json_response.
    APPEND wa_return TO lt_errors.
    
    CALL METHOD lo_msg->add_messages_from_bapi
      EXPORTING
        it_bapi_messages = lt_errors.

    " Set appropriate HTTP status
    IF lv_overall_status = 'FAILED'.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid            = /iwbep/cx_mgw_busi_exception=>business_error
          message_container = lo_msg.
    ENDIF.
  ENDIF.

ENDMETHOD.