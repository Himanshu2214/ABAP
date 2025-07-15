METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.
  TYPES ty_item  TYPE zcl_zmigo_mvmt_auto_mpc_ext=>ts_zmat.
  TYPES ty_items TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY.

  TYPES: BEGIN OF ty_slip,
           slip TYPE string,
         END OF ty_slip.

  TYPES: BEGIN OF ty_payload,
           ZMATSet TYPE ty_items,
         END OF ty_payload.

  DATA ls_payload     TYPE ty_payload.
  DATA lt_item_data   TYPE ty_items.
  DATA lt_grp_slips   TYPE SORTED TABLE OF ty_slip WITH UNIQUE KEY slip.
  DATA ls_slip        TYPE ty_slip.
  DATA lt_return      TYPE TABLE OF bapiret2.
  DATA lt_result_data TYPE ty_items.

  DATA lv_overall_status_is_success TYPE abap_bool VALUE abap_true.
  DATA lv_any_item_succeeded        TYPE abap_bool VALUE abap_false.

  " Read payload data
  io_data_provider->read_entry_data( IMPORTING es_data = ls_payload ).
  lt_item_data = ls_payload-ZMATSet.

  " --- Initial global validation of payload ---
  IF lt_item_data IS INITIAL.
    DATA(ls_empty_payload_result) = VALUE ty_item( Status  = 'FAILED'
                                                  Message = 'ZMATSet is empty in the request payload.' ).
    APPEND ls_empty_payload_result TO lt_result_data.

    TYPES: BEGIN OF ty_final_empty,
             ZMATSet TYPE ty_items,
           END OF ty_final_empty.
    DATA(ls_final_empty) = VALUE ty_final_empty( ZMATSet = lt_result_data ).
    lv_overall_status_is_success = abap_false.

    copy_data_to_ref( EXPORTING is_data = ls_final_empty CHANGING cr_data = er_deep_entity ).
    RETURN.
  ENDIF.

  " --- Pre-processing and grouping of items ---
  LOOP AT lt_item_data ASSIGNING FIELD-SYMBOL(<fs_item>).
    IF <fs_item>-GrGiSlipNo IS INITIAL.
      DATA(ls_skipped_item) = CORRESPONDING ty_item( <fs_item> ).
      ls_skipped_item-Status  = 'FAILED'.
      ls_skipped_item-Message = 'GrGiSlipNo is mandatory. This item cannot be processed.'.
      APPEND ls_skipped_item TO lt_result_data.
      lv_overall_status_is_success = abap_false.
      CONTINUE.
    ENDIF.

    <fs_item>-ZtypeGm      = 'A07'.
    <fs_item>-ZsubType     = 'R10'.
    <fs_item>-Movementtype = '963'.
    <fs_item>-ItemOk       = abap_true.

    IF <fs_item>-Material IS NOT INITIAL.
      SELECT SINGLE maktx FROM makt
        INTO @<fs_item>-MatDesc
        WHERE matnr = @<fs_item>-Material AND spras = @sy-langu.
      SELECT SINGLE meins FROM mara
        INTO @<fs_item>-BaseUom
        WHERE matnr = @<fs_item>-Material.
    ENDIF.

    ls_slip-slip = <fs_item>-GrGiSlipNo.
    COLLECT ls_slip INTO lt_grp_slips.
  ENDLOOP.

  " --- Process each unique slip (group) ---
  LOOP AT lt_grp_slips INTO ls_slip.
    DATA lt_group_items       TYPE ty_items.
    DATA ls_bapiheader        TYPE bapi2017_gm_head_01.
    DATA lt_bapiitems         TYPE TABLE OF bapi2017_gm_item_create.
    DATA lv_migo_doc          TYPE bapi2017_gm_head_ret-mat_doc.
    DATA lv_doc_year          TYPE bapi2017_gm_head_ret-doc_year.
    DATA lv_doc_date          TYPE dats.
    DATA lv_pstng_date        TYPE dats.
    DATA lv_str               TYPE string.
    DATA ls_result_item       TYPE ty_item.
    DATA lv_item_counter      TYPE i VALUE 10.

    DATA(lv_current_slip_has_error) = abap_false.
    DATA lt_error_messages        TYPE TABLE OF string.
    DATA lv_error_message         TYPE string.
    DATA lt_processed_materials   TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.

    " Clear error messages and processed materials for the new slip
    CLEAR lt_error_messages.

    READ TABLE lt_item_data INTO DATA(ls_first_item_of_slip) WITH KEY GrGiSlipNo = ls_slip-slip.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    ls_result_item = CORRESPONDING #( ls_first_item_of_slip ).
    CLEAR ls_result_item-Status.
    CLEAR ls_result_item-Message.
    CLEAR ls_result_item-ItemNo.

    " --- Validation 1: Check if slip already exists in MKPF ---
    SELECT SINGLE xabln FROM mkpf INTO @DATA(lv_exists) WHERE xabln = @ls_first_item_of_slip-GrGiSlipNo.
    IF sy-subrc = 0.
      lv_current_slip_has_error = abap_true.
      APPEND |Slip { ls_first_item_of_slip-GrGiSlipNo } already exists in MKPF| TO lt_error_messages.
    ENDIF.

    " --- Validate all items for the slip before processing ---
    LOOP AT lt_item_data INTO DATA(ls_item_in_group) WHERE GrGiSlipNo = ls_slip-slip.
      " Check for duplicate material within the slip
      IF line_exists( lt_processed_materials[ table_line = ls_item_in_group-Material ] ).
        lv_current_slip_has_error = abap_true.
        APPEND |Duplicate material { ls_item_in_group-Material } for slip { ls_slip-slip }| TO lt_error_messages.
      ELSE.
        INSERT ls_item_in_group-Material INTO TABLE lt_processed_materials.
        ls_item_in_group-ItemNo = |{ lv_item_counter WIDTH = 6 ALIGN = RIGHT PAD = '0' }|.
        lv_item_counter += 10.
        APPEND ls_item_in_group TO lt_group_items.
      ENDIF.
    ENDLOOP.

    " --- Validation 2: Mandatory fields for items within the slip ---
    LOOP AT lt_group_items INTO DATA(ls_check).
      IF ls_check-Plant IS INITIAL OR ls_check-StrgLoc IS INITIAL
         OR ls_check-DocDate IS INITIAL OR ls_check-PstngDate IS INITIAL
         OR ls_check-Material IS INITIAL OR ls_check-Quantity <= 0.
        lv_current_slip_has_error = abap_true.
        APPEND |Validation failed for Material { ls_check-Material } in Slip { ls_slip-slip }. Missing mandatory field.| TO lt_error_messages.
      ENDIF.
    ENDLOOP.

    " --- Validation 3: Date conversion logic ---
    IF lv_current_slip_has_error = abap_false.
      TRY.
          lv_str = ls_first_item_of_slip-DocDate.
          IF NOT ( lv_str CS '/Date(' AND lv_str CS ')/' ).
            REPLACE ALL OCCURRENCES OF REGEX `[^0-9]` IN lv_str WITH ``.
          ENDIF.
          IF strlen( lv_str ) >= 8.
            lv_doc_date = lv_str(8).
          ELSE.
            RAISE EXCEPTION NEW cx_sy_conversion_no_date_time( ).
          ENDIF.

          lv_str = ls_first_item_of_slip-PstngDate.
          IF NOT ( lv_str CS '/Date(' AND lv_str CS ')/' ).
            REPLACE ALL OCCURRENCES OF REGEX `[^0-9]` IN lv_str WITH ``.
          ENDIF.
          IF strlen( lv_str ) >= 8.
            lv_pstng_date = lv_str(8).
          ELSE.
            RAISE EXCEPTION NEW cx_sy_conversion_no_date_time( ).
          ENDIF.
        CATCH cx_sy_conversion_no_date_time INTO DATA(lx_date_conv_sy).
          lv_current_slip_has_error = abap_true.
          APPEND |Date conversion error: { lx_date_conv_sy->get_text( ) }| TO lt_error_messages.
        CATCH cx_sy_conversion_overflow INTO DATA(lx_conv_overflow).
          lv_current_slip_has_error = abap_true.
          APPEND |Conversion overflow error: { lx_conv_overflow->get_text( ) }| TO lt_error_messages.
        CATCH cx_root INTO DATA(lx_root_catch).
          lv_current_slip_has_error = abap_true.
          APPEND |Unexpected date conversion error: { lx_root_catch->get_text( ) }| TO lt_error_messages.
      ENDTRY.
    ENDIF.

    " --- Consolidate error messages for the slip ---
    IF lv_current_slip_has_error = abap_true.
      CONCATENATE LINES OF lt_error_messages INTO lv_error_message SEPARATED BY '; '.
      ls_result_item-Status = 'FAILED'.
      ls_result_item-Message = |Slip { ls_slip-slip } failed: { lv_error_message }|.
      APPEND ls_result_item TO lt_result_data.
      lv_overall_status_is_success = abap_false.
      CONTINUE.
    ENDIF.

    " --- Proceed with BAPI call if no errors ---
    ls_bapiheader-doc_date      = lv_doc_date.
    ls_bapiheader-pstng_date    = lv_pstng_date.
    ls_bapiheader-ref_doc_no    = ls_first_item_of_slip-GrGiSlipNo.
    ls_bapiheader-gr_gi_slip_no = ls_first_item_of_slip-GrGiSlipNo.
    ls_bapiheader-header_txt    = ls_first_item_of_slip-HeaderTxt.

    LOOP AT lt_group_items INTO DATA(ls_post).
      DATA(ls_bapiitem) = VALUE bapi2017_gm_item_create( ).
      ls_bapiitem-line_id = ls_post-ItemNo.

      CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
        EXPORTING
          input  = ls_post-Material
        IMPORTING
          output = ls_bapiitem-material.

      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING
          input  = ls_post-GlAccount
        IMPORTING
          output = ls_bapiitem-gl_account.

      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING
          input  = ls_post-Costcenter
        IMPORTING
          output = ls_bapiitem-costcenter.

      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING
          input  = ls_post-OrderNo
        IMPORTING
          output = ls_bapiitem-orderid.

      ls_bapiitem-plant      = ls_post-Plant.
      ls_bapiitem-move_type  = ls_post-Movementtype.
      ls_bapiitem-entry_qnt  = ls_post-Quantity.
      ls_bapiitem-entry_uom  = ls_post-BaseUom.
      ls_bapiitem-stge_loc   = ls_post-StrgLoc.
      ls_bapiitem-no_more_gr = 'X'.

      APPEND ls_bapiitem TO lt_bapiitems.
    ENDLOOP.

    " Execute BAPI_GOODSMVT_CREATE
    CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
      EXPORTING
        goodsmvt_header  = ls_bapiheader
        goodsmvt_code    = '03'
      IMPORTING
        materialdocument = lv_migo_doc
        matdocumentyear  = lv_doc_year
      TABLES
        goodsmvt_item    = lt_bapiitems
        return           = lt_return.

    DATA(lv_bapi_error_found) = abap_false.
    DATA lv_bapi_error_message TYPE bapi_msg VALUE IS INITIAL.

    IF lv_migo_doc IS INITIAL.
      lv_bapi_error_found = abap_true.
      LOOP AT lt_return INTO DATA(lv_ret) WHERE type <> 'S' AND type <> 'I'.
        IF lv_bapi_error_message IS INITIAL.
          lv_bapi_error_message = lv_ret-message.
        ELSE.
          lv_bapi_error_message = |{ lv_bapi_error_message }; { lv_ret-message }|.
        ENDIF.
      ENDLOOP.
      IF lv_bapi_error_message IS INITIAL.
        lv_bapi_error_message = 'Posting failed. MIGO document not generated.'.
      ENDIF.
    ENDIF.

    " --- Handling BAPI outcome ---
    IF lv_bapi_error_found = abap_true.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      ls_result_item-Status = 'FAILED'.
      ls_result_item-Message = |Slip { ls_first_item_of_slip-GrGiSlipNo } failed: { lv_bapi_error_message }|.
      APPEND ls_result_item TO lt_result_data.
      lv_overall_status_is_success = abap_false.
    ELSE.
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait = 'X'.
      ls_result_item-Status    = 'SUCCESS'.
      ls_result_item-Message   = |Slip { ls_first_item_of_slip-GrGiSlipNo } - Document { lv_migo_doc } posted|.
      ls_result_item-MigoDocNo = lv_migo_doc.
      APPEND ls_result_item TO lt_result_data.
      lv_any_item_succeeded = abap_true.
    ENDIF.

  ENDLOOP.

  " --- Final OData Response Construction ---
  DATA lv_success_count TYPE i.
  DATA lv_failed_count TYPE i.
  LOOP AT lt_result_data INTO DATA(ls_result_count).
    IF ls_result_count-Status = 'SUCCESS'.
      lv_success_count += 1.
    ELSE.
      lv_failed_count += 1.
    ENDIF.
  ENDLOOP.
  DATA(lv_total_count) = lv_success_count + lv_failed_count.

  TYPES: BEGIN OF ty_final,
           Header  TYPE string,
           ZMATSet TYPE ty_items,
         END OF ty_final.

  DATA(ls_final) = VALUE ty_final( ZMATSet = lt_result_data ).
  ls_final-Header = |OVERALL_STATUS: { lv_total_count } records processed, { lv_success_count } passed, { lv_failed_count } failed.|.

  copy_data_to_ref( EXPORTING is_data = ls_final
                    CHANGING  cr_data = er_deep_entity ).
ENDMETHOD.
