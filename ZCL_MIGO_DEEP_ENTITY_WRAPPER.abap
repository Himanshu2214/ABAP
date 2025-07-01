CLASS zcl_migo_deep_entity_wrapper DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_header_item,
             material    TYPE matnr,
             plant       TYPE werks_d,
             stge_loc    TYPE lgort_d,
             entry_qnt   TYPE menge_d,
             entry_uom   TYPE meins,
           END OF ty_header_item.

    TYPES: tt_header_items TYPE TABLE OF ty_header_item.

    TYPES: BEGIN OF ty_header,
             ztype_gm         TYPE char4,
             zsub_type        TYPE char3,
             movement_type    TYPE bwart,
             doc_date         TYPE dats,
             pstng_date       TYPE dats,
             gr_gi_slip_no    TYPE char10,
             header_txt       TYPE bktxt,
             header_to_item_nav TYPE tt_header_items,
           END OF ty_header.

    TYPES: tt_headers TYPE TABLE OF ty_header.

    TYPES: BEGIN OF ty_response_item,
             material      TYPE matnr,
             plant         TYPE werks_d,
             migo_number   TYPE mblnr,
             message       TYPE string,
             message_type  TYPE char1,
           END OF ty_response_item.

    TYPES: tt_response_items TYPE TABLE OF ty_response_item.

    TYPES: BEGIN OF ty_response,
             header_id        TYPE char10,
             migo_number      TYPE mblnr,
             fiscal_year      TYPE mjahr,
             success          TYPE abap_bool,
             message          TYPE string,
             response_items   TYPE tt_response_items,
           END OF ty_response.

    TYPES: tt_responses TYPE TABLE OF ty_response.

    METHODS:
      constructor
        IMPORTING
          iv_service_url TYPE string OPTIONAL
          iv_username    TYPE string OPTIONAL
          iv_password    TYPE string OPTIONAL,

      post_multiple_headers
        IMPORTING
          it_headers    TYPE tt_headers
        RETURNING
          VALUE(rt_responses) TYPE tt_responses
        RAISING
          cx_sy_exception,

      convert_to_json
        IMPORTING
          it_headers    TYPE tt_headers
        RETURNING
          VALUE(rv_json) TYPE string,

      parse_response
        IMPORTING
          iv_response_json TYPE string
        RETURNING
          VALUE(rt_responses) TYPE tt_responses.

  PRIVATE SECTION.

    DATA: mv_service_url TYPE string,
          mv_username    TYPE string,
          mv_password    TYPE string,
          mo_http_client TYPE REF TO if_http_client.

    METHODS:
      setup_http_client
        RAISING
          cx_sy_exception,

      format_date_for_json
        IMPORTING
          iv_date TYPE dats
        RETURNING
          VALUE(rv_formatted_date) TYPE string,

      send_http_request
        IMPORTING
          iv_json_payload TYPE string
        RETURNING
          VALUE(rv_response) TYPE string
        RAISING
          cx_sy_exception.

ENDCLASS.


