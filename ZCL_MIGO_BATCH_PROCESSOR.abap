CLASS zcl_migo_batch_processor DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_migo_item,
             material  TYPE string,
             plant     TYPE string,
             stgeloc   TYPE string,
             entryqnt  TYPE string,
             entryuom  TYPE string,
           END OF ty_migo_item.

    TYPES: tt_migo_item TYPE STANDARD TABLE OF ty_migo_item WITH NON-UNIQUE DEFAULT KEY.

    TYPES: BEGIN OF ty_migo_header,
             ztypegm         TYPE string,
             zsubtype        TYPE string,
             movementtype    TYPE string,
             docdate         TYPE string,
             pstngdate       TYPE string,
             grgiSlipno      TYPE string,
             headertxt       TYPE string,
             headertoitemnav TYPE tt_migo_item,
           END OF ty_migo_header.

    TYPES: BEGIN OF ty_response,
             success           TYPE abap_bool,
             material_document TYPE string,
             message           TYPE string,
             grgiSlipno        TYPE string,
             processing_time   TYPE string,
             item_count        TYPE i,
             errors            TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY,
           END OF ty_response.

    TYPES: BEGIN OF ty_batch_summary,
             total_records     TYPE i,
             successful_count  TYPE i,
             failed_count      TYPE i,
             total_items       TYPE i,
             processing_time   TYPE string,
             start_time        TYPE timestampl,
             end_time          TYPE timestampl,
           END OF ty_batch_summary.

    TYPES: BEGIN OF ty_batch_response,
             batch_summary TYPE ty_batch_summary,
             responses     TYPE STANDARD TABLE OF ty_response WITH NON-UNIQUE DEFAULT KEY,
           END OF ty_batch_response.

    TYPES: tt_migo_header TYPE STANDARD TABLE OF ty_migo_header WITH NON-UNIQUE DEFAULT KEY.

    CONSTANTS: c_max_batch_size TYPE i VALUE 100.

    METHODS: post_migo_batch
      IMPORTING
        iv_payload TYPE string
        iv_batch_size TYPE i DEFAULT 10
      RETURNING
        VALUE(rv_response) TYPE string,

      validate_payload_size
        IMPORTING
          iv_payload TYPE string
        RETURNING
          VALUE(rv_valid) TYPE abap_bool.

  PRIVATE SECTION.
    METHODS: convert_odata_date
      IMPORTING
        iv_date_string TYPE string
      RETURNING
        VALUE(rv_date) TYPE dats,

      process_batch_chunk
        IMPORTING
          it_headers TYPE tt_migo_header
          iv_start_index TYPE i
          iv_end_index TYPE i
        RETURNING
          VALUE(rt_responses) TYPE TABLE,

      process_single_migo
        IMPORTING
          is_header TYPE ty_migo_header
        RETURNING
          VALUE(rs_response) TYPE ty_response,

      call_bapi_goodsmvt_create
        IMPORTING
          is_header TYPE ty_migo_header
        RETURNING
          VALUE(rs_response) TYPE ty_response,

      validate_header_data
        IMPORTING
          is_header TYPE ty_migo_header
        RETURNING
          VALUE(rt_errors) TYPE TABLE,

      log_processing_info
        IMPORTING
          iv_message TYPE string
          iv_severity TYPE string DEFAULT 'I'.

ENDCLASS.

