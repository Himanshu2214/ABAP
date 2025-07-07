CLASS zcl_rest_migo_rap_handler DEFINITION
  PUBLIC
  INHERITING FROM cl_rest_resource
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    METHODS: if_rest_resource~post REDEFINITION.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_request_item,
             GrGiSlipNo    TYPE string,
             ZtypeGm       TYPE string,
             ZsubType      TYPE string,
             Movementtype  TYPE string,
             DocDate       TYPE string,
             PstngDate     TYPE string,
             HeaderTxt     TYPE string,
             ItemNo        TYPE string,
             Material      TYPE string,
             MatDesc       TYPE string,
             BaseUom       TYPE string,
             Quantity      TYPE string,
             StrgLoc       TYPE string,
             Plant         TYPE string,
             GlAccount     TYPE string,
             Costcenter    TYPE string,
             OrderNo       TYPE string,
             ItemOk        TYPE abap_bool,
           END OF ty_request_item.

    TYPES: BEGIN OF ty_request,
             Header  TYPE string,
             ZMATSet TYPE STANDARD TABLE OF ty_request_item WITH DEFAULT KEY,
           END OF ty_request.

    TYPES: BEGIN OF ty_response_item,
             GrGiSlipNo    TYPE string,
             Status        TYPE string,
             Message       TYPE string,
             MigoDocNo     TYPE string,
             ProcessedDate TYPE string,
             ProcessedTime TYPE string,
           END OF ty_response_item.

    TYPES: BEGIN OF ty_response,
             Header  TYPE string,
             ZMATSet TYPE STANDARD TABLE OF ty_response_item WITH DEFAULT KEY,
           END OF ty_response.

    METHODS: process_migo_via_rap
      IMPORTING iv_json_payload TYPE string
      RETURNING VALUE(rv_response) TYPE string.

ENDCLASS.

