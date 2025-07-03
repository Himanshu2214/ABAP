METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

  " Data declarations for batch processing
  DATA(ls_header_payload) = VALUE zcl_zmm01_migo_auto_mpc_ext=>ts_deep_entity( ).
  DATA: lt_batch_items    TYPE zcl_zmm01_migo_auto_mpc_ext=>tt_goodsmvtitem,
        lt_success_docs   TYPE TABLE OF string,
        lt_failed_items   TYPE TABLE OF string,
        lt_processing_log TYPE TABLE OF string.
  
  " BAPI related variables
  DATA(ls_bapi_header)    = VALUE bapi2017_gm_head_01( ).
  DATA(lv_bapi_gm_code)   = VALUE gm_code( ).
  DATA(lt_bapi_items)     = VALUE tt_bapi_items( ).
  DATA(ls_bapi_headret)   = VALUE bapi2017_gm_head_ret( ).
  DATA(lt_return)         = VALUE bapiret2_t( ).
  
  " Response tracking variables
  DATA: lv_total_records   TYPE i VALUE 0,
        lv_success_count   TYPE i VALUE 0,
        lv_failure_count   TYPE i VALUE 0,
        lv_overall_status  TYPE string,
        lv_response_message TYPE string.
  
  " Message container and performance optimization
  DATA lo_message_container TYPE REF TO /iwbep/if_message_container.
  DATA: lv_commit_counter  TYPE i VALUE 0.
  CONSTANTS: gc_commit_interval TYPE i VALUE 10. " Commit every 10 successful transactions

  TRY.
      " Read input data
      io_data_provider->read_entry_data( IMPORTING es_data = ls_header_payload ).
      
      " Check if we have batch items in the deep entity
      IF ls_header_payload-goodsmvtitem IS NOT INITIAL.
        " Batch processing mode
        lt_batch_items = ls_header_payload-goodsmvtitem.
        lv_total_records = lines( lt_batch_items ).
      ELSE.
        " Single record mode - create single item from header data
        DATA: ls_single_item TYPE zcl_zmm01_migo_auto_mpc_ext=>ts_goodsmvtitem.
        
        " Map header fields to item structure (adjust field names as per your structure)
        ls_single_item-material = ls_header_payload-material.
        ls_single_item-plant = ls_header_payload-plant.
        ls_single_item-stge_loc = ls_header_payload-stge_loc.
        ls_single_item-move_type = ls_header_payload-movementtype.
        ls_single_item-entry_qnt = ls_header_payload-entry_qnt.
        ls_single_item-entry_uom = ls_header_payload-entry_uom.
        
        APPEND ls_single_item TO lt_batch_items.
        lv_total_records = 1.
      ENDIF.

      " Validate total records limit for performance
      IF lv_total_records > 100.
        RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
          textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = |Maximum 100 records allowed per batch. Received: { lv_total_records }| ).
      ENDIF.

      " If no items to process, raise error
      IF lv_total_records = 0.
        RAISE EXCEPTION NEW /iwbep/cx_mgw_busi_exception(
          textid  = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
          message = 'No goods movement items found for processing' ).
      ENDIF.

      " Process each record in the batch
      LOOP AT lt_batch_items INTO DATA(ls_current_item).
        DATA(lv_current_index) = sy-tabix.
        
        TRY.
            " Clear variables for each iteration
            CLEAR: ls_bapi_header, lv_bapi_gm_code, lt_bapi_items, ls_bapi_headret, lt_return.

            " Create temporary header for current item using existing fields
            DATA(ls_temp_header) = ls_header_payload.
            
            " Override with current item specific data
            ls_temp_header-material = ls_current_item-material.
            ls_temp_header-plant = ls_current_item-plant.
            ls_temp_header-stge_loc = ls_current_item-stge_loc.
            ls_temp_header-movementtype = ls_current_item-move_type.
            ls_temp_header-entry_qnt = ls_current_item-entry_qnt.
            ls_temp_header-entry_uom = ls_current_item-entry_uom.

            " Validate current item
            validate_input_data( is_header_payload = ls_temp_header ).

            " Map current item to BAPI format
            map_to_bapi_format(
              EXPORTING is_header_payload = ls_temp_header
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
                DATA(lv_success_msg) = |Item { lv_current_index }: Material { ls_current_item-material } - Document { ls_bapi_headret-mat_doc }|.
                APPEND lv_success_msg TO lt_success_docs.
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
                DATA(lv_error_details) = VALUE string( ).
                LOOP AT lt_return INTO DATA(ls_return_msg) WHERE type CA 'AEX'.
                  IF lv_error_details IS NOT INITIAL.
                    lv_error_details = |{ lv_error_details }; { ls_return_msg-message }|.
                  ELSE.
                    lv_error_details = ls_return_msg-message.
                  ENDIF.
                ENDLOOP.
                
                IF lv_error_details IS INITIAL.
                  lv_error_details = 'Business validation failed - no specific error message'.
                ENDIF.
                
                DATA(lv_failed_msg) = |Item { lv_current_index }: Material { ls_current_item-material } - Error: { lv_error_details }|.
                APPEND lv_failed_msg TO lt_failed_items.
                lv_failure_count = lv_failure_count + 1.
                APPEND |Record { lv_current_index }: FAILED - { lv_error_details }| TO lt_processing_log.
                
                " Rollback current transaction
                CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
              ENDIF.
              
            ELSE.
              " Technical error case
              DATA(lv_tech_error) = COND string(
                WHEN sy-subrc = 1 THEN |BAPI Communication Failure|
                WHEN sy-subrc = 2 THEN |BAPI System Failure|
                ELSE                   |BAPI Technical Error (subrc: { sy-subrc })| ).
              
              DATA(lv_tech_failed_msg) = |Item { lv_current_index }: Material { ls_current_item-material } - Error: { lv_tech_error }|.
              APPEND lv_tech_failed_msg TO lt_failed_items.
              lv_failure_count = lv_failure_count + 1.
              APPEND |Record { lv_current_index }: FAILED - { lv_tech_error }| TO lt_processing_log.
              
              " Rollback current transaction
              CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
            ENDIF.

          CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_item_exception).
            " Handle validation errors for individual items
            DATA(lv_val_error_msg) = |Item { lv_current_index }: Material { ls_current_item-material } - Validation Error: { lx_item_exception->get_text( ) }|.
            APPEND lv_val_error_msg TO lt_failed_items.
            lv_failure_count = lv_failure_count + 1.
            APPEND |Record { lv_current_index }: FAILED - { lx_item_exception->get_text( ) }| TO lt_processing_log.

          CATCH cx_root INTO DATA(lx_item_technical).
            " Handle unexpected technical errors for individual items
            DATA(lv_tech_error_msg) = |Item { lv_current_index }: Material { ls_current_item-material } - Technical Error: { lx_item_technical->get_text( ) }|.
            APPEND lv_tech_error_msg TO lt_failed_items.
            lv_failure_count = lv_failure_count + 1.
            APPEND |Record { lv_current_index }: FAILED - Technical Error: { lx_item_technical->get_text( ) }| TO lt_processing_log.

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

      " Prepare response message
      CASE lv_overall_status.
        WHEN 'SUCCESS: FULLY'.
          lv_response_message = |All { lv_total_records } goods movements created successfully|.
        WHEN 'PARTIAL SUCCESS'.
          lv_response_message = |{ lv_success_count } of { lv_total_records } goods movements created successfully. { lv_failure_count } failed.|.
        WHEN 'FAILED: ALL'.
          lv_response_message = |All { lv_total_records } goods movements failed processing|.
        WHEN OTHERS.
          lv_response_message = |Processing completed with unknown status|.
      ENDCASE.

      " Prepare response using existing structure
      DATA(ls_response) = ls_header_payload.
      
      " Update response fields with batch processing results
      ls_response-response_msg = |{ lv_overall_status }: { lv_response_message }|.
      ls_response-header_txt = |Batch: { lv_overall_status } - Success: { lv_success_count }, Failed: { lv_failure_count }|.
      
      " For single successful record, include the material document number
      IF lv_success_count = 1 AND lv_total_records = 1 AND lines( lt_success_docs ) = 1.
        DATA(lv_success_doc_info) = lt_success_docs[ 1 ].
        " Extract document number from success message (format: "Item X: Material Y - Document Z")
        SPLIT lv_success_doc_info AT 'Document ' INTO DATA(lv_prefix) DATA(lv_doc_part).
        IF lv_doc_part IS NOT INITIAL.
          ls_response-mat_doc_num = lv_doc_part.
        ENDIF.
      ELSEIF lv_success_count > 1.
        ls_response-mat_doc_num = |{ lv_success_count } documents created|.
      ENDIF.

      " Set appropriate message type based on overall status
      DATA(lv_msg_type) = COND string(
        WHEN lv_overall_status = 'SUCCESS: FULLY' THEN 'S'
        WHEN lv_overall_status = 'PARTIAL SUCCESS' THEN 'W'
        ELSE 'E' ).

      " Add main message to container for proper JSON response
      mo_context->get_message_container( )->add_message_text_only(
        iv_msg_text = ls_response-response_msg
        iv_msg_type = lv_msg_type ).

      " Add detailed success information
      IF lv_success_count > 0.
        LOOP AT lt_success_docs INTO DATA(lv_success_detail).
          mo_context->get_message_container( )->add_message_text_only(
            iv_msg_text = |SUCCESS: { lv_success_detail }|
            iv_msg_type = 'S' ).
        ENDLOOP.
      ENDIF.

      " Add detailed failure information
      IF lv_failure_count > 0.
        LOOP AT lt_failed_items INTO DATA(lv_failed_detail).
          mo_context->get_message_container( )->add_message_text_only(
            iv_msg_text = |FAILED: { lv_failed_detail }|
            iv_msg_type = 'E' ).
        ENDLOOP.
      ENDIF.

      " Add processing log as information messages
      LOOP AT lt_processing_log INTO DATA(lv_log_entry).
        mo_context->get_message_container( )->add_message_text_only(
          iv_msg_text = lv_log_entry
          iv_msg_type = 'I' ).
      ENDLOOP.

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