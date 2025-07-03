CLASS zcl_migo_posting_enhanced DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Types for the exact payload structure
    TYPES: BEGIN OF ty_goods_mvt_item,
             material    TYPE string,
             itemno      TYPE string,
             matdesc     TYPE string,
             baseuom     TYPE string,
             quantity    TYPE string,
             strgloc     TYPE string,
             plant       TYPE string,
             glaccount   TYPE string,
             costcenter  TYPE string,
             orderno     TYPE string,
             itemok      TYPE abap_bool,
           END OF ty_goods_mvt_item.

    TYPES: tt_goods_mvt_item TYPE STANDARD TABLE OF ty_goods_mvt_item WITH NON-UNIQUE DEFAULT KEY.

    TYPES: BEGIN OF ty_migo_request,
             ztypegm          TYPE string,
             zsubtype         TYPE string,
             movementtype     TYPE string,
             docdate          TYPE string,
             pstngdate        TYPE string,
             grgiSlipno       TYPE string,
             headertxt        TYPE string,
             goodsmvtitemset  TYPE tt_goods_mvt_item,
           END OF ty_migo_request.

    TYPES: tt_migo_request TYPE STANDARD TABLE OF ty_migo_request WITH NON-UNIQUE DEFAULT KEY.

    TYPES: BEGIN OF ty_migo_response,
             success           TYPE abap_bool,
             migo_number       TYPE string,
             gigrnum           TYPE string,
             material_document TYPE string,
             document_year     TYPE string,
             message           TYPE string,
             error_details     TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY,
           END OF ty_migo_response.

    TYPES: tt_migo_response TYPE STANDARD TABLE OF ty_migo_response WITH NON-UNIQUE DEFAULT KEY.

    " Main method to process MIGO posting
    METHODS: process_migo_posting
      IMPORTING
        iv_payload TYPE string
      RETURNING
        VALUE(rv_response) TYPE string.

  PRIVATE SECTION.
    METHODS: convert_odata_date
      IMPORTING
        iv_date_string TYPE string
      RETURNING
        VALUE(rv_date) TYPE dats,

      process_single_migo
        IMPORTING
          is_request TYPE ty_migo_request
        RETURNING
          VALUE(rs_response) TYPE ty_migo_response,

      call_bapi_goodsmvt_create
        IMPORTING
          is_request TYPE ty_migo_request
        RETURNING
          VALUE(rs_response) TYPE ty_migo_response,

      format_material_number
        IMPORTING
          iv_material TYPE string
        RETURNING
          VALUE(rv_material) TYPE matnr,

      get_movement_code
        IMPORTING
          iv_movement_type TYPE string
        RETURNING
          VALUE(rv_gm_code) TYPE bapi2017_gm_code-gm_code.

ENDCLASS.

