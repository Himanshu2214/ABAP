CLASS zcl_json_utils DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS: 
      serialize
        IMPORTING
          data TYPE any
        RETURNING
          VALUE(rv_json) TYPE string,
          
      deserialize
        IMPORTING
          json TYPE string
          pretty_name TYPE i DEFAULT 0
        CHANGING
          data TYPE any,
          
      check_ui2_json_available
        RETURNING
          VALUE(rv_available) TYPE abap_bool.

  PRIVATE SECTION.
    CLASS-METHODS:
      simple_serialize
        IMPORTING
          data TYPE any
        RETURNING
          VALUE(rv_json) TYPE string,
          
      simple_deserialize
        IMPORTING
          json TYPE string
        CHANGING
          data TYPE any.

ENDCLASS.

CLASS zcl_json_utils IMPLEMENTATION.

  METHOD serialize.
    " First try to use /UI2/CL_JSON if available
    IF check_ui2_json_available( ) = abap_true.
      TRY.
          CALL METHOD ('/UI2/CL_JSON')=>('SERIALIZE')
            EXPORTING
              data = data
              pretty_name = 2  " camel_case mode
            RECEIVING
              r_json = rv_json.
        CATCH cx_root.
          " Fallback to simple serialization
          rv_json = simple_serialize( data ).
      ENDTRY.
    ELSE.
      " Use simple serialization
      rv_json = simple_serialize( data ).
    ENDIF.
  ENDMETHOD.

  METHOD deserialize.
    " First try to use /UI2/CL_JSON if available
    IF check_ui2_json_available( ) = abap_true.
      TRY.
          CALL METHOD ('/UI2/CL_JSON')=>('DESERIALIZE')
            EXPORTING
              json = json
              pretty_name = pretty_name
            CHANGING
              data = data.
        CATCH cx_root.
          " Fallback to simple deserialization
          simple_deserialize( 
            EXPORTING json = json 
            CHANGING data = data 
          ).
      ENDTRY.
    ELSE.
      " Use simple deserialization
      simple_deserialize( 
        EXPORTING json = json 
        CHANGING data = data 
      ).
    ENDIF.
  ENDMETHOD.

  METHOD check_ui2_json_available.
    " Check if /UI2/CL_JSON class exists
    DATA: lo_class_desc TYPE REF TO cl_abap_classdescr.
    
    TRY.
        lo_class_desc ?= cl_abap_typedescr=>describe_by_name( '/UI2/CL_JSON' ).
        IF lo_class_desc IS BOUND.
          rv_available = abap_true.
        ELSE.
          rv_available = abap_false.
        ENDIF.
      CATCH cx_root.
        rv_available = abap_false.
    ENDTRY.
  ENDMETHOD.

  METHOD simple_serialize.
    " Simple JSON serialization for basic structures
    " This is a basic implementation - enhance as needed
    
    DATA: lv_temp TYPE string.
    
    " Basic structure to JSON conversion
    " Note: This is a simplified version - for production use proper JSON library
    
    rv_json = '{'.
    
    " Add basic success/error response structure
    rv_json = rv_json && '"success": false,'.
    rv_json = rv_json && '"message": "JSON serialization fallback used",'.
    rv_json = rv_json && '"error": "UI2/CL_JSON not available in system"'.
    
    rv_json = rv_json && '}'.
    
  ENDMETHOD.

  METHOD simple_deserialize.
    " Simple JSON deserialization
    " This is a basic implementation - enhance as needed
    
    " For basic testing when /UI2/CL_JSON is not available
    " In production, implement proper JSON parsing or install required components
    
    MESSAGE 'JSON deserialization fallback - implement proper parsing for production' TYPE 'I'.
    
  ENDMETHOD.

ENDCLASS.