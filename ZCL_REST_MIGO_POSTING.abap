CLASS zcl_rest_migo_posting DEFINITION
  PUBLIC
  INHERITING FROM cl_rest_resource
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS: if_rest_resource~post REDEFINITION.

  PRIVATE SECTION.
    METHODS: handle_migo_posting
      IMPORTING
        iv_payload TYPE string
      RETURNING
        VALUE(rv_response) TYPE string.

ENDCLASS.

CLASS zcl_rest_migo_posting IMPLEMENTATION.

  METHOD if_rest_resource~post.
    DATA: lv_payload  TYPE string,
          lv_response TYPE string,
          lv_content_type TYPE string.

    TRY.
        " Get the request payload
        DATA(lo_entity) = mo_request->get_entity( ).
        
        IF lo_entity IS BOUND.
          lv_payload = lo_entity->get_string( ).
        ENDIF.

        " Process MIGO posting
        lv_response = handle_migo_posting( lv_payload ).

        " Set response
        mo_response->create_entity( )->set_string_data( lv_response ).
        mo_response->set_status( cl_rest_status_code=>gc_success_ok ).
        mo_response->set_header_field( 
          iv_name = 'Content-Type' 
          iv_value = 'application/json'
        ).

      CATCH cx_rest_exception INTO DATA(lx_rest).
        " Handle REST exceptions
        DATA(lv_error_msg) = |REST Error: { lx_rest->get_text( ) }|.
        mo_response->create_entity( )->set_string_data( 
          |{{"success": false, "message": "{ lv_error_msg }"}}|
        ).
        mo_response->set_status( cl_rest_status_code=>gc_server_error_internal ).

      CATCH cx_root INTO DATA(lx_root).
        " Handle any other exceptions
        DATA(lv_general_error) = |General Error: { lx_root->get_text( ) }|.
        mo_response->create_entity( )->set_string_data( 
          |{{"success": false, "message": "{ lv_general_error }"}}|
        ).
        mo_response->set_status( cl_rest_status_code=>gc_server_error_internal ).
    ENDTRY.

  ENDMETHOD.

  METHOD handle_migo_posting.
    DATA: lo_migo_api TYPE REF TO zcl_migo_posting_api.

    " Validate payload
    IF iv_payload IS INITIAL.
      rv_response = '{"success": false, "message": "Empty payload provided"}' .
      RETURN.
    ENDIF.

    TRY.
        " Create MIGO API instance and process the request
        CREATE OBJECT lo_migo_api.
        rv_response = lo_migo_api->post_migo( iv_payload ).

      CATCH cx_root INTO DATA(lx_error).
        rv_response = |{{"success": false, "message": "Processing Error: { lx_error->get_text( ) }"}}|.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.