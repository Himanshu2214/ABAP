# Implementation Checklist for OData Deep Entity

## ✅ Step-by-Step Implementation

### 1. **SEGW Model Updates**
- [ ] Add response fields to your entity types:
  ```abap
  " HeaderDummy: ProcessStatus (String 20)
  " GoodsMovementHeader: MaterialDoc (String 10), DocYear (String 4), ProcessStatus (String 20)  
  " GoodsMovementItem: MaterialDoc (String 10), DocYear (String 4), ProcessStatus (String 20)
  ```

### 2. **Create/Update DPC_EXT Class**
- [ ] Create class `ZCL_ZGM_DPC_EXT` inheriting from `ZCL_ZGM_DPC`
- [ ] Copy the complete code from `ZCL_ZGM_DPC_EXT.abap`
- [ ] Replace placeholder class names with your actual MPC class names

### 3. **Configure Service in SEGW**
- [ ] Go to Service Implementation
- [ ] Set DPC Extension Class to `ZCL_ZGM_DPC_EXT`
- [ ] Generate runtime objects
- [ ] Activate the service

### 4. **Test the Implementation**

#### Test URL:
```
POST /sap/opu/odata/sap/ZGM_SRV/HeaderDummySet
Content-Type: application/json
```

#### Test Payload:
```json
{
  "GrGiSlipNo": "GI999",
  "ToGoodsMvmtHeader": [
    {
      "GrGiSlipNo": "GI999",
      "ZtypeGm": "A007",
      "ZsubType": "R10",
      "Movementtype": "963",
      "DocDate": "/Date(1750099200000)/",
      "PstngDate": "/Date(1750099200000)/",
      "HeaderTxt": "Test Header",
      "ToGoodsMvmtItem": [
        {
          "GrGiSlipNo": "GI999",
          "ItemNo": "0001",
          "Material": "TEST_MAT",
          "MatDesc": "Test Material",
          "BaseUom": "EA",
          "Quantity": "10",
          "StrgLoc": "0001",
          "Plant": "1000",
          "ItemOk": true
        }
      ]
    }
  ]
}
```

### 5. **Key Points to Verify**

- [ ] **Entity Set Name**: Ensure `HeaderDummySet` matches your entity set name
- [ ] **Entity Types**: Verify `ts_headerdummy`, `ts_goodsmovementheader`, `ts_goodsmovementitem` match your generated types
- [ ] **Navigation Properties**: Confirm `to_goods_mvmt_header` and `to_goods_mvmt_item` match your associations
- [ ] **BAPI Authorization**: Ensure user has proper authorization for `BAPI_GOODSMVT_CREATE`

### 6. **Expected Behavior**

✅ **Success Case**:
- Material document created
- Response includes `MaterialDoc` and `DocYear`
- `ProcessStatus = 'SUCCESS'`

⚠️ **ItemOk = false**:
- Item skipped with warning message
- Other items processed normally

❌ **Error Case**:
- Transaction rolled back
- Detailed error messages returned
- `ProcessStatus = 'ERROR'`

### 7. **Common Issues & Solutions**

| Issue | Solution |
|-------|----------|
| `BAPI_GOODSMVT_CREATE` not found | Check if movement type BAPI is available |
| Authorization dump | Ensure user has `/IWFND/ADMIN` and movement type authorization |
| Date conversion error | Verify OData date format `/Date(timestamp)/` |
| Deep entity not working | Check associations and navigation properties in SEGW |

### 8. **Testing Commands**

```bash
# Test metadata
GET /sap/opu/odata/sap/ZGM_SRV/$metadata

# Test deep entity creation  
POST /sap/opu/odata/sap/ZGM_SRV/HeaderDummySet

# Test with expand
GET /sap/opu/odata/sap/ZGM_SRV/HeaderDummySet('GI999')?$expand=ToGoodsMvmtHeader/ToGoodsMvmtItem
```

## 🔧 Replace These Placeholders:

- `ZGM_SRV` → Your service name
- `ZCL_ZGM_MPC` → Your model provider class  
- `ZCL_ZGM_DPC` → Your data provider class
- `HeaderDummySet` → Your entity set name (if different)

## 📝 Notes:

1. **Date Handling**: The code handles OData date format `/Date(1750099200000)/`
2. **Error Handling**: Uses proper OData message container for errors
3. **Transaction Management**: Proper BAPI commit/rollback handling
4. **ItemOk Logic**: Automatically skips items where `ItemOk = false`
5. **Batch Processing**: Handles multiple headers with multiple items each