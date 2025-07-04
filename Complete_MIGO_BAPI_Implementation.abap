METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  " Step 1: Define the structure matching the deep entity (your working structure)
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
        lv_processed_items TYPE i.

  " Step 2: Read full deep structure
  io_data_provider->read_entry_data(
    IMPORTING
      es_data = ls_deep_entity
  ).

  MESSAGE |Starting MIGO creation for { ls_deep_entity-grgislipno }| TYPE 'I'.

  " Count total headers
  lv_total_headers = lines( ls_deep_entity-torealheaders ).
  MESSAGE |Total headers to process: { lv_total_headers }| TYPE 'I'.

  " Step 3: Process each real header
  LOOP AT ls_deep_entity-torealheaders INTO DATA(ls_header).
    
    CLEAR: ls_gm_header, lt_gm_items, ls_gm_code, lt_return,
           lv_materialdoc, lv_matdocyear, lv_processed_items.

    MESSAGE |Processing header { sy-tabix }: { ls_header-grgislipno }, Movement Type: { ls_header-movementtype }| TYPE 'I'.

    " Step 4: Map header data to BAPI structure
    " Convert OData dates to SAP dates
    DATA: lv_doc_date  TYPE sy-datum,
          lv_post_date TYPE sy-datum.

    " Handle date conversion (OData format: 2025-06-16T18:40:00)
    IF ls_header-docdate IS NOT INITIAL.
      CALL FUNCTION 'CONVERT_DATE_TO_INTERNAL'
        EXPORTING
          date_external = ls_header-docdate+0(10)  " Extract YYYY-MM-DD part
        IMPORTING
          date_internal = lv_doc_date
        EXCEPTIONS
          OTHERS = 1.
      IF sy-subrc <> 0.
        lv_doc_date = sy-datum.
      ENDIF.
    ELSE.
      lv_doc_date = sy-datum.
    ENDIF.

    IF ls_header-pstngdate IS NOT INITIAL.
      CALL FUNCTION 'CONVERT_DATE_TO_INTERNAL'
        EXPORTING
          date_external = ls_header-pstngdate+0(10)  " Extract YYYY-MM-DD part
        IMPORTING
          date_internal = lv_post_date
        EXCEPTIONS
          OTHERS = 1.
      IF sy-subrc <> 0.
        lv_post_date = sy-datum.
      ENDIF.
    ELSE.
      lv_post_date = sy-datum.
    ENDIF.

    " Fill BAPI header
    ls_gm_header-pstng_date = lv_post_date.
    ls_gm_header-doc_date   = lv_doc_date.
    ls_gm_header-header_txt = ls_header-headertxt.
    ls_gm_header-ref_doc_no = ls_header-grgislipno.

    " Determine GM Code based on movement type
    CASE ls_header-movementtype.
      WHEN '101' OR '103' OR '121' OR '122' OR '161' OR '501' OR '511' OR '541' OR '561'.
        " Goods Receipt movements
        ls_gm_code-gm_code = '01'.
      WHEN '201' OR '202' OR '221' OR '222' OR '261' OR '262' OR '281' OR '282' OR 
           '301' OR '302' OR '311' OR '312' OR '313' OR '411' OR '412' OR '413' OR '414' OR
           '551' OR '552' OR '553' OR '554' OR '555' OR '556' OR '601' OR '602' OR '641' OR '642' OR
           '701' OR '702' OR '711' OR '712' OR '713' OR '714' OR '801' OR '802' OR '961' OR '962' OR
           '963' OR '964'.
        " Goods Issue movements  
        ls_gm_code-gm_code = '03'.
      WHEN '305' OR '306' OR '315' OR '316' OR '317' OR '318' OR '321' OR '322' OR '325' OR '326'.
        " Transfer posting
        ls_gm_code-gm_code = '04'.
      WHEN OTHERS.
        " Default to goods issue
        ls_gm_code-gm_code = '03'.
    ENDCASE.

    MESSAGE |Using GM Code: { ls_gm_code-gm_code } for movement type { ls_header-movementtype }| TYPE 'I'.

    " Step 5: Process items for this header
    LOOP AT ls_header-headertoitemnav INTO DATA(ls_item).

      " Skip if ItemOk is false
      IF ls_item-itemok = abap_false.
        MESSAGE |Skipping item { ls_item-itemno } (ItemOk = false)| TYPE 'W'.
        CONTINUE.
      ENDIF.

      " Validate required item fields
      IF ls_item-material IS INITIAL OR 
         ls_item-plant IS INITIAL OR 
         ls_item-quantity IS INITIAL OR 
         ls_item-baseuom IS INITIAL.
        MESSAGE |Error: Missing required fields in item { ls_item-itemno }| TYPE 'E'.
        CONTINUE.
      ENDIF.

      CLEAR: ls_gm_item.

      " Map item data to BAPI structure
      ls_gm_item-material     = ls_item-material.
      ls_gm_item-plant        = ls_item-plant.
      ls_gm_item-stge_loc     = ls_item-strgloc.
      ls_gm_item-move_type    = ls_header-movementtype.
      ls_gm_item-entry_qnt    = ls_item-quantity.
      ls_gm_item-entry_uom    = ls_item-baseuom.
      ls_gm_item-move_mat     = ls_item-material.

      " Optional fields
      IF ls_item-glaccount IS NOT INITIAL.
        ls_gm_item-gl_account = ls_item-glaccount.
      ENDIF.
      IF ls_item-costcenter IS NOT INITIAL.
        ls_gm_item-costcenter = ls_item-costcenter.
      ENDIF.
      IF ls_item-orderno IS NOT INITIAL.
        ls_gm_item-orderid = ls_item-orderno.
      ENDIF.

      " Add specific fields based on movement type
      CASE ls_header-movementtype.
        WHEN '201' OR '202' OR '261' OR '262'.
          " Cost center required for these movement types
          IF ls_item-costcenter IS INITIAL.
            MESSAGE |Warning: Cost center missing for movement type { ls_header-movementtype }| TYPE 'W'.
          ENDIF.
        WHEN '301' OR '302' OR '311' OR '312'.
          " Transfer postings might need receiving plant/storage location
          " Add logic as needed
      ENDCASE.

      APPEND ls_gm_item TO lt_gm_items.
      lv_processed_items = lv_processed_items + 1.

      MESSAGE |Added item { ls_item-itemno }: { ls_item-material }, Qty: { ls_item-quantity } { ls_item-baseuom }| TYPE 'I'.

    ENDLOOP.

    " Step 6: Call BAPI if we have valid items
    IF lt_gm_items IS NOT INITIAL.

      MESSAGE |Calling BAPI_GOODSMVT_CREATE with { lv_processed_items } items| TYPE 'I'.

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

        MESSAGE |❌ ERROR in header { sy-tabix }: { ls_return-message }| TYPE 'E'.

        " Log all error messages
        LOOP AT lt_return INTO ls_return WHERE type = 'E' OR type = 'A'.
          MESSAGE |  Error detail: { ls_return-message }| TYPE 'E'.
        ENDLOOP.

        " Update response with error status
        ls_header-grgislipno = |ERROR_{ ls_header-grgislipno }|.

      ELSE.
        " Success - commit
        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING
            wait = 'X'.

        lv_success_count = lv_success_count + 1.

        MESSAGE |✅ SUCCESS: Material document { lv_materialdoc }/{ lv_matdocyear } created for header { sy-tabix }| TYPE 'S'.

        " Update response with material document
        ls_header-grgislipno = |{ ls_header-grgislipno }_MD{ lv_materialdoc }|.

        " Log any warning messages
        LOOP AT lt_return INTO ls_return WHERE type = 'W'.
          MESSAGE |  Warning: { ls_return-message }| TYPE 'W'.
        ENDLOOP.

      ENDIF.

    ELSE.
      MESSAGE |❌ No valid items found for header { sy-tabix }| TYPE 'E'.
      lv_error_count = lv_error_count + 1.
      ls_header-grgislipno = |NOITEMS_{ ls_header-grgislipno }|.
    ENDIF.

    " Update the header in the response structure
    MODIFY ls_deep_entity-torealheaders FROM ls_header INDEX sy-tabix.

  ENDLOOP.

  " Step 7: Final processing summary
  MESSAGE |🎯 PROCESSING COMPLETE:| TYPE 'S'.
  MESSAGE |  Total headers: { lv_total_headers }| TYPE 'S'.
  MESSAGE |  Successful: { lv_success_count }| TYPE 'S'.
  MESSAGE |  Errors: { lv_error_count }| TYPE 'S'.

  " Step 8: Return the updated structure back
  copy_data_to_ref(
    EXPORTING
      is_data = ls_deep_entity
    CHANGING
      cr_data = er_deep_entity
  ).

ENDMETHOD.