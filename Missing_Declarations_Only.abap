" ===== ADD ONLY THESE MISSING DECLARATIONS TO YOUR PRIVATE SECTION =====
" (Don't add if you already have them declared)

" Helper method declarations
METHODS: validate_payload_structure
  IMPORTING is_deep_entity TYPE ty_deep_headerdummy
  RETURNING VALUE(rv_valid) TYPE abap_bool,

validate_header
  IMPORTING is_header TYPE ty_header
            it_processed_slips TYPE string_table
  RETURNING VALUE(rv_error_msg) TYPE string,

process_items
  IMPORTING it_items TYPE ty_items
  EXPORTING et_gm_items TYPE BAPI2017_GM_ITEM_CREATE_T
            ev_processed_items TYPE i
  RETURNING VALUE(rv_error_msg) TYPE string,

validate_single_item
  IMPORTING is_item TYPE ty_item
  RETURNING VALUE(rv_error_msg) TYPE string,

map_item_to_bapi
  IMPORTING is_item TYPE ty_item
  RETURNING VALUE(rs_gm_item) TYPE bapi2017_gm_item_create,

append_error_message
  IMPORTING iv_new_error TYPE string
  CHANGING cv_error_msg TYPE string,

add_error_result
  IMPORTING iv_grgislipno TYPE string
            iv_error_msg TYPE string
  CHANGING ct_results TYPE STANDARD TABLE
           cv_error_count TYPE i,

prepare_bapi_header
  IMPORTING is_header TYPE ty_header
  EXPORTING es_gm_header TYPE bapi2017_gm_head_01
            es_gm_code TYPE bapi2017_gm_code,

execute_goods_movement
  IMPORTING is_gm_header TYPE bapi2017_gm_head_01
            is_gm_code TYPE bapi2017_gm_code
            it_gm_items TYPE BAPI2017_GM_ITEM_CREATE_T
            iv_grgislipno TYPE string
  CHANGING ct_results TYPE STANDARD TABLE
           cv_success_count TYPE i
           cv_error_count TYPE i,

collect_bapi_errors
  IMPORTING it_return TYPE bapiret2_tab
  RETURNING VALUE(rv_error_msg) TYPE string,

determine_overall_status
  IMPORTING iv_success_count TYPE i
            iv_error_count TYPE i
  RETURNING VALUE(rv_status) TYPE string,

generate_json_response
  IMPORTING is_response TYPE ty_response,

get_http_status_code
  IMPORTING is_response TYPE ty_response
  RETURNING VALUE(rv_status_code) TYPE i,

raise_business_exception
  IMPORTING iv_message TYPE string.