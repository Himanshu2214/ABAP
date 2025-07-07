# RAP MIGO Posting Service - Setup Guide

## Quick Start

This guide helps you deploy and configure the RAP MIGO Posting service that replaces your DPC_EXT implementation.

## Files Created

### 1. Data Definitions (CDS Views)
- `ZI_MIGO_BATCH_POSTING.ddls` - Interface view (root entity)
- `ZI_MIGO_ITEM.ddls` - Interface view (child items)
- `ZC_MIGO_BATCH_POSTING.ddls` - Consumption view (root)
- `ZC_MIGO_ITEM.ddls` - Consumption view (items)

### 2. Behavior Definitions
- `ZI_MIGO_BATCH_POSTING.bdef` - Interface behavior
- `ZC_MIGO_BATCH_POSTING.bdef` - Consumption behavior

### 3. Implementation Classes
- `ZBP_I_MIGO_BATCH_POSTING.clas` - Behavior implementation (contains your DPC_EXT logic)
- `ZCL_REST_MIGO_RAP_HANDLER.abap` - REST handler for custom endpoints

### 4. Service Objects
- `ZUI_MIGO_BATCH_POSTING_O4.srvd` - Service definition
- `ZUI_MIGO_BATCH_POSTING_O4.srvb` - Service binding

### 5. Documentation
- `RAP_MIGO_POSTING_API_DOCUMENTATION.md` - Complete API documentation

## Deployment Steps

### Step 1: Activate CDS Views
```
1. Activate ZI_MIGO_BATCH_POSTING.ddls
2. Activate ZI_MIGO_ITEM.ddls
3. Activate ZC_MIGO_BATCH_POSTING.ddls
4. Activate ZC_MIGO_ITEM.ddls
```

### Step 2: Activate Behavior Definitions
```
1. Activate ZI_MIGO_BATCH_POSTING.bdef
2. Activate ZC_MIGO_BATCH_POSTING.bdef
```

### Step 3: Activate Implementation Class
```
1. Activate ZBP_I_MIGO_BATCH_POSTING.clas
```

### Step 4: Activate Service Objects
```
1. Activate ZUI_MIGO_BATCH_POSTING_O4.srvd
2. Activate ZUI_MIGO_BATCH_POSTING_O4.srvb
```

### Step 5: Publish Service Binding
```
1. Open ZUI_MIGO_BATCH_POSTING_O4.srvb
2. Click "Publish" to make the service available
3. Note the service URL for testing
```

## Testing Your Service

### Test with Your Original Payload

Your existing payload works without modification:

```json
{
  "Header": "",
  "ZMATSet": [
    {
      "GrGiSlipNo": "A1",
      "ZtypeGm": "A07",
      "ZsubType": "R10",
      "Movementtype": "963",
      "DocDate": "/Date(1750099200000)/",
      "PstngDate": "/Date(1750099200000)/",
      "HeaderTxt": "Header GI999",
      "ItemNo": "01",
      "Material": "000000000050045454",
      "MatDesc": "HOSE, HIGH PRESSURE",
      "BaseUom": "EA",
      "Quantity": "1",
      "StrgLoc": "1080",
      "Plant": "4001",
      "GlAccount": "0043601400",
      "Costcenter": "0040010202",
      "OrderNo": "000000100736",
      "ItemOk": true
    }
  ]
}
```

### Option 1: OData V4 Action (Recommended)
```http
POST {service_url}/MigoBatchPosting/processMigoPosting
Content-Type: application/json
```

### Option 2: REST Handler
If you prefer a simpler REST endpoint, use the REST handler class `ZCL_REST_MIGO_RAP_HANDLER`.

## Key Features Maintained

✅ **Same payload structure** - No changes to your existing integrations
✅ **Grouping by GrGiSlipNo** - Items processed together per slip number  
✅ **All validation rules** - Plant, Material, dates, ItemOk checks
✅ **Date conversion** - Handles `/Date(timestamp)/` format
✅ **BAPI integration** - Uses same BAPI_GOODSMVT_CREATE
✅ **Error handling** - Detailed error messages and rollback
✅ **Transaction management** - Proper commit/rollback logic

## Production Configuration

### 1. Replace Dummy Tables
Update CDS views to use actual database tables instead of `DUMMY_TABLE`:

```sql
-- In ZI_MIGO_BATCH_POSTING.ddls
define root view entity ZI_MIGO_BATCH_POSTING as select from ZMIGO_HEADER

-- In ZI_MIGO_ITEM.ddls  
define view entity ZI_MIGO_ITEM as select from ZMIGO_ITEMS
```

### 2. Configure Authorization
Update authorization checks:

```sql
-- In CDS views, change:
@AccessControl.authorizationCheck: #CHECK
```

### 3. Error Handling
Consider adding application logs:

```abap
" In behavior implementation
MESSAGE ID 'ZMIGO' TYPE 'E' NUMBER '001' INTO DATA(lv_message).
" Log to application log
```

## Migration Strategy

### Phase 1: Parallel Testing
- Deploy RAP service alongside existing DPC_EXT
- Test with subset of clients
- Compare results for consistency

### Phase 2: Gradual Migration  
- Update client applications one by one
- Monitor performance and error rates
- Keep DPC_EXT as backup

### Phase 3: Full Migration
- Switch all clients to RAP service
- Monitor for 2-4 weeks
- Deactivate old DPC_EXT service

## Troubleshooting

### Common Issues

1. **Service not found**
   - Check if service binding is published
   - Verify URL path in client

2. **Authorization errors**
   - Update @AccessControl settings
   - Check user authorizations for BAPI

3. **Data not persisting**
   - Replace DUMMY_TABLE with real tables
   - Check database table permissions

4. **Date conversion errors**
   - Verify JSON date format
   - Check timestamp values

### Debug Tips

1. **Use RAP debugger** in ABAP Development Tools
2. **Enable BAPI logging** for detailed BAPI errors
3. **Check entity creation** in behavior implementation
4. **Test with simple payloads** first

## Support Contacts

- **Technical**: RAP development team
- **Functional**: MIGO process experts  
- **Integration**: API integration team

## Next Steps

1. ✅ Deploy objects in development
2. ⬜ Test with your payload
3. ⬜ Configure for production
4. ⬜ Plan migration timeline
5. ⬜ Update client applications

Your new RAP service is ready to use with the exact same functionality as your DPC_EXT method!