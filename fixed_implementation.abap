METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  TYPES: ty_item TYPE zcl_zmigo_mvmt_auto_mpc_ext=>ts_zmat,
         ty_items TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY.

  TYPES: BEGIN OF ty_slip,
           slip TYPE string,
         END OF ty_slip.

  TYPES: BEGIN OF ty_payload,
           ZMATSet TYPE ty_items,
         END OF ty_payload.

  DATA: ls_payload TYPE ty_payload,
        lt_item_data TYPE ty_items,
        lt_grp_slips TYPE SORTED TABLE OF ty_slip WITH UNIQUE KEY slip,
        ls_slip TYPE ty_slip.

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
        message = 'ZMATSet is empty in the request payload.'.
  ENDIF.

  " Collect distinct slip numbers
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

  DATA: lt_result_data TYPE ty_items.

  LOOP AT lt_grp_slips INTO ls_slip.

    DATA: lt_group_items     TYPE ty_items,
          ls_bapiheader      TYPE bapi2017_gm_head_01,
          lt_bapiitems       TYPE TABLE OF bapi2017_gm_item_create,
          ls_bapiitem        TYPE bapi2017_gm_item_create,
          lv_doc_date        TYPE dats,
          lv_pstng_date      TYPE dats,
          lv_str             TYPE string,
          lv_migo_doc        TYPE bapi2017_gm_head_ret-mat_doc,
          lv_doc_year        TYPE bapi2017_gm_head_ret-doc_year,
          ls_result_item     TYPE ty_item,
          lv_item_counter    TYPE i.

    CLEAR: lt_group_items, lt_bapiitems, ls_bapiheader, lt_return, lv_migo_doc, ls_result_item.

    " Get items of the group
    LOOP AT lt_item_data INTO DATA(ls_item_from_payload) WHERE GrGiSlipNo = ls_slip-slip.
      APPEND ls_item_from_payload TO lt_group_items.
    ENDLOOP.

    " Validate group items
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
      ENDIF.

      IF ls_check-itemok IS INITIAL OR ls_check-itemok EQ SPACE.
        lv_return-type = 'E'.
        lv_return-message = |ItemOk must be true to process the item for GrGiSlipNo { ls_slip-slip }|.
        APPEND lv_return TO lt_bapi_error_messages.
        lv_validation_failed = abap_true.
      ENDIF.

      " Additional validations
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

    ENDLOOP.

    IF lv_validation_failed = abap_true.
      READ TABLE lt_group_items INTO DATA(ls_error_item) INDEX 1.
      ls_result_item = CORRESPONDING #( ls_error_item ).
      ls_result_item-status = 'ERROR'.

      " Collect all relevant messages into one string
      DATA(lv_validation_msg) = ``.
      LOOP AT lt_bapi_error_messages INTO lv_return.
        IF lv_validation_msg IS INITIAL.
          lv_validation_msg = lv_return-message.
        ELSE.
          lv_validation_msg = |{ lv_validation_msg } / { lv_return-message }|.
        ENDIF.
      ENDLOOP.

      ls_result_item-message = lv_validation_msg.
      APPEND ls_result_item TO lt_result_data.
      lv_any_error_occurred = abap_true.

      CONTINUE.
    ENDIF.

    " Get header fields from first item of the current group
    READ TABLE lt_group_items INTO DATA(ls_first_item_in_group) INDEX 1.
    IF sy-subrc = 0.
      TRY.
          " Convert date from JSON format /Date(timestamp)/ to ABAP date
          lv_str = ls_first_item_in_group-docdate.
          IF lv_str CS '/Date(' AND lv_str CS ')/' .
            " Extract timestamp from /Date(1750099200000)/
            REPLACE '/Date(' IN lv_str WITH ''.
            REPLACE ')/' IN lv_str WITH ''.
            " Convert timestamp to date (timestamp is in milliseconds)
            DATA(lv_timestamp) = CONV int8( lv_str ).
            lv_timestamp = lv_timestamp / 1000. " Convert to seconds
            " Convert Unix timestamp to ABAP date
            CALL FUNCTION 'CONVERT_DATE_TO_EXTERNAL'
              EXPORTING
                date_internal = '19700101'
              IMPORTING
                date_external = lv_str.
            lv_doc_date = '19700101'.
            lv_doc_date = lv_doc_date + ( lv_timestamp / 86400 ). " Add days
          ELSE.
            " Handle regular date format
            REPLACE ALL OCCURRENCES OF REGEX `[^0-9]` IN lv_str WITH ``.
            IF strlen( lv_str ) >= 8.
              lv_doc_date = lv_str(8).
            ELSE.
              RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                EXPORTING message = 'Invalid DocDate format for GrGiSlipNo: ' && ls_slip-slip.
            ENDIF.
          ENDIF.

          " Same for posting date
          lv_str = ls_first_item_in_group-pstngdate.
          IF lv_str CS '/Date(' AND lv_str CS ')/' .
            " Extract timestamp from /Date(1750099200000)/
            REPLACE '/Date(' IN lv_str WITH ''.
            REPLACE ')/' IN lv_str WITH ''.
            " Convert timestamp to date (timestamp is in milliseconds)
            lv_timestamp = CONV int8( lv_str ).
            lv_timestamp = lv_timestamp / 1000. " Convert to seconds
            " Convert Unix timestamp to ABAP date
            lv_pstng_date = '19700101'.
            lv_pstng_date = lv_pstng_date + ( lv_timestamp / 86400 ). " Add days
          ELSE.
            " Handle regular date format
            REPLACE ALL OCCURRENCES OF REGEX `[^0-9]` IN lv_str WITH ``.
            IF strlen( lv_str ) >= 8.
              lv_pstng_date = lv_str(8).
            ELSE.
              RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                EXPORTING message = 'Invalid PstngDate format for GrGiSlipNo: ' && ls_slip-slip.
            ENDIF.
          ENDIF.

        CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_date_conv).
          ls_result_item = CORRESPONDING #( ls_first_item_in_group ).
          ls_result_item-status  = 'ERROR'.
          ls_result_item-message = lx_date_conv->get_text( ).
          APPEND ls_result_item TO lt_result_data.
          lv_any_error_occurred = abap_true.
          CONTINUE.
      ENDTRY.

      ls_bapiheader-doc_date      = lv_doc_date.
      ls_bapiheader-pstng_date    = lv_pstng_date.
      ls_bapiheader-gr_gi_slip_no = ls_first_item_in_group-grgislipno.
      ls_bapiheader-header_txt    = ls_first_item_in_group-headertxt.
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

      " FIXED: Use stge_type instead of stck_type
      ls_bapiitem-stge_type = lv_item_counter.

      " Apply proper conversion exits
      CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
        EXPORTING
          input  = ls_item_from_payload-material
        IMPORTING
          output = ls_bapiitem-material.

      " Only apply ALPHA conversion if fields are not initial
      IF ls_item_from_payload-glaccount IS NOT INITIAL.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = ls_item_from_payload-glaccount
          IMPORTING
            output = ls_bapiitem-gl_account.
      ENDIF.

      IF ls_item_from_payload-costcenter IS NOT INITIAL.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = ls_item_from_payload-costcenter
          IMPORTING
            output = ls_bapiitem-costcenter.
      ENDIF.

      IF ls_item_from_payload-orderno IS NOT INITIAL.
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING
            input  = ls_item_from_payload-orderno
          IMPORTING
            output = ls_bapiitem-orderid.
      ENDIF.

      ls_bapiitem-plant      = ls_item_from_payload-plant.
      ls_bapiitem-move_type  = ls_item_from_payload-movementtype.
      ls_bapiitem-entry_qnt  = ls_item_from_payload-quantity.
      ls_bapiitem-entry_uom  = ls_item_from_payload-baseuom.
      ls_bapiitem-stge_loc   = ls_item_from_payload-strgloc.

      APPEND ls_bapiitem TO lt_bapiitems.
      lv_item_counter = lv_item_counter + 10.
    ENDLOOP.

    IF lt_bapiitems IS INITIAL.
      ls_result_item = CORRESPONDING #( ls_first_item_in_group ).
      ls_result_item-status = 'ERROR'.
      ls_result_item-message = 'No items prepared for BAPI for GrGiSlipNo: ' && ls_slip-slip.
      APPEND ls_result_item TO lt_result_data.
      lv_any_error_occurred = abap_true.
      CONTINUE.
    ENDIF.

    " Call BAPI
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

    " Use first item of the group as the base for the response item for this slip
    ls_result_item = CORRESPONDING #( ls_first_item_in_group ).

    DATA lv_bapi_error_message TYPE string.
    CLEAR lv_bapi_error_message.

    LOOP AT lt_return INTO lv_return WHERE type = 'E' OR type = 'A'.
      IF lv_bapi_error_message IS INITIAL.
        lv_bapi_error_message = lv_return-message.
      ELSE.
        lv_bapi_error_message = |{ lv_bapi_error_message } / { lv_return-message }|.
      ENDIF.
    ENDLOOP.

    IF lv_bapi_error_message IS NOT INITIAL.
      ls_result_item-Status     = 'ERROR'.
      ls_result_item-Message    = lv_bapi_error_message.
      ls_result_item-MigoDocNo  = ''.
      lv_any_error_occurred = abap_true.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    ELSE.
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait = 'X'.
      ls_result_item-Status     = 'SUCCESS'.
      ls_result_item-MigoDocNo  = lv_migo_doc.

      " Try to find a success message, otherwise provide a generic one
      READ TABLE lt_return INTO lv_return WITH KEY type = 'S'.
      IF sy-subrc = 0.
        ls_result_item-Message = lv_return-message.
      ELSE.
        ls_result_item-Message = 'Document ' && lv_migo_doc && ' posted successfully.'.
      ENDIF.
    ENDIF.

    " Only one response per slip
    APPEND ls_result_item TO lt_result_data.
  ENDLOOP.

  " Prepare final response structure
  TYPES: BEGIN OF ty_final_response,
           ZMATSet TYPE ty_items,
         END OF ty_final_response.
  DATA: ls_final_response TYPE ty_final_response.
  ls_final_response-ZMATSet = lt_result_data.

  " APPROACH 1: Set response data first, then handle HTTP status via exception
  copy_data_to_ref(
    EXPORTING
      is_data = ls_final_response
    CHANGING
      cr_data = er_deep_entity
  ).

  " APPROACH 2: Handle HTTP status code using business exception
  " This approach works across all SAP Gateway versions
  IF lv_any_error_occurred = abap_true.
    
    " Method A: Use exception with specific HTTP status code
    " This method preserves the response body while setting correct status
    DATA: lx_busi_exception TYPE REF TO /iwbep/cx_mgw_busi_exception.
    
    CREATE OBJECT lx_busi_exception
      EXPORTING
        textid           = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message          = 'Business validation errors occurred'
        message_unlimited = 'One or more material movements failed. Check response details.'.
    
    " Try to set HTTP status code if supported
    TRY.
        lx_busi_exception->set_http_status_code( '422' ).
      CATCH cx_sy_no_handler.
        " HTTP status code setting not supported in this version
        " The exception will still result in a 4xx status code
    ENDTRY.
    
    RAISE EXCEPTION lx_busi_exception.
    
  ENDIF.

ENDMETHOD.