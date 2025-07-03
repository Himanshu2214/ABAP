# SEGW OData Service Creation Guide for MIGO Posting

## Step-by-Step Implementation Guide

### 1. Create OData Service Project in SEGW

#### 1.1 Start SEGW Transaction
- Execute transaction **SEGW**
- Click on "Create Project"
- Enter Project Details:
  - **Project Name**: `ZGW_MIGO_PROJECT`
  - **Description**: `MIGO Posting OData Service`
  - **Project Type**: `Service Development`
  - **Generation Strategy**: `Standard`

#### 1.2 Define Service Details
- **Service ID**: `ZGW_MIGO_SRV`
- **Service Version**: `0001`
- **Description**: `MIGO Document Posting Service`

### 2. Create Entity Types and Entity Sets

#### 2.1 Create Main Entity Type: MigoDocument

**Right-click on Data Model → Entity Types → Create**

**Entity Type Properties:**
- **Name**: `MigoDocument`
- **Description**: `MIGO Document Entity`

**Define Properties:**

| Property Name | EDM Type | Max Length | Key | Nullable | Description |
|---------------|----------|------------|-----|----------|-------------|
| RequestId | Edm.String | 32 | ✓ | No | Unique Request ID |
| ZtypeGm | Edm.String | 10 | | Yes | GM Type |
| ZsubType | Edm.String | 10 | | Yes | GM Sub Type |
| MovementType | Edm.String | 3 | | Yes | Movement Type |
| DocDate | Edm.String | 50 | | Yes | Document Date |
| PstngDate | Edm.String | 50 | | Yes | Posting Date |
| GrGiSlipNo | Edm.String | 20 | | Yes | GR/GI Slip Number |
| HeaderTxt | Edm.String | 50 | | Yes | Header Text |
| MaterialDocument | Edm.String | 20 | | Yes | Material Document |
| DocumentYear | Edm.String | 4 | | Yes | Document Year |
| MigoNumber | Edm.String | 20 | | Yes | MIGO Number |
| Gigrnum | Edm.String | 20 | | Yes | GI/GR Number |
| Success | Edm.Boolean | | | Yes | Success Flag |
| Message | Edm.String | 255 | | Yes | Response Message |
| Payload | Edm.String | | | Yes | Input Payload |
| Response | Edm.String | | | Yes | Complete Response |
| ErrorDetails | Edm.String | | | Yes | Error Details |

#### 2.2 Create Entity Set: MigoDocumentSet

**Right-click on Data Model → Entity Sets → Create**

- **Name**: `MigoDocumentSet`
- **Entity Type**: `MigoDocument`
- **Description**: `MIGO Document Collection`

**Set Entity Set Properties:**
- **Creatable**: ✓ (Enable POST operations)
- **Updatable**: ✗
- **Deletable**: ✗
- **Pageable**: ✗
- **Addressable**: ✓

### 3. Create Item Entity Type (Optional - for navigation)

#### 3.1 Create Entity Type: MigoItem

**Entity Type Properties:**
- **Name**: `MigoItem`
- **Description**: `MIGO Item Entity`

**Define Properties:**

| Property Name | EDM Type | Max Length | Key | Nullable | Description |
|---------------|----------|------------|-----|----------|-------------|
| RequestId | Edm.String | 32 | ✓ | No | Parent Request ID |
| ItemNo | Edm.String | 6 | ✓ | No | Item Number |
| Material | Edm.String | 40 | | Yes | Material Number |
| MatDesc | Edm.String | 50 | | Yes | Material Description |
| BaseUom | Edm.String | 3 | | Yes | Base UOM |
| Quantity | Edm.Decimal | | | Yes | Quantity |
| StrgLoc | Edm.String | 4 | | Yes | Storage Location |
| Plant | Edm.String | 4 | | Yes | Plant |
| GlAccount | Edm.String | 10 | | Yes | GL Account |
| Costcenter | Edm.String | 10 | | Yes | Cost Center |
| OrderNo | Edm.String | 12 | | Yes | Order Number |
| ItemOk | Edm.Boolean | | | Yes | Item Valid Flag |

#### 3.2 Create Entity Set: MigoItemSet

- **Name**: `MigoItemSet`
- **Entity Type**: `MigoItem`
- **Description**: `MIGO Item Collection`

### 4. Create Navigation (Optional)

#### 4.1 Create Association: HeaderToItems

**Right-click on Data Model → Associations → Create**

- **Name**: `HeaderToItems`
- **Description**: `Header to Items Navigation`

**Principal Entity:**
- **Entity Type**: `MigoDocument`
- **Property**: `RequestId`
- **Multiplicity**: `1`

**Dependent Entity:**
- **Entity Type**: `MigoItem`
- **Property**: `RequestId`
- **Multiplicity**: `*`

#### 4.2 Create Association Set

**Right-click on Data Model → Association Sets → Create**

- **Name**: `HeaderToItemsSet`
- **Association**: `HeaderToItems`
- **Principal Entity Set**: `MigoDocumentSet`
- **Dependent Entity Set**: `MigoItemSet`

#### 4.3 Add Navigation Property

**In MigoDocument Entity Type:**
- **Right-click → Navigation Properties → Create**
- **Name**: `ToItems`
- **Association**: `HeaderToItems`
- **From Role**: `FromRole_HeaderToItems`
- **To Role**: `ToRole_HeaderToItems`