CLASS zcl_rest_migo_rap_handler IMPLEMENTATION.

  METHOD if_rest_resource~post.
    DATA: lv_request_body TYPE string,
          lv_response     TYPE string.

    " Get the request body
    DATA(lo_entity) = mo_request->get_entity( ).
    IF lo_entity IS BOUND.
      lv_request_body = lo_entity->get_string_data( ).
    ENDIF.

    IF lv_request_body IS INITIAL.
      mo_response->create_entity( )->set_string_data( 
        '{"error": "Request body is empty"}' ).
      mo_response->set_status( cl_rest_status_code=>gc_server_error_internal ).
      RETURN.
    ENDIF.

    TRY.
        " Process the MIGO request via RAP
        lv_response = process_migo_via_rap( lv_request_body ).
        
        " Set response
        mo_response->create_entity( )->set_string_data( lv_response ).
        mo_response->set_status( cl_rest_status_code=>gc_success_ok ).
        mo_response->set_header_field( 
          name = 'Content-Type' 
          value = 'application/json' ).

      CATCH cx_root INTO DATA(lx_error).
        " Handle errors
        DATA(lv_error_response) = |{{ "error": "{ lx_error->get_text( ) }" }}|.
        mo_response->create_entity( )->set_string_data( lv_error_response ).
        mo_response->set_status( cl_rest_status_code=>gc_server_error_internal ).
    ENDTRY.

  ENDMETHOD.

  METHOD process_migo_via_rap.
    DATA: ls_request     TYPE ty_request,
          ls_response    TYPE ty_response,
          lv_request_id  TYPE string,
          lt_items_create TYPE TABLE FOR CREATE ZI_MIGO_BATCH_POSTING\_Items.

    " Deserialize JSON request
    /ui2/cl_json=>deserialize(
      EXPORTING
        json = iv_json_payload
        pretty_name = /ui2/cl_json=>pretty_mode-camel_case
      CHANGING
        data = ls_request
    ).

    " Generate unique request ID
    CALL FUNCTION 'GUID_CREATE'
      IMPORTING
        ev_guid_16 = DATA(lv_guid).
    
    lv_request_id = lv_guid.

    " Prepare items for creation
    DATA(lv_item_sequence) = 0.
    LOOP AT ls_request-ZMATSet INTO DATA(ls_item).
      lv_item_sequence = lv_item_sequence + 1.
      
      APPEND VALUE #( 
        %cid = |{ lv_item_sequence }|
        RequestId = lv_request_id
        ItemSequence = lv_item_sequence
        GrGiSlipNo = ls_item-GrGiSlipNo
        ZtypeGm = ls_item-ZtypeGm
        ZsubType = ls_item-ZsubType
        Movementtype = ls_item-Movementtype
        DocDate = ls_item-DocDate
        PstngDate = ls_item-PstngDate
        HeaderTxt = ls_item-HeaderTxt
        ItemNo = ls_item-ItemNo
        Material = ls_item-Material
        MatDesc = ls_item-MatDesc
        BaseUom = ls_item-BaseUom
        Quantity = ls_item-Quantity
        StrgLoc = ls_item-StrgLoc
        Plant = ls_item-Plant
        GlAccount = ls_item-GlAccount
        Costcenter = ls_item-Costcenter
        OrderNo = ls_item-OrderNo
        ItemOk = ls_item-ItemOk
      ) TO lt_items_create.
    ENDLOOP.

    " Create the deep entity via RAP
    MODIFY ENTITIES OF ZI_MIGO_BATCH_POSTING
      ENTITY MigoBatchPosting
      CREATE FIELDS ( RequestId Header )
      WITH VALUE #( ( %cid = 'ROOT'
                      RequestId = lv_request_id
                      Header = ls_request-Header ) )
      CREATE BY \_Items
      FIELDS ( RequestId ItemSequence GrGiSlipNo ZtypeGm ZsubType Movementtype
               DocDate PstngDate HeaderTxt ItemNo Material MatDesc BaseUom
               Quantity StrgLoc Plant GlAccount Costcenter OrderNo ItemOk )
      WITH VALUE #( ( %cid_ref = 'ROOT'
                      %target = lt_items_create ) )
    MAPPED   DATA(ls_mapped)
    FAILED   DATA(ls_failed)
    REPORTED DATA(ls_reported).

    " Execute the action to process MIGO
    IF ls_failed IS INITIAL.
      MODIFY ENTITIES OF ZI_MIGO_BATCH_POSTING
        ENTITY MigoBatchPosting
        EXECUTE processMigoPosting
        FROM VALUE #( ( %cid_ref = 'ROOT' ) )
      MAPPED   DATA(ls_action_mapped)
      FAILED   DATA(ls_action_failed)
      REPORTED DATA(ls_action_reported).

      " Read the result
      READ ENTITIES OF ZI_MIGO_BATCH_POSTING
        ENTITY MigoBatchPosting
        ALL FIELDS WITH VALUE #( ( %cid_ref = 'ROOT' ) )
        RESULT DATA(lt_result_headers)
        ENTITY MigoBatchPosting BY \_Items
        ALL FIELDS WITH VALUE #( ( %cid_ref = 'ROOT' ) )
        RESULT DATA(lt_result_items).

      " Prepare response
      ls_response-Header = ls_request-Header.
      
      LOOP AT lt_result_items INTO DATA(ls_result_item).
        APPEND VALUE #( 
          GrGiSlipNo = ls_result_item-GrGiSlipNo
          Status = ls_result_item-Status
          Message = ls_result_item-Message
          MigoDocNo = ls_result_item-MigoDocNo
          ProcessedDate = |{ ls_result_item-DocDate DATE = ISO }|
          ProcessedTime = |{ sy-uzeit TIME = ISO }|
        ) TO ls_response-ZMATSet.
      ENDLOOP.

    ELSE.
      " Handle creation errors
      ls_response-Header = ls_request-Header.
      APPEND VALUE #( 
        Status = 'ERROR'
        Message = 'Failed to create RAP entity'
      ) TO ls_response-ZMATSet.
    ENDIF.

    " Serialize response to JSON
    rv_response = /ui2/cl_json=>serialize(
      data = ls_response
      pretty_name = /ui2/cl_json=>pretty_mode-camel_case
    ).

  ENDMETHOD.

ENDCLASS.