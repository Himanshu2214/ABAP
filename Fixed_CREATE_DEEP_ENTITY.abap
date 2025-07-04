METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  " Alternative approach - check the navigation path or use different methods
  DATA: lv_entity_set_name TYPE string,
        lv_entity_name     TYPE string.

  TRY.
      " Try different ways to get entity information
      
      " Method 1: Try through tech request context
      IF io_tech_request_context IS BOUND.
        lv_entity_set_name = io_tech_request_context->get_entity_set_name( ).
        lv_entity_name = io_tech_request_context->get_entity_type_name( ).
      ENDIF.
      
      " Method 2: If above doesn't work, try data provider methods with different names
      IF lv_entity_set_name IS INITIAL.
        TRY.
            " These might be the correct method names in your version
            lv_entity_set_name = io_data_provider->get_entityset_name( ).
          CATCH cx_root.
            " If this fails too, we'll handle it below
        ENDTRY.
      ENDIF.
      
      " Log what we got
      MESSAGE |Entity Set Name: '{ lv_entity_set_name }'| TYPE 'I'.
      MESSAGE |Entity Type Name: '{ lv_entity_name }'| TYPE 'I'.

    CATCH cx_root INTO DATA(lx_error).
      MESSAGE |Error getting entity info: { lx_error->get_text( ) }| TYPE 'W'.
  ENDTRY.

  " For HeaderDummySet processing - try direct approach
  " Since we know we're working with HeaderDummySet, let's try to read the data directly
  
  " Data structures matching your exact metadata
  DATA: ls_header_dummy TYPE zmm_migo_automation_=>ts_headerdummy,
        ls_header       TYPE zmm_migo_automation_=>ts_goodsmovementheader,
        ls_item         TYPE zmm_migo_automation_=>ts_goodsmovementitem.

  TRY.
      " Direct attempt to read deep entity data
      MESSAGE 'Attempting to read deep entity data...' TYPE 'I'.
      
      io_data_provider->read_entry_data( IMPORTING es_data = ls_header_dummy ).

      " Test 1: Log the main dummy header
      MESSAGE |✓ SUCCESS: Read HeaderDummy with GrGiSlipNo: '{ ls_header_dummy-gr_gi_slip_no }'| TYPE 'S'.
      
      " Test 2: Check navigation to real headers  
      DATA(lv_header_count) = lines( ls_header_dummy-to_real_headers ).
      MESSAGE |✓ Found { lv_header_count } real header(s) in ToRealHeaders navigation| TYPE 'I'.

      " Test 3: Loop through each real header
      LOOP AT ls_header_dummy-to_real_headers INTO ls_header.
        
        MESSAGE |✓ Header { sy-tabix }: GrGiSlipNo='{ ls_header-gr_gi_slip_no }'| TYPE 'I'.
        MESSAGE |  ZtypeGm='{ ls_header-ztype_gm }', ZsubType='{ ls_header-zsub_type }'| TYPE 'I'.
        MESSAGE |  Movementtype='{ ls_header-movementtype }', HeaderTxt='{ ls_header-header_txt }'| TYPE 'I'.
        MESSAGE |  DocDate='{ ls_header-doc_date }', PstngDate='{ ls_header-pstng_date }'| TYPE 'I'.
        
        " Test 4: Check navigation to items
        DATA(lv_item_count) = lines( ls_header-header_to_item_nav ).
        MESSAGE |✓ Header { sy-tabix } has { lv_item_count } item(s) in HeaderToItemNav| TYPE 'I'.
        
        " Test 5: Loop through each item
        LOOP AT ls_header-header_to_item_nav INTO ls_item.
          
          MESSAGE |✓ Item { sy-tabix }: GiGiSlipNo='{ ls_item-gi_gi_slip_no }', ItemNo='{ ls_item-item_no }'| TYPE 'I'.
          MESSAGE |  Material='{ ls_item-material }', MatDesc='{ ls_item-mat_desc }'| TYPE 'I'.
          MESSAGE |  Quantity={ ls_item-quantity } { ls_item-base_uom }, Plant='{ ls_item-plant }'| TYPE 'I'.
          MESSAGE |  StrgLoc='{ ls_item-strg_loc }', ItemOk={ ls_item-item_ok }| TYPE 'I'.
          
          IF ls_item-gl_account IS NOT INITIAL.
            MESSAGE |  GlAccount='{ ls_item-gl_account }', Costcenter='{ ls_item-costcenter }'| TYPE 'I'.
          ENDIF.
          
          IF ls_item-order_no IS NOT INITIAL.
            MESSAGE |  OrderNo='{ ls_item-order_no }'| TYPE 'I'.
          ENDIF.
          
        ENDLOOP.
        
      ENDLOOP.

      " Test 6: Create response (echo back the input)
      CREATE DATA er_deep_entity TYPE zmm_migo_automation_=>ts_headerdummy.
      ASSIGN er_deep_entity->* TO FIELD-SYMBOL(<ls_response>).
      <ls_response> = ls_header_dummy.

      " Final success message
      MESSAGE |🎉 COMPLETE SUCCESS: Deep entity processed!| TYPE 'S'.
      MESSAGE |Summary: { lv_header_count } headers processed with all items| TYPE 'S'.

    CATCH cx_sy_move_cast_error INTO DATA(lx_cast_error).
      MESSAGE |❌ Data structure mismatch: { lx_cast_error->get_text( ) }| TYPE 'E'.
      MESSAGE 'Check if entity type names match your generated classes' TYPE 'E'.
      
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
        EXPORTING
          textid = /iwbep/cx_mgw_tech_exception=>internal_error
          message = |Data structure error: { lx_cast_error->get_text( ) }|.

    CATCH cx_root INTO DATA(lx_error).
      
      MESSAGE |❌ ERROR in CREATE_DEEP_ENTITY: { lx_error->get_text( ) }| TYPE 'E'.
      
      " Get class name to help debug
      DATA(lv_class_name) = cl_abap_typedescr=>describe_by_object_ref( lx_error )->get_relative_name( ).
      MESSAGE |Error class: { lv_class_name }| TYPE 'E'.
      
      " Try to get more details
      TRY.
          DATA(lv_error_details) = lx_error->get_longtext( ).
          IF lv_error_details IS NOT INITIAL.
            MESSAGE |Error details: { lv_error_details }| TYPE 'E'.
          ENDIF.
        CATCH cx_root.
          " Ignore if we can't get details
      ENDTRY.
      
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
        EXPORTING
          textid = /iwbep/cx_mgw_tech_exception=>internal_error
          message = |Deep entity error: { lx_error->get_text( ) }|.

  ENDTRY.

ENDMETHOD.

*&---------------------------------------------------------------------*
*& Test with this exact payload structure:
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