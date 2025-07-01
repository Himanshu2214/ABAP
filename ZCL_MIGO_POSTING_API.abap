CLASS zcl_migo_posting_api DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_migo_header,
             ztypegm         TYPE string,
             zsubtype        TYPE string,
             movementtype    TYPE string,
             docdate         TYPE string,
             pstngdate       TYPE string,
             grgiSlipno      TYPE string,
             headertxt       TYPE string,
             headertoitemnav TYPE TABLE OF REF TO data,
           END OF ty_migo_header.

    TYPES: BEGIN OF ty_migo_item,
             material  TYPE string,
             plant     TYPE string,
             stgeloc   TYPE string,
             entryqnt  TYPE string,
             entryuom  TYPE string,
           END OF ty_migo_item.

    TYPES: BEGIN OF ty_response,
             success         TYPE abap_bool,
             material_document TYPE mblnr,
             message         TYPE string,
             errors          TYPE TABLE OF string,
           END OF ty_response.

    TYPES: tt_migo_header TYPE TABLE OF ty_migo_header,
           tt_migo_item   TYPE TABLE OF ty_migo_item,
           tt_response    TYPE TABLE OF ty_response.

    METHODS: post_migo
      IMPORTING
        iv_payload TYPE string
      RETURNING
        VALUE(rv_response) TYPE string.

  PRIVATE SECTION.
    METHODS: convert_date
      IMPORTING
        iv_date_string TYPE string
      RETURNING
        VALUE(rv_date) TYPE dats,

      process_single_migo
        IMPORTING
          is_header TYPE ty_migo_header
        RETURNING
          VALUE(rs_response) TYPE ty_response,

      call_bapi_movement_create
        IMPORTING
          is_header TYPE ty_migo_header
          it_items  TYPE tt_migo_item
        RETURNING
          VALUE(rs_response) TYPE ty_response.

ENDCLASS.

CLASS zcl_migo_posting_api IMPLEMENTATION.

  METHOD post_migo.
    DATA: lo_reader     TYPE REF TO cl_sxml_string_reader,
          lo_writer     TYPE REF TO cl_sxml_string_writer,
          lt_headers    TYPE tt_migo_header,
          lt_responses  TYPE tt_response,
          ls_response   TYPE ty_response.

    TRY.
        " Deserialize JSON payload
        /ui2/cl_json=>deserialize(
          EXPORTING
            json = iv_payload
            pretty_name = /ui2/cl_json=>pretty_mode-camel_case
          CHANGING
            data = lt_headers
        ).

        " Process each MIGO header
        LOOP AT lt_headers INTO DATA(ls_header).
          ls_response = process_single_migo( ls_header ).
          APPEND ls_response TO lt_responses.
        ENDLOOP.

        " Serialize response to JSON
        rv_response = /ui2/cl_json=>serialize(
          data = lt_responses
          pretty_name = /ui2/cl_json=>pretty_mode-camel_case
        ).

      CATCH cx_sy_conversion_no_number
            cx_sy_move_cast_error
            /ui2/cx_json INTO DATA(lx_error).
        
        ls_response-success = abap_false.
        ls_response-message = |JSON processing error: { lx_error->get_text( ) }|.
        APPEND ls_response TO lt_responses.
        
        rv_response = /ui2/cl_json=>serialize(
          data = lt_responses
          pretty_name = /ui2/cl_json=>pretty_mode-camel_case
        ).
    ENDTRY.

  ENDMETHOD.

  METHOD process_single_migo.
    DATA: lt_items TYPE tt_migo_item,
          ls_item  TYPE ty_migo_item.

    " For simplified processing, assume items are passed in a different way
    " This would need to be adjusted based on actual JSON structure
    " For now, create a sample item structure
    CLEAR lt_items.
    
    " This is a placeholder - in real implementation, you would 
    " properly deserialize the HeaderToItemNav structure
    " For demo purposes, we'll create empty items table
    
    " Call BAPI to create movement  
    rs_response = call_bapi_movement_create(
      is_header = is_header
      it_items = lt_items
    ).

  ENDMETHOD.

  METHOD call_bapi_movement_create.
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
    ls_goodsmvt_header-pstng_date = convert_date( is_header-pstngdate ).
    ls_goodsmvt_header-doc_date = convert_date( is_header-docdate ).
    ls_goodsmvt_header-header_txt = is_header-headertxt.
    ls_goodsmvt_header-ref_doc_no = is_header-grgiSlipno.

    " Set movement code (based on movement type)
    CASE is_header-movementtype.
      WHEN '963'.
        ls_goodsmvt_code-gm_code = '04'. " Goods issue
      WHEN '261'.
        ls_goodsmvt_code-gm_code = '03'. " Goods issue for production order
      WHEN '101'.
        ls_goodsmvt_code-gm_code = '01'. " Goods receipt
      WHEN OTHERS.
        ls_goodsmvt_code-gm_code = '04'. " Default to goods issue
    ENDCASE.

    " Fill item data
    LOOP AT it_items INTO DATA(ls_item).
      CLEAR ls_goodsmvt_item.
      ls_goodsmvt_item-material = |{ ls_item-material ALPHA = IN }|.
      ls_goodsmvt_item-plant = ls_item-plant.
      ls_goodsmvt_item-stge_loc = ls_item-stgeloc.
      ls_goodsmvt_item-move_type = is_header-movementtype.
      ls_goodsmvt_item-entry_qnt = ls_item-entryqnt.
      ls_goodsmvt_item-entry_uom = ls_item-entryuom.
      APPEND ls_goodsmvt_item TO lt_goodsmvt_item.
    ENDLOOP.

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
      " Success - commit the transaction
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait = 'X'.
      
      rs_response-success = abap_true.
      rs_response-material_document = lv_materialdocument.
      rs_response-message = |Material Document { lv_materialdocument } created successfully|.
    ENDIF.

  ENDMETHOD.

  METHOD convert_date.
    DATA: lv_timestamp TYPE string,
          lv_date_only TYPE string,
          lv_year      TYPE string,
          lv_month     TYPE string,
          lv_day       TYPE string.

    " Extract timestamp from /Date(timestamp)/ format
    IF iv_date_string CS '/Date(' AND iv_date_string CS ')/' .
      FIND REGEX '/Date\((\d+)\)/' IN iv_date_string SUBMATCHES lv_timestamp.
      
      " Convert timestamp (milliseconds) to date
      DATA: lv_timestamp_sec TYPE i,
            lv_date_internal TYPE d.
      
      lv_timestamp_sec = lv_timestamp / 1000.
      
      " Convert Unix timestamp to ABAP date
      CALL FUNCTION 'CONVERT_DATE_TO_EXTERNAL'
        EXPORTING
          date_internal = lv_date_internal
        IMPORTING
          date_external = lv_date_only.
      
      " For simplicity, using current date if conversion fails
      " In production, implement proper timestamp conversion
      rv_date = sy-datum.
    ELSE.
      rv_date = sy-datum.
    ENDIF.

  ENDMETHOD.

ENDCLASS.