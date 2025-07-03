# Flat Structure Implementation Guide

## Overview
The new flat structure approach combines header and item data into a single record, making it much simpler to send multiple goods movement records.

## OData Service URL
```
/sap/opu/odata/sap/ZMM01_MIGO_AUTO_SRV/GoodsMvtFlatSet
```

## Flat Structure Fields

### Header Fields (Common for grouped items)
- `ZtypeGm` - Goods Movement Type
- `ZsubType` - Sub Type  
- `Movementtype` - Movement Type (101, 261, etc.)
- `DocDate` - Document Date
- `PstngDate` - Posting Date
- `GrGiSlipNo` - GR/GI Slip Number
- `HeaderTxt` - Header Text

### Item Fields (Unique per item)
- `Material` - Material Number
- `ItemNo` - Item Number  
- `MatDesc` - Material Description
- `BaseUom` - Base Unit of Measure
- `Quantity` - Quantity
- `StrgLoc` - Storage Location
- `Plant` - Plant
- `GlAccount` - GL Account
- `Costcenter` - Cost Center
- `OrderNo` - Order Number
- `ItemOk` - Item OK Flag

### Response Fields
- `MatDocNum` - Material Document Number (Success)
- `Status` - Processing Status (SUCCESS/ERROR)
- `Message` - Response Message

## Usage Scenarios

### 1. Single Record Processing
**Request:**
```json
POST /sap/opu/odata/sap/ZMM01_MIGO_AUTO_SRV/GoodsMvtFlatSet
Content-Type: application/json

{
  "ZtypeGm": "A007",
  "ZsubType": "R11", 
  "Movementtype": "963",
  "DocDate": "/Date(1750099200000)/",
  "PstngDate": "/Date(1750099200000)/",
  "GrGiSlipNo": "GI903",
  "HeaderTxt": "Header Post 1",
  "Material": "50045457",
  "ItemNo": "000001",
  "MatDesc": "Item B1",
  "BaseUom": "EA",
  "Quantity": "1",
  "StrgLoc": "1082",
  "Plant": "4000",
  "GlAccount": "44041013",
  "Costcenter": "40010003",
  "OrderNo": "100130",
  "ItemOk": true
}
```

**Success Response:**
```json
{
  "d": {
    "ZtypeGm": "A007",
    "ZsubType": "R11",
    "Movementtype": "963", 
    "DocDate": "/Date(1750099200000)/",
    "PstngDate": "/Date(1750099200000)/",
    "GrGiSlipNo": "GI903",
    "HeaderTxt": "Header Post 1",
    "Material": "50045457",
    "ItemNo": "000001",
    "MatDesc": "Item B1",
    "BaseUom": "EA",
    "Quantity": "1",
    "StrgLoc": "1082",
    "Plant": "4000",
    "GlAccount": "44041013",
    "Costcenter": "40010003", 
    "OrderNo": "100130",
    "ItemOk": true,
    "MatDocNum": "4900001234",
    "Status": "SUCCESS",
    "Message": "Material Document 4900001234 created successfully"
  }
}
```

**Error Response:**
```json
{
  "d": {
    "ZtypeGm": "A007",
    "ZsubType": "R11",
    "Movementtype": "963",
    "DocDate": "/Date(1750099200000)/",
    "PstngDate": "/Date(1750099200000)/", 
    "GrGiSlipNo": "GI903",
    "HeaderTxt": "Header Post 1",
    "Material": "50045457",
    "ItemNo": "000001",
    "MatDesc": "Item B1",
    "BaseUom": "EA",
    "Quantity": "1",
    "StrgLoc": "1082",
    "Plant": "4000",
    "GlAccount": "44041013",
    "Costcenter": "40010003",
    "OrderNo": "100130", 
    "ItemOk": true,
    "MatDocNum": "",
    "Status": "ERROR",
    "Message": "Material not extended to Plant 4000/Sloc 1082"
  }
}
```

