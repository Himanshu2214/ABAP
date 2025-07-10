METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  TYPES: ty_item  TYPE zcl_zmigo_mvmt_auto_mpc_ext=>ts_zmat,
         ty_items TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY.

  TYPES: BEGIN OF ty_slip,
           slip TYPE string,
         END OF ty_slip.

  TYPES: BEGIN OF ty_payload,
           ZMATSet TYPE ty_items,
         END OF ty_payload.

  DATA: ls_payload   TYPE ty_payload,
        lt_item_data TYPE ty_items,
        lt_grp_slips TYPE SORTED TABLE OF ty_slip WITH UNIQUE KEY slip,
        ls_slip      TYPE ty_slip.

  DATA: lt_return TYPE TABLE OF bapiret2,
        lv_return TYPE bapiret2.

  DATA: lv_any_error_occurred TYPE abap_bool VALUE abap_false.
  DATA: lt_bapi_error_messages TYPE TABLE OF bapiret2.

  io_data_provider->read_entry_data( IMPORTING es_data = ls_payload ).
  lt_item_data = ls_payload-ZMATSet.

  IF lt_item_data IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message = 'ZMATSet is empty in the request payload.'
        http_status_code = '400'.
  ENDIF.

  " Sort item data for better performance in loops
  SORT lt_item_data BY grgislipno.

  " Collect unique slip numbers
  LOOP AT lt_item_data ASSIGNING FIELD-SYMBOL(<fs_item>).
    IF <fs_item>-GrGiSlipNo IS NOT INITIAL.
      ls_slip-slip = <fs_item>-GrGiSlipNo.
      COLLECT ls_slip INTO lt_grp_slips.
    ENDIF.
  ENDLOOP.

  IF lt_grp_slips IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message = 'No GrGiSlipNo found in ZMATSet items to process.'
        http_status_code = '400'.
  ENDIF.

  DATA: lt_result_data TYPE ty_items.

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

    " Get items of the group - optimized with binary search
    LOOP AT lt_item_data INTO DATA(ls_item_from_payload) WHERE GrGiSlipNo = ls_slip-slip.
      APPEND ls_item_from_payload TO lt_group_items.
    ENDLOOP.

    " Enhanced validation for group items
    DATA(lv_validation_failed) = abap_false.
    CLEAR: lv_return, lt_bapi_error_messages.

    LOOP AT lt_group_items INTO DATA(ls_check).

      " Basic field validations
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

      " Material validation with proper conversion
      IF ls_check-material IS INITIAL.
        lv_return-type = 'E'.
        lv_return-message = |Material must not be blank for GrGiSlipNo { ls_slip-slip }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ELSE.
        " Use proper material conversion
        DATA(lv_material) = ls_check-material.
        CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
          EXPORTING
            input  = lv_material
          IMPORTING
            output = lv_material.

        " Validate material exists in MARC
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
      ENDIF.

      " Enhanced ItemOk validation
      IF ls_check-itemok IS INITIAL OR ls_check-itemok EQ space OR 
         ls_check-itemok EQ 'false' OR ls_check-itemok EQ '0' OR ls_check-itemok EQ 'FALSE'.
        lv_return-type = 'E'.
        lv_return-message = |ItemOk must be true to process the item for GrGiSlipNo { ls_slip-slip }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ENDIF.

      " Quantity validation
      IF ls_check-quantity <= 0.
        lv_return-type = 'E'.
        lv_return-message = |Quantity must be greater than zero for item { ls_check-itemno }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ENDIF.

      " Movement type validation - NEW
      IF ls_check-movementtype IS INITIAL.
        lv_return-type = 'E'.
        lv_return-message = |Movement type is required for item { ls_check-itemno }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ELSE.
        " Validate movement type exists
        SELECT SINGLE bwart FROM t156
          WHERE bwart = @ls_check-movementtype
          INTO @DATA(lv_movement_type_check).

        IF sy-subrc <> 0.
          lv_return-type = 'E'.
          lv_return-message = |Invalid movement type { ls_check-movementtype } for item { ls_check-itemno }|.
          APPEND lv_return TO lt_bapi_error_messages.
          lv_validation_failed = abap_true.
        ENDIF.
      ENDIF.

      " Base UOM validation - NEW
      IF ls_check-baseuom IS NOT INITIAL.
        SELECT SINGLE msehi FROM t006
          WHERE msehi = @ls_check-baseuom
          INTO @DATA(lv_uom_check).

        IF sy-subrc <> 0.
          lv_return-type = 'E'.
          lv_return-message = |Invalid unit of measure { ls_check-baseuom } for item { ls_check-itemno }|.
          APPEND lv_return TO lt_bapi_error_messages.
          lv_validation_failed = abap_true.
        ENDIF.
      ENDIF.

      " Storage location validation - NEW
      IF ls_check-strgloc IS NOT INITIAL.
        SELECT SINGLE lgort FROM t001l
          WHERE werks = @ls_check-plant
            AND lgort = @ls_check-strgloc
          INTO @DATA(lv_sloc_check).

        IF sy-subrc <> 0.
          lv_return-type = 'E'.
          lv_return-message = |Storage location { ls_check-strgloc } not valid for plant { ls_check-plant }|.
          APPEND lv_return TO lt_bapi_error_messages.
          lv_validation_failed = abap_true.
        ENDIF.
      ENDIF.

      " GL Account validation - NEW
      IF ls_check-glaccount IS NOT INITIAL.
        SELECT SINGLE saknr FROM ska1
          WHERE saknr = @ls_check-glaccount
          INTO @DATA(lv_glacc_check).

        IF sy-subrc <> 0.
          lv_return-type = 'E'.
          lv_return-message = |Invalid GL account { ls_check-glaccount } for item { ls_check-itemno }|.
          APPEND lv_return TO lt_bapi_error_messages.
          lv_validation_failed = abap_true.
        ENDIF.
      ENDIF.

      " Cost center validation - NEW
      IF ls_check-costcenter IS NOT INITIAL.
        SELECT SINGLE kostl FROM csks
          WHERE kostl = @ls_check-costcenter
            AND datbi >= @sy-datum
            AND datab <= @sy-datum
          INTO @DATA(lv_costcenter_check).

        IF sy-subrc <> 0.
          lv_return-type = 'E'.
          lv_return-message = |Invalid or inactive cost center { ls_check-costcenter } for item { ls_check-itemno }|.
          APPEND lv_return TO lt_bapi_error_messages.
          lv_validation_failed = abap_true.
        ENDIF.
      ENDIF.

      " Order number validation - NEW
      IF ls_check-orderno IS NOT INITIAL.
        SELECT SINGLE aufnr FROM aufk
          WHERE aufnr = @ls_check-orderno
          INTO @DATA(lv_order_check).

        IF sy-subrc <> 0.
          lv_return-type = 'E'.
          lv_return-message = |Invalid order number { ls_check-orderno } for item { ls_check-itemno }|.
          APPEND lv_return TO lt_bapi_error_messages.
          lv_validation_failed = abap_true.
        ENDIF.
      ENDIF.

      " Authorization checks - NEW
      AUTHORITY-CHECK OBJECT 'M_MATE_WRK'
        ID 'ACTVT' FIELD '02'
        ID 'WERKS' FIELD ls_check-plant.

      IF sy-subrc <> 0.
        lv_return-type = 'E'.
        lv_return-message = |No authorization for plant { ls_check-plant }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ENDIF.

      " Enhanced duplicate slip number check - IMPROVED
      SELECT SINGLE mblnr FROM mkpf
        WHERE xabln = @ls_check-grgislipno
        INTO @DATA(lv_xabln_check).

      IF sy-subrc = 0.
        lv_return-type = 'E'.
        lv_return-message = |GrGiSlipNo { ls_check-grgislipno } already exists in SAP system|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ENDIF.

    ENDLOOP.

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
      TRY.
          " Enhanced date conversion with better error handling
          lv_str = ls_first_item_in_group-docdate.
          PERFORM convert_date_safely USING lv_str CHANGING lv_doc_date.

          " Same for posting date
          lv_str = ls_first_item_in_group-pstngdate.
          PERFORM convert_date_safely USING lv_str CHANGING lv_pstng_date.

        CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_date_conv).
          ls_result_item = CORRESPONDING #( ls_first_item_in_group ).
          ls_result_item-status = 'ERROR'.
          ls_result_item-message = lx_date_conv->get_text( ).
          APPEND ls_result_item TO lt_result_data.
          lv_any_error_occurred = abap_true.
          CONTINUE.
      ENDTRY.

      ls_bapiheader-doc_date = lv_doc_date.
      ls_bapiheader-pstng_date = lv_pstng_date.
      ls_bapiheader-ref_doc_no = ls_first_item_in_group-grgislipno.
      ls_bapiheader-gr_gi_slip_no = ls_first_item_in_group-grgislipno.
      ls_bapiheader-header_txt = ls_first_item_in_group-headertxt.
    ELSE.
      ls_result_item-grgislipno = ls_slip-slip.
      ls_result_item-status = 'ERROR'.
      ls_result_item-message = 'Failed to read first item for group: ' && ls_slip-slip.
      APPEND ls_result_item TO lt_result_data.
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
      ls_result_item = CORRESPONDING #( ls_first_item_in_group ).
      ls_result_item-status = 'ERROR'.
      ls_result_item-message = 'No items prepared for BAPI for GrGiSlipNo: ' && ls_slip-slip.
      APPEND ls_result_item TO lt_result_data.
      lv_any_error_occurred = abap_true.
      CONTINUE.
    ENDIF.

    " Enhanced transaction handling with savepoint
    DATA(lv_savepoint_name) = |SP_{ ls_slip-slip }|.
    CALL FUNCTION 'DB_COMMIT'.

    " Call BAPI
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

    " Check for BAPI errors - if ANY error occurs, ALL items in the group should fail
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
      " Rollback the transaction for this group only
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

  " NEW: Enhanced HTTP status code handling
  DATA: lv_success_count TYPE i,
        lv_failed_count TYPE i,
        lv_error_count TYPE i.

  " Count results by status
  LOOP AT lt_result_data INTO DATA(ls_result).
    CASE ls_result-status.
      WHEN 'SUCCESS'.
        lv_success_count = lv_success_count + 1.
      WHEN 'FAILED'.
        lv_failed_count = lv_failed_count + 1.
      WHEN 'ERROR'.
        lv_error_count = lv_error_count + 1.
    ENDCASE.
  ENDLOOP.

  " Determine appropriate HTTP status and action
  IF lv_error_count > 0 OR lv_failed_count > 0.
    IF lv_success_count = 0.
      " All failed - return 400 Bad Request
      DATA(lv_all_errors) = ``.
      LOOP AT lt_result_data INTO ls_result WHERE status <> 'SUCCESS'.
        IF lv_all_errors IS INITIAL.
          lv_all_errors = ls_result-message.
        ELSE.
          lv_all_errors = |{ lv_all_errors }; { ls_result-message }|.
        ENDIF.
      ENDLOOP.

      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = lv_all_errors
          http_status_code = '400'.
    ELSE.
      " Mixed results - add warning message (still returns 201 but with warnings)
      MESSAGE i001(z_custom) WITH 'Partial success:' lv_success_count 'succeeded,' lv_failed_count + lv_error_count 'failed'.
    ENDIF.
  ENDIF.
  " All successful cases continue with default 201 status

  " Prepare final response structure
  TYPES: BEGIN OF ty_final_response,
           ZMATSet TYPE ty_items,
         END OF ty_final_response.
  DATA: ls_final_response TYPE ty_final_response.
  ls_final_response-ZMATSet = lt_result_data.

  copy_data_to_ref(
    EXPORTING
      is_data = ls_final_response
    CHANGING
      cr_data = er_deep_entity
  ).

