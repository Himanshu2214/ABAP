METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  DATA: lv_entity_set_name TYPE string,
        lv_entity_name     TYPE string.

  " Get entity information  
  lv_entity_set_name = io_data_provider->get_entity_set_name( ).
  lv_entity_name = io_data_provider->get_entity_type_name( ).

  " Log what we received
  MESSAGE |CREATE_DEEP_ENTITY called for: { lv_entity_set_name }| TYPE 'I'.

  " Process HeaderDummySet
  IF lv_entity_set_name = 'HeaderDummySet'.
    
    " Data structures matching your exact metadata
    DATA: ls_header_dummy TYPE zmm_migo_automation_=>ts_headerdummy,
          ls_header       TYPE zmm_migo_automation_=>ts_goodsmovementheader,
          ls_item         TYPE zmm_migo_automation_=>ts_goodsmovementitem.

    TRY.
        " Read the incoming deep entity payload
        io_data_provider->read_entry_data( IMPORTING es_data = ls_header_dummy ).

        " Test 1: Log the main dummy header
        MESSAGE |✓ Main HeaderDummy GrGiSlipNo: '{ ls_header_dummy-gr_gi_slip_no }'| TYPE 'I'.
        
        " Test 2: Check navigation to real headers  
        DATA(lv_header_count) = lines( ls_header_dummy-to_real_headers ).
        MESSAGE |✓ Found { lv_header_count } real header(s) in ToRealHeaders navigation| TYPE 'I'.

        " Test 3: Loop through each real header
        LOOP AT ls_header_dummy-to_real_headers INTO ls_header.
          
          MESSAGE |✓ Header { sy-tabix }: GrGiSlipNo='{ ls_header-gr_gi_slip_no }', Type='{ ls_header-ztype_gm }', MovType='{ ls_header-movementtype }'| TYPE 'I'.
          MESSAGE |  DocDate='{ ls_header-doc_date }', PostDate='{ ls_header-pstng_date }', HeaderTxt='{ ls_header-header_txt }'| TYPE 'I'.
          
          " Test 4: Check navigation to items
          DATA(lv_item_count) = lines( ls_header-header_to_item_nav ).
          MESSAGE |✓ Header { sy-tabix } has { lv_item_count } item(s) in HeaderToItemNav| TYPE 'I'.
          
          " Test 5: Loop through each item
          LOOP AT ls_header-header_to_item_nav INTO ls_item.
            
            MESSAGE |✓ Item { sy-tabix }: GiGiSlipNo='{ ls_item-gi_gi_slip_no }', ItemNo='{ ls_item-item_no }'| TYPE 'I'.
            MESSAGE |  Material='{ ls_item-material }', Desc='{ ls_item-mat_desc }', Qty={ ls_item-quantity } { ls_item-base_uom }| TYPE 'I'.
            MESSAGE |  Plant='{ ls_item-plant }', StrgLoc='{ ls_item-strg_loc }', ItemOk={ ls_item-item_ok }| TYPE 'I'.
            
            IF ls_item-gl_account IS NOT INITIAL.
              MESSAGE |  GL Account='{ ls_item-gl_account }', Cost Center='{ ls_item-costcenter }'| TYPE 'I'.
            ENDIF.
            
            IF ls_item-order_no IS NOT INITIAL.
              MESSAGE |  Order No='{ ls_item-order_no }'| TYPE 'I'.
            ENDIF.
            
          ENDLOOP.
          
        ENDLOOP.

        " Test 6: Create response (just echo back the input for now)
        CREATE DATA er_deep_entity TYPE zmm_migo_automation_=>ts_headerdummy.
        ASSIGN er_deep_entity->* TO FIELD-SYMBOL(<ls_response>).
        <ls_response> = ls_header_dummy.

        " Success message
        MESSAGE |✅ SUCCESS: Deep entity payload received and parsed correctly!| TYPE 'S'.
        MESSAGE |Total: { lv_header_count } headers with items processed| TYPE 'S'.

      CATCH cx_root INTO DATA(lx_error).
        
        " Log the error details
        MESSAGE |❌ ERROR in CREATE_DEEP_ENTITY: { lx_error->get_text( ) }| TYPE 'E'.
        
        " Try to get more error details
        DATA(lv_error_details) = lx_error->get_longtext( ).
        IF lv_error_details IS NOT INITIAL.
          MESSAGE |Error details: { lv_error_details }| TYPE 'E'.
        ENDIF.
        
        " Re-raise as OData exception
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
          EXPORTING
            textid = /iwbep/cx_mgw_tech_exception=>internal_error
            message = |Deep entity processing error: { lx_error->get_text( ) }|.

    ENDTRY.

  ELSE.
    " For other entity sets, call parent
    MESSAGE |Calling parent method for entity set: { lv_entity_set_name }| TYPE 'I'.
    
    CALL METHOD super->/iwbep/if_mgw_appl_srv_runtime~create_deep_entity
      EXPORTING
        io_data_provider        = io_data_provider
        it_key_tab              = it_key_tab
        it_navigation_path      = it_navigation_path
        io_expand               = io_expand
        io_tech_request_context = io_tech_request_context
      IMPORTING
        er_deep_entity          = er_deep_entity.
  ENDIF.

ENDMETHOD.

*&---------------------------------------------------------------------*
*& For your test, use this payload structure:
*&---------------------------------------------------------------------*
*" POST /sap/opu/odata/sap/ZMM_MIGO_AUTOMATION_SRV/HeaderDummySet
*" Content-Type: application/json
*"
*" {
*"   "GrGiSlipNo": "TEST001",
*"   "ToRealHeaders": [
*"     {
*"       "GrGiSlipNo": "TEST001",
*"       "ZtypeGm": "A007", 
*"       "ZsubType": "R10",
*"       "Movementtype": "963",
*"       "DocDate": "/Date(1735689600000)/",
*"       "PstngDate": "/Date(1735689600000)/",
*"       "HeaderTxt": "Test Header",
*"       "HeaderToItemNav": [
*"         {
*"           "GiGiSlipNo": "TEST001",
*"           "ItemNo": "0001",
*"           "Material": "TEST_MAT",
*"           "MatDesc": "Test Material",
*"           "BaseUom": "EA",
*"           "Quantity": "10",
*"           "StrgLoc": "0001",
*"           "Plant": "1000",
*"           "GlAccount": "500000",
*"           "Costcenter": "CC1000",
*"           "OrderNo": "",
*"           "ItemOk": true
*"         }
*"       ]
*"     }
*"   ]
*" }