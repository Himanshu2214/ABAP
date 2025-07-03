# Field Mapping Guide for Optimized Goods Movement Service

## OData Structure Mapping

### Header Structure (ts_deep_entity)
```abap
TYPES: BEGIN OF ts_deep_entity,
         gr_gi_slip_no     TYPE xabln,           " GR/GI Slip Number
         header_txt        TYPE bapi2017_gm_head_01-header_txt, " Header Text
         movementtype      TYPE bapi2017_gm_item_create-move_type, " Movement Type
         doc_date          TYPE string,          " Document Date
         pstng_date        TYPE string,          " Posting Date
         mat_doc_num       TYPE string,          " Material Document Number (Response)
         ztype_gm          TYPE char4,           " GM Type
         GoodsMvtItemSet   TYPE STANDARD TABLE OF ts_goodsmvtitem, " Item Table
       END OF ts_deep_entity.
```

### Item Structure (ts_goodsmvtitem)
```abap
TYPES: BEGIN OF ts_goodsmvtitem,
         MATERIAL        TYPE MATNR,           " Material Number
         ITEM_NO         TYPE CHAR6,           " Item Number
         MAT_DESC        TYPE MAKTX,           " Material Description
         BASE_UOM        TYPE MEINS,           " Base Unit of Measure
         QUANTITY        TYPE MENGE_D,         " Quantity
         STRG_LOC        TYPE LGORT_D,         " Storage Location
         PLANT           TYPE WERKS_D,         " Plant
         GL_ACCOUNT      TYPE SAKNR,           " GL Account
         COSTCENTER      TYPE KOSTL,           " Cost Center
         ORDER_NO        TYPE AUFNR,           " Order Number
         ITEM_OK         TYPE FLAG,            " Item OK Flag
         GR_GI_SLIP_NO   TYPE XABLN,           " GR/GI Slip Number
       END OF ts_goodsmvtitem.
```

## Field Mapping to BAPI_GOODSMVT_CREATE

### Header Mapping (bapi2017_gm_head_01)
| OData Field | BAPI Field | Description |
|-------------|------------|-------------|
| `doc_date` | `doc_date` | Document Date |
| `pstng_date` | `pstng_date` | Posting Date |
| `header_txt` | `header_txt` | Header Text |

### Item Mapping (bapi2017_gm_item_create)
| OData Field | BAPI Field | Description |
|-------------|------------|-------------|
| `MATERIAL` | `material` | Material Number |
| `PLANT` | `plant` | Plant |
| `STRG_LOC` | `stge_loc` | Storage Location |
| `QUANTITY` | `entry_qnt` | Entry Quantity |
| `BASE_UOM` | `entry_uom` | Entry Unit of Measure |
| `GL_ACCOUNT` | `gl_account` | GL Account |
| `COSTCENTER` | `costcenter` | Cost Center |
| `ORDER_NO` | `orderid` | Order ID |
| `movementtype` | `move_type` | Movement Type (from header) |

### Code Mapping (bapi2017_gm_code)
| OData Field | BAPI Field | Description |
|-------------|------------|-------------|
| `ztype_gm` | `gm_code` | Goods Movement Code |

## Expected JSON Request Structure

### Single Item Processing
```json
{
  "gr_gi_slip_no": "GR001",
  "header_txt": "Test Goods Movement",
  "movementtype": "101",
  "doc_date": "2024-01-15",
  "pstng_date": "2024-01-15",
  "ztype_gm": "01",
  "GoodsMvtItemSet": [
    {
      "MATERIAL": "MAT001",
      "ITEM_NO": "000010",
      "MAT_DESC": "Test Material",
      "BASE_UOM": "EA",
      "QUANTITY": 10,
      "STRG_LOC": "0001",
      "PLANT": "1000",
      "GL_ACCOUNT": "400000",
      "COSTCENTER": "CC001",
      "ORDER_NO": "",
      "ITEM_OK": "X",
      "GR_GI_SLIP_NO": "GR001"
    }
  ]
}
```

### Batch Processing (50 Items)
```json
{
  "gr_gi_slip_no": "BATCH001",
  "header_txt": "Batch Goods Movement",
  "movementtype": "101", 
  "doc_date": "2024-01-15",
  "pstng_date": "2024-01-15",
  "ztype_gm": "01",
  "GoodsMvtItemSet": [
    {
      "MATERIAL": "MAT001",
      "ITEM_NO": "000010",
      "QUANTITY": 10,
      "PLANT": "1000",
      "STRG_LOC": "0001",
      "BASE_UOM": "EA"
    },
    {
      "MATERIAL": "MAT002", 
      "ITEM_NO": "000020",
      "QUANTITY": 5,
      "PLANT": "1000",
      "STRG_LOC": "0001",
      "BASE_UOM": "KG"
    }
    // ... up to 50 items
  ]
}
```

## Expected JSON Response Structure

### SUCCESS: FULLY (All 50 Records)
```json
{
  "gr_gi_slip_no": "BATCH001",
  "header_txt": "Batch: SUCCESS: FULLY - Success: 50, Failed: 0",
  "movementtype": "101",
  "doc_date": "2024-01-15", 
  "pstng_date": "2024-01-15",
  "mat_doc_num": "50 documents created",
  "ztype_gm": "01",
  "GoodsMvtItemSet": []
}
```

### PARTIAL SUCCESS (45 Success, 5 Failed)
```json
{
  "gr_gi_slip_no": "BATCH001",
  "header_txt": "Batch: PARTIAL SUCCESS - Success: 45, Failed: 5",
  "movementtype": "101", 
  "doc_date": "2024-01-15",
  "pstng_date": "2024-01-15",
  "mat_doc_num": "45 documents created",
  "ztype_gm": "01",
  "GoodsMvtItemSet": []
}
```

## Message Container Structure

The optimized method adds comprehensive messages to the OData message container:

### Main Status Message
- **Type**: 'S' (Success), 'W' (Warning), 'E' (Error)
- **Text**: `"SUCCESS: FULLY: All 50 goods movements created successfully"`

### Individual Success Messages
- **Type**: 'S'
- **Text**: `"SUCCESS: Item 000010: Material MAT001 - Document 5000000123"`

### Individual Failure Messages  
- **Type**: 'E'
- **Text**: `"FAILED: Item 000020: Material MAT002 - Error: Plant 1000 is not defined"`

### Processing Log Messages
- **Type**: 'I' 
- **Text**: `"Record 1: SUCCESS - Mat Doc: 5000000123"`

## Performance Optimizations

### Periodic Commits
- Commits every 10 successful transactions
- Reduces database lock time
- Improves performance for large batches

### Memory Management
- Variables cleared in each loop iteration
- Efficient table operations
- Garbage collection friendly

### Error Handling
- Individual item processing prevents cascade failures
- Detailed error tracking per item
- Proper transaction rollback for failed items

## Validation Rules

### Required Fields per Item
1. **MATERIAL** - Must not be initial
2. **PLANT** - Must not be initial  
3. **QUANTITY** - Must be > 0
4. **BASE_UOM** - Recommended for quantity validation

### Business Validations
- Material must exist in plant
- Storage location must be valid for plant
- Movement type must be allowed for material
- GL Account and Cost Center validation (if provided)

This optimized implementation provides robust batch processing with clear status reporting and maintains backward compatibility with single-item processing.