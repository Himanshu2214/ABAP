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
           ZMATSet TYPE ty_items,
         END OF ty_final_response.

  DATA: ls_payload     TYPE ty_payload,
        lt_item_data   TYPE ty_items,
        lt_grp_slips   TYPE SORTED TABLE OF ty_slip WITH UNIQUE KEY slip,
        ls_slip        TYPE ty_slip,
        lt_result_data TYPE ty_items,
        ls_final_response TYPE ty_final_response.

  DATA: lt_return TYPE TABLE OF bapiret2,
        lv_return TYPE bapiret2.

  " Read payload data
  io_data_provider->read_entry_data( IMPORTING es_data = ls_payload ).
  lt_item_data = ls_payload-ZMATSet.

  " Early validation - Bad Request (400)
  IF lt_item_data IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message = 'ZMATSet is empty in the request payload'.
  ENDIF.

  " Collect unique slip numbers
  LOOP AT lt_item_data ASSIGNING FIELD-SYMBOL(<fs_item>).
    IF <fs_item>-GrGiSlipNo IS NOT INITIAL.
      ls_slip-slip = <fs_item>-GrGiSlipNo.
      COLLECT ls_slip INTO lt_grp_slips.
    ENDIF.
  ENDLOOP.

  " Early validation - Bad Request (400)
  IF lt_grp_slips IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message = 'No GrGiSlipNo found in ZMATSet items to process'.
  ENDIF.

  " Bulk validation optimization - check for existing slip numbers
  DATA: lt_existing_slips TYPE STANDARD TABLE OF string,
        lv_slip_range     TYPE RANGE OF xabln.

  " Build range for existing slip check
  LOOP AT lt_grp_slips INTO ls_slip.
    APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_slip-slip ) TO lv_slip_range.
  ENDLOOP.

  " Single query to check all existing slips
  IF lv_slip_range IS NOT INITIAL.
    SELECT xabln FROM mkpf
      WHERE xabln IN @lv_slip_range
      INTO TABLE @lt_existing_slips.
  ENDIF.

  " Process each group
  LOOP AT lt_grp_slips INTO ls_slip.

    DATA: lt_group_items    TYPE ty_items,
          ls_bapiheader     TYPE bapi2017_gm_head_01,
          lt_bapiitems      TYPE TABLE OF bapi2017_gm_item_create,
          ls_bapiitem       TYPE bapi2017_gm_item_create,
          lv_doc_date       TYPE dats,
          lv_pstng_date     TYPE dats,
          lv_str            TYPE string,
          lv_migo_doc       TYPE bapi2017_gm_head_ret-mat_doc,
          lv_doc_year       TYPE bapi2017_gm_head_ret-doc_year,
          ls_result_item    TYPE ty_item,
          lv_item_counter   TYPE i,
          lv_error_message  TYPE string,
          lv_validation_failed TYPE abap_bool,
          lv_material       TYPE matnr,
          lv_timestamp      TYPE int8,
          lv_bapi_error_message TYPE string,
          lv_success_message TYPE string.

    CLEAR: lt_group_items, lt_bapiitems, ls_bapiheader, lt_return, 
           lv_migo_doc, lv_error_message, lv_validation_failed, lv_bapi_error_message.

    " Get items of the current group
    LOOP AT lt_item_data INTO DATA(ls_item_from_payload) WHERE GrGiSlipNo = ls_slip-slip.
      APPEND ls_item_from_payload TO lt_group_items.
    ENDLOOP.

    " === VALIDATION WITH EARLY EXIT ===
    " Check if slip already exists (fast check using pre-loaded data)
    READ TABLE lt_existing_slips TRANSPORTING NO FIELDS WITH KEY table_line = ls_slip-slip.
    IF sy-subrc = 0.
      lv_validation_failed = abap_true.
      lv_error_message = |GrGiSlipNo { ls_slip-slip } already exists in SAP system|.
    ENDIF.

    " Continue with other validations only if not already failed
    IF lv_validation_failed = abap_false.
      " Prepare materials for bulk validation
      DATA: lt_material_plant_pairs TYPE STANDARD TABLE OF marc.

      " Fast validation with early exit on first error
      LOOP AT lt_group_items INTO DATA(ls_check).
        
        " Early exit validations
        IF ls_check-plant IS INITIAL.
          lv_validation_failed = abap_true.
          lv_error_message = |Plant must not be blank for GrGiSlipNo { ls_slip-slip }|.
          EXIT.
        ENDIF.

        IF ls_check-grgislipno IS INITIAL.
          lv_validation_failed = abap_true.
          lv_error_message = |GrGiSlipNo must not be blank for item { ls_check-itemno }|.
          EXIT.
        ENDIF.

        IF ls_check-docdate IS INITIAL.
          lv_validation_failed = abap_true.
          lv_error_message = |DocDate must not be blank for GrGiSlipNo { ls_slip-slip }|.
          EXIT.
        ENDIF.

        IF ls_check-pstngdate IS INITIAL.
          lv_validation_failed = abap_true.
          lv_error_message = |PstngDate must not be blank for GrGiSlipNo { ls_slip-slip }|.
          EXIT.
        ENDIF.

        IF ls_check-material IS INITIAL.
          lv_validation_failed = abap_true.
          lv_error_message = |Material must not be blank for GrGiSlipNo { ls_slip-slip }|.
          EXIT.
        ENDIF.

        " Enhanced ItemOk validation - FIXED
        IF ls_check-itemok IS INITIAL OR ls_check-itemok EQ space OR 
           ls_check-itemok EQ 'false' OR ls_check-itemok EQ '0' OR ls_check-itemok EQ 'FALSE'.
          lv_validation_failed = abap_true.
          lv_error_message = |ItemOk must be true to process the item for GrGiSlipNo { ls_slip-slip }|.
          EXIT.
        ENDIF.

        IF ls_check-quantity <= 0.
          lv_validation_failed = abap_true.
          lv_error_message = |Quantity must be greater than zero for item { ls_check-itemno }|.
          EXIT.
        ENDIF.

        IF ls_check-movementtype IS INITIAL.
          lv_validation_failed = abap_true.
          lv_error_message = |Movement type is required for item { ls_check-itemno }|.
          EXIT.
        ENDIF.

        " Prepare material for MARC check - FIXED
        CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
          EXPORTING
            input  = ls_check-material
          IMPORTING
            output = lv_material.

        " Add to material-plant pairs for bulk check
        APPEND VALUE #( matnr = lv_material werks = ls_check-plant ) TO lt_material_plant_pairs.

      ENDLOOP.

      " Bulk material validation only if no errors so far - FIXED
      IF lv_validation_failed = abap_false AND lt_material_plant_pairs IS NOT INITIAL.
        DATA: lt_marc_existing TYPE STANDARD TABLE OF marc.
        
        " Get all existing material-plant combinations
        SELECT matnr, werks FROM marc
          FOR ALL ENTRIES IN @lt_material_plant_pairs
          WHERE matnr = @lt_material_plant_pairs-matnr
            AND werks = @lt_material_plant_pairs-werks
          INTO TABLE @lt_marc_existing.

        " Check if all required combinations exist
        LOOP AT lt_material_plant_pairs INTO DATA(ls_required_pair).
          READ TABLE lt_marc_existing TRANSPORTING NO FIELDS 
            WITH KEY matnr = ls_required_pair-matnr werks = ls_required_pair-werks.
          IF sy-subrc <> 0.
            " Find the original material number for error message
            LOOP AT lt_group_items INTO ls_check.
              CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
                EXPORTING
                  input  = ls_check-material
                IMPORTING
                  output = lv_material.
              IF lv_material = ls_required_pair-matnr AND ls_check-plant = ls_required_pair-werks.
                lv_validation_failed = abap_true.
                lv_error_message = |Material { ls_check-material } is not maintained in Plant { ls_check-plant }|.
                EXIT.
              ENDIF.
            ENDLOOP.
            IF lv_validation_failed = abap_true.
              EXIT.
            ENDIF.
          ENDIF.
        ENDLOOP.
      ENDIF.
    ENDIF.

    " If validation failed, mark all items in group as FAILED and continue
    IF lv_validation_failed = abap_true.
      LOOP AT lt_group_items INTO DATA(ls_failed_item).
        CLEAR ls_result_item.
        ls_result_item = CORRESPONDING #( ls_failed_item ).
        ls_result_item-status = 'FAILED'.
        ls_result_item-message = lv_error_message.
        APPEND ls_result_item TO lt_result_data.
      ENDLOOP.
      CONTINUE.
    ENDIF.

    " === PROCESS HEADER DATA ===
    READ TABLE lt_group_items INTO DATA(ls_first_item_in_group) INDEX 1.
    IF sy-subrc <> 0.
      LOOP AT lt_group_items INTO ls_failed_item.
        CLEAR ls_result_item.
        ls_result_item = CORRESPONDING #( ls_failed_item ).
        ls_result_item-status = 'ERROR'.
        ls_result_item-message = 'Failed to read first item for group'.
        APPEND ls_result_item TO lt_result_data.
      ENDLOOP.
      CONTINUE.
    ENDIF.

    " === DATE CONVERSION ===
    TRY.
        " Convert document date
        lv_str = ls_first_item_in_group-docdate.
        IF lv_str CS '/Date(' AND lv_str CS ')/' .
          REPLACE '/Date(' IN lv_str WITH ''.
          REPLACE ')/' IN lv_str WITH ''.
          " Add validation for numeric timestamp - FIXED
          IF lv_str CO '0123456789'.
            lv_timestamp = CONV int8( lv_str ).
            lv_timestamp = lv_timestamp / 1000.
            " Add range validation - FIXED
            IF lv_timestamp BETWEEN 0 AND 4102444800.
              lv_doc_date = '19700101'.
              lv_doc_date = lv_doc_date + ( lv_timestamp / 86400 ).
            ELSE.
              RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                EXPORTING
                  textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                  message = 'Invalid timestamp range in DocDate'.
            ENDIF.
          ELSE.
            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                message = 'Non-numeric timestamp in DocDate'.
          ENDIF.
        ELSE.
          REPLACE ALL OCCURRENCES OF REGEX `[^0-9]` IN lv_str WITH ``.
          IF strlen( lv_str ) >= 8.
            lv_doc_date = lv_str(8).
            " Add date validation - FIXED
            CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
              EXPORTING
                date = lv_doc_date
              EXCEPTIONS
                plausibility_check_failed = 1.
            IF sy-subrc <> 0.
              RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                EXPORTING
                  textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                  message = 'Invalid DocDate format'.
            ENDIF.
          ELSE.
            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                message = 'Invalid DocDate format'.
          ENDIF.
        ENDIF.

        " Convert posting date
        lv_str = ls_first_item_in_group-pstngdate.
        IF lv_str CS '/Date(' AND lv_str CS ')/' .
          REPLACE '/Date(' IN lv_str WITH ''.
          REPLACE ')/' IN lv_str WITH ''.
          " Add validation for numeric timestamp - FIXED
          IF lv_str CO '0123456789'.
            lv_timestamp = CONV int8( lv_str ).
            lv_timestamp = lv_timestamp / 1000.
            " Add range validation - FIXED
            IF lv_timestamp BETWEEN 0 AND 4102444800.
              lv_pstng_date = '19700101'.
              lv_pstng_date = lv_pstng_date + ( lv_timestamp / 86400 ).
            ELSE.
              RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                EXPORTING
                  textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                  message = 'Invalid timestamp range in PstngDate'.
            ENDIF.
          ELSE.
            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                message = 'Non-numeric timestamp in PstngDate'.
          ENDIF.
        ELSE.
          REPLACE ALL OCCURRENCES OF REGEX `[^0-9]` IN lv_str WITH ``.
          IF strlen( lv_str ) >= 8.
            lv_pstng_date = lv_str(8).
            " Add date validation - FIXED
            CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
              EXPORTING
                date = lv_pstng_date
              EXCEPTIONS
                plausibility_check_failed = 1.
            IF sy-subrc <> 0.
              RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                EXPORTING
                  textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                  message = 'Invalid PstngDate format'.
            ENDIF.
          ELSE.
            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                message = 'Invalid PstngDate format'.
          ENDIF.
        ENDIF.

      CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_date_conv).
        LOOP AT lt_group_items INTO ls_failed_item.
          CLEAR ls_result_item.
          ls_result_item = CORRESPONDING #( ls_failed_item ).
          ls_result_item-status = 'ERROR'.
          ls_result_item-message = lx_date_conv->get_text( ).
          APPEND ls_result_item TO lt_result_data.
        ENDLOOP.
        CONTINUE.
      CATCH cx_sy_conversion_no_number.
        LOOP AT lt_group_items INTO ls_failed_item.
          CLEAR ls_result_item.
          ls_result_item = CORRESPONDING #( ls_failed_item ).
          ls_result_item-status = 'ERROR'.
          ls_result_item-message = 'Date conversion error'.
          APPEND ls_result_item TO lt_result_data.
        ENDLOOP.
        CONTINUE.
    ENDTRY.

    " === PREPARE BAPI HEADER ===
    ls_bapiheader-doc_date      = lv_doc_date.
    ls_bapiheader-pstng_date    = lv_pstng_date.
    ls_bapiheader-ref_doc_no    = ls_first_item_in_group-grgislipno.
    ls_bapiheader-gr_gi_slip_no = ls_first_item_in_group-grgislipno.
    ls_bapiheader-header_txt    = ls_first_item_in_group-headertxt.

    " === PREPARE BAPI ITEMS ===
    lv_item_counter = 10.
    LOOP AT lt_group_items INTO ls_item_from_payload.
      CLEAR ls_bapiitem.

      " Set proper line number
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

      ls_bapiitem-plant      = ls_item_from_payload-plant.
      ls_bapiitem-move_type  = ls_item_from_payload-movementtype.
      ls_bapiitem-entry_qnt  = ls_item_from_payload-quantity.
      ls_bapiitem-entry_uom  = ls_item_from_payload-baseuom.
      ls_bapiitem-stge_loc   = ls_item_from_payload-strgloc.
      ls_bapiitem-no_more_gr = 'X'.

      APPEND ls_bapiitem TO lt_bapiitems.
    ENDLOOP.

    IF lt_bapiitems IS INITIAL.
      LOOP AT lt_group_items INTO ls_failed_item.
        CLEAR ls_result_item.
        ls_result_item = CORRESPONDING #( ls_failed_item ).
        ls_result_item-status = 'ERROR'.
        ls_result_item-message = 'No items prepared for BAPI'.
        APPEND ls_result_item TO lt_result_data.
      ENDLOOP.
      CONTINUE.
    ENDIF.

    " === CALL BAPI ===
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

    " === PROCESS BAPI RESULTS ===
    CLEAR lv_bapi_error_message.

    " Check for BAPI errors
    LOOP AT lt_return INTO lv_return WHERE type = 'E' OR type = 'A'.
      IF lv_bapi_error_message IS INITIAL.
        lv_bapi_error_message = lv_return-message.
      ELSE.
        lv_bapi_error_message = |{ lv_bapi_error_message } / { lv_return-message }|.
      ENDIF.
    ENDLOOP.

    IF lv_bapi_error_message IS NOT INITIAL.
      " BAPI failed - mark ALL items as FAILED
      LOOP AT lt_group_items INTO ls_failed_item.
        CLEAR ls_result_item.
        ls_result_item = CORRESPONDING #( ls_failed_item ).
        ls_result_item-Status = 'FAILED'.
        ls_result_item-Message = lv_bapi_error_message.
        ls_result_item-MigoDocNo = ''.
        APPEND ls_result_item TO lt_result_data.
      ENDLOOP.

      " Rollback transaction
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.

    ELSE.
      " BAPI succeeded - commit and mark ALL items as SUCCESS
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait = 'X'.

      " Get success message
      READ TABLE lt_return INTO lv_return WITH KEY type = 'S'.
      IF sy-subrc = 0 AND lv_return-message IS NOT INITIAL.
        lv_success_message = lv_return-message.
      ELSE.
        lv_success_message = |Document { lv_migo_doc } posted successfully|.
      ENDIF.

      " Mark ALL items as SUCCESS
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

  " === PREPARE FINAL RESPONSE ===
  ls_final_response-ZMATSet = lt_result_data.

  " Check for any errors to determine if we should raise exception
  DATA: lv_has_errors   TYPE abap_bool,
        lv_has_success  TYPE abap_bool,
        lv_all_errors   TYPE string.

  LOOP AT lt_result_data INTO ls_result_item.
    CASE ls_result_item-status.
      WHEN 'SUCCESS'.
        lv_has_success = abap_true.
      WHEN 'FAILED' OR 'ERROR'.
        lv_has_errors = abap_true.
        " Collect error messages for exception
        IF lv_all_errors IS INITIAL.
          lv_all_errors = ls_result_item-message.
        ELSE.
          lv_all_errors = |{ lv_all_errors }; { ls_result_item-message }|.
        ENDIF.
    ENDCASE.
  ENDLOOP.

  " Return appropriate HTTP status - FIXED
  IF lv_has_errors = abap_true AND lv_has_success = abap_false.
    " All failed - raise exception for 400 Bad Request
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message = lv_all_errors.
  ELSEIF lv_has_errors = abap_true AND lv_has_success = abap_true.
    " Partial success - return 201 with warning in response
    " (SAP Gateway doesn't support 207 Multi-Status well)
    copy_data_to_ref(
      EXPORTING
        is_data = ls_final_response
      CHANGING
        cr_data = er_deep_entity
    ).
  ELSE.
    " All success - return 201 Created (default)
    copy_data_to_ref(
      EXPORTING
        is_data = ls_final_response
      CHANGING
        cr_data = er_deep_entity
    ).
  ENDIF.

ENDMETHOD.