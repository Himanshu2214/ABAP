class ZCL_ZMM01_MIGO_AUTO_MPC_EXT definition
  public
  inheriting from zcl_zmm01_migo_auto_mpc
  create public .

public section.

  " Constants for entity names
  constants GC_GOODSMVTFLAT type /IWBEP/IF_MGW_MED_ODATA_TYPES=>TY_E_MED_ENTITY_NAME value 'GoodsMvtFlat' ##NO_TEXT.

  " Flat structure combining header and item data
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

  " Keep the deep entity for backward compatibility if needed
  TYPES: BEGIN OF ts_deep_entity,
         gr_gi_slip_no     TYPE xabln,
         header_txt        TYPE bapi2017_gm_head_01-header_txt,
         movementtype      TYPE bapi2017_gm_item_create-move_type,
         doc_date          TYPE string,
         pstng_date        TYPE string,
         mat_doc_num       TYPE string,
         ztype_gm          TYPE char4,
         GoodsMvtItemSet   TYPE STANDARD TABLE OF zcl_zmm01_migo_auto_mpc_ext=>ts_goodsmvtitem WITH EMPTY KEY,
       END OF ts_deep_entity.

  TYPES: tt_deep_entity TYPE STANDARD TABLE OF ts_deep_entity WITH EMPTY KEY.

  " Original item structure (keep for compatibility)
  types:
  begin of TS_GOODSMVTITEM,
     MATERIAL type MATNR,
     ITEM_NO type CHAR6,
     MAT_DESC type MAKTX,
     BASE_UOM type MEINS,
     QUANTITY type MENGE_D,
     STRG_LOC type LGORT_D,
     PLANT type WERKS_D,
     GL_ACCOUNT type SAKNR,
     COSTCENTER type KOSTL,
     ORDER_NO type AUFNR,
     ITEM_OK type FLAG,
     GR_GI_SLIP_NO type XABLN,
  end of TS_GOODSMVTITEM .
  types:
    TT_GOODSMVTITEM type standard table of TS_GOODSMVTITEM .

  types:
  begin of TS_GOODSMVTHEADER,
     ZTYPE_GM type CHAR10,
     ZSUB_TYPE type CHAR4,
     MOVEMENTTYPE type BWART,
     DOC_DATE type BLDAT,
     PSTNG_DATE type BUDAT,
     GR_GI_SLIP_NO type XABLN,
     HEADER_TXT type BKTXT,
     MAT_DOC_NUM TYPE MATNR,
     SUCCESS_FLAG TYPE FLAG,
     RESPONSE_MSG type CHAR100,
  end of TS_GOODSMVTHEADER .
  types:
    TT_GOODSMVTHEADER type standard table of TS_GOODSMVTHEADER .

  METHODS define REDEFINITION.

protected section.
private section.
endclass.

class ZCL_ZMM01_MIGO_AUTO_MPC_EXT implementation.

  method define.
    
    " Call parent define first
    super->define( ).
    
    " Define the flat entity
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

  endmethod.

endclass.