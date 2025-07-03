METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  " Data declarations for batch processing
  DATA(ls_header_payload) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity( ).
  DATA(lt_batch_items)    = VALUE zcl_zmm01_migo_auto_mpc_ext=>tt_deep_entity( ).
  DATA(lt_success_items)  = VALUE zcl_zmm01_migo_auto_mpc_ext=>tt_deep_entity( ).
  DATA(lt_failed_items)   = VALUE zcl_zmm01_migo_auto_mpc_ext=>tt_deep_entity( ).
  DATA(lt_processing_log) = VALUE TABLE OF string( ).
  
  " BAPI related variables
  DATA(ls_bapi_header)    = VALUE bapi2017_gm_head_01( ).
  DATA(lv_bapi_gm_code)   = VALUE gm_code( ).
  DATA(lt_bapi_items)     = VALUE tt_bapi_items( ).
  DATA(ls_bapi_headret)   = VALUE bapi2017_gm_head_ret( ).
  DATA(lt_return)         = VALUE bapiret2_t( ).
  
  " Response tracking variables
  DATA(lv_total_records)   = 0.
  DATA(lv_success_count)   = 0.
  DATA(lv_failure_count)   = 0.
  DATA(lv_overall_status)  = VALUE string( ).
  
  " Message container and performance optimization
  DATA lo_message_container TYPE REF TO /iwbep/if_message_container.
  DATA(lv_commit_counter)  = 0.
  CONSTANTS: gc_commit_interval TYPE i VALUE 10. " Commit every 10 successful transactions

  TRY.
      " Read input data - check if it's batch or single record
      io_data_provider->read_entry_data( IMPORTING es_data = ls_header_payload ).
      
      " Check if we have batch items in the deep entity
      IF ls_header_payload-goodsmvtitems IS NOT INITIAL.
        " Batch processing mode
        lt_batch_items = ls_header_payload-goodsmvtitems.
        lv_total_records = lines( lt_batch_items ).
      ELSE.
        " Single record mode - convert to batch for uniform processing
        APPEND ls_header_payload TO lt_batch_items.
        lv_total_records = 1.
      ENDIF.

      " Validate total records limit for performance
      IF lv_total_records > 100.
        RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
          textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |Maximum 100 records allowed per batch. Received: { lv_total_records }| ).
      ENDIF.

      " Process each record in the batch
      LOOP AT lt_batch_items INTO DATA(ls_current_item).
        DATA(lv_current_index) = sy-tabix.
        
        TRY.
            " Clear variables for each iteration
            CLEAR: ls_bapi_header, lv_bapi_gm_code, lt_bapi_items, ls_bapi_headret, lt_return.

            " Validate current item
            validate_input_data( is_header_payload = ls_current_item ).

            " Map current item to BAPI format
            map_to_bapi_format(
              EXPORTING is_header_payload = ls_current_item
              IMPORTING es_bapi_header    = ls_bapi_header
                        ev_bapi_gm_code   = lv_bapi_gm_code
                        et_bapi_items     = lt_bapi_items ).

            " Call BAPI for current item
            CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
              EXPORTING
                goodsmvt_header  = ls_bapi_header
                goodsmvt_code    = VALUE bapi2017_gm_code( gm_code = lv_bapi_gm_code )
              IMPORTING
                goodsmvt_headret = ls_bapi_headret
              TABLES
                goodsmvt_item    = lt_bapi_items
                return           = lt_return
              EXCEPTIONS
                communication_failure = 1
                system_failure        = 2
                OTHERS                = 3.

            " Check BAPI execution result
            IF sy-subrc = 0.
              " Check for business errors in return messages
              DATA(lv_has_errors) = COND abap_bool(
                WHEN line_exists( lt_return[ type = 'E' ] )
                  OR line_exists( lt_return[ type = 'A' ] )
                  OR line_exists( lt_return[ type = 'X' ] )
                THEN abap_true
                ELSE abap_false ).

              IF lv_has_errors = abap_false AND ls_bapi_headret-mat_doc IS NOT INITIAL.
                " Success case
                ls_current_item-mat_doc_num = ls_bapi_headret-mat_doc.
                ls_current_item-status = 'SUCCESS'.
                ls_current_item-message = |Material Document { ls_bapi_headret-mat_doc } created successfully|.
                APPEND ls_current_item TO lt_success_items.
                lv_success_count = lv_success_count + 1.
                
                " Commit periodically for performance
                lv_commit_counter = lv_commit_counter + 1.
                IF lv_commit_counter >= gc_commit_interval.
                  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' EXPORTING wait = 'X'.
                  lv_commit_counter = 0.
                ENDIF.
                
                APPEND |Record { lv_current_index }: SUCCESS - Mat Doc: { ls_bapi_headret-mat_doc }| TO lt_processing_log.
                
              ELSE.
                " Business error case
                ls_current_item-status = 'FAILED'.
                ls_current_item-message = 'Business validation failed'.
                
                " Collect error messages
                DATA(lv_error_details) = VALUE string( ).
                LOOP AT lt_return INTO DATA(ls_return_msg) WHERE type CA 'AEX'.
                  IF lv_error_details IS NOT INITIAL.
                    lv_error_details = |{ lv_error_details }; { ls_return_msg-message }|.
                  ELSE.
                    lv_error_details = ls_return_msg-message.
                  ENDIF.
                ENDLOOP.
                
                IF lv_error_details IS NOT INITIAL.
                  ls_current_item-message = lv_error_details.
                ENDIF.
                
                APPEND ls_current_item TO lt_failed_items.
                lv_failure_count = lv_failure_count + 1.
                APPEND |Record { lv_current_index }: FAILED - { ls_current_item-message }| TO lt_processing_log.
                
                " Rollback current transaction
                CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
              ENDIF.
              
            ELSE.
              " Technical error case
              ls_current_item-status = 'FAILED'.
              ls_current_item-message = COND string(
                WHEN sy-subrc = 1 THEN |BAPI Communication Failure|
                WHEN sy-subrc = 2 THEN |BAPI System Failure|
                ELSE                   |BAPI Technical Error (subrc: { sy-subrc })| ).
              
              APPEND ls_current_item TO lt_failed_items.
              lv_failure_count = lv_failure_count + 1.
              APPEND |Record { lv_current_index }: FAILED - { ls_current_item-message }| TO lt_processing_log.
              
              " Rollback current transaction
              CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
            ENDIF.

          CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_item_exception).
            " Handle validation errors for individual items
            ls_current_item-status = 'FAILED'.
            ls_current_item-message = lx_item_exception->get_text( ).
            APPEND ls_current_item TO lt_failed_items.
            lv_failure_count = lv_failure_count + 1.
            APPEND |Record { lv_current_index }: FAILED - { ls_current_item-message }| TO lt_processing_log.

          CATCH cx_root INTO DATA(lx_item_technical).
            " Handle unexpected technical errors for individual items
            ls_current_item-status = 'FAILED'.
            ls_current_item-message = |Technical error: { lx_item_technical->get_text( ) }|.
            APPEND ls_current_item TO lt_failed_items.
            lv_failure_count = lv_failure_count + 1.
            APPEND |Record { lv_current_index }: FAILED - { ls_current_item-message }| TO lt_processing_log.

        ENDTRY.
      ENDLOOP.

      " Final commit for any remaining successful transactions
      IF lv_commit_counter > 0.
        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' EXPORTING wait = 'X'.
      ENDIF.

      " Determine overall status based on success/failure ratio
      CASE abap_true.
        WHEN lv_success_count = lv_total_records.
          lv_overall_status = 'SUCCESS: FULLY'.
        WHEN lv_success_count > 0 AND lv_failure_count > 0.
          lv_overall_status = 'PARTIAL SUCCESS'.
        WHEN lv_failure_count = lv_total_records.
          lv_overall_status = 'FAILED: ALL'.
        WHEN OTHERS.
          lv_overall_status = 'UNKNOWN STATUS'.
      ENDCASE.

      " Prepare comprehensive response structure
      DATA(ls_response) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity(
        overall_status    = lv_overall_status
        total_records     = lv_total_records
        success_count     = lv_success_count
        failure_count     = lv_failure_count
        processing_time   = |{ cl_abap_tstmp=>utclong2tstmp( utclong_current( ) ) }|
        response_msg      = COND string(
                              WHEN lv_overall_status = 'SUCCESS: FULLY'
                              THEN |All { lv_total_records } goods movements created successfully|
                              WHEN lv_overall_status = 'PARTIAL SUCCESS'
                              THEN |{ lv_success_count } of { lv_total_records } goods movements created successfully|
                              ELSE |Batch processing failed: { lv_failure_count } errors occurred| )
        success_items    = lt_success_items
        failed_items     = lt_failed_items
        processing_log   = lt_processing_log ).

      " Set appropriate message type based on overall status
      DATA(lv_msg_type) = COND string(
        WHEN lv_overall_status = 'SUCCESS: FULLY' THEN 'S'
        WHEN lv_overall_status = 'PARTIAL SUCCESS' THEN 'W'
        ELSE 'E' ).

      " Add message to container for proper JSON response
      mo_context->get_message_container( )->add_message_text_only(
        iv_msg_text = ls_response-response_msg
        iv_msg_type = lv_msg_type ).

      " For partial success or full failure, add detailed error information
      IF lv_failure_count > 0.
        lo_message_container = mo_context->get_message_container( ).
        LOOP AT lt_failed_items INTO DATA(ls_failed_item).
          lo_message_container->add_message_text_only(
            iv_msg_text = |Item { sy-tabix }: { ls_failed_item-message }|
            iv_msg_type = 'E' ).
        ENDLOOP.
      ENDIF.

      " Set response data with proper JSON structure
      copy_data_to_ref(
        EXPORTING is_data = ls_response
        CHANGING  cr_data = er_deep_entity ).

      " Handle failure cases for proper HTTP status codes
      IF lv_overall_status = 'FAILED: ALL'.
        RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
          textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |All { lv_total_records } goods movement records failed processing| ).
      ENDIF.

    CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_busi_exception).
      " Re-raise business exceptions with context
      RAISE EXCEPTION lx_busi_exception.

    CATCH cx_root INTO DATA(lx_root).
      " Handle unexpected technical errors
      RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
        textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message = |Critical technical error in batch processing: { lx_root->get_text( ) }| ).

  ENDTRY.

ENDMETHOD.