### 2. Multiple Records via $batch
**Request:**
```json
POST /sap/opu/odata/sap/ZMM01_MIGO_AUTO_SRV/$batch
Content-Type: multipart/mixed; boundary=batch_123

--batch_123
Content-Type: multipart/mixed; boundary=changeset_456

--changeset_456
Content-Type: application/http
Content-Transfer-Encoding: binary

POST GoodsMvtFlatSet HTTP/1.1
Content-Type: application/json

{
  "ZtypeGm": "A007",
  "ZsubType": "R11",
  "Movementtype": "963",
  "DocDate": "/Date(1750099200000)/",
  "PstngDate": "/Date(1750099200000)/",
  "GrGiSlipNo": "GI903", 
  "HeaderTxt": "Header Post 1",
  "Material": "50045457",
  "ItemNo": "000001",
  "MatDesc": "Item B1",
  "BaseUom": "EA",
  "Quantity": "1",
  "StrgLoc": "1082",
  "Plant": "4000",
  "GlAccount": "44041013",
  "Costcenter": "40010003",
  "OrderNo": "100130",
  "ItemOk": true
}

--changeset_456
Content-Type: application/http
Content-Transfer-Encoding: binary

POST GoodsMvtFlatSet HTTP/1.1
Content-Type: application/json

{
  "ZtypeGm": "A007",
  "ZsubType": "R11", 
  "Movementtype": "963",
  "DocDate": "/Date(1750099200000)/",
  "PstngDate": "/Date(1750099200000)/",
  "GrGiSlipNo": "GI904",
  "HeaderTxt": "Header Post 2",
  "Material": "50045458",
  "ItemNo": "000002",
  "MatDesc": "Item B2",
  "BaseUom": "EA", 
  "Quantity": "2",
  "StrgLoc": "1083",
  "Plant": "4000",
  "GlAccount": "44041013",
  "Costcenter": "40010004",
  "OrderNo": "100131",
  "ItemOk": true
}

--changeset_456--
--batch_123--
```

## How Records Are Grouped

The system automatically groups records by:
1. **GrGiSlipNo** - Same slip number
2. **ZtypeGm** - Same movement type
3. **Movementtype** - Same movement type

Records with the same grouping criteria will be processed as a single goods movement with multiple items.

### Example: Multiple Items, Same Document
If you send:
```json
// Record 1
{
  "GrGiSlipNo": "GI903",
  "ZtypeGm": "A007", 
  "Movementtype": "963",
  "Material": "50045457",
  "ItemNo": "000001",
  "Quantity": "1"
}

// Record 2  
{
  "GrGiSlipNo": "GI903",
  "ZtypeGm": "A007",
  "Movementtype": "963", 
  "Material": "50045458",
  "ItemNo": "000002",
  "Quantity": "2"
}
```

**Result:** One material document with 2 items

### Example: Separate Documents
If you send:
```json
// Record 1
{
  "GrGiSlipNo": "GI903",
  "ZtypeGm": "A007",
  "Movementtype": "963",
  "Material": "50045457"
}

// Record 2
{
  "GrGiSlipNo": "GI904", // Different slip number
  "ZtypeGm": "A007",
  "Movementtype": "963",
  "Material": "50045458"
}
```

**Result:** Two separate material documents

## Implementation Benefits

✅ **Simplified Structure** - No nested objects, flat field mapping
✅ **Flexible Grouping** - Automatic grouping by business logic
✅ **Batch Processing** - Multiple records via $batch requests
✅ **Clear Responses** - Individual status per record
✅ **Backward Compatible** - Can still process single records

## Error Handling

Each record gets individual status tracking:
- **SUCCESS** - Record processed successfully with material document number
- **ERROR** - Record failed with specific error message

The system continues processing other records even if some fail, providing comprehensive results for all submitted records.

## Performance Considerations

- Records are grouped and processed together when possible
- Each group creates one material document transaction
- Failed groups don't affect successful ones
- Efficient memory usage with flat structure