METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  DATA: lv_entity_set_name TYPE string,
        lv_entity_name     TYPE string.

  " Get entity information
  lv_entity_set_name = io_data_provider->get_entity_set_name( ).
  lv_entity_name = io_data_provider->get_entity_type_name( ).

  " Log entity information
  MESSAGE |Entity Set: { lv_entity_set_name }, Entity Type: { lv_entity_name }| TYPE 'I'.

  " Process HeaderDummySet for testing
  IF lv_entity_set_name = 'HeaderDummySet'.
    
    " Define data structures based on your metadata
    DATA: BEGIN OF ls_header_dummy,
            gr_gi_slip_no TYPE string,
            to_real_headers TYPE TABLE OF zmm_migo_automation_=>ts_goodsmovementheader,
          END OF ls_header_dummy.

    DATA: ls_header TYPE zmm_migo_automation_=>ts_goodsmovementheader,
          ls_item   TYPE zmm_migo_automation_=>ts_goodsmovementitem.

    TRY.
        " Read the deep entity from request
        io_data_provider->read_entry_data( IMPORTING es_data = ls_header_dummy ).

        " Log main header data
        MESSAGE |Main GrGiSlipNo: { ls_header_dummy-gr_gi_slip_no }| TYPE 'I'.
        
        " Log number of headers
        DATA(lv_header_count) = lines( ls_header_dummy-to_real_headers ).
        MESSAGE |Number of headers received: { lv_header_count }| TYPE 'I'.

        " Loop through headers to test data
        LOOP AT ls_header_dummy-to_real_headers INTO ls_header.
          
          MESSAGE |Header { sy-tabix }: GrGiSlipNo={ ls_header-gr_gi_slip_no }, MovementType={ ls_header-movementtype }, HeaderTxt={ ls_header-header_txt }| TYPE 'I'.
          
          " Log number of items for this header
          DATA(lv_item_count) = lines( ls_header-header_to_item_nav ).
          MESSAGE |  - Header { sy-tabix } has { lv_item_count } items| TYPE 'I'.
          
          " Loop through items to test data
          LOOP AT ls_header-header_to_item_nav INTO ls_item.
            
            MESSAGE |    Item { sy-tabix }: GiGiSlipNo={ ls_item-gi_gi_slip_no }, ItemNo={ ls_item-item_no }, Material={ ls_item-material }, Qty={ ls_item-quantity }, ItemOk={ ls_item-item_ok }| TYPE 'I'.
            
          ENDLOOP.
          
        ENDLOOP.

        " Create a simple response - just echo back the input for testing
        CREATE DATA er_deep_entity TYPE zmm_migo_automation_=>ts_headerdummy.
        ASSIGN er_deep_entity->* TO FIELD-SYMBOL(<ls_response>).
        <ls_response> = ls_header_dummy.

        MESSAGE 'Deep entity data received and processed successfully!' TYPE 'S'.

      CATCH cx_root INTO DATA(lx_error).
        MESSAGE |Error reading deep entity: { lx_error->get_text( ) }| TYPE 'E'.
        
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
          EXPORTING
            textid = /iwbep/cx_mgw_tech_exception=>internal_error
            message = |Error processing deep entity: { lx_error->get_text( ) }|.

    ENDTRY.

  ELSE.
    " For other entity sets, call parent method
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