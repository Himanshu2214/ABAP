*&---------------------------------------------------------------------*
*& SEGW Configuration and Method Implementation
*& Step-by-step guide for ODATA service setup
*&---------------------------------------------------------------------*

*" 1. Entity Types Definition in SEGW

*" HeaderDummy Entity
*" Key: GrGiSlipNo (String, Key, MaxLength 20)
*" Additional Properties:
*"   ProcessStatus (String, MaxLength 20)

*" GoodsMovementHeader Entity  
*" Key: GrGiSlipNo (String, Key, MaxLength 20)
*" Properties:
*"   ZtypeGm (String, MaxLength 10)
*"   ZsubType (String, MaxLength 10)  
*"   Movementtype (String, MaxLength 3)
*"   DocDate (String, DateTimeOffset)
*"   PstngDate (String, DateTimeOffset)
*"   HeaderTxt (String, MaxLength 25)
*"   MaterialDoc (String, MaxLength 10)
*"   DocYear (String, MaxLength 4)
*"   ProcessStatus (String, MaxLength 20)

*" GoodsMovementItem Entity
*" Key: GrGiSlipNo (String, Key, MaxLength 20)
*"      ItemNo (String, Key, MaxLength 6)
*" Properties:
*"   Material (String, MaxLength 40)
*"   MatDesc (String, MaxLength 40)
*"   BaseUom (String, MaxLength 3)
*"   Quantity (Decimal, Precision 13, Scale 3)
*"   StrgLoc (String, MaxLength 4)
*"   Plant (String, MaxLength 4)
*"   GlAccount (String, MaxLength 10)
*"   Costcenter (String, MaxLength 10)
*"   OrderNo (String, MaxLength 12)
*"   ItemOk (Boolean)
*"   MaterialDoc (String, MaxLength 10)
*"   DocYear (String, MaxLength 4)
*"   ProcessStatus (String, MaxLength 20)

*&---------------------------------------------------------------------*
*& Association Configuration in SEGW
*&---------------------------------------------------------------------*

*" Association 1: HeaderDummy_To_Header
*" From: HeaderDummy
*" To: GoodsMovementHeader
*" Cardinality: 1 to *
*" Principal Key: GrGiSlipNo
*" Dependent Key: GrGiSlipNo

*" Association 2: Header_To_Item  
*" From: GoodsMovementHeader
*" To: GoodsMovementItem
*" Cardinality: 1 to *
*" Principal Key: GrGiSlipNo
*" Dependent Key: GrGiSlipNo

*&---------------------------------------------------------------------*
*& Navigation Properties in SEGW
*&---------------------------------------------------------------------*

*" HeaderDummy Entity:
*" Navigation Property: ToGoodsMvmtHeader
*" Association: HeaderDummy_To_Header
*" To-Role: GoodsMovementHeader

*" GoodsMovementHeader Entity:
*" Navigation Property: ToGoodsMvmtItem  
*" Association: Header_To_Item
*" To-Role: GoodsMovementItem

*&---------------------------------------------------------------------*
*& Data Provider Class Implementation
*&---------------------------------------------------------------------*

CLASS zcl_zgm_dpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zgm_dpc
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS: headerdummyset_create_entity REDEFINITION.

ENDCLASS.

CLASS zcl_zgm_dpc_ext IMPLEMENTATION.

  METHOD headerdummyset_create_entity.
  
    " This is where your deep entity implementation goes
    " Use the enhanced code from goods_movement_enhanced.abap
    
    DATA: lo_message_container TYPE REF TO /iwbep/if_message_container,
          lv_deep_entity        TYPE zcl_zgm_mpc=>ts_headerdummy.

    " Get message container
    lo_message_container = mo_context->get_message_container( ).

    " Read the deep entity from request
    io_data_provider->read_entry_data( IMPORTING es_data = lv_deep_entity ).

    " Your implementation logic here...
    " (Insert the complete implementation from goods_movement_enhanced.abap)

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Entity Set Configuration in SEGW
*&---------------------------------------------------------------------*

*" Entity Set: HeaderDummySet
*" Entity Type: HeaderDummy
*" Enable: Create, Update, Delete operations
*" Addressable: Yes

*" Entity Set: GoodsMvmtHeaderSet  
*" Entity Type: GoodsMovementHeader
*" Enable: Read, Create, Update, Delete operations
*" Addressable: Yes

*" Entity Set: GoodsMvmtItemSet
*" Entity Type: GoodsMovementItem  
*" Enable: Read, Create, Update, Delete operations
*" Addressable: Yes

*&---------------------------------------------------------------------*
*& Method Signature Details
*&---------------------------------------------------------------------*

*" Method: HEADERDUMMYSET_CREATE_ENTITY
*" Importing Parameters:
*"   IO_DATA_PROVIDER TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET
*"   IT_KEY_TAB TYPE /IWBEP/T_MGW_NAME_VALUE_PAIR
*"   IT_NAVIGATION_PATH TYPE /IWBEP/T_MGW_NAVIGATION_PATH
*"   IO_TECH_REQUEST_CONTEXT TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET
*" Exporting Parameters:
*"   ER_ENTITY TYPE REF TO DATA
*" Raising:
*"   /IWBEP/CX_MGW_BUSI_EXCEPTION
*"   /IWBEP/CX_MGW_TECH_EXCEPTION

*&---------------------------------------------------------------------*
*& Sample Service URLs for Testing
*&---------------------------------------------------------------------*

*" Create Deep Entity (POST):
*" /sap/opu/odata/sap/ZGM_SRV/HeaderDummySet
*" Content-Type: application/json

*" Read with Expand (GET):
*" /sap/opu/odata/sap/ZGM_SRV/HeaderDummySet('GI999')?$expand=ToGoodsMvmtHeader/ToGoodsMvmtItem

*" Metadata URL:
*" /sap/opu/odata/sap/ZGM_SRV/$metadata

*&---------------------------------------------------------------------*
*& Error Handling in OData Context
*&---------------------------------------------------------------------*

*" Add business exception for validation errors:
*" RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
*"   EXPORTING
*"     textid = /iwbep/cx_mgw_busi_exception=>business_error
*"     message = 'Your error message here'.

*" Add technical exception for system errors:
*" RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
*"   EXPORTING
*"     textid = /iwbep/cx_mgw_tech_exception=>internal_error.

*&---------------------------------------------------------------------*
*& Testing Checklist
*&---------------------------------------------------------------------*

*" 1. Test metadata generation: /sap/opu/odata/sap/ZGM_SRV/$metadata
*" 2. Test deep entity creation with valid payload
*" 3. Test error handling with invalid data
*" 4. Test navigation properties
*" 5. Verify BAPI integration and material document creation
*" 6. Test authorization scenarios
*" 7. Performance testing with large payloads

*&---------------------------------------------------------------------*
*& Important Notes
*&---------------------------------------------------------------------*

*" 1. Ensure BAPI_GOODSMVT_CREATE is available in your system
*" 2. Configure proper authorization for movement types
*" 3. Test date conversion thoroughly for your system
*" 4. Consider implementing soft validation before BAPI call
*" 5. Add logging for audit trail
*" 6. Implement proper error rollback scenarios