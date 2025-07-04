METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  " Simple approach - just read the data directly
  DATA: ls_header_dummy TYPE zmm_migo_automation_=>ts_headerdummy,
        ls_header       TYPE zmm_migo_automation_=>ts_goodsmovementheader,
        ls_item         TYPE zmm_migo_automation_=>ts_goodsmovementitem.

  MESSAGE 'CREATE_DEEP_ENTITY method called - starting data read...' TYPE 'I'.

  TRY.
      " Read the incoming deep entity payload
      io_data_provider->read_entry_data( IMPORTING es_data = ls_header_dummy ).

      " Test 1: Check main header
      MESSAGE |✓ Main GrGiSlipNo: '{ ls_header_dummy-gr_gi_slip_no }'| TYPE 'I'.
      
      " Test 2: Count headers  
      DATA(lv_header_count) = lines( ls_header_dummy-to_real_headers ).
      MESSAGE |✓ Headers found: { lv_header_count }| TYPE 'I'.

      " Test 3: Loop through headers
      LOOP AT ls_header_dummy-to_real_headers INTO ls_header.
        
        MESSAGE |Header { sy-tabix }: GrGiSlipNo={ ls_header-gr_gi_slip_no }, MovType={ ls_header-movementtype }| TYPE 'I'.
        MESSAGE |  ZtypeGm={ ls_header-ztype_gm }, ZsubType={ ls_header-zsub_type }| TYPE 'I'.
        MESSAGE |  HeaderTxt={ ls_header-header_txt }| TYPE 'I'.
        
        " Test 4: Count items
        DATA(lv_item_count) = lines( ls_header-header_to_item_nav ).
        MESSAGE |  Items in header { sy-tabix }: { lv_item_count }| TYPE 'I'.
        
        " Test 5: Loop through items
        LOOP AT ls_header-header_to_item_nav INTO ls_item.
          
          MESSAGE |  Item { sy-tabix }: GiGiSlipNo={ ls_item-gi_gi_slip_no }, ItemNo={ ls_item-item_no }| TYPE 'I'.
          MESSAGE |    Material={ ls_item-material }, Qty={ ls_item-quantity }, ItemOk={ ls_item-item_ok }| TYPE 'I'.
          
        ENDLOOP.
        
      ENDLOOP.

      " Create response (echo back)
      CREATE DATA er_deep_entity TYPE zmm_migo_automation_=>ts_headerdummy.
      ASSIGN er_deep_entity->* TO FIELD-SYMBOL(<ls_response>).
      <ls_response> = ls_header_dummy.

      MESSAGE |SUCCESS: { lv_header_count } headers processed!| TYPE 'S'.

    CATCH cx_root INTO DATA(lx_error).
      
      MESSAGE |ERROR: { lx_error->get_text( ) }| TYPE 'E'.
      
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
        EXPORTING
          textid = /iwbep/cx_mgw_tech_exception=>internal_error
          message = lx_error->get_text( ).

  ENDTRY.

ENDMETHOD.