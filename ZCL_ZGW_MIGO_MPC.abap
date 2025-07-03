CLASS zcl_zgw_migo_mpc DEFINITION
  PUBLIC
  INHERITING FROM /iwbep/cl_mgw_med_provider
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Entity type for MIGO Document
    TYPES: BEGIN OF ts_migodocument,
             requestid         TYPE string,
             ztypegm          TYPE string,
             zsubtype         TYPE string,
             movementtype     TYPE string,
             docdate          TYPE string,
             pstngdate        TYPE string,
             grgiSlipno       TYPE string,
             headertxt        TYPE string,
             material_document TYPE string,
             document_year    TYPE string,
             migo_number      TYPE string,
             gigrnum          TYPE string,
             success          TYPE abap_bool,
             message          TYPE string,
             payload          TYPE string,
             response         TYPE string,
             error_details    TYPE string,
           END OF ts_migodocument.

    " Table type for entity set
    TYPES: tt_migodocument TYPE STANDARD TABLE OF ts_migodocument.

    " Override method to define model
    METHODS: define REDEFINITION.

  PRIVATE SECTION.
    " Constants for entity and property names
    CONSTANTS: 
      gc_entity_type_name     TYPE string VALUE 'MigoDocument',
      gc_entity_set_name      TYPE string VALUE 'MigoDocumentSet',
      gc_service_id           TYPE string VALUE 'ZGW_MIGO_SRV',
      gc_service_version      TYPE string VALUE '0001'.

ENDCLASS.

CLASS zcl_zgw_migo_mpc IMPLEMENTATION.

  METHOD define.
    DATA: lo_entity_type   TYPE REF TO /iwbep/if_mgw_odata_entity_typ,
          lo_entity_set    TYPE REF TO /iwbep/if_mgw_odata_entity_set,
          lo_property      TYPE REF TO /iwbep/if_mgw_odata_property.

    " Call super method
    super->define( ).

    " Create entity type
    lo_entity_type = model->create_entity_type(
      iv_entity_type_name = gc_entity_type_name
      iv_def_entity_set = abap_true
      iv_entity_set_name = gc_entity_set_name
    ).

    " Define key property
    lo_property = lo_entity_type->create_property(
      iv_property_name = 'RequestId'
      iv_abap_field_name = 'REQUESTID'
    ).
    lo_property->set_is_key( ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 32 ).

    " Define other properties
    lo_property = lo_entity_type->create_property(
      iv_property_name = 'ZtypeGm'
      iv_abap_field_name = 'ZTYPEGM'
    ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 10 ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'ZsubType'
      iv_abap_field_name = 'ZSUBTYPE'
    ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 10 ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'MovementType'
      iv_abap_field_name = 'MOVEMENTTYPE'
    ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 3 ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'DocDate'
      iv_abap_field_name = 'DOCDATE'
    ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 50 ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'PstngDate'
      iv_abap_field_name = 'PSTNGDATE'
    ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 50 ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'GrGiSlipNo'
      iv_abap_field_name = 'GRGISLIPNO'
    ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 20 ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'HeaderTxt'
      iv_abap_field_name = 'HEADERTXT'
    ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 50 ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'MaterialDocument'
      iv_abap_field_name = 'MATERIAL_DOCUMENT'
    ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 20 ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'DocumentYear'
      iv_abap_field_name = 'DOCUMENT_YEAR'
    ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 4 ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'MigoNumber'
      iv_abap_field_name = 'MIGO_NUMBER'
    ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 20 ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'Gigrnum'
      iv_abap_field_name = 'GIGRNUM'
    ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 20 ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'Success'
      iv_abap_field_name = 'SUCCESS'
    ).
    lo_property->set_type_edm_boolean( ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'Message'
      iv_abap_field_name = 'MESSAGE'
    ).
    lo_property->set_type_edm_string( ).
    lo_property->set_maxlength( 255 ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'Payload'
      iv_abap_field_name = 'PAYLOAD'
    ).
    lo_property->set_type_edm_string( ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'Response'
      iv_abap_field_name = 'RESPONSE'
    ).
    lo_property->set_type_edm_string( ).

    lo_property = lo_entity_type->create_property(
      iv_property_name = 'ErrorDetails'
      iv_abap_field_name = 'ERROR_DETAILS'
    ).
    lo_property->set_type_edm_string( ).

    " Get entity set reference
    lo_entity_set = model->get_entity_set( gc_entity_set_name ).
    
    " Set entity set properties
    lo_entity_set->set_creatable( abap_true ).
    lo_entity_set->set_updatable( abap_false ).
    lo_entity_set->set_deletable( abap_false ).
    lo_entity_set->set_pageable( abap_false ).
    lo_entity_set->set_addressable( abap_true ).
    lo_entity_set->set_has_ftxt_search( abap_false ).

  ENDMETHOD.

ENDCLASS.