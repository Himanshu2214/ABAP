CLASS zcl_test_migo_odata_service DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Test methods
    METHODS: test_single_migo_posting,
             test_multiple_migo_posting,
             test_invalid_payload,
             run_all_tests.

  PRIVATE SECTION.
    " Helper methods
    METHODS: get_single_payload
      RETURNING
        VALUE(rv_payload) TYPE string,

      get_multiple_payload
        RETURNING
          VALUE(rv_payload) TYPE string,

      get_invalid_payload
        RETURNING
          VALUE(rv_payload) TYPE string,

      execute_test
        IMPORTING
          iv_test_name TYPE string
          iv_payload TYPE string.

ENDCLASS.

CLASS zcl_test_migo_odata_service IMPLEMENTATION.

  METHOD run_all_tests.
    " Execute all test methods
    WRITE: / 'Starting MIGO OData Service Tests'.
    WRITE: / '===================================='.
    
    test_single_migo_posting( ).
    test_multiple_migo_posting( ).
    test_invalid_payload( ).
    
    WRITE: / '===================================='.
    WRITE: / 'All tests completed'.
  ENDMETHOD.

  METHOD test_single_migo_posting.
    " Test with single MIGO document
    DATA: lv_payload TYPE string.
    
    lv_payload = get_single_payload( ).
    execute_test(
      iv_test_name = 'Single MIGO Posting'
      iv_payload = lv_payload
    ).
  ENDMETHOD.

  METHOD test_multiple_migo_posting.
    " Test with multiple MIGO documents
    DATA: lv_payload TYPE string.
    
    lv_payload = get_multiple_payload( ).
    execute_test(
      iv_test_name = 'Multiple MIGO Posting'
      iv_payload = lv_payload
    ).
  ENDMETHOD.

  METHOD test_invalid_payload.
    " Test with invalid payload
    DATA: lv_payload TYPE string.
    
    lv_payload = get_invalid_payload( ).
    execute_test(
      iv_test_name = 'Invalid Payload Test'
      iv_payload = lv_payload
    ).
  ENDMETHOD.

  METHOD get_single_payload.
    " Return single MIGO document payload
    rv_payload = '{' &&
                 '"ZtypeGm": "A007",' &&
                 '"ZsubType": "R10",' &&
                 '"Movementtype": "963",' &&
                 '"DocDate": "/Date(1750099200000)/",' &&
                 '"PstngDate": "/Date(1750099200000)/",' &&
                 '"GrGiSlipNo": "GI602",' &&
                 '"HeaderTxt": "Header Post 1",' &&
                 '"GoodsMvtItemSet": [' &&
                 '{' &&
                 '"Material": "50045456",' &&
                 '"ItemNo": "000001",' &&
                 '"MatDesc": "Item A1",' &&
                 '"BaseUom": "EA",' &&
                 '"Quantity": 2,' &&
                 '"StrgLoc": "1081",' &&
                 '"Plant": "4000",' &&
                 '"GlAccount": "44041012",' &&
                 '"Costcenter": "40010002",' &&
                 '"OrderNo": "100129",' &&
                 '"ItemOk": true' &&
                 '}' &&
                 ']' &&
                 '}'.
  ENDMETHOD.

  METHOD get_multiple_payload.
    " Return multiple MIGO documents payload
    rv_payload = '[' &&
                 '{' &&
                 '"ZtypeGm": "A007",' &&
                 '"ZsubType": "R10",' &&
                 '"Movementtype": "963",' &&
                 '"DocDate": "/Date(1750099200000)/",' &&
                 '"PstngDate": "/Date(1750099200000)/",' &&
                 '"GrGiSlipNo": "GI602",' &&
                 '"HeaderTxt": "Header Post 1",' &&
                 '"GoodsMvtItemSet": [' &&
                 '{' &&
                 '"Material": "50045456",' &&
                 '"ItemNo": "000001",' &&
                 '"MatDesc": "Item A1",' &&
                 '"BaseUom": "EA",' &&
                 '"Quantity": 2,' &&
                 '"StrgLoc": "1081",' &&
                 '"Plant": "4000",' &&
                 '"GlAccount": "44041012",' &&
                 '"Costcenter": "40010002",' &&
                 '"OrderNo": "100129",' &&
                 '"ItemOk": true' &&
                 '}' &&
                 ']' &&
                 '},' &&
                 '{' &&
                 '"ZtypeGm": "A007",' &&
                 '"ZsubType": "R10",' &&
                 '"Movementtype": "963",' &&
                 '"DocDate": "/Date(1750099200000)/",' &&
                 '"PstngDate": "/Date(1750099200000)/",' &&
                 '"GrGiSlipNo": "GI603",' &&
                 '"HeaderTxt": "Header Post 2",' &&
                 '"GoodsMvtItemSet": [' &&
                 '{' &&
                 '"Material": "50045457",' &&
                 '"ItemNo": "000001",' &&
                 '"MatDesc": "Item A2",' &&
                 '"BaseUom": "EA",' &&
                 '"Quantity": 3,' &&
                 '"StrgLoc": "1081",' &&
                 '"Plant": "4000",' &&
                 '"GlAccount": "44041012",' &&
                 '"Costcenter": "40010002",' &&
                 '"OrderNo": "100130",' &&
                 '"ItemOk": true' &&
                 '}' &&
                 ']' &&
                 '}' &&
                 ']'.
  ENDMETHOD.

  METHOD get_invalid_payload.
    " Return invalid JSON payload
    rv_payload = '{' &&
                 '"ZtypeGm": "A007",' &&
                 '"ZsubType": "R10",' &&
                 '"Movementtype": "963",' &&
                 '"DocDate": "/Date(1750099200000)/",' &&
                 '"PstngDate": "/Date(1750099200000)/",' &&
                 '"GrGiSlipNo": "GI602",' &&
                 '"HeaderTxt": "Header Post 1",' &&
                 '"GoodsMvtItemSet": [' &&
                 '{' &&
                 '"Material": "50045456",' &&
                 '"ItemNo": "000001",' &&
                 '"MatDesc": "Item A1",' &&
                 '"BaseUom": "EA",' &&
                 '"Quantity": 2,' &&
                 '"StrgLoc": "1081",' &&
                 '"Plant": "4000",' &&
                 '"GlAccount": "44041012",' &&
                 '"Costcenter": "40010002",' &&
                 '"OrderNo": "100129",' &&
                 '"ItemOk": true' &&
                 '}' &&
                 ']'.  " Missing closing brace - invalid JSON
  ENDMETHOD.

  METHOD execute_test.
    DATA: lo_processor TYPE REF TO zcl_migo_posting_enhanced,
          lv_response TYPE string.

    WRITE: / |Test: { iv_test_name }|.
    WRITE: / '----------------------------------------'.

    TRY.
        " Create processor instance
        CREATE OBJECT lo_processor.

        " Execute the test
        lv_response = lo_processor->process_migo_posting( iv_payload ).

        " Display results
        WRITE: / 'Request Payload:'.
        WRITE: / iv_payload.
        WRITE: / 'Response:'.
        WRITE: / lv_response.
        WRITE: / 'Status: SUCCESS'.

      CATCH cx_root INTO DATA(lx_error).
        WRITE: / 'Status: ERROR'.
        WRITE: / 'Error Message:', lx_error->get_text( ).
    ENDTRY.

    WRITE: / '----------------------------------------'.
    WRITE: /.

  ENDMETHOD.