ENDMETHOD.

" Helper form for enhanced date conversion
FORM convert_date_safely USING p_date_string TYPE string
                        CHANGING p_result_date TYPE dats.

  DATA: lv_str TYPE string,
        lv_timestamp TYPE int8.

  lv_str = p_date_string.

  IF lv_str CS '/Date(' AND lv_str CS ')/' .
    " Handle JSON date format /Date(timestamp)/
    TRY.
        REPLACE '/Date(' IN lv_str WITH ''.
        REPLACE ')/' IN lv_str WITH ''.

        " Validate timestamp is numeric
        IF lv_str CO '0123456789'.
          lv_timestamp = CONV int8( lv_str ).
          lv_timestamp = lv_timestamp / 1000. " Convert to seconds

          " Validate timestamp range (between 1970 and 2099)
          IF lv_timestamp BETWEEN 0 AND 4102444800.
            p_result_date = '19700101'.
            p_result_date = p_result_date + ( lv_timestamp / 86400 ).
          ELSE.
            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                message = |Invalid timestamp range in date: { p_date_string }|.
          ENDIF.
        ELSE.
          RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
            EXPORTING
              message = |Non-numeric timestamp in date: { p_date_string }|.
        ENDIF.

      CATCH cx_sy_conversion_no_number.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            message = |Invalid timestamp format in date: { p_date_string }|.
    ENDTRY.
  ELSE.
    " Handle regular date format (YYYYMMDD)
    REPLACE ALL OCCURRENCES OF REGEX `[^0-9]` IN lv_str WITH ``.
    IF strlen( lv_str ) >= 8.
      p_result_date = lv_str(8).
      " Validate date
      CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
        EXPORTING
          date = p_result_date
        EXCEPTIONS
          plausibility_check_failed = 1.
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            message = |Invalid date format: { p_date_string }|.
      ENDIF.
    ELSE.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          message = |Invalid date format: { p_date_string }|.
    ENDIF.
  ENDIF.

ENDFORM.