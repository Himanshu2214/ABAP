METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  " Step 1: Define the structure matching the deep entity
  TYPES: ty_item  TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementitem,
         ty_items TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY.

  TYPES: BEGIN OF ty_header,
           grgislipno     TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-grgislipno,
           ztypegm        TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-ztypegm,
           zsubtype       TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-zsubtype,
           movementtype   TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-movementtype,
           docdate        TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-docdate,
           pstngdate      TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-pstngdate,
           headertxt      TYPE zcl_zmm_migo_automatio_mpc=>ts_goodsmovementheader-headertxt,
           headertoitemnav TYPE ty_items,
         END OF ty_header.

  TYPES: ty_headers TYPE STANDARD TABLE OF ty_header WITH DEFAULT KEY.

  TYPES: BEGIN OF ty_deep_headerdummy,
           grgislipno    TYPE zcl_zmm_migo_automatio_mpc=>ts_headerdummy-grgislipno,
           overallstatus TYPE string,  " Added overall status
           torealheaders TYPE ty_headers,
         END OF ty_deep_headerdummy.

  DATA: ls_deep_entity TYPE ty_deep_headerdummy.

  " BAPI structures
  DATA: ls_gm_header    TYPE bapi2017_gm_head_01,
        lt_gm_items     TYPE TABLE OF bapi2017_gm_item_create,
        ls_gm_item      TYPE bapi2017_gm_item_create,
        ls_gm_code      TYPE bapi2017_gm_code,
        lv_materialdoc  TYPE bapi2017_gm_head_ret-mat_doc,
        lv_matdocyear   TYPE bapi2017_gm_head_ret-doc_year,
        lt_return       TYPE TABLE OF bapiret2,
        ls_return       TYPE bapiret2.

  " Processing variables
  DATA: lv_success_count TYPE i,
        lv_error_count   TYPE i,
        lv_total_headers TYPE i,
        lv_processed_items TYPE i,
        lv_validation_errors TYPE i,
        lv_overall_failed TYPE abap_bool.  " Track overall status

  " Validation table for unique GrGiSlipNo
  DATA: lt_processed_slips TYPE TABLE OF string.

  " Step 2: Read full deep structure
  TRY.
      io_data_provider->read_entry_data(
        IMPORTING
          es_data = ls_deep_entity
      ).
    CATCH cx_root INTO DATA(lx_read_error).
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
        EXPORTING
          textid = /iwbep/cx_mgw_tech_exception=>internal_error.
  ENDTRY.

  MESSAGE |🚀 Starting MIGO automation for: { ls_deep_entity-grgislipno }| TYPE 'I'.

  " Count total headers
  lv_total_headers = lines( ls_deep_entity-torealheaders ).
  MESSAGE |📊 Total headers to process: { lv_total_headers }| TYPE 'I'.

  " Validate main payload
  IF ls_deep_entity-grgislipno IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error
        message = 'Main GrGiSlipNo is required'.
  ENDIF.

  " Step 3: Process each real header with validation
  LOOP AT ls_deep_entity-torealheaders INTO DATA(ls_header).

    CLEAR: ls_gm_header, lt_gm_items, ls_gm_code, lt_return,
           lv_materialdoc, lv_matdocyear, lv_processed_items.

    MESSAGE |📋 Processing header { sy-tabix }: { ls_header-grgislipno }| TYPE 'I'.

    " === HEADER VALIDATIONS ===
    DATA: lv_header_valid TYPE abap_bool VALUE abap_true.

    " Validate ZtypeGm must be A007
    IF ls_header-ztypegm <> 'A007'.
      MESSAGE |❌ Header { sy-tabix }: ZtypeGm must be 'A007', received: '{ ls_header-ztypegm }'| TYPE 'E'.
      lv_validation_errors = lv_validation_errors + 1.
      lv_overall_failed = abap_true.
      lv_header_valid = abap_false.
      ls_header-grgislipno = |ERROR_ZTYPE_{ ls_header-grgislipno }|.
    ENDIF.

    " Validate ZsubType must be R10
    IF ls_header-zsubtype <> 'R10'.
      MESSAGE |❌ Header { sy-tabix }: ZsubType must be 'R10', received: '{ ls_header-zsubtype }'| TYPE 'E'.
      lv_validation_errors = lv_validation_errors + 1.
      lv_overall_failed = abap_true.
      lv_header_valid = abap_false.
      ls_header-grgislipno = |ERROR_ZSUB_{ ls_header-grgislipno }|.
    ENDIF.

    " Validate Movementtype must be 963
    IF ls_header-movementtype <> '963'.
      MESSAGE |❌ Header { sy-tabix }: Movementtype must be '963', received: '{ ls_header-movementtype }'| TYPE 'E'.
      lv_validation_errors = lv_validation_errors + 1.
      lv_overall_failed = abap_true.
      lv_header_valid = abap_false.
      ls_header-grgislipno = |ERROR_MVMT_{ ls_header-grgislipno }|.
    ENDIF.

    " Validate GrGiSlipNo uniqueness
    READ TABLE lt_processed_slips TRANSPORTING NO FIELDS WITH KEY table_line = ls_header-grgislipno.
    IF sy-subrc = 0.
      MESSAGE |❌ Header { sy-tabix }: GrGiSlipNo '{ ls_header-grgislipno }' already processed (must be unique)| TYPE 'E'.
      lv_validation_errors = lv_validation_errors + 1.
      lv_overall_failed = abap_true.
      lv_header_valid = abap_false.
      ls_header-grgislipno = |ERROR_DUP_{ ls_header-grgislipno }|.
    ELSE.
      APPEND ls_header-grgislipno TO lt_processed_slips.
    ENDIF.

    " Validate required header fields
    IF ls_header-grgislipno IS INITIAL OR
       ls_header-docdate IS INITIAL OR
       ls_header-pstngdate IS INITIAL.
      MESSAGE |❌ Header { sy-tabix }: Missing required header fields| TYPE 'E'.
      lv_validation_errors = lv_validation_errors + 1.
      lv_overall_failed = abap_true.
      lv_header_valid = abap_false.
      ls_header-grgislipno = |ERROR_HDR_{ ls_header-grgislipno }|.
    ENDIF.

    " Skip BAPI call if header validation failed, but continue processing other headers
    IF lv_header_valid = abap_false.
      MESSAGE |⚠️ Header { sy-tabix }: Skipping BAPI call due to validation errors| TYPE 'W'.
      MODIFY ls_deep_entity-torealheaders FROM ls_header INDEX sy-tabix.
      CONTINUE.
    ENDIF.

    MESSAGE |✅ Header { sy-tabix }: Business validation passed| TYPE 'S'.

    " Fill BAPI header (no date conversion needed)
    ls_gm_header-pstng_date = sy-datum.  " Use current date
    ls_gm_header-doc_date   = sy-datum.  " Use current date
    ls_gm_header-header_txt = ls_header-headertxt.
    ls_gm_header-ref_doc_no = ls_header-grgislipno.

    " Set GM Code for movement type 963 (Goods Issue for Sampling)
    ls_gm_code-gm_code = '03'.

    MESSAGE |🔧 Using GM Code 03 for movement type 963 (Goods Issue for Sampling)| TYPE 'I'.

    " Step 5: Process items with mandatory field validation
    LOOP AT ls_header-headertoitemnav INTO DATA(ls_item).

      MESSAGE |📦 Validating item { sy-tabix }: { ls_item-itemno }| TYPE 'I'.

      " === ITEM VALIDATIONS ===
      DATA: lv_item_valid TYPE abap_bool VALUE abap_true.

      " ItemOk must be true (mandatory and fixed)
      IF ls_item-itemok <> abap_true.
        MESSAGE |❌ Item { ls_item-itemno }: ItemOk must be true, received: { ls_item-itemok }| TYPE 'E'.
        lv_item_valid = abap_false.
      ENDIF.

      " Material Code - Mandatory
      IF ls_item-material IS INITIAL.
        MESSAGE |❌ Item { ls_item-itemno }: Material Code is mandatory| TYPE 'E'.
        lv_item_valid = abap_false.
      ENDIF.

      " Material Description - Mandatory
      IF ls_item-matdesc IS INITIAL.
        MESSAGE |❌ Item { ls_item-itemno }: Material Description is mandatory| TYPE 'E'.
        lv_item_valid = abap_false.
      ENDIF.

      " UOM - Mandatory
      IF ls_item-baseuom IS INITIAL.
        MESSAGE |❌ Item { ls_item-itemno }: UOM is mandatory| TYPE 'E'.
        lv_item_valid = abap_false.
      ENDIF.

      " Quantity - Mandatory
      IF ls_item-quantity IS INITIAL OR ls_item-quantity <= 0.
        MESSAGE |❌ Item { ls_item-itemno }: Quantity must be greater than 0| TYPE 'E'.
        lv_item_valid = abap_false.
      ENDIF.

      " Storage Location - Mandatory
      IF ls_item-strgloc IS INITIAL.
        MESSAGE |❌ Item { ls_item-itemno }: Storage Location is mandatory| TYPE 'E'.
        lv_item_valid = abap_false.
      ENDIF.

      " Plant - Mandatory
      IF ls_item-plant IS INITIAL.
        MESSAGE |❌ Item { ls_item-itemno }: Plant is mandatory| TYPE 'E'.
        lv_item_valid = abap_false.
      ENDIF.

      " General Ledger - Mandatory
      IF ls_item-glaccount IS INITIAL.
        MESSAGE |❌ Item { ls_item-itemno }: General Ledger Account is mandatory| TYPE 'E'.
        lv_item_valid = abap_false.
      ENDIF.

      " Cost Center - Mandatory
      IF ls_item-costcenter IS INITIAL.
        MESSAGE |❌ Item { ls_item-itemno }: Cost Center is mandatory| TYPE 'E'.
        lv_item_valid = abap_false.
      ENDIF.

      " Order No (Internal Order) - Mandatory
      IF ls_item-orderno IS INITIAL.
        MESSAGE |❌ Item { ls_item-itemno }: Order No (Internal Order) is mandatory| TYPE 'E'.
        lv_item_valid = abap_false.
      ENDIF.

      " Only add valid items to BAPI call
      IF lv_item_valid = abap_true.
        MESSAGE |✅ Item { ls_item-itemno }: All mandatory validations passed| TYPE 'S'.

        " Map validated item to BAPI structure
        CLEAR: ls_gm_item.

        ls_gm_item-material     = ls_item-material.
        ls_gm_item-plant        = ls_item-plant.
        ls_gm_item-stge_loc     = ls_item-strgloc.
        ls_gm_item-move_type    = '963'.
        ls_gm_item-entry_qnt    = ls_item-quantity.
        ls_gm_item-entry_uom    = ls_item-baseuom.
        ls_gm_item-move_mat     = ls_item-material.
        ls_gm_item-gl_account   = ls_item-glaccount.
        ls_gm_item-costcenter   = ls_item-costcenter.
        ls_gm_item-orderid      = ls_item-orderno.

        APPEND ls_gm_item TO lt_gm_items.
        lv_processed_items = lv_processed_items + 1.

        MESSAGE |✅ Item { ls_item-itemno }: { ls_item-material } added to BAPI call| TYPE 'I'.
      ELSE.
        MESSAGE |⚠️ Item { ls_item-itemno }: Skipping due to validation errors| TYPE 'W'.
        lv_overall_failed = abap_true.
      ENDIF.

    ENDLOOP.

    " Step 6: Call BAPI if we have valid items
    IF lt_gm_items IS NOT INITIAL.

      MESSAGE |🚀 Calling BAPI_GOODSMVT_CREATE with { lv_processed_items } validated items| TYPE 'I'.

      CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
        EXPORTING
          goodsmvt_header       = ls_gm_header
          goodsmvt_code         = ls_gm_code
          testrun              = ''  " Set to 'X' for test mode
        IMPORTING
          materialdocument     = lv_materialdoc
          matdocumentyear      = lv_matdocyear
        TABLES
          goodsmvt_item        = lt_gm_items
          return               = lt_return.

      " Check for errors
      READ TABLE lt_return INTO ls_return WITH KEY type = 'E'.
      IF sy-subrc = 0.
        " Error occurred - rollback
        CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
        lv_error_count = lv_error_count + 1.
        lv_overall_failed = abap_true.

        MESSAGE |❌ BAPI ERROR in header { sy-tabix }: { ls_return-message }| TYPE 'E'.

        " Log all error messages
        LOOP AT lt_return INTO ls_return WHERE type = 'E' OR type = 'A'.
          MESSAGE |  📋 BAPI Error: { ls_return-message }| TYPE 'E'.
        ENDLOOP.

        " Update response with error status
        ls_header-grgislipno = |ERROR_BAPI_{ ls_header-grgislipno }|.

      ELSE.
        " Success - commit
        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING
            wait = 'X'.

        lv_success_count = lv_success_count + 1.

        MESSAGE |🎉 SUCCESS: Material document { lv_materialdoc }/{ lv_matdocyear } created!| TYPE 'S'.

        " Update response with material document
        ls_header-grgislipno = |{ ls_header-grgislipno }_MD{ lv_materialdoc }|.

        " Log any warning messages
        LOOP AT lt_return INTO ls_return WHERE type = 'W'.
          MESSAGE |  ⚠️ Warning: { ls_return-message }| TYPE 'W'.
        ENDLOOP.

      ENDIF.

    ELSE.
      MESSAGE |❌ No valid items found for header { sy-tabix } after validation| TYPE 'E'.
      lv_error_count = lv_error_count + 1.
      lv_overall_failed = abap_true.
      ls_header-grgislipno = |NOITEMS_{ ls_header-grgislipno }|.
    ENDIF.

    " Update the header in the response structure
    MODIFY ls_deep_entity-torealheaders FROM ls_header INDEX sy-tabix.

  ENDLOOP.

  " Step 7: Set overall status
  IF lv_overall_failed = abap_true.
    ls_deep_entity-overallstatus = 'FAILED'.
    MESSAGE |🏁 OVERALL STATUS: FAILED - Some records had errors| TYPE 'W'.
  ELSE.
    ls_deep_entity-overallstatus = 'PASSED'.
    MESSAGE |🏁 OVERALL STATUS: PASSED - All records processed successfully| TYPE 'S'.
  ENDIF.

  " Step 8: Final processing summary
  MESSAGE |🏁 MIGO AUTOMATION COMPLETE:| TYPE 'S'.
  MESSAGE |  📊 Total headers: { lv_total_headers }| TYPE 'S'.
  MESSAGE |  ✅ Successful: { lv_success_count }| TYPE 'S'.
  MESSAGE |  ❌ BAPI Errors: { lv_error_count }| TYPE 'S'.
  MESSAGE |  📋 Validation Errors: { lv_validation_errors }| TYPE 'S'.
  MESSAGE |  🎯 Overall Status: { ls_deep_entity-overallstatus }| TYPE 'S'.

  " Step 9: Return the updated structure
  copy_data_to_ref(
    EXPORTING
      is_data = ls_deep_entity
    CHANGING
      cr_data = er_deep_entity
  ).

ENDMETHOD.