CLASS zcl_migo_deep_entity_wrapper IMPLEMENTATION.

  " Constructor Method
  METHOD constructor.
    mv_service_url = COND #( WHEN iv_service_url IS NOT INITIAL 
                            THEN iv_service_url 
                            ELSE 'http://localhost:8080/sap/opu/odata/sap/ZMM_MIGO_SRV/' ).
    mv_username = iv_username.
    mv_password = iv_password.
  ENDMETHOD.

  " Main method to post multiple headers and get responses
  METHOD post_multiple_headers.
    DATA: lv_json_payload TYPE string,
          lv_response     TYPE string.

    " Convert headers to JSON
    lv_json_payload = convert_to_json( it_headers ).

    " Send HTTP request
    lv_response = send_http_request( lv_json_payload ).

    " Parse response and return
    rt_responses = parse_response( lv_response ).
  ENDMETHOD.

  " Convert headers to JSON format
  METHOD convert_to_json.
    DATA: lv_json TYPE string,
          lv_temp TYPE string.

    " Start JSON array
    lv_json = '['.

    LOOP AT it_headers INTO DATA(ls_header).
      IF sy-tabix > 1.
        lv_json = |{ lv_json },|.
      ENDIF.

      " Build header JSON
      lv_json = |{ lv_json }\{|.
      lv_json = |{ lv_json }"ZtypeGm":"{ ls_header-ztype_gm }",|.
      lv_json = |{ lv_json }"ZsubType":"{ ls_header-zsub_type }",|.
      lv_json = |{ lv_json }"Movementtype":"{ ls_header-movement_type }",|.
      lv_json = |{ lv_json }"DocDate":"{ format_date_for_json( ls_header-doc_date ) }",|.
      lv_json = |{ lv_json }"PstngDate":"{ format_date_for_json( ls_header-pstng_date ) }",|.
      lv_json = |{ lv_json }"GrGiSlipNo":"{ ls_header-gr_gi_slip_no }",|.
      lv_json = |{ lv_json }"HeaderTxt":"{ ls_header-header_txt }",|.
      lv_json = |{ lv_json }"HeaderToItemNav":[|.

      " Build items JSON
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

    " Close JSON array
    lv_json = |{ lv_json }]|.
    rv_json = lv_json.
  ENDMETHOD.

  " Format date for JSON (Microsoft JSON date format)
  METHOD format_date_for_json.
    DATA: lv_timestamp TYPE timestampl,
          lv_milliseconds TYPE int8.

    " Convert date to timestamp
    CONVERT DATE iv_date TIME '000000' INTO TIME STAMP lv_timestamp TIME ZONE 'UTC'.
    
    " Convert to milliseconds since epoch (Jan 1, 1970)
    lv_milliseconds = lv_timestamp * 1000.
    
    " Format as Microsoft JSON date
    rv_formatted_date = |/Date({ lv_milliseconds })/|.
  ENDMETHOD.

  " Setup HTTP client
  METHOD setup_http_client.
    DATA: lv_host TYPE string,
          lv_service TYPE string.

    " Extract host and service from URL
    " This is a simplified version - in real implementation you'd parse the URL properly
    lv_host = mv_service_url.
    lv_service = '/sap/opu/odata/sap/ZMM_MIGO_SRV/'.

    " Create HTTP client
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
      RAISE EXCEPTION TYPE cx_sy_exception.
    ENDIF.

    " Set authentication if provided
    IF mv_username IS NOT INITIAL.
      mo_http_client->authenticate(
        username = mv_username
        password = mv_password
      ).
    ENDIF.

    " Set request headers
    mo_http_client->request->set_header_field(
      name  = 'Content-Type'
      value = 'application/json'
    ).

    mo_http_client->request->set_header_field(
      name  = 'Accept'
      value = 'application/json'
    ).
  ENDMETHOD.

  " Send HTTP request
  METHOD send_http_request.
    DATA: lv_response_text TYPE string,
          lv_status_code   TYPE i.

    " Setup HTTP client
    setup_http_client( ).

    " Set request method and payload
    mo_http_client->request->set_method( 'POST' ).
    mo_http_client->request->set_cdata( iv_json_payload ).

    " Send request
    mo_http_client->send(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        OTHERS                     = 4
    ).

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE cx_sy_exception.
    ENDIF.

    " Receive response
    mo_http_client->receive(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        OTHERS                     = 4
    ).

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE cx_sy_exception.
    ENDIF.

    " Get response
    lv_response_text = mo_http_client->response->get_cdata( ).
    lv_status_code = mo_http_client->response->get_status( )-code.

    " Check status code
    IF lv_status_code >= 400.
      RAISE EXCEPTION TYPE cx_sy_exception.
    ENDIF.

    rv_response = lv_response_text.

    " Close HTTP client
    mo_http_client->close( ).
  ENDMETHOD.

  " Parse JSON response
  METHOD parse_response.
    " This is a simplified JSON parser
    " In real implementation, you'd use a proper JSON library like /UI2/CL_JSON
    DATA: lv_json TYPE string,
          ls_response TYPE ty_response.

    lv_json = iv_response_json.

    " Simple parsing logic (you'd implement proper JSON parsing here)
    " For demonstration purposes, creating a mock response
    ls_response-header_id = 'HDR001'.
    ls_response-migo_number = '5000000001'.
    ls_response-fiscal_year = sy-datum(4).
    ls_response-success = abap_true.
    ls_response-message = 'Material document created successfully'.

    APPEND ls_response TO rt_responses.
  ENDMETHOD.

ENDCLASS.