CLASS zcl_test_migo_api DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS: test_migo_posting,
             test_json_parsing,
             test_date_conversion.

  PRIVATE SECTION.
    DATA: mo_migo_api TYPE REF TO zcl_migo_posting_improved.

ENDCLASS.

CLASS zcl_test_migo_api IMPLEMENTATION.

  METHOD test_migo_posting.
    " Sample test payload
    DATA: lv_test_payload TYPE string,
          lv_response     TYPE string.

    lv_test_payload = 
    '[' &&
    '  {' &&
    '    "ZtypeGm": "A007",' &&
    '    "ZsubType": "R10",' &&
    '    "Movementtype": "963",' &&
    '    "DocDate": "/Date(1750099200000)/",' &&
    '    "PstngDate": "/Date(1750099200000)/",' &&
    '    "GrGiSlipNo": "TEST001",' &&
    '    "HeaderTxt": "Test MIGO Posting",' &&
    '    "HeaderToItemNav": [' &&
    '      {' &&
    '        "Material": "000000000000000001",' &&
    '        "Plant": "1000",' &&
    '        "StgeLoc": "0001",' &&
    '        "EntryQnt": "1",' &&
    '        "EntryUom": "EA"' &&
    '      }' &&
    '    ]' &&
    '  }' &&
    ']'.

    CREATE OBJECT mo_migo_api.
    
    TRY.
        lv_response = mo_migo_api->post_migo( lv_test_payload ).
        
        WRITE: / 'Test Response:', lv_response.
        
      CATCH cx_root INTO DATA(lx_error).
        WRITE: / 'Error during test:', lx_error->get_text( ).
    ENDTRY.

  ENDMETHOD.

  METHOD test_json_parsing.
    " Test JSON deserialization
    DATA: lv_test_json TYPE string,
          lt_headers   TYPE zcl_migo_posting_improved=>tt_migo_header.

    lv_test_json = 
    '[' &&
    '  {' &&
    '    "ZtypeGm": "A007",' &&
    '    "ZsubType": "R10",' &&
    '    "Movementtype": "963",' &&
    '    "DocDate": "/Date(1750099200000)/",' &&
    '    "PstngDate": "/Date(1750099200000)/",' &&
    '    "GrGiSlipNo": "TEST001",' &&
    '    "HeaderTxt": "Test Header",' &&
    '    "HeaderToItemNav": [' &&
    '      {' &&
    '        "Material": "TEST001",' &&
    '        "Plant": "1000",' &&
    '        "StgeLoc": "0001",' &&
    '        "EntryQnt": "1",' &&
    '        "EntryUom": "EA"' &&
    '      }' &&
    '    ]' &&
    '  }' &&
    ']'.

    TRY.
        /ui2/cl_json=>deserialize(
          EXPORTING
            json = lv_test_json
            pretty_name = /ui2/cl_json=>pretty_mode-camel_case
          CHANGING
            data = lt_headers
        ).

        READ TABLE lt_headers INTO DATA(ls_header) INDEX 1.
        IF sy-subrc = 0.
          WRITE: / 'JSON Parsing Successful'.
          WRITE: / 'Movement Type:', ls_header-movementtype.
          WRITE: / 'Header Text:', ls_header-headertxt.
          WRITE: / 'Number of Items:', lines( ls_header-headertoitemnav ).
        ENDIF.

      CATCH cx_root INTO DATA(lx_json).
        WRITE: / 'JSON Parsing Error:', lx_json->get_text( ).
    ENDTRY.

  ENDMETHOD.

  METHOD test_date_conversion.
    " Test date conversion functionality
    CREATE OBJECT mo_migo_api.
    
    " Test various date formats
    DATA: lv_test_date1 TYPE string VALUE '/Date(1750099200000)/',
          lv_test_date2 TYPE string VALUE '/Date(1640995200000)/',
          lv_result1    TYPE dats,
          lv_result2    TYPE dats.

    " Note: This would require making convert_odata_date public or creating a wrapper
    " For testing purposes, we can test the overall functionality
    
    WRITE: / 'Date conversion test would be performed here'.
    WRITE: / 'Input date 1:', lv_test_date1.
    WRITE: / 'Input date 2:', lv_test_date2.

  ENDMETHOD.

ENDCLASS.