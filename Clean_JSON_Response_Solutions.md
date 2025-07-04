# Clean JSON Response Solutions for SAP OData Deep Entity

## Problem
The current CREATE_DEEP_ENTITY implementation returns BAPI errors correctly but wraps them in OData error structure:

```json
{
  "error": {
    "message": {
      "value": "{\"response\":{\"grgislipno\":\"GI901\",\"overallstatus\":\"FAILED\"...}}"
    }
  }
}
```

**Desired Clean Response:**
```json
{
  "RESPONSE": {
    "GRGISLIPNO": "GI901",
    "OVERALLSTATUS": "FAILED",
    "RESULTS": [
      {
        "GRGISLIPNO": "GI902",
        "STATUS": "FAILED",
        "ERROR": "Posting only possible in periods 2025/06 and 2025/05 in company code 4000"
      }
    ]
  }
}
```

## Solution 1: Custom Response Override (Recommended)

Use the version in `Final_Clean_Response_DPC_EXT.abap` which:

1. **Processes all BAPI calls normally**
2. **Captures BAPI errors correctly** (as shown: "Posting only possible in periods...")
3. **Overrides response directly** using `mo_context->get_response()`
4. **Sets JSON content type** and appropriate HTTP status codes
5. **Returns empty OData entity** to bypass standard processing

**Key Changes:**
```abap
" Get the response object and set custom content
DATA: lo_response TYPE REF TO /iwbep/if_mgw_core_srv_runtime.
lo_response = mo_context.

" Set response content type to JSON
lo_response->get_response( )->set_header( 
  name = 'Content-Type' 
  value = 'application/json; charset=utf-8' 
).

" Set HTTP status code and response body
lo_response->get_response( )->set_status( lv_http_status ).
lo_response->get_response( )->set_text( lv_response_json ).

" Return empty entity to avoid OData processing
DATA: ls_dummy_entity TYPE zcl_zmm_migo_automatio_mpc=>ts_headerdummy.
copy_data_to_ref(
  EXPORTING
    is_data = ls_dummy_entity
  CHANGING
    cr_data = er_deep_entity
).
```

## Solution 2: Function Import (Alternative)

If Solution 1 doesn't work, create a **Function Import** instead of using CREATE_DEEP_ENTITY:

### Step 1: Create Function Import in SEGW
1. Go to **Service Builder (SEGW)**
2. Create **Function Import**: `ProcessGoodsMovement`
3. **Parameters:**
   - `IV_PAYLOAD` (String) - Input JSON payload
   - `EV_RESPONSE` (String) - Output JSON response

### Step 2: Implementation
```abap
METHOD processgoods_movementset_ge.
  
  " Deserialize input JSON
  DATA: ls_input TYPE your_input_structure.
  /ui2/cl_json=>deserialize( 
    EXPORTING json = iv_payload 
    CHANGING data = ls_input 
  ).
  
  " Process BAPI calls (same logic as current implementation)
  " ...BAPI processing logic...
  
  " Serialize response to clean JSON
  ev_response = /ui2/cl_json=>serialize( 
    data = ls_final_response 
    compress = abap_false 
    pretty_name = /ui2/cl_json=>pretty_mode-upper_case 
  ).
  
ENDMETHOD.
```

### Step 3: Usage
```javascript
// Instead of POST to entity
POST /sap/opu/odata/sap/ZMM_MIGO_AUTOMATION_SRV/HeaderDummySet

// Use Function Import
POST /sap/opu/odata/sap/ZMM_MIGO_AUTOMATION_SRV/ProcessGoodsMovement
{
  "IV_PAYLOAD": "{\"GrGiSlipNo\":\"GI901\",\"ToRealHeaders\":{...}}"
}
```

## Solution 3: REST Resource (Most Flexible)

Create a **REST Resource** using **SICF** transaction:

1. **Transaction SICF** → Create new service node
2. **Handler Class** → Implement `IF_HTTP_EXTENSION`
3. **Direct HTTP handling** → Complete control over response

```abap
METHOD if_http_extension~handle_request.
  
  DATA: lv_json_input TYPE string,
        lv_json_output TYPE string.
  
  " Get JSON payload
  lv_json_input = server->request->get_cdata( ).
  
  " Process (same BAPI logic)
  " ...
  
  " Set response
  server->response->set_header_field( 
    name = 'Content-Type' 
    value = 'application/json' 
  ).
  server->response->set_cdata( lv_json_output ).
  server->response->set_status( code = 200 reason = 'OK' ).
  
ENDMETHOD.
```

## Recommendation

**Try Solution 1 first** (using the `Final_Clean_Response_DPC_EXT.abap` file). If that doesn't work due to OData framework limitations, **use Solution 2** (Function Import) which is guaranteed to work and gives you complete control over the response format.

The BAPI processing logic is working correctly - you just need to bypass the OData response wrapper!

## Test Results Expected

With any of these solutions, your BAPI error will be returned as:

```json
{
  "RESPONSE": {
    "GRGISLIPNO": "GI901",
    "OVERALLSTATUS": "FAILED", 
    "RESULTS": [
      {
        "GRGISLIPNO": "GI902",
        "STATUS": "FAILED",
        "ERROR": "Posting only possible in periods 2025/06 and 2025/05 in company code 4000"
      }
    ]
  }
}
```

**HTTP Status Codes:**
- `200` - All successful
- `400` - All failed  
- `207` - Partial success