CLASS zcl_migo_batch_processor IMPLEMENTATION.

  METHOD post_migo_batch.
    DATA: lt_headers      TYPE tt_migo_header,
          ls_batch_response TYPE ty_batch_response,
          lv_start_time   TYPE timestampl,
          lv_end_time     TYPE timestampl,
          lv_total_items  TYPE i,
          lv_batch_size   TYPE i.

    GET TIME STAMP FIELD lv_start_time.

    " Validate payload size first
    IF validate_payload_size( iv_payload ) = abap_false.
      ls_batch_response-batch_summary-total_records = 0.
      ls_batch_response-batch_summary-failed_count = 1.
      
      DATA(ls_error_response) = VALUE ty_response(
        success = abap_false
        message = 'Payload too large or invalid format'
        grgiSlipno = 'BATCH_ERROR'
      ).
      APPEND ls_error_response TO ls_batch_response-responses.
      
      rv_response = /ui2/cl_json=>serialize(
        data = ls_batch_response
        pretty_name = /ui2/cl_json=>pretty_mode-camel_case
      ).
      RETURN.
    ENDIF.

    " Set batch size with maximum limit
    lv_batch_size = COND #( WHEN iv_batch_size > c_max_batch_size 
                           THEN c_max_batch_size 
                           ELSE iv_batch_size ).

    TRY.
        " Deserialize JSON payload
        /ui2/cl_json=>deserialize(
          EXPORTING
            json = iv_payload
            pretty_name = /ui2/cl_json=>pretty_mode-camel_case
          CHANGING
            data = lt_headers
        ).

        " Calculate total items for monitoring
        LOOP AT lt_headers INTO DATA(ls_header).
          lv_total_items = lv_total_items + lines( ls_header-headertoitemnav ).
        ENDLOOP.

        " Initialize batch summary
        ls_batch_response-batch_summary-total_records = lines( lt_headers ).
        ls_batch_response-batch_summary-total_items = lv_total_items.
        ls_batch_response-batch_summary-start_time = lv_start_time.

        " Log start of batch processing
        log_processing_info( 
          iv_message = |Starting batch processing of { lines( lt_headers ) } records with { lv_total_items } total items|
        ).

        " Process in chunks to manage memory and performance
        DATA: lv_start_index TYPE i VALUE 1,
              lv_end_index   TYPE i,
              lt_chunk_responses TYPE TABLE OF ty_response.

        WHILE lv_start_index <= lines( lt_headers ).
          lv_end_index = lv_start_index + lv_batch_size - 1.
          IF lv_end_index > lines( lt_headers ).
            lv_end_index = lines( lt_headers ).
          ENDIF.

          " Process chunk
          lt_chunk_responses = process_batch_chunk(
            it_headers = lt_headers
            iv_start_index = lv_start_index
            iv_end_index = lv_end_index
          ).

          " Append chunk responses to main response
          APPEND LINES OF lt_chunk_responses TO ls_batch_response-responses.

          " Log chunk completion
          log_processing_info(
            iv_message = |Processed chunk { lv_start_index } to { lv_end_index }|
          ).

          lv_start_index = lv_end_index + 1.

          " Commit after each chunk to avoid long-running transactions
          COMMIT WORK.
        ENDWHILE.

        " Calculate summary statistics
        LOOP AT ls_batch_response-responses INTO DATA(ls_response).
          IF ls_response-success = abap_true.
            ls_batch_response-batch_summary-successful_count = 
              ls_batch_response-batch_summary-successful_count + 1.
          ELSE.
            ls_batch_response-batch_summary-failed_count = 
              ls_batch_response-batch_summary-failed_count + 1.
          ENDIF.
        ENDLOOP.

        GET TIME STAMP FIELD lv_end_time.
        ls_batch_response-batch_summary-end_time = lv_end_time.
        
        " Calculate processing time
        DATA: lv_duration TYPE p DECIMALS 3.
        lv_duration = lv_end_time - lv_start_time.
        ls_batch_response-batch_summary-processing_time = |{ lv_duration } seconds|.

        " Log completion
        log_processing_info(
          iv_message = |Batch processing completed. Success: { ls_batch_response-batch_summary-successful_count }, Failed: { ls_batch_response-batch_summary-failed_count }|
        ).

        " Serialize response to JSON
        rv_response = /ui2/cl_json=>serialize(
          data = ls_batch_response
          pretty_name = /ui2/cl_json=>pretty_mode-camel_case
        ).

      CATCH cx_sy_conversion_no_number
            cx_sy_move_cast_error INTO DATA(lx_error).
        
        " Handle JSON processing errors
        ls_batch_response-batch_summary-failed_count = 1.
        ls_error_response = VALUE ty_response(
          success = abap_false
          message = |JSON processing error: { lx_error->get_text( ) }|
          grgiSlipno = 'JSON_ERROR'
        ).
        APPEND ls_error_response TO ls_batch_response-responses.
        
        rv_response = /ui2/cl_json=>serialize(
          data = ls_batch_response
          pretty_name = /ui2/cl_json=>pretty_mode-camel_case
        ).

      CATCH cx_root INTO DATA(lx_general).
        " Handle any other errors
        ls_batch_response-batch_summary-failed_count = 1.
        ls_error_response = VALUE ty_response(
          success = abap_false
          message = |General processing error: { lx_general->get_text( ) }|
          grgiSlipno = 'GENERAL_ERROR'
        ).
        APPEND ls_error_response TO ls_batch_response-responses.
        
        rv_response = /ui2/cl_json=>serialize(
          data = ls_batch_response
          pretty_name = /ui2/cl_json=>pretty_mode-camel_case
        ).
    ENDTRY.

  ENDMETHOD.

  METHOD validate_payload_size.
    DATA: lv_payload_length TYPE i.
    
    lv_payload_length = strlen( iv_payload ).
    
    " Check if payload is too large (e.g., > 50MB)
    IF lv_payload_length > 52428800. " 50MB in bytes
      rv_valid = abap_false.
      RETURN.
    ENDIF.

    " Basic JSON structure validation
    IF iv_payload(1) <> '[' OR iv_payload+lv_payload_length-1(1) <> ']'.
      rv_valid = abap_false.
      RETURN.
    ENDIF.

    rv_valid = abap_true.
  ENDMETHOD.

  METHOD process_batch_chunk.
    DATA: lv_start_time TYPE timestampl,
          lv_end_time   TYPE timestampl,
          ls_response   TYPE ty_response.

    GET TIME STAMP FIELD lv_start_time.

    " Process headers in the specified range
    DO.
      DATA(lv_index) = sy-index + iv_start_index - 1.
      IF lv_index > iv_end_index.
        EXIT.
      ENDIF.

      READ TABLE it_headers INTO DATA(ls_header) INDEX lv_index.
      IF sy-subrc = 0.
        ls_response = process_single_migo( ls_header ).
        
        " Add processing time for individual record
        GET TIME STAMP FIELD lv_end_time.
        DATA: lv_duration TYPE p DECIMALS 3.
        lv_duration = lv_end_time - lv_start_time.
        ls_response-processing_time = |{ lv_duration } sec|.
        ls_response-item_count = lines( ls_header-headertoitemnav ).
        
        APPEND ls_response TO rt_responses.
        GET TIME STAMP FIELD lv_start_time. " Reset for next iteration
      ENDIF.
    ENDDO.

  ENDMETHOD.

  METHOD process_single_migo.
    DATA: lt_validation_errors TYPE TABLE OF string.

    " Validate header data first
    lt_validation_errors = validate_header_data( is_header ).
    
    IF lines( lt_validation_errors ) > 0.
      rs_response-success = abap_false.
      rs_response-message = 'Validation failed'.
      rs_response-grgiSlipno = is_header-grgiSlipno.
      rs_response-errors = lt_validation_errors.
      RETURN.
    ENDIF.

    " Call BAPI to create movement
    rs_response = call_bapi_goodsmvt_create( is_header ).
    rs_response-grgiSlipno = is_header-grgiSlipno.
    rs_response-item_count = lines( is_header-headertoitemnav ).
  ENDMETHOD.

  METHOD validate_header_data.
    " Validate required fields
    IF is_header-movementtype IS INITIAL.
      APPEND 'Movement type is required' TO rt_errors.
    ENDIF.

    IF is_header-grgiSlipno IS INITIAL.
      APPEND 'GR/GI slip number is required' TO rt_errors.
    ENDIF.

    IF lines( is_header-headertoitemnav ) = 0.
      APPEND 'At least one item is required' TO rt_errors.
    ENDIF.

    " Validate items
    LOOP AT is_header-headertoitemnav INTO DATA(ls_item).
      IF ls_item-material IS INITIAL.
        APPEND |Item { sy-tabix }: Material is required| TO rt_errors.
      ENDIF.

      IF ls_item-plant IS INITIAL.
        APPEND |Item { sy-tabix }: Plant is required| TO rt_errors.
      ENDIF.

      IF ls_item-entryqnt IS INITIAL OR ls_item-entryqnt = '0'.
        APPEND |Item { sy-tabix }: Quantity must be greater than 0| TO rt_errors.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD call_bapi_goodsmvt_create.
    DATA: ls_goodsmvt_header  TYPE bapi2017_gm_head_01,
          ls_goodsmvt_code    TYPE bapi2017_gm_code,
          lt_goodsmvt_item    TYPE TABLE OF bapi2017_gm_item_create,
          ls_goodsmvt_item    TYPE bapi2017_gm_item_create,
          lt_return           TYPE TABLE OF bapiret2,
          ls_goodsmvt_headret TYPE bapi2017_gm_head_ret,
          lv_materialdocument TYPE bapi2017_gm_head_ret-mat_doc,
          lv_matdocumentyear  TYPE bapi2017_gm_head_ret-doc_year.

    " Initialize response
    rs_response-success = abap_false.

    " Fill header data
    ls_goodsmvt_header-pstng_date = convert_odata_date( is_header-pstngdate ).
    ls_goodsmvt_header-doc_date = convert_odata_date( is_header-docdate ).
    ls_goodsmvt_header-header_txt = is_header-headertxt.
    ls_goodsmvt_header-ref_doc_no = is_header-grgiSlipno.

    " Set movement code based on movement type
    CASE is_header-movementtype.
      WHEN '963'.
        ls_goodsmvt_code-gm_code = '04'. " Goods issue
      WHEN '261'.
        ls_goodsmvt_code-gm_code = '03'. " Goods issue for production order
      WHEN '101'.
        ls_goodsmvt_code-gm_code = '01'. " Goods receipt
      WHEN '201'.
        ls_goodsmvt_code-gm_code = '03'. " Goods issue for cost center
      WHEN OTHERS.
        ls_goodsmvt_code-gm_code = '04'. " Default to goods issue
    ENDCASE.

    " Fill item data
    LOOP AT is_header-headertoitemnav INTO DATA(ls_item).
      CLEAR ls_goodsmvt_item.
      
      " Format material number with leading zeros
      ls_goodsmvt_item-material = |{ ls_item-material ALPHA = IN }|.
      ls_goodsmvt_item-plant = ls_item-plant.
      ls_goodsmvt_item-stge_loc = ls_item-stgeloc.
      ls_goodsmvt_item-move_type = is_header-movementtype.
      
      " Convert quantity to numeric
      TRY.
          ls_goodsmvt_item-entry_qnt = ls_item-entryqnt.
        CATCH cx_sy_conversion_no_number.
          APPEND |Invalid quantity format for material { ls_item-material }| TO rs_response-errors.
          CONTINUE.
      ENDTRY.
      
      ls_goodsmvt_item-entry_uom = ls_item-entryuom.
      APPEND ls_goodsmvt_item TO lt_goodsmvt_item.
    ENDLOOP.

    " Validate that we have items to process
    IF lines( lt_goodsmvt_item ) = 0.
      rs_response-success = abap_false.
      rs_response-message = 'No valid items found for processing'.
      RETURN.
    ENDIF.

    " Call BAPI
    CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
      EXPORTING
        goodsmvt_header  = ls_goodsmvt_header
        goodsmvt_code    = ls_goodsmvt_code
      IMPORTING
        goodsmvt_headret = ls_goodsmvt_headret
        materialdocument = lv_materialdocument
        matdocumentyear  = lv_matdocumentyear
      TABLES
        goodsmvt_item    = lt_goodsmvt_item
        return           = lt_return.

    " Check results
    READ TABLE lt_return INTO DATA(ls_return) WITH KEY type = 'E'.
    IF sy-subrc = 0.
      " Error occurred
      rs_response-success = abap_false.
      rs_response-message = ls_return-message.
      LOOP AT lt_return INTO ls_return WHERE type = 'E'.
        APPEND ls_return-message TO rs_response-errors.
      ENDLOOP.
    ELSE.
      " Success
      rs_response-success = abap_true.
      rs_response-material_document = lv_materialdocument.
      rs_response-message = |Material Document { lv_materialdocument } created successfully for { is_header-grgiSlipno }|.
    ENDIF.

  ENDMETHOD.

  METHOD convert_odata_date.
    DATA: lv_timestamp_str TYPE string,
          lv_timestamp_ms  TYPE int8,
          lv_timestamp_sec TYPE int8.

    " Handle OData date format: /Date(1750099200000)/
    IF iv_date_string CS '/Date(' AND iv_date_string CS ')/' .
      FIND REGEX '/Date\((\d+)\)/' IN iv_date_string SUBMATCHES lv_timestamp_str.
      
      IF sy-subrc = 0.
        TRY.
            lv_timestamp_ms = lv_timestamp_str.
            lv_timestamp_sec = lv_timestamp_ms / 1000.
            
            DATA: lv_days_since_epoch TYPE i.
            lv_days_since_epoch = lv_timestamp_sec / 86400.
            
            rv_date = '19700101'.
            rv_date = rv_date + lv_days_since_epoch.
            
          CATCH cx_sy_conversion_no_number cx_sy_arithmetic_overflow.
            rv_date = sy-datum.
        ENDTRY.
      ELSE.
        rv_date = sy-datum.
      ENDIF.
    ELSE.
      rv_date = sy-datum.
    ENDIF.

  ENDMETHOD.

  METHOD log_processing_info.
    " Write to application log or system log
    " This is a placeholder - implement actual logging as needed
    MESSAGE iv_message TYPE iv_severity.
  ENDMETHOD.

ENDCLASS.