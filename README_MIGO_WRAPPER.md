# MIGO Deep Entity Wrapper Classes

This repository contains ABAP wrapper classes designed to handle multiple header items with their associated line items in JSON format, send them to a deep entity service, and return responses including MIGO (Material Document) numbers.

## Overview

The wrapper classes are designed to solve the following requirements:
- Accept multiple header items with their line items in JSON format
- Post data to a deep entity service (typically SAP OData service)
- Return all responses including generated MIGO numbers
- Handle authentication, CSRF tokens, and error handling

## Classes Included

### 1. ZCL_MIGO_DEEP_ENTITY_WRAPPER
Basic wrapper class with manual JSON handling.

### 2. ZCL_MIGO_WRAPPER_ENHANCED
Enhanced version with better JSON serialization/deserialization capabilities.

### 3. ZPR_MIGO_WRAPPER_EXAMPLE
Example program demonstrating usage.

## JSON Structure

The expected JSON format matches your provided structure:

```json
[
  {
    "ZtypeGm": "A007",
    "ZsubType": "R10",
    "Movementtype": "963",
    "DocDate": "/Date(1750099200000)/",
    "PstngDate": "/Date(1750099200000)/",
    "GrGiSlipNo": "GI407",
    "HeaderTxt": "Text Header 1",
    "HeaderToItemNav": [
      {
        "Material": "50000001",
        "Plant": "1000",
        "StgeLoc": "0001",
        "EntryQnt": "10",
        "EntryUom": "EA"
      },
      {
        "Material": "50000002",
        "Plant": "1000",
        "StgeLoc": "0001",
        "EntryQnt": "5",
        "EntryUom": "EA"
      }
    ]
  }
]
```

## Key Features

### 1. Multiple Header Support
- Handles batch processing of multiple headers
- Each header can contain multiple line items
- Maintains data integrity across headers

### 2. Authentication & Security
- Basic authentication support
- CSRF token handling for SAP systems
- Secure HTTP communication

### 3. Error Handling
- Comprehensive error handling with meaningful messages
- HTTP status code interpretation
- Exception management

### 4. JSON Processing
- Automatic conversion from ABAP structures to JSON
- Microsoft JSON date format support (`/Date(timestamp)/`)
- Response parsing back to ABAP structures

## Usage Examples

### Basic Usage

```abap
DATA: lo_wrapper TYPE REF TO zcl_migo_deep_entity_wrapper,
      lt_headers TYPE zcl_migo_deep_entity_wrapper=>tt_headers,
      lt_responses TYPE zcl_migo_deep_entity_wrapper=>tt_responses.

" Initialize wrapper
CREATE OBJECT lo_wrapper
  EXPORTING
    iv_service_url = 'http://your-server:8000/sap/opu/odata/sap/ZMM_MIGO_SRV/'
    iv_username    = 'your_username'
    iv_password    = 'your_password'.

" Prepare data (see example program for detailed data preparation)
" ... prepare lt_headers ...

" Post data and get responses
TRY.
  lt_responses = lo_wrapper->post_multiple_headers( lt_headers ).
  
  " Process responses
  LOOP AT lt_responses INTO DATA(ls_response).
    WRITE: / 'MIGO Number:', ls_response-migo_number.
  ENDLOOP.
  
CATCH cx_sy_exception INTO DATA(lx_exception).
  WRITE: / 'Error:', lx_exception->get_text( ).
ENDTRY.
```

### Enhanced Usage

```abap
DATA: lo_wrapper TYPE REF TO zcl_migo_wrapper_enhanced.

CREATE OBJECT lo_wrapper
  EXPORTING
    iv_service_url = 'http://your-server:8000/sap/opu/odata/sap/ZMM_MIGO_SRV/'
    iv_username    = 'your_username'
    iv_password    = 'your_password'
    iv_csrf_token  = 'your_csrf_token'.  " Optional - will be fetched if not provided

" Use enhanced wrapper with better JSON handling
lt_responses = lo_wrapper->post_headers_batch( lt_headers ).
```

## Response Structure

The wrapper returns structured responses containing:

```abap
" Response Header
header_id        TYPE char10,
migo_number      TYPE mblnr,     " Material Document Number
fiscal_year      TYPE mjahr,
success          TYPE abap_bool,
message          TYPE string,

" Response Items (for detailed item-level information)
response_items   TYPE tt_response_items
```

## Configuration

### Service URL
Update the default service URL in the constructor or pass it during instantiation:
```
http://your-sap-server:8000/sap/opu/odata/sap/ZMM_MIGO_SRV/
```

### Authentication
The wrapper supports:
- Basic HTTP authentication
- SAP session-based authentication
- CSRF token handling (automatic fetch if not provided)

## Error Handling

The wrapper handles various error scenarios:

1. **HTTP Errors**: 400, 401, 403, 500, etc.
2. **JSON Parsing Errors**: Invalid JSON structure
3. **Authentication Errors**: Invalid credentials
4. **Service Errors**: Backend service issues

## Best Practices

1. **Use Enhanced Version**: For production use, prefer `ZCL_MIGO_WRAPPER_ENHANCED`
2. **Error Handling**: Always wrap calls in TRY-CATCH blocks
3. **Authentication**: Use service user credentials, not personal accounts
4. **Batch Size**: Consider batch size limits for large datasets
5. **Logging**: Implement proper logging for debugging and monitoring

## Dependencies

- SAP NetWeaver ABAP Stack
- HTTP client functionality (`CL_HTTP_CLIENT`)
- JSON transformation capabilities
- OData service endpoint

## Customization

The wrapper classes can be extended for:
- Custom authentication methods
- Additional JSON transformations
- Specific error handling requirements
- Custom response processing

## Testing

Use the provided example program `ZPR_MIGO_WRAPPER_EXAMPLE` to test the functionality with sample data.

## Support

For issues or questions regarding the wrapper classes:
1. Check the error messages and logs
2. Verify service endpoint accessibility
3. Validate JSON structure
4. Check authentication credentials