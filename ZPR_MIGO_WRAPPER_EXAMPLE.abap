REPORT zpr_migo_wrapper_example.

*----------------------------------------------------------------------*
* Example program to demonstrate usage of ZCL_MIGO_DEEP_ENTITY_WRAPPER
* This program shows how to:
* 1. Prepare multiple header data with items
* 2. Send data via the wrapper class
* 3. Process the responses including MIGO numbers
*----------------------------------------------------------------------*

DATA: lo_wrapper TYPE REF TO zcl_migo_deep_entity_wrapper,
      lt_headers TYPE zcl_migo_deep_entity_wrapper=>tt_headers,
      lt_responses TYPE zcl_migo_deep_entity_wrapper=>tt_responses,
      ls_header TYPE zcl_migo_deep_entity_wrapper=>ty_header,
      ls_item TYPE zcl_migo_deep_entity_wrapper=>ty_header_item,
      ls_response TYPE zcl_migo_deep_entity_wrapper=>ty_response.

START-OF-SELECTION.

  " Initialize the wrapper class
  CREATE OBJECT lo_wrapper
    EXPORTING
      iv_service_url = 'http://your-sap-server:8000/sap/opu/odata/sap/ZMM_MIGO_SRV/'
      iv_username    = 'your_username'
      iv_password    = 'your_password'.

  " Prepare first header with items
  CLEAR: ls_header.
  ls_header-ztype_gm = 'A007'.
  ls_header-zsub_type = 'R10'.
  ls_header-movement_type = '963'.
  ls_header-doc_date = sy-datum.
  ls_header-pstng_date = sy-datum.
  ls_header-gr_gi_slip_no = 'GI407'.
  ls_header-header_txt = 'Text Header 1'.

  " Add items to first header
  CLEAR: ls_item.
  ls_item-material = '50000001'.
  ls_item-plant = '1000'.
  ls_item-stge_loc = '0001'.
  ls_item-entry_qnt = '10.000'.
  ls_item-entry_uom = 'EA'.
  APPEND ls_item TO ls_header-header_to_item_nav.

  CLEAR: ls_item.
  ls_item-material = '50000002'.
  ls_item-plant = '1000'.
  ls_item-stge_loc = '0001'.
  ls_item-entry_qnt = '5.000'.
  ls_item-entry_uom = 'EA'.
  APPEND ls_item TO ls_header-header_to_item_nav.

  APPEND ls_header TO lt_headers.

  " Prepare second header with items
  CLEAR: ls_header.
  ls_header-ztype_gm = 'A007'.
  ls_header-zsub_type = 'R10'.
  ls_header-movement_type = '963'.
  ls_header-doc_date = sy-datum.
  ls_header-pstng_date = sy-datum.
  ls_header-gr_gi_slip_no = 'GI408'.
  ls_header-header_txt = 'Text Header 2'.

  " Add items to second header
  CLEAR: ls_item.
  ls_item-material = '50000003'.
  ls_item-plant = '1000'.
  ls_item-stge_loc = '0001'.
  ls_item-entry_qnt = '8.000'.
  ls_item-entry_uom = 'EA'.
  APPEND ls_item TO ls_header-header_to_item_nav.

  CLEAR: ls_item.
  ls_item-material = '50000004'.
  ls_item-plant = '1000'.
  ls_item-stge_loc = '0001'.
  ls_item-entry_qnt = '12.000'.
  ls_item-entry_uom = 'EA'.
  APPEND ls_item TO ls_header-header_to_item_nav.

  APPEND ls_header TO lt_headers.

  " Post the headers and get responses
  TRY.
    lt_responses = lo_wrapper->post_multiple_headers( lt_headers ).

    " Process responses
    WRITE: / 'Response Summary:',
           / '================'.

    LOOP AT lt_responses INTO ls_response.
      WRITE: / 'Header ID:', ls_response-header_id,
             / 'MIGO Number:', ls_response-migo_number,
             / 'Fiscal Year:', ls_response-fiscal_year,
             / 'Success:', COND #( WHEN ls_response-success = abap_true THEN 'YES' ELSE 'NO' ),
             / 'Message:', ls_response-message,
             / '-----------------------------------'.

      " Process response items if any
      LOOP AT ls_response-response_items INTO DATA(ls_resp_item).
        WRITE: / '  Item - Material:', ls_resp_item-material,
               / '         Plant:', ls_resp_item-plant,
               / '         MIGO Number:', ls_resp_item-migo_number,
               / '         Message:', ls_resp_item-message.
      ENDLOOP.
    ENDLOOP.

    " Display JSON that was sent (for debugging)
    DATA: lv_json TYPE string.
    lv_json = lo_wrapper->convert_to_json( lt_headers ).
    
    WRITE: / '',
           / 'JSON Payload Sent:',
           / '==================',
           / lv_json.

  CATCH cx_sy_exception INTO DATA(lx_exception).
    WRITE: / 'Error occurred:', lx_exception->get_text( ).
  ENDTRY.