ENDCLASS.

" Report to execute the tests
REPORT z_test_migo_odata.

START-OF-SELECTION.
  DATA: lo_test TYPE REF TO zcl_test_migo_odata_service.
  
  CREATE OBJECT lo_test.
  lo_test->run_all_tests( ).

" Example of how to call the service programmatically
FORM test_service_call.
  DATA: lo_dpc_ext TYPE REF TO zcl_zgw_migo_dpc_ext,
        lr_entity_in TYPE REF TO data,
        lr_entity_out TYPE REF TO data,
        ls_test_entity TYPE zcl_zgw_migo_mpc=>ts_migodocument.

  " Create test entity
  ls_test_entity-requestid = '12345'.
  ls_test_entity-payload = '{
    "ZtypeGm": "A007",
    "ZsubType": "R10",
    "Movementtype": "963",
    "DocDate": "/Date(1750099200000)/",
    "PstngDate": "/Date(1750099200000)/",
    "GrGiSlipNo": "GI602",
    "HeaderTxt": "Header Post 1",
    "GoodsMvtItemSet": [
      {
        "Material": "50045456",
        "ItemNo": "000001",
        "MatDesc": "Item A1",
        "BaseUom": "EA",
        "Quantity": 2,
        "StrgLoc": "1081",
        "Plant": "4000",
        "GlAccount": "44041012",
        "Costcenter": "40010002",
        "OrderNo": "100129",
        "ItemOk": true
      }
    ]
  }'.

  " Create data references
  CREATE DATA lr_entity_in TYPE zcl_zgw_migo_mpc=>ts_migodocument.
  ASSIGN lr_entity_in->* TO FIELD-SYMBOL(<ls_entity_in>).
  <ls_entity_in> = ls_test_entity.

  TRY.
      " Create DPC extension instance
      CREATE OBJECT lo_dpc_ext.

      " Call the create method
      lr_entity_out = lo_dpc_ext->migodocumentset_create_entity( lr_entity_in ).

      " Display result
      ASSIGN lr_entity_out->* TO FIELD-SYMBOL(<ls_entity_out>).
      
      WRITE: / 'Service Call Result:'.
      WRITE: / 'Request ID:', <ls_entity_out>-requestid.
      WRITE: / 'Success:', <ls_entity_out>-success.
      WRITE: / 'Message:', <ls_entity_out>-message.
      WRITE: / 'MIGO Number:', <ls_entity_out>-migo_number.
      WRITE: / 'GIGRNUM:', <ls_entity_out>-gigrnum.

    CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_business).
      WRITE: / 'Business Error:', lx_business->get_text( ).

    CATCH /iwbep/cx_mgw_tech_exception INTO DATA(lx_technical).
      WRITE: / 'Technical Error:', lx_technical->get_text( ).

    CATCH cx_root INTO DATA(lx_general).
      WRITE: / 'General Error:', lx_general->get_text( ).
  ENDTRY.

ENDFORM.