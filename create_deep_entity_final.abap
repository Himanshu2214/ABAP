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

  io_data_provider->read_entry_data( IMPORTING es_data = ls_payload ).
  lt_item_data = ls_payload-ZMATSet.

  IF lt_item_data IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message = 'ZMATSet is empty in the request payload.'.
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
        message = 'No GrGiSlipNo found in ZMATSet items to process.'.
  ENDIF.

  " FAIL FAST VALIDATION - Stop at first error
  LOOP AT lt_item_data INTO DATA(ls_check).

    " Basic field validations
    IF ls_check-plant IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |Plant must not be blank for GrGiSlipNo { ls_check-grgislipno }|.
    ENDIF.

    IF ls_check-grgislipno IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |GrGiSlipNo must not be blank for item { ls_check-itemno }|.
    ENDIF.

    IF ls_check-docdate IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |DocDate must not be blank for GrGiSlipNo { ls_check-grgislipno }|.
    ENDIF.

    IF ls_check-pstngdate IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |PstngDate must not be blank for GrGiSlipNo { ls_check-grgislipno }|.
    ENDIF.

    " Material validation with proper conversion
    IF ls_check-material IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |Material must not be blank for GrGiSlipNo { ls_check-grgislipno }|.
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
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
            message = |Material { ls_check-material } is not maintained in Plant { ls_check-plant } (MARC check failed)|.
      ENDIF.
    ENDIF.

    " Enhanced ItemOk validation
    IF ls_check-itemok IS INITIAL OR ls_check-itemok EQ space OR 
       ls_check-itemok EQ 'false' OR ls_check-itemok EQ '0' OR ls_check-itemok EQ 'FALSE'.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |ItemOk must be true to process the item for GrGiSlipNo { ls_check-grgislipno }|.
    ENDIF.

    " Quantity validation
    IF ls_check-quantity <= 0.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |Quantity must be greater than zero for item { ls_check-itemno }|.
    ENDIF.

    " Movement type validation
    IF ls_check-movementtype IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |Movement type is required for item { ls_check-itemno }|.
    ELSE.
      " Validate movement type exists
      SELECT SINGLE bwart FROM t156
        WHERE bwart = @ls_check-movementtype
        INTO @DATA(lv_movement_type_check).

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
            message = |Invalid movement type { ls_check-movementtype } for item { ls_check-itemno }|.
      ENDIF.
    ENDIF.

    " Base UOM validation
    IF ls_check-baseuom IS NOT INITIAL.
      SELECT SINGLE msehi FROM t006
        WHERE msehi = @ls_check-baseuom
        INTO @DATA(lv_uom_check).

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
            message = |Invalid unit of measure { ls_check-baseuom } for item { ls_check-itemno }|.
      ENDIF.
    ENDIF.

    " Storage location validation
    IF ls_check-strgloc IS NOT INITIAL.
      SELECT SINGLE lgort FROM t001l
        WHERE werks = @ls_check-plant
          AND lgort = @ls_check-strgloc
        INTO @DATA(lv_sloc_check).

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
            message = |Storage location { ls_check-strgloc } not valid for plant { ls_check-plant }|.
      ENDIF.
    ENDIF.

    " GL Account validation
    IF ls_check-glaccount IS NOT INITIAL.
      SELECT SINGLE saknr FROM ska1
        WHERE saknr = @ls_check-glaccount
        INTO @DATA(lv_glacc_check).

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
            message = |Invalid GL account { ls_check-glaccount } for item { ls_check-itemno }|.
      ENDIF.
    ENDIF.

    " Cost center validation
    IF ls_check-costcenter IS NOT INITIAL.
      SELECT SINGLE kostl FROM csks
        WHERE kostl = @ls_check-costcenter
          AND datbi >= @sy-datum
          AND datab <= @sy-datum
        INTO @DATA(lv_costcenter_check).

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
            message = |Invalid or inactive cost center { ls_check-costcenter } for item { ls_check-itemno }|.
      ENDIF.
    ENDIF.

    " Order number validation
    IF ls_check-orderno IS NOT INITIAL.
      SELECT SINGLE aufnr FROM aufk
        WHERE aufnr = @ls_check-orderno
        INTO @DATA(lv_order_check).

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
            message = |Invalid order number { ls_check-orderno } for item { ls_check-itemno }|.
      ENDIF.
    ENDIF.

    " Enhanced duplicate slip number check
    SELECT SINGLE mblnr FROM mkpf
      WHERE xabln = @ls_check-grgislipno
      INTO @DATA(lv_xabln_check).

    IF sy-subrc = 0.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |GrGiSlipNo { ls_check-grgislipno } already exists in SAP system|.
    ENDIF.

  ENDLOOP.

  " If we reach here, all validations passed - now process the data
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

    " Get items of the group
    LOOP AT lt_item_data INTO DATA(ls_item_from_payload) WHERE GrGiSlipNo = ls_slip-slip.
      APPEND ls_item_from_payload TO lt_group_items.
    ENDLOOP.

    " Get header fields from first item of the current group
    READ TABLE lt_group_items INTO DATA(ls_first_item_in_group) INDEX 1.
    IF sy-subrc = 0.
      TRY.
          " Enhanced date conversion with better error handling
          lv_str = ls_first_item_in_group-docdate.
          " Convert DocDate
          IF lv_str CS '/Date(' AND lv_str CS ')/' .
            " Handle JSON date format /Date(timestamp)/
            REPLACE '/Date(' IN lv_str WITH ''.
            REPLACE ')/' IN lv_str WITH ''.
            " Validate timestamp is numeric
            IF lv_str CO '0123456789'.
              DATA(lv_timestamp) = CONV int8( lv_str ).
              lv_timestamp = lv_timestamp / 1000. " Convert to seconds
              " Validate timestamp range (between 1970 and 2099)
              IF lv_timestamp BETWEEN 0 AND 4102444800.
                lv_doc_date = '19700101'.
                lv_doc_date = lv_doc_date + ( lv_timestamp / 86400 ).
              ELSE.
                RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                  EXPORTING
                    textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                    message = |Invalid timestamp range in DocDate: { ls_first_item_in_group-docdate }|.
              ENDIF.
            ELSE.
              RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                EXPORTING
                  textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                  message = |Non-numeric timestamp in DocDate: { ls_first_item_in_group-docdate }|.
            ENDIF.
          ELSE.
            " Handle regular date format (YYYYMMDD)
            REPLACE ALL OCCURRENCES OF REGEX `[^0-9]` IN lv_str WITH ``.
            IF strlen( lv_str ) >= 8.
              lv_doc_date = lv_str(8).
              " Validate date
              CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
                EXPORTING
                  date = lv_doc_date
                EXCEPTIONS
                  plausibility_check_failed = 1.
              IF sy-subrc <> 0.
                RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                  EXPORTING
                    textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                    message = |Invalid DocDate format: { ls_first_item_in_group-docdate }|.
              ENDIF.
            ELSE.
              RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                EXPORTING
                  textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                  message = |Invalid DocDate format: { ls_first_item_in_group-docdate }|.
            ENDIF.
          ENDIF.

          " Same for posting date
          lv_str = ls_first_item_in_group-pstngdate.
          " Convert PstngDate
          IF lv_str CS '/Date(' AND lv_str CS ')/' .
            " Handle JSON date format /Date(timestamp)/
            REPLACE '/Date(' IN lv_str WITH ''.
            REPLACE ')/' IN lv_str WITH ''.
            " Validate timestamp is numeric
            IF lv_str CO '0123456789'.
              lv_timestamp = CONV int8( lv_str ).
              lv_timestamp = lv_timestamp / 1000. " Convert to seconds
              " Validate timestamp range (between 1970 and 2099)
              IF lv_timestamp BETWEEN 0 AND 4102444800.
                lv_pstng_date = '19700101'.
                lv_pstng_date = lv_pstng_date + ( lv_timestamp / 86400 ).
              ELSE.
                RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                  EXPORTING
                    textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                    message = |Invalid timestamp range in PstngDate: { ls_first_item_in_group-pstngdate }|.
              ENDIF.
            ELSE.
              RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                EXPORTING
                  textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                  message = |Non-numeric timestamp in PstngDate: { ls_first_item_in_group-pstngdate }|.
            ENDIF.
          ELSE.
            " Handle regular date format (YYYYMMDD)
            REPLACE ALL OCCURRENCES OF REGEX `[^0-9]` IN lv_str WITH ``.
            IF strlen( lv_str ) >= 8.
              lv_pstng_date = lv_str(8).
              " Validate date
              CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
                EXPORTING
                  date = lv_pstng_date
                EXCEPTIONS
                  plausibility_check_failed = 1.
              IF sy-subrc <> 0.
                RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                  EXPORTING
                    textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                    message = |Invalid PstngDate format: { ls_first_item_in_group-pstngdate }|.
              ENDIF.
            ELSE.
              RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                EXPORTING
                  textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
                  message = |Invalid PstngDate format: { ls_first_item_in_group-pstngdate }|.
            ENDIF.
          ENDIF.

        CATCH cx_sy_conversion_no_number.
          RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
            EXPORTING
              textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
              message = |Invalid date conversion error|.
      ENDTRY.

      ls_bapiheader-doc_date = lv_doc_date.
      ls_bapiheader-pstng_date = lv_pstng_date.
      ls_bapiheader-ref_doc_no = ls_first_item_in_group-grgislipno.
      ls_bapiheader-gr_gi_slip_no = ls_first_item_in_group-grgislipno.
      ls_bapiheader-header_txt = ls_first_item_in_group-headertxt.
    ELSE.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |Failed to read first item for group: { ls_slip-slip }|.
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
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |No items prepared for BAPI for GrGiSlipNo: { ls_slip-slip }|.
    ENDIF.

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

    " Check for BAPI errors - fail immediately on first error
    LOOP AT lt_return INTO lv_return WHERE type = 'E' OR type = 'A'.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = lv_return-message.
    ENDLOOP.

    " BAPI succeeded - commit
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

  ENDLOOP.

  " If we reach here, everything was successful
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