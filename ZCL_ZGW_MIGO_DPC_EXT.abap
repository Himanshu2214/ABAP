CLASS zcl_zgw_migo_dpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zgw_migo_dpc
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Override CRUD methods for main entity
    METHODS: migodocumentset_create_entity REDEFINITION,
             migodocumentset_get_entityset REDEFINITION,
             migodocumentset_get_entity REDEFINITION.

    " Override methods for item entity (if using navigation)
    METHODS: migoitemset_get_entityset REDEFINITION.

  PRIVATE SECTION.
    " Instance of enhanced MIGO processor
    DATA: lo_migo_processor TYPE REF TO zcl_migo_posting_enhanced.

    " Helper methods
    METHODS: handle_migo_creation
      IMPORTING
        ir_entity TYPE REF TO data
      RETURNING
        VALUE(er_entity) TYPE REF TO data
      RAISING
        /iwbep/cx_mgw_busi_exception
        /iwbep/cx_mgw_tech_exception,

      validate_input
        IMPORTING
          is_entity TYPE zcl_zgw_migo_mpc=>ts_migodocument
        RAISING
          /iwbep/cx_mgw_busi_exception,

      generate_request_id
        RETURNING
          VALUE(rv_request_id) TYPE string,

      parse_response_json
        IMPORTING
          iv_response_json TYPE string
          iv_request_id TYPE string
          iv_payload TYPE string
        RETURNING
          VALUE(rs_entity) TYPE zcl_zgw_migo_mpc=>ts_migodocument
        RAISING
          /iwbep/cx_mgw_tech_exception.

ENDCLASS.

