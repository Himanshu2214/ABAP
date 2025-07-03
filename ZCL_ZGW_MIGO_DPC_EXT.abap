CLASS zcl_zgw_migo_dpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zgw_migo_dpc
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Override methods for CRUD operations
    METHODS: migodocumentset_create_entity REDEFINITION,
             migodocumentset_get_entityset REDEFINITION,
             migodocumentset_get_entity REDEFINITION.

  PRIVATE SECTION.
    " Instance of enhanced MIGO processor
    DATA: lo_migo_processor TYPE REF TO zcl_migo_posting_enhanced.

    METHODS: handle_migo_creation
      IMPORTING
        ir_entity TYPE REF TO data
      RETURNING
        VALUE(er_entity) TYPE REF TO data
      RAISING
        /iwbep/cx_mgw_busi_exception
        /iwbep/cx_mgw_tech_exception.

ENDCLASS.

CLASS zcl_zgw_migo_dpc_ext IMPLEMENTATION.

  METHOD migodocumentset_create_entity.
    " Handle POST request for MIGO document creation
    er_entity = handle_migo_creation( ir_entity ).
  ENDMETHOD.

  METHOD migodocumentset_get_entityset.
    " Handle GET request for entity set (optional - for testing)
    DATA: lt_entityset TYPE zcl_zgw_migo_mpc=>tt_migodocument.
    
    " Return empty set for now
    copy_data_to_ref(
      EXPORTING
        is_data = lt_entityset
      CHANGING
        cr_data = er_entityset
    ).
  ENDMETHOD.

  METHOD migodocumentset_get_entity.
    " Handle GET request for single entity (optional - for testing)
    DATA: ls_entity TYPE zcl_zgw_migo_mpc=>ts_migodocument.
    
    " Return empty entity for now
    copy_data_to_ref(
      EXPORTING
        is_data = ls_entity
      CHANGING
        cr_data = er_entity
    ).
  ENDMETHOD.

  METHOD handle_migo_creation.
    DATA: ls_entity_in  TYPE zcl_zgw_migo_mpc=>ts_migodocument,
          ls_entity_out TYPE zcl_zgw_migo_mpc=>ts_migodocument,
          lv_json_payload TYPE string,
          lv_response_json TYPE string,
          lo_json_des TYPE REF TO /ui2/cl_json,
          lt_responses TYPE zcl_migo_posting_enhanced=>tt_migo_response,
          ls_response TYPE zcl_migo_posting_enhanced=>ty_migo_response.

    " Copy input entity
    MOVE-CORRESPONDING ir_entity->* TO ls_entity_in.

    " Validate input
    IF ls_entity_in-payload IS INITIAL.
      MESSAGE e001(z_migo) WITH 'Payload is required' INTO DATA(lv_message).
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          textid = /iwbep/cx_mgw_busi_exception=>business_error
          message = lv_message.
    ENDIF.

    TRY.
        " Create instance of enhanced MIGO processor if not exists
        IF lo_migo_processor IS INITIAL.
          CREATE OBJECT lo_migo_processor.
        ENDIF.

        " Process the MIGO posting
        lv_response_json = lo_migo_processor->process_migo_posting( ls_entity_in-payload ).

        " Deserialize response to get details
        /ui2/cl_json=>deserialize(
          EXPORTING
            json = lv_response_json
            pretty_name = /ui2/cl_json=>pretty_mode-camel_case
          CHANGING
            data = lt_responses
        ).

        " Process first response for main entity
        READ TABLE lt_responses INTO ls_response INDEX 1.
        IF sy-subrc = 0.
          ls_entity_out-requestid = cl_system_uuid=>create_uuid_x16_static( ).
          ls_entity_out-success = ls_response-success.
          ls_entity_out-message = ls_response-message.
          ls_entity_out-migo_number = ls_response-migo_number.
          ls_entity_out-gigrnum = ls_response-gigrnum.
          ls_entity_out-material_document = ls_response-material_document.
          ls_entity_out-document_year = ls_response-document_year.
          ls_entity_out-payload = ls_entity_in-payload.
          ls_entity_out-response = lv_response_json.
          
          " Combine error details into single string
          IF lines( ls_response-error_details ) > 0.
            CLEAR lv_message.
            LOOP AT ls_response-error_details INTO DATA(lv_error).
              IF lv_message IS INITIAL.
                lv_message = lv_error.
              ELSE.
                lv_message = |{ lv_message }; { lv_error }|.
              ENDIF.
            ENDLOOP.
            ls_entity_out-error_details = lv_message.
          ENDIF.

          " Set response entity
          copy_data_to_ref(
            EXPORTING
              is_data = ls_entity_out
            CHANGING
              cr_data = er_entity
          ).

          " If there's an error, raise business exception
          IF ls_response-success = abap_false.
            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                textid = /iwbep/cx_mgw_busi_exception=>business_error
                message = ls_response-message
                entity_type = 'MigoDocument'.
          ENDIF.

        ELSE.
          " No response received
          MESSAGE e002(z_migo) WITH 'No response from MIGO processor' INTO lv_message.
          RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
            EXPORTING
              textid = /iwbep/cx_mgw_busi_exception=>business_error
              message = lv_message.
        ENDIF.

      CATCH cx_sy_conversion_no_number
            cx_sy_move_cast_error INTO DATA(lx_conversion_error).
        
        MESSAGE e003(z_migo) WITH 'Data conversion error:' lx_conversion_error->get_text( ) INTO lv_message.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
          EXPORTING
            textid = /iwbep/cx_mgw_tech_exception=>internal_error
            message = lv_message.

      CATCH cx_root INTO DATA(lx_general_error).
        MESSAGE e004(z_migo) WITH 'General processing error:' lx_general_error->get_text( ) INTO lv_message.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
          EXPORTING
            textid = /iwbep/cx_mgw_tech_exception=>internal_error
            message = lv_message.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.