CLASS zcl_migo_posting_enhanced IMPLEMENTATION.

  METHOD process_migo_posting.
    DATA: lt_requests  TYPE tt_migo_request,
          lt_responses TYPE tt_migo_response,
          ls_response  TYPE ty_migo_response,
          lt_single_request TYPE TABLE OF ty_migo_request.

    TRY.
        " Try to deserialize as array first
        /ui2/cl_json=>deserialize(
          EXPORTING
            json = iv_payload
            pretty_name = /ui2/cl_json=>pretty_mode-camel_case
          CHANGING
            data = lt_requests
        ).

        " If array is empty, try single object
        IF lines( lt_requests ) = 0.
          DATA: ls_single_request TYPE ty_migo_request.
          
          /ui2/cl_json=>deserialize(
            EXPORTING
              json = iv_payload
              pretty_name = /ui2/cl_json=>pretty_mode-camel_case
            CHANGING
              data = ls_single_request
          ).
          
          APPEND ls_single_request TO lt_requests.
        ENDIF.

        " Process each request
        LOOP AT lt_requests INTO DATA(ls_request).
          ls_response = process_single_migo( ls_request ).
          APPEND ls_response TO lt_responses.
        ENDLOOP.

        " Serialize response
        rv_response = /ui2/cl_json=>serialize(
          data = lt_responses
          pretty_name = /ui2/cl_json=>pretty_mode-camel_case
        ).

      CATCH cx_sy_conversion_no_number
            cx_sy_move_cast_error INTO DATA(lx_error).
        
        ls_response-success = abap_false.
        ls_response-message = |JSON processing error: { lx_error->get_text( ) }|.
        APPEND ls_response TO lt_responses.
        
        rv_response = /ui2/cl_json=>serialize(
          data = lt_responses
          pretty_name = /ui2/cl_json=>pretty_mode-camel_case
        ).

      CATCH cx_root INTO DATA(lx_general_error).
        ls_response-success = abap_false.
        ls_response-message = |General processing error: { lx_general_error->get_text( ) }|.
        APPEND ls_response TO lt_responses.
        
        rv_response = /ui2/cl_json=>serialize(
          data = lt_responses
          pretty_name = /ui2/cl_json=>pretty_mode-camel_case
        ).
    ENDTRY.

  ENDMETHOD.

  METHOD process_single_migo.
    " Call BAPI to create goods movement
    rs_response = call_bapi_goodsmvt_create( is_request ).
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
    CLEAR rs_response.
    rs_response-success = abap_false.

    " Validate input
    IF is_request-movementtype IS INITIAL.
      rs_response-message = 'Movement type is required'.
      RETURN.
    ENDIF.

    IF lines( is_request-goodsmvtitemset ) = 0.
      rs_response-message = 'At least one item is required'.
      RETURN.
    ENDIF.

    " Fill header data
    ls_goodsmvt_header-pstng_date = convert_odata_date( is_request-pstngdate ).
    ls_goodsmvt_header-doc_date = convert_odata_date( is_request-docdate ).
    ls_goodsmvt_header-header_txt = is_request-headertxt.
    ls_goodsmvt_header-ref_doc_no = is_request-grgiSlipno.

    " Set movement code based on movement type
    ls_goodsmvt_code-gm_code = get_movement_code( is_request-movementtype ).

    " Fill item data
    LOOP AT is_request-goodsmvtitemset INTO DATA(ls_item).
      " Skip items marked as not OK
      IF ls_item-itemok = abap_false.
        CONTINUE.
      ENDIF.

      CLEAR ls_goodsmvt_item.
      ls_goodsmvt_item-material = format_material_number( ls_item-material ).
      ls_goodsmvt_item-plant = ls_item-plant.
      ls_goodsmvt_item-stge_loc = ls_item-strgloc.
      ls_goodsmvt_item-move_type = is_request-movementtype.
      ls_goodsmvt_item-entry_qnt = ls_item-quantity.
      ls_goodsmvt_item-entry_uom = ls_item-baseuom.
      ls_goodsmvt_item-move_mat = ls_item-material.
      
      " Additional fields for specific movement types
      IF is_request-movementtype = '963'.
        ls_goodsmvt_item-gl_account = ls_item-glaccount.
        ls_goodsmvt_item-costcenter = ls_item-costcenter.
      ENDIF.
      
      IF ls_item-orderno IS NOT INITIAL.
        ls_goodsmvt_item-orderid = ls_item-orderno.
      ENDIF.

      APPEND ls_goodsmvt_item TO lt_goodsmvt_item.
    ENDLOOP.

    " Validate that we have items to process
    IF lines( lt_goodsmvt_item ) = 0.
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

    " Check for errors
    READ TABLE lt_return INTO DATA(ls_return) WITH KEY type = 'E'.
    IF sy-subrc = 0.
      " Error occurred
      rs_response-success = abap_false.
      rs_response-message = ls_return-message.
      
      " Collect all error messages
      LOOP AT lt_return INTO ls_return WHERE type = 'E'.
        APPEND ls_return-message TO rs_response-error_details.
      ENDLOOP.
      
      " Rollback
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    ELSE.
      " Success - commit the transaction
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait = 'X'.
      
      rs_response-success = abap_true.
      rs_response-migo_number = lv_materialdocument.
      rs_response-material_document = lv_materialdocument.
      rs_response-document_year = lv_matdocumentyear.
      rs_response-gigrnum = ls_goodsmvt_headret-mat_doc. " GIGRNUM typically same as material document
      rs_response-message = |Material Document { lv_materialdocument } created successfully|.
      
      " Add success messages
      LOOP AT lt_return INTO ls_return WHERE type = 'S'.
        APPEND ls_return-message TO rs_response-error_details.
      ENDLOOP.
    ENDIF.

  ENDMETHOD.

  METHOD convert_odata_date.
    DATA: lv_timestamp TYPE string,
          lv_timestamp_num TYPE int8,
          lv_timestamp_sec TYPE int8,
          lv_days_since_epoch TYPE int4,
          lv_epoch_date TYPE d VALUE '19700101'.

    " Handle /Date(timestamp)/ format
    IF iv_date_string CS '/Date(' AND iv_date_string CS ')/'.
      FIND REGEX '/Date\((\d+)\)/' IN iv_date_string SUBMATCHES lv_timestamp.
      
      IF lv_timestamp IS NOT INITIAL.
        " Convert timestamp (milliseconds) to seconds
        lv_timestamp_num = lv_timestamp.
        lv_timestamp_sec = lv_timestamp_num / 1000.
        
        " Convert to days since epoch
        lv_days_since_epoch = lv_timestamp_sec / 86400.
        
        " Add days to epoch date
        rv_date = lv_epoch_date + lv_days_since_epoch.
      ELSE.
        rv_date = sy-datum.
      ENDIF.
    ELSE.
      " Fallback to current date
      rv_date = sy-datum.
    ENDIF.

  ENDMETHOD.

  METHOD format_material_number.
    " Remove leading zeros and then add them back properly
    DATA: lv_material_internal TYPE matnr.
    
    lv_material_internal = |{ iv_material ALPHA = IN }|.
    rv_material = lv_material_internal.
  ENDMETHOD.

  METHOD get_movement_code.
    " Map movement types to goods movement codes
    CASE iv_movement_type.
      WHEN '101'.
        rv_gm_code = '01'. " Goods receipt
      WHEN '102'.
        rv_gm_code = '02'. " Goods receipt reversal
      WHEN '261'.
        rv_gm_code = '03'. " Goods issue for production order
      WHEN '262'.
        rv_gm_code = '04'. " Goods issue reversal
      WHEN '963'.
        rv_gm_code = '04'. " Goods issue
      WHEN OTHERS.
        rv_gm_code = '04'. " Default to goods issue
    ENDCASE.
  ENDMETHOD.

ENDCLASS.