CLASS zcl_zgw_migo_dpc_ext IMPLEMENTATION.

  METHOD migodocumentset_create_entity.
    " Main POST method for creating MIGO documents
    er_entity = handle_migo_creation( ir_entity ).
  ENDMETHOD.

  METHOD migodocumentset_get_entityset.
    " Handle GET request for entity set (for testing purposes)
    DATA: lt_entityset TYPE zcl_zgw_migo_mpc=>tt_migodocument.
    
    " Return empty set - this service is primarily for POST operations
    copy_data_to_ref(
      EXPORTING
        is_data = lt_entityset
      CHANGING
        cr_data = er_entityset
    ).
  ENDMETHOD.

  METHOD migodocumentset_get_entity.
    " Handle GET request for single entity (for testing purposes)
    DATA: ls_entity TYPE zcl_zgw_migo_mpc=>ts_migodocument.
    
    " For this implementation, return empty entity
    " In production, you might want to implement actual retrieval logic
    copy_data_to_ref(
      EXPORTING
        is_data = ls_entity
      CHANGING
        cr_data = er_entity
    ).
  ENDMETHOD.

  METHOD migoitemset_get_entityset.
    " Handle GET request for item entity set (if using navigation)
    DATA: lt_items TYPE TABLE OF zcl_zgw_migo_mpc=>ts_migoitem.
    
    " Return empty set for now
    copy_data_to_ref(
      EXPORTING
        is_data = lt_items
      CHANGING
        cr_data = er_entityset
    ).
  ENDMETHOD.

  METHOD handle_migo_creation.
    DATA: ls_entity_in      TYPE zcl_zgw_migo_mpc=>ts_migodocument,
          ls_entity_out     TYPE zcl_zgw_migo_mpc=>ts_migodocument,
          lv_response_json  TYPE string,
          lv_request_id     TYPE string.

    " Copy input entity
    MOVE-CORRESPONDING ir_entity->* TO ls_entity_in.

    " Generate request ID if not provided
    IF ls_entity_in-requestid IS INITIAL.
      lv_request_id = generate_request_id( ).
      ls_entity_in-requestid = lv_request_id.
    ELSE.
      lv_request_id = ls_entity_in-requestid.
    ENDIF.

    " Validate input
    validate_input( ls_entity_in ).

    TRY.
        " Create MIGO processor instance if not exists
        IF lo_migo_processor IS INITIAL.
          CREATE OBJECT lo_migo_processor.
        ENDIF.

        " Process MIGO posting
        lv_response_json = lo_migo_processor->process_migo_posting( ls_entity_in-payload ).

        " Parse response and populate output entity
        ls_entity_out = parse_response_json(
          iv_response_json = lv_response_json
          iv_request_id = lv_request_id
          iv_payload = ls_entity_in-payload
        ).

        " Set response entity
        copy_data_to_ref(
          EXPORTING
            is_data = ls_entity_out
          CHANGING
            cr_data = er_entity
        ).

        " Raise business exception if processing failed
        IF ls_entity_out-success = abap_false.
          RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
            EXPORTING
              textid = /iwbep/cx_mgw_busi_exception=>business_error
              message = ls_entity_out-message
              entity_type = 'MigoDocument'.
        ENDIF.

      CATCH /iwbep/cx_mgw_busi_exception.
        " Re-raise business exceptions
        RAISE.

      CATCH cx_sy_conversion_no_number
            cx_sy_move_cast_error INTO DATA(lx_conversion_error).
        
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
          EXPORTING
            textid = /iwbep/cx_mgw_tech_exception=>internal_error
            message = |Data conversion error: { lx_conversion_error->get_text( ) }|.

      CATCH cx_root INTO DATA(lx_general_error).
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
          EXPORTING
            textid = /iwbep/cx_mgw_tech_exception=>internal_error
            message = |General processing error: { lx_general_error->get_text( ) }|.
    ENDTRY.

  ENDMETHOD.

  METHOD validate_input.
    " Validate input payload
    IF is_entity-payload IS INITIAL.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error
          message = 'Payload is required for MIGO posting'
          entity_type = 'MigoDocument'.
    ENDIF.

    " Additional validation can be added here
    " For example, check if payload is valid JSON
    TRY.
        DATA: lo_reader TYPE REF TO /ui2/cl_json.
        CREATE OBJECT lo_reader.
        
        " Try to parse JSON to validate format
        DATA: lv_test_data TYPE string.
        /ui2/cl_json=>deserialize(
          EXPORTING
            json = is_entity-payload
          CHANGING
            data = lv_test_data
        ).

      CATCH cx_sy_conversion_no_number
            cx_sy_move_cast_error.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            textid = /iwbep/cx_mgw_busi_exception=>business_error
            message = 'Invalid JSON format in payload'
            entity_type = 'MigoDocument'.
    ENDTRY.

  ENDMETHOD.

  METHOD generate_request_id.
    " Generate unique request ID using timestamp and random number
    DATA: lv_timestamp TYPE timestampl,
          lv_random TYPE i.

    GET TIME STAMP FIELD lv_timestamp.
    
    " Get random number
    CALL FUNCTION 'QF05_RANDOM_INTEGER'
      EXPORTING
        ran_int_max = 9999
        ran_int_min = 1000
      IMPORTING
        ran_int = lv_random.

    " Combine timestamp and random for unique ID
    rv_request_id = |{ lv_timestamp }{ lv_random }|.
    
    " Ensure it fits in 32 characters
    IF strlen( rv_request_id ) > 32.
      rv_request_id = rv_request_id+0(32).
    ENDIF.

  ENDMETHOD.

  METHOD parse_response_json.
    DATA: lt_responses TYPE zcl_migo_posting_enhanced=>tt_migo_response,
          ls_response  TYPE zcl_migo_posting_enhanced=>ty_migo_response,
          lv_error_concat TYPE string.

    " Initialize output entity
    CLEAR rs_entity.
    rs_entity-requestid = iv_request_id.
    rs_entity-payload = iv_payload.
    rs_entity-response = iv_response_json.

    TRY.
        " Deserialize response
        /ui2/cl_json=>deserialize(
          EXPORTING
            json = iv_response_json
            pretty_name = /ui2/cl_json=>pretty_mode-camel_case
          CHANGING
            data = lt_responses
        ).

        " Process first response (main response)
        READ TABLE lt_responses INTO ls_response INDEX 1.
        IF sy-subrc = 0.
          " Map response fields
          rs_entity-success = ls_response-success.
          rs_entity-message = ls_response-message.
          rs_entity-migo_number = ls_response-migo_number.
          rs_entity-gigrnum = ls_response-gigrnum.
          rs_entity-material_document = ls_response-material_document.
          rs_entity-document_year = ls_response-document_year.

          " Concatenate error details
          IF lines( ls_response-error_details ) > 0.
            CLEAR lv_error_concat.
            LOOP AT ls_response-error_details INTO DATA(lv_error).
              IF lv_error_concat IS INITIAL.
                lv_error_concat = lv_error.
              ELSE.
                lv_error_concat = |{ lv_error_concat } | { lv_error }|.
              ENDIF.
            ENDLOOP.
            rs_entity-error_details = lv_error_concat.
          ENDIF.

          " If multiple responses exist, process them and add to error details
          IF lines( lt_responses ) > 1.
            DATA: lv_multi_response TYPE string.
            lv_multi_response = |Multiple records processed: { lines( lt_responses ) }|.
            
            IF rs_entity-error_details IS INITIAL.
              rs_entity-error_details = lv_multi_response.
            ELSE.
              rs_entity-error_details = |{ rs_entity-error_details } | { lv_multi_response }|.
            ENDIF.
          ENDIF.

        ELSE.
          " No response found
          rs_entity-success = abap_false.
          rs_entity-message = 'No response received from MIGO processor'.
        ENDIF.

      CATCH cx_sy_conversion_no_number
            cx_sy_move_cast_error.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
          EXPORTING
            textid = /iwbep/cx_mgw_tech_exception=>internal_error
            message = 'Failed to parse response JSON'.

      CATCH cx_root INTO DATA(lx_error).
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
          EXPORTING
            textid = /iwbep/cx_mgw_tech_exception=>internal_error
            message = |JSON parsing error: { lx_error->get_text( ) }|.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.