### 5. Generate Runtime Objects

#### 5.1 Generate Service
- **Right-click on Service Implementation → Generate**
- **Package**: `$TMP` (or your development package)
- **Generated Classes:**
  - `ZCL_ZGW_MIGO_MPC` (Model Provider Class)
  - `ZCL_ZGW_MIGO_DPC` (Data Provider Class)

### 6. Create DPC Extension Class

#### 6.1 Create Extension Class
```abap
CLASS zcl_zgw_migo_dpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zgw_migo_dpc
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Override CRUD methods
    METHODS: migodocumentset_create_entity REDEFINITION,
             migodocumentset_get_entityset REDEFINITION,
             migodocumentset_get_entity REDEFINITION.

    " Optional: Override item methods if using navigation
    METHODS: migoitemset_get_entityset REDEFINITION.

  PRIVATE SECTION.
    " Instance of MIGO processor
    DATA: lo_migo_processor TYPE REF TO zcl_migo_posting_enhanced.

    METHODS: handle_migo_creation
      IMPORTING
        ir_entity TYPE REF TO data
      RETURNING
        VALUE(er_entity) TYPE REF TO data
      RAISING
        /iwbep/cx_mgw_busi_exception
        /iwbep/cx_mgw_tech_exception.
ENDCLASS.
```

#### 6.2 Implement Main POST Method
```abap
METHOD migodocumentset_create_entity.
  DATA: ls_entity_in  TYPE zcl_zgw_migo_mpc=>ts_migodocument,
        ls_entity_out TYPE zcl_zgw_migo_mpc=>ts_migodocument,
        lv_response_json TYPE string.

  " Copy input entity
  MOVE-CORRESPONDING ir_entity->* TO ls_entity_in.

  " Validate payload
  IF ls_entity_in-payload IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid = /iwbep/cx_mgw_busi_exception=>business_error
        message = 'Payload is required'.
  ENDIF.

  TRY.
      " Create MIGO processor instance
      IF lo_migo_processor IS INITIAL.
        CREATE OBJECT lo_migo_processor.
      ENDIF.

      " Process MIGO posting
      lv_response_json = lo_migo_processor->process_migo_posting( ls_entity_in-payload ).

      " Parse response and populate output entity
      " ... (detailed implementation)

      " Set response
      copy_data_to_ref(
        EXPORTING is_data = ls_entity_out
        CHANGING cr_data = er_entity
      ).

    CATCH cx_root INTO DATA(lx_error).
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
        EXPORTING
          textid = /iwbep/cx_mgw_tech_exception=>internal_error
          message = lx_error->get_text( ).
  ENDTRY.
ENDMETHOD.
```

### 7. Register Service

#### 7.1 Activate Service in SICF
- Execute transaction **SICF**
- Navigate to: `/default_host/sap/opu/odata/sap/`
- Create new service node: `zgw_migo_srv`
- **Handler List**: `/iwbep/cl_cp_abs_gw_request`
- **Service Data**: Your service details

#### 7.2 Register in Service Catalog
- Execute transaction **/IWFND/MAINT_SERVICE**
- Add Service:
  - **System Alias**: LOCAL
  - **Service ID**: `ZGW_MIGO_SRV`
  - **Service Version**: `0001`

### 8. Test the Service

#### 8.1 Service Document URL
```
http://server:port/sap/opu/odata/sap/zgw_migo_srv/
```

#### 8.2 Metadata URL
```
http://server:port/sap/opu/odata/sap/zgw_migo_srv/$metadata
```

#### 8.3 POST Request Example
**URL:**
```
http://server:port/sap/opu/odata/sap/zgw_migo_srv/MigoDocumentSet
```

**Headers:**
```
Content-Type: application/json
Accept: application/json
X-CSRF-Token: <fetch token>
```

**Body:**
```json
{
  "RequestId": "12345",
  "Payload": "{\"ZtypeGm\":\"A007\",\"ZsubType\":\"R10\",\"Movementtype\":963,...}"
}
```

### 9. Error Handling Best Practices

#### 9.1 Business Exceptions
```abap
" For business logic errors
RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
  EXPORTING
    textid = /iwbep/cx_mgw_busi_exception=>business_error
    message = 'Your business error message'
    entity_type = 'MigoDocument'.
```

#### 9.2 Technical Exceptions
```abap
" For technical errors
RAISE EXCEPTION TYPE /iwbep/cx_mgw_tech_exception
  EXPORTING
    textid = /iwbep/cx_mgw_tech_exception=>internal_error
    message = 'Technical error message'.
```

### 10. Security Considerations

#### 10.1 CSRF Protection
- Always validate CSRF tokens for POST operations
- Implement proper authorization checks

#### 10.2 Input Validation
- Validate all input parameters
- Sanitize JSON payload
- Check user authorizations

### 11. Debugging Tips

#### 11.1 Gateway Error Log
- Transaction: `/IWBEP/ERROR_LOG`
- Check for runtime errors and exceptions

#### 11.2 Service Maintenance
- Transaction: `/IWFND/MAINT_SERVICE`
- Test service functionality

#### 11.3 Gateway Client
- Transaction: `/IWFND/GW_CLIENT`
- Test HTTP requests directly

This guide provides the complete foundation for creating your MIGO posting OData service using SEGW. Each step builds upon the previous one to create a fully functional service.