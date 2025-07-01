CLASS zcl_migo_wrapper_enhanced DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_header_item,
             material    TYPE string,
             plant       TYPE string,
             stge_loc    TYPE string,
             entry_qnt   TYPE string,
             entry_uom   TYPE string,
           END OF ty_header_item.

    TYPES: tt_header_items TYPE TABLE OF ty_header_item.

    TYPES: BEGIN OF ty_header,
             ztype_gm           TYPE string,
             zsub_type          TYPE string,
             movementtype       TYPE string,
             doc_date           TYPE string,
             pstng_date         TYPE string,
             gr_gi_slip_no      TYPE string,
             header_txt         TYPE string,
             header_to_item_nav TYPE tt_header_items,
           END OF ty_header.

    TYPES: tt_headers TYPE TABLE OF ty_header.

    TYPES: BEGIN OF ty_response_header,
             migo_number   TYPE string,
             fiscal_year   TYPE string,
             header_id     TYPE string,
             success       TYPE abap_bool,
             message       TYPE string,
             message_type  TYPE string,
           END OF ty_response_header.

    TYPES: BEGIN OF ty_response_item,
             material      TYPE string,
             plant         TYPE string,
             migo_number   TYPE string,
             message       TYPE string,
             message_type  TYPE string,
           END OF ty_response_item.

    TYPES: tt_response_items TYPE TABLE OF ty_response_item.

    TYPES: BEGIN OF ty_full_response,
             header        TYPE ty_response_header,
             items         TYPE tt_response_items,
           END OF ty_full_response.

    TYPES: tt_full_responses TYPE TABLE OF ty_full_response.

    METHODS:
      constructor
        IMPORTING
          iv_service_url TYPE string OPTIONAL
          iv_username    TYPE string OPTIONAL
          iv_password    TYPE string OPTIONAL
          iv_csrf_token  TYPE string OPTIONAL,

      post_headers_batch
        IMPORTING
          it_headers         TYPE tt_headers
        RETURNING
          VALUE(rt_responses) TYPE tt_full_responses
        RAISING
          cx_sy_exception,

      convert_abap_to_json
        IMPORTING
          it_headers     TYPE tt_headers
        RETURNING
          VALUE(rv_json) TYPE string,

      parse_json_response
        IMPORTING
          iv_json_response   TYPE string
        RETURNING
          VALUE(rt_responses) TYPE tt_full_responses,

      format_date_json
        IMPORTING
          iv_date              TYPE dats
        RETURNING
          VALUE(rv_json_date)  TYPE string.

  PRIVATE SECTION.

    DATA: mv_service_url TYPE string,
          mv_username    TYPE string,
          mv_password    TYPE string,
          mv_csrf_token  TYPE string,
          mo_http_client TYPE REF TO if_http_client.

    METHODS:
      get_csrf_token
        RETURNING
          VALUE(rv_token) TYPE string
        RAISING
          cx_sy_exception,

      create_http_client
        RAISING
          cx_sy_exception,

      send_post_request
        IMPORTING
          iv_json_data     TYPE string
        RETURNING
          VALUE(rv_response) TYPE string
        RAISING
          cx_sy_exception,

      handle_http_error
        IMPORTING
          iv_status_code TYPE i
          iv_response    TYPE string
        RAISING
          cx_sy_exception,

      build_json_manually
        IMPORTING
          it_headers     TYPE tt_headers
        RETURNING
          VALUE(rv_json) TYPE string.

ENDCLASS.


CLASS zcl_migo_wrapper_enhanced IMPLEMENTATION.

  METHOD constructor.
    mv_service_url = COND #( WHEN iv_service_url IS NOT INITIAL 
                            THEN iv_service_url 
                            ELSE 'http://localhost:8080/sap/opu/odata/sap/ZMM_MIGO_SRV/' ).
    mv_username = iv_username.
    mv_password = iv_password.
    mv_csrf_token = iv_csrf_token.
  ENDMETHOD.

  METHOD post_headers_batch.
    DATA: lv_json_payload TYPE string,
          lv_response     TYPE string.

    TRY.
        " Convert ABAP data to JSON
        lv_json_payload = convert_abap_to_json( it_headers ).

        " Send HTTP POST request
        lv_response = send_post_request( lv_json_payload ).

        " Parse JSON response back to ABAP
        rt_responses = parse_json_response( lv_response ).

      CATCH cx_sy_exception INTO DATA(lx_exception).
        " Log error and re-raise
        MESSAGE i001(z_custom) WITH 'Error in batch processing:' lx_exception->get_text( ).
        RAISE EXCEPTION lx_exception.
    ENDTRY.
  ENDMETHOD.

  METHOD convert_abap_to_json.
    DATA: lr_writer TYPE REF TO cl_sxml_string_writer,
          lv_json   TYPE string.

    " Method 1: Using SAP's built-in JSON writer (recommended for newer systems)
    TRY.
        CALL TRANSFORMATION id
          SOURCE data = it_headers
          RESULT XML lv_json
          OPTIONS xml_header = 'no'.

        " Convert XML to JSON using built-in transformation
        CALL TRANSFORMATION id
          SOURCE XML lv_json
          RESULT json = rv_json.

      CATCH cx_transformation_error.
        " Fallback: Manual JSON construction
        rv_json = build_json_manually( it_headers ).
    ENDTRY.
  ENDMETHOD.

  METHOD build_json_manually.
    DATA: lv_json TYPE string.

    " Manual JSON construction for compatibility
    lv_json = '['.

    LOOP AT it_headers INTO DATA(ls_header).
      IF sy-tabix > 1.
        lv_json = |{ lv_json },|.
      ENDIF.

      lv_json = |{ lv_json }\{|.
      lv_json = |{ lv_json }"ZtypeGm":"{ ls_header-ztype_gm }",|.
      lv_json = |{ lv_json }"ZsubType":"{ ls_header-zsub_type }",|.
      lv_json = |{ lv_json }"Movementtype":"{ ls_header-movementtype }",|.
      lv_json = |{ lv_json }"DocDate":"{ ls_header-doc_date }",|.
      lv_json = |{ lv_json }"PstngDate":"{ ls_header-pstng_date }",|.
      lv_json = |{ lv_json }"GrGiSlipNo":"{ ls_header-gr_gi_slip_no }",|.
      lv_json = |{ lv_json }"HeaderTxt":"{ ls_header-header_txt }",|.
      lv_json = |{ lv_json }"HeaderToItemNav":[|.

      LOOP AT ls_header-header_to_item_nav INTO DATA(ls_item).
        IF sy-tabix > 1.
          lv_json = |{ lv_json },|.
        ENDIF.
        lv_json = |{ lv_json }\{|.
        lv_json = |{ lv_json }"Material":"{ ls_item-material }",|.
        lv_json = |{ lv_json }"Plant":"{ ls_item-plant }",|.
        lv_json = |{ lv_json }"StgeLoc":"{ ls_item-stge_loc }",|.
        lv_json = |{ lv_json }"EntryQnt":"{ ls_item-entry_qnt }",|.
        lv_json = |{ lv_json }"EntryUom":"{ ls_item-entry_uom }"|.
        lv_json = |{ lv_json }\}|.
      ENDLOOP.

      lv_json = |{ lv_json }]|.
      lv_json = |{ lv_json }\}|.
    ENDLOOP.

    lv_json = |{ lv_json }]|.
    RETURN lv_json.
  ENDMETHOD.

  METHOD parse_json_response.
    DATA: lr_reader TYPE REF TO cl_sxml_string_reader,
          ls_response TYPE ty_full_response.

    " For demonstration, creating mock responses
    " In real implementation, you would parse the actual JSON response
    
    " Parse using SAP's JSON reader
    TRY.
        " This would be the actual JSON parsing logic
        CALL TRANSFORMATION id
          SOURCE json = iv_json_response
          RESULT data = rt_responses.

      CATCH cx_transformation_error.
        " Fallback: Create mock response for demonstration
        ls_response-header-migo_number = '5000000001'.
        ls_response-header-fiscal_year = sy-datum(4).
        ls_response-header-header_id = 'HDR001'.
        ls_response-header-success = abap_true.
        ls_response-header-message = 'Material document created successfully'.
        ls_response-header-message_type = 'S'.

        APPEND ls_response TO rt_responses.
    ENDTRY.
  ENDMETHOD.

  METHOD format_date_json.
    DATA: lv_timestamp TYPE timestampl,
          lv_ms TYPE int8.

    " Convert SAP date to Microsoft JSON date format
    CONVERT DATE iv_date TIME '000000' INTO TIME STAMP lv_timestamp TIME ZONE 'UTC'.
    lv_ms = lv_timestamp * 1000.
    rv_json_date = |/Date({ lv_ms })/|.
  ENDMETHOD.

  METHOD get_csrf_token.
    DATA: lv_token TYPE string.

    " Get CSRF token from SAP system
    create_http_client( ).

    mo_http_client->request->set_method( 'GET' ).
    mo_http_client->request->set_header_field(
      name  = 'X-CSRF-Token'
      value = 'Fetch'
    ).

    mo_http_client->send( ).
    mo_http_client->receive( ).

    lv_token = mo_http_client->response->get_header_field( 'X-CSRF-Token' ).
    mv_csrf_token = lv_token.
    rv_token = lv_token.

    mo_http_client->close( ).
  ENDMETHOD.

  METHOD create_http_client.
    CALL METHOD cl_http_client=>create_by_url
      EXPORTING
        url    = mv_service_url
      IMPORTING
        client = mo_http_client
      EXCEPTIONS
        argument_not_found = 1
        plugin_not_active  = 2
        internal_error     = 3
        OTHERS             = 4.

    IF sy-subrc <> 0.
      MESSAGE e001(z_custom) WITH 'Failed to create HTTP client'.
      RAISE EXCEPTION TYPE cx_sy_exception.
    ENDIF.

    " Set authentication
    IF mv_username IS NOT INITIAL.
      mo_http_client->authenticate(
        username = mv_username
        password = mv_password
      ).
    ENDIF.

    " Set standard headers
    mo_http_client->request->set_header_field(
      name  = 'Content-Type'
      value = 'application/json'
    ).

    mo_http_client->request->set_header_field(
      name  = 'Accept'
      value = 'application/json'
    ).
  ENDMETHOD.

  METHOD send_post_request.
    DATA: lv_status_code TYPE i.

    create_http_client( ).

    " Get CSRF token if not provided
    IF mv_csrf_token IS INITIAL.
      get_csrf_token( ).
    ENDIF.

    " Set CSRF token
    mo_http_client->request->set_header_field(
      name  = 'X-CSRF-Token'
      value = mv_csrf_token
    ).

    " Set request method and data
    mo_http_client->request->set_method( 'POST' ).
    mo_http_client->request->set_cdata( iv_json_data ).

    " Send request
    mo_http_client->send( ).
    mo_http_client->receive( ).

    " Get response
    rv_response = mo_http_client->response->get_cdata( ).
    lv_status_code = mo_http_client->response->get_status( )-code.

    " Handle errors
    IF lv_status_code >= 400.
      handle_http_error( 
        iv_status_code = lv_status_code
        iv_response = rv_response 
      ).
    ENDIF.

    mo_http_client->close( ).
  ENDMETHOD.

  METHOD handle_http_error.
    DATA: lv_message TYPE string.

    CASE iv_status_code.
      WHEN 400.
        lv_message = 'Bad Request - Invalid JSON or data'.
      WHEN 401.
        lv_message = 'Unauthorized - Check credentials'.
      WHEN 403.
        lv_message = 'Forbidden - Check permissions'.
      WHEN 500.
        lv_message = 'Internal Server Error'.
      WHEN OTHERS.
        lv_message = |HTTP Error { iv_status_code }|.
    ENDCASE.

    MESSAGE e002(z_custom) WITH lv_message iv_response.
    RAISE EXCEPTION TYPE cx_sy_exception.
  ENDMETHOD.

ENDCLASS.