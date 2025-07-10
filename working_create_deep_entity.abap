METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  TYPES: ty_item  TYPE zcl_zmigo_mvmt_auto_mpc_ext=>ts_zmat,
         ty_items TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY.

  TYPES: BEGIN OF ty_slip,
           slip TYPE string,
         END OF ty_slip.

  TYPES: BEGIN OF ty_payload,
           ZMATSet TYPE ty_items,
         END OF ty_payload.

  TYPES: BEGIN OF ty_final_response,
           Header TYPE string,
           ZMATSet TYPE ty_items,
         END OF ty_final_response.

  DATA: ls_payload   TYPE ty_payload,
        lt_item_data TYPE ty_items,
        lt_grp_slips TYPE SORTED TABLE OF ty_slip WITH UNIQUE KEY slip,
        ls_slip      TYPE ty_slip.

  DATA: lt_return TYPE TABLE OF bapiret2,
        lv_return TYPE bapiret2.

  DATA: lv_any_error_occurred TYPE abap_bool VALUE abap_false.
  DATA: lt_bapi_error_messages TYPE TABLE OF bapiret2.

  " Read payload data
  TRY.
      io_data_provider->read_entry_data( IMPORTING es_data = ls_payload ).
      lt_item_data = ls_payload-ZMATSet.
    CATCH cx_root INTO DATA(lx_read_error).
      " If we can't read the payload, we have to raise an exception
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |Error reading payload: { lx_read_error->get_text( ) }|.
  ENDTRY.

  " Early validation - only raise exception for critical structure issues
  IF lt_item_data IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message = 'ZMATSet is empty in the request payload.'.
  ENDIF.

  " Collect unique slip numbers
  LOOP AT lt_item_data ASSIGNING FIELD-SYMBOL(<fs_item>).
    IF <fs_item>-GrGiSlipNo IS NOT INITIAL.
      ls_slip-slip = <fs_item>-GrGiSlipNo.
      COLLECT ls_slip INTO lt_grp_slips.
    ENDIF.
  ENDLOOP.

  " Early validation - only raise exception for critical structure issues
  IF lt_grp_slips IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message = 'No GrGiSlipNo found in ZMATSet items to process.'.
  ENDIF.

  DATA: lt_result_data TYPE ty_items.

  " Process each group - handle all errors gracefully without exceptions
  LOOP AT lt_grp_slips INTO ls_slip.

    DATA: lt_group_items  TYPE ty_items,
          ls_bapiheader   TYPE bapi2017_gm_head_01,
          lt_bapiitems    TYPE TABLE OF bapi2017_gm_item_create,
          ls_bapiitem     TYPE bapi2017_gm_item_create,
          lv_doc_date     TYPE dats,
          lv_pstng_date   TYPE dats,
          lv_str          TYPE string,
          lv_migo_doc     TYPE bapi2017_gm_head_ret-mat_doc,
          lv_doc_year     TYPE bapi2017_gm_head_ret-doc_year,
          ls_result_item  TYPE ty_item,
          lv_item_counter TYPE i.

    CLEAR: lt_group_items, lt_bapiitems, ls_bapiheader, lt_return, lv_migo_doc, ls_result_item.

    " Get items of the group
    LOOP AT lt_item_data INTO DATA(ls_item_from_payload) WHERE GrGiSlipNo = ls_slip-slip.
      APPEND ls_item_from_payload TO lt_group_items.
    ENDLOOP.

    " Validate group items - collect all errors but don't throw exceptions
    DATA(lv_validation_failed) = abap_false.
    CLEAR: lv_return, lt_bapi_error_messages.

    LOOP AT lt_group_items INTO DATA(ls_check).

      IF ls_check-plant IS INITIAL.
        lv_return-type = 'E'.
        lv_return-message = |Plant must not be blank for GrGiSlipNo { ls_slip-slip }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ENDIF.

      IF ls_check-grgislipno IS INITIAL.
        lv_return-type = 'E'.
        lv_return-message = |GrGiSlipNo must not be blank for item { ls_check-itemno }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ENDIF.

      IF ls_check-docdate IS INITIAL.
        lv_return-type = 'E'.
        lv_return-message = |DocDate must not be blank for GrGiSlipNo { ls_slip-slip }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ENDIF.

      IF ls_check-pstngdate IS INITIAL.
        lv_return-type = 'E'.
        lv_return-message = |PstngDate must not be blank for GrGiSlipNo { ls_slip-slip }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ENDIF.

      IF ls_check-material IS INITIAL.
        lv_return-type = 'E'.
        lv_return-message = |Material must not be blank for GrGiSlipNo { ls_slip-slip }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ELSE.
        " Validate material exists in MARC - handle errors gracefully
        TRY.
            DATA(lv_material) = |{ ls_check-material WIDTH = 18 ALIGN = RIGHT PAD = '0' }|.
            SELECT SINGLE matnr FROM marc
              WHERE matnr = @lv_material
                AND werks = @ls_check-plant
              INTO @DATA(lv_marc_check).

            IF sy-subrc <> 0.
              lv_return-type = 'E'.
              lv_return-message = |Material { ls_check-material } is not maintained in Plant { ls_check-plant } (MARC check failed).|.
              APPEND lv_return TO lt_bapi_error_messages.
              lv_validation_failed = abap_true.
            ENDIF.

          CATCH cx_root INTO DATA(lx_marc_error).
            lv_return-type = 'E'.
            lv_return-message = |Material validation error: { lx_marc_error->get_text( ) }|.
            APPEND lv_return TO lt_bapi_error_messages.
            lv_validation_failed = abap_true.
        ENDTRY.
      ENDIF.

      IF ls_check-itemok IS INITIAL OR ls_check-itemok EQ space.
        lv_return-type = 'E'.
        lv_return-message = |ItemOk must be true to process the item for GrGiSlipNo { ls_slip-slip }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ENDIF.

      " Additional validations for better error handling
      IF ls_check-quantity <= 0.
        lv_return-type = 'E'.
        lv_return-message = |Quantity must be greater than zero for item { ls_check-itemno }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ENDIF.

      IF ls_check-movementtype IS INITIAL.
        lv_return-type = 'E'.
        lv_return-message = |Movement type is required for item { ls_check-itemno }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ENDIF.

      " Check for existing slip number - handle errors gracefully
      TRY.
          SELECT SINGLE xabln FROM mkpf
            WHERE xabln = @ls_check-grgislipno
            INTO @DATA(lv_xabln_check).

          IF sy-subrc = 0.
            lv_return-type = 'E'.
            lv_return-message = |GrGiSlipNo { ls_check-grgislipno } already exists in SAP system|.
            APPEND lv_return TO lt_bapi_error_messages.
            lv_validation_failed = abap_true.
          ENDIF.

        CATCH cx_root INTO DATA(lx_slip_error).
          lv_return-type = 'E'.
          lv_return-message = |Slip number validation error: { lx_slip_error->get_text( ) }|.
          APPEND lv_return TO lt_bapi_error_messages.
          lv_validation_failed = abap_true.
      ENDTRY.

    ENDLOOP.

    " If validation failed, mark all items as FAILED and continue
    IF lv_validation_failed = abap_true.

      " Combine all validation messages into one string
      DATA(lv_validation_msg) = ``.
      LOOP AT lt_bapi_error_messages INTO lv_return.
        IF lv_validation_msg IS INITIAL.
          lv_validation_msg = lv_return-message.
        ELSE.
          lv_validation_msg = |{ lv_validation_msg } / { lv_return-message }|.
        ENDIF.
      ENDLOOP.

      " Mark all items in the group as FAILED with the validation message
      LOOP AT lt_group_items INTO DATA(ls_failed_item).
        CLEAR ls_result_item.
        ls_result_item = CORRESPONDING #( ls_failed_item ).
        ls_result_item-status = 'FAILED'.
        ls_result_item-message = lv_validation_msg.
        APPEND ls_result_item TO lt_result_data.
      ENDLOOP.

      lv_any_error_occurred = abap_true.
      CONTINUE.

    ENDIF.

    " Get header fields from first item of the current group
    READ TABLE lt_group_items INTO DATA(ls_first_item_in_group) INDEX 1.
    IF sy-subrc = 0.
      " Handle date conversion with error handling
      TRY.
          " Convert document date
          lv_str = ls_first_item_in_group-docdate.
          IF lv_str CS '/Date(' AND lv_str CS ')/' .
            REPLACE '/Date(' IN lv_str WITH ''.
            REPLACE ')/' IN lv_str WITH ''.
            DATA(lv_timestamp) = CONV int8( lv_str ).
            lv_timestamp = lv_timestamp / 1000.
            lv_doc_date = '19700101'.
            lv_doc_date = lv_doc_date + ( lv_timestamp / 86400 ).
          ELSE.
            " Handle regular date format
            REPLACE ALL OCCURRENCES OF REGEX `[^0-9]` IN lv_str WITH ``.
            IF strlen( lv_str ) >= 8.
              lv_doc_date = lv_str(8).
            ELSE.
              " Date error - mark as failed and continue
              LOOP AT lt_group_items INTO DATA(ls_failed_item).
                CLEAR ls_result_item.
                ls_result_item = CORRESPONDING #( ls_failed_item ).
                ls_result_item-status = 'ERROR'.
                ls_result_item-message = |Invalid DocDate format for GrGiSlipNo: { ls_slip-slip }|.
                APPEND ls_result_item TO lt_result_data.
              ENDLOOP.
              lv_any_error_occurred = abap_true.
              CONTINUE.
            ENDIF.
          ENDIF.

          " Convert posting date
          lv_str = ls_first_item_in_group-pstngdate.
          IF lv_str CS '/Date(' AND lv_str CS ')/' .
            REPLACE '/Date(' IN lv_str WITH ''.
            REPLACE ')/' IN lv_str WITH ''.
            lv_timestamp = CONV int8( lv_str ).
            lv_timestamp = lv_timestamp / 1000.
            lv_pstng_date = '19700101'.
            lv_pstng_date = lv_pstng_date + ( lv_timestamp / 86400 ).
          ELSE.
            " Handle regular date format
            REPLACE ALL OCCURRENCES OF REGEX `[^0-9]` IN lv_str WITH ``.
            IF strlen( lv_str ) >= 8.
              lv_pstng_date = lv_str(8).
            ELSE.
              " Date error - mark as failed and continue
              LOOP AT lt_group_items INTO DATA(ls_failed_item).
                CLEAR ls_result_item.
                ls_result_item = CORRESPONDING #( ls_failed_item ).
                ls_result_item-status = 'ERROR'.
                ls_result_item-message = |Invalid PstngDate format for GrGiSlipNo: { ls_slip-slip }|.
                APPEND ls_result_item TO lt_result_data.
              ENDLOOP.
              lv_any_error_occurred = abap_true.
              CONTINUE.
            ENDIF.
          ENDIF.

        CATCH cx_root INTO DATA(lx_date_error).
          " Date conversion error - mark as failed and continue
          LOOP AT lt_group_items INTO DATA(ls_failed_item).
            CLEAR ls_result_item.
            ls_result_item = CORRESPONDING #( ls_failed_item ).
            ls_result_item-status = 'ERROR'.
            ls_result_item-message = |Date conversion error: { lx_date_error->get_text( ) }|.
            APPEND ls_result_item TO lt_result_data.
          ENDLOOP.
          lv_any_error_occurred = abap_true.
          CONTINUE.
      ENDTRY.

      ls_bapiheader-doc_date = lv_doc_date.
      ls_bapiheader-pstng_date = lv_pstng_date.
      ls_bapiheader-ref_doc_no = ls_first_item_in_group-grgislipno.
      ls_bapiheader-gr_gi_slip_no = ls_first_item_in_group-grgislipno.
      ls_bapiheader-header_txt = ls_first_item_in_group-headertxt.
    ELSE.
      " Can't read first item - mark as error and continue
      LOOP AT lt_group_items INTO DATA(ls_failed_item).
        CLEAR ls_result_item.
        ls_result_item = CORRESPONDING #( ls_failed_item ).
        ls_result_item-status = 'ERROR'.
        ls_result_item-message = |Failed to read first item for group: { ls_slip-slip }|.
        APPEND ls_result_item TO lt_result_data.
      ENDLOOP.
      lv_any_error_occurred = abap_true.
      CONTINUE.
    ENDIF.

    " Prepare BAPI items with proper line item numbering
    lv_item_counter = 10.
    LOOP AT lt_group_items INTO ls_item_from_payload.
      CLEAR ls_bapiitem.

      " Set proper line number in LINE_ID
      IF ls_item_from_payload-itemno IS NOT INITIAL.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING input = ls_item_from_payload-itemno
          IMPORTING output = ls_bapiitem-line_id.
      ELSE.
        ls_bapiitem-line_id = lv_item_counter.
        lv_item_counter = lv_item_counter + 10.
      ENDIF.

      " Material conversion
      CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
        EXPORTING input = ls_item_from_payload-material
        IMPORTING output = ls_bapiitem-material.

      " Apply ALPHA conversions
      IF ls_item_from_payload-glaccount IS NOT INITIAL.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING input = ls_item_from_payload-glaccount
          IMPORTING output = ls_bapiitem-gl_account.
      ENDIF.

      IF ls_item_from_payload-costcenter IS NOT INITIAL.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING input = ls_item_from_payload-costcenter
          IMPORTING output = ls_bapiitem-costcenter.
      ENDIF.

      IF ls_item_from_payload-orderno IS NOT INITIAL.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING input = ls_item_from_payload-orderno
          IMPORTING output = ls_bapiitem-orderid.
      ENDIF.

      ls_bapiitem-plant = ls_item_from_payload-plant.
      ls_bapiitem-move_type = ls_item_from_payload-movementtype.
      ls_bapiitem-entry_qnt = ls_item_from_payload-quantity.
      ls_bapiitem-entry_uom = ls_item_from_payload-baseuom.
      ls_bapiitem-stge_loc = ls_item_from_payload-strgloc.
      ls_bapiitem-no_more_gr = 'X'.

      APPEND ls_bapiitem TO lt_bapiitems.
    ENDLOOP.

    IF lt_bapiitems IS INITIAL.
      " No BAPI items - mark as error and continue
      LOOP AT lt_group_items INTO DATA(ls_failed_item).
        CLEAR ls_result_item.
        ls_result_item = CORRESPONDING #( ls_failed_item ).
        ls_result_item-status = 'ERROR'.
        ls_result_item-message = |No items prepared for BAPI for GrGiSlipNo: { ls_slip-slip }|.
        APPEND ls_result_item TO lt_result_data.
      ENDLOOP.
      lv_any_error_occurred = abap_true.
      CONTINUE.
    ENDIF.

    " Call BAPI with error handling
    TRY.
        CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
          EXPORTING
            goodsmvt_header = ls_bapiheader
            goodsmvt_code = '03'
          IMPORTING
            materialdocument = lv_migo_doc
            matdocumentyear = lv_doc_year
          TABLES
            goodsmvt_item = lt_bapiitems
            return = lt_return.

      CATCH cx_root INTO DATA(lx_bapi_error).
        " BAPI call failed - mark as error and continue
        LOOP AT lt_group_items INTO DATA(ls_failed_item).
          CLEAR ls_result_item.
          ls_result_item = CORRESPONDING #( ls_failed_item ).
          ls_result_item-Status = 'ERROR'.
          ls_result_item-Message = |BAPI call error: { lx_bapi_error->get_text( ) }|.
          ls_result_item-MigoDocNo = ''.
          APPEND ls_result_item TO lt_result_data.
        ENDLOOP.
        lv_any_error_occurred = abap_true.
        CONTINUE.
    ENDTRY.

    " Check for BAPI errors
    DATA lv_bapi_error_message TYPE string.
    CLEAR lv_bapi_error_message.

    LOOP AT lt_return INTO lv_return WHERE type = 'E' OR type = 'A'.
      IF lv_bapi_error_message IS INITIAL.
        lv_bapi_error_message = lv_return-message.
      ELSE.
        lv_bapi_error_message = |{ lv_bapi_error_message } / { lv_return-message }|.
      ENDIF.
    ENDLOOP.

    " Process the result for ALL items in the group
    IF lv_bapi_error_message IS NOT INITIAL.
      " BAPI failed - mark ALL items in this group as FAILED
      LOOP AT lt_group_items INTO DATA(ls_failed_item).
        CLEAR ls_result_item.
        ls_result_item = CORRESPONDING #( ls_failed_item ).
        ls_result_item-Status = 'FAILED'.
        ls_result_item-Message = lv_bapi_error_message.
        ls_result_item-MigoDocNo = ''.
        APPEND ls_result_item TO lt_result_data.
      ENDLOOP.

      lv_any_error_occurred = abap_true.
      " Rollback the transaction for this group
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.

    ELSE.
      " BAPI succeeded - commit and mark ALL items in this group as SUCCESS
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait = 'X'.

      " Find success message
      DATA: lv_success_message TYPE string.
      READ TABLE lt_return INTO lv_return WITH KEY type = 'S'.
      IF sy-subrc = 0 AND lv_return-message IS NOT INITIAL.
        lv_success_message = lv_return-message.
      ELSE.
        lv_success_message = |Document { lv_migo_doc } posted successfully.|.
      ENDIF.

      " Mark ALL items in this group as SUCCESS
      LOOP AT lt_group_items INTO DATA(ls_success_item).
        CLEAR ls_result_item.
        ls_result_item = CORRESPONDING #( ls_success_item ).
        ls_result_item-Status = 'SUCCESS'.
        ls_result_item-MigoDocNo = lv_migo_doc.
        ls_result_item-Message = lv_success_message.
        APPEND ls_result_item TO lt_result_data.
      ENDLOOP.

    ENDIF.

  ENDLOOP.

  " Prepare final response structure with proper error handling
  DATA: ls_final_response TYPE ty_final_response.
  
  " Set the header field (required for proper OData structure)
  ls_final_response-Header = ''.
  ls_final_response-ZMATSet = lt_result_data.

  " Always return the response - let the client handle the status
  TRY.
      copy_data_to_ref(
        EXPORTING
          is_data = ls_final_response
        CHANGING
          cr_data = er_deep_entity
      ).

    CATCH cx_root INTO DATA(lx_copy_error).
      " If copy fails, raise an exception as last resort
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |Response preparation error: { lx_copy_error->get_text( ) }|.
  ENDTRY.

ENDMETHOD.