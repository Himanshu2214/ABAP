" =============================================================================
" MINIMAL CHANGES FOR EXISTING ZCL_ZMM01_MIGO_AUTO_MPC_EXT CLASS
" =============================================================================
" Just add these lines to your existing MPC_EXT class without removing anything

" Add this constant to public section:
constants GC_GOODSMVTFLAT type /IWBEP/IF_MGW_MED_ODATA_TYPES=>TY_E_MED_ENTITY_NAME value 'GoodsMvtFlat' ##NO_TEXT.

" Add this flat structure to public section (only new addition):
TYPES: BEGIN OF ts_flat_entity,
         ztype_gm      TYPE char10,       " GM Type
         zsub_type     TYPE char4,        " Sub Type  
         movementtype  TYPE bwart,        " Movement Type
         doc_date      TYPE string,       " Document Date
         pstng_date    TYPE string,       " Posting Date
         gr_gi_slip_no TYPE xabln,        " GR/GI Slip Number
         header_txt    TYPE bktxt,        " Header Text
         material      TYPE matnr,        " Material Number
         item_no       TYPE char6,        " Item Number
         mat_desc      TYPE maktx,        " Material Description
         base_uom      TYPE meins,        " Base Unit of Measure
         quantity      TYPE menge_d,      " Quantity
         strg_loc      TYPE lgort_d,      " Storage Location
         plant         TYPE werks_d,      " Plant
         gl_account    TYPE saknr,        " GL Account
         costcenter    TYPE kostl,        " Cost Center
         order_no      TYPE aufnr,        " Order Number
         item_ok       TYPE flag,         " Item OK Flag
         " Response fields
         mat_doc_num   TYPE string,       " Material Document Number (Response)
         status        TYPE string,       " Processing Status
         message       TYPE string,       " Response Message
       END OF ts_flat_entity.

TYPES: tt_flat_entity TYPE STANDARD TABLE OF ts_flat_entity WITH EMPTY KEY.

" =============================================================================
" UPDATE YOUR EXISTING define METHOD by adding this code at the end:
" =============================================================================

" Add this to your existing define method (after super->define( )):

    " Define the new flat entity (ADD THIS TO EXISTING DEFINE METHOD)
    DATA: lo_entity_type TYPE REF TO /iwbep/if_mgw_odata_entity_typ,
          lo_entity_set  TYPE REF TO /iwbep/if_mgw_odata_entity_set.

    " Create flat entity type
    lo_entity_type = model->create_entity_type_by_annotation(
      iv_entity_type_name       = 'GoodsMvtFlat'
      iv_def_entity_container   = abap_false
      iv_gen_prim_props         = abap_false
      iv_gen_prim_keys          = abap_false
      iv_add_conv_to_prim_props = abap_true ).

    " Set structure for flat entity
    lo_entity_type->bind_structure( iv_structure_name = 'ZCL_ZMM01_MIGO_AUTO_MPC_EXT=>TS_FLAT_ENTITY' ).

    " Create entity set for flat structure
    lo_entity_set = lo_entity_type->create_entity_set( 'GoodsMvtFlatSet' ).

    " Enable create operations
    lo_entity_set->set_creatable( abap_true ).
    lo_entity_set->set_updatable( abap_false ).
    lo_entity_set->set_deletable( abap_false ).

    " Set key fields for the flat entity
    DATA: lo_property TYPE REF TO /iwbep/if_mgw_odata_property.
    
    " Set GR_GI_SLIP_NO as key
    lo_property = lo_entity_type->get_property( 'GrGiSlipNo' ).
    IF lo_property IS BOUND.
      lo_property->set_as_key( ).
    ENDIF.

    " Set ITEM_NO as part of composite key  
    lo_property = lo_entity_type->get_property( 'ItemNo' ).
    IF lo_property IS BOUND.
      lo_property->set_as_key( ).
    ENDIF.