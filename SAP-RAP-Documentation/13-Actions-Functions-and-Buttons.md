# Chapter 13 — Actions, Functions and Buttons

[< Validations & Determinations](12-Validations-and-Determinations.md) | [Index](00-README.md) | [Next: Feature Control & Authorization >](14-Feature-Control-and-Authorization.md)

---

## 13.1 The four things you must do to get a working button

This is the checklist that turns an idea into a button on screen. Missing any one gives a silent
failure.

```
1. BDEF (base)        action acceptTravel result [1] $self;
2. Behavior pool      METHOD acceptTravel. ... ENDMETHOD.
3. BDEF (projection)  use action acceptTravel;
4. Metadata extension @UI.lineItem: [{ type: #FOR_ACTION, dataAction: 'acceptTravel', label: '...' }]
```

| Missing step | Symptom |
|---|---|
| 1 | Activation error in the behavior pool |
| 2 | Activation error in the BDEF ("method not implemented") |
| **3** | **Button never appears. No error anywhere.** ← by far the most common |
| 4 | Action exists in `$metadata` and is callable via OData/EML, but there is no button |

---

## 13.2 Action types

```abap
action              acceptTravel;                       " instance action
static action       archiveOldTravels;                  " not bound to an instance
factory action      copyTravel [1];                     " creates new instances
internal action     recalculatePrices;                  " BO-internal only, never in OData
function            getPriceBreakdown result [1..*] ZE_PriceLine;  " read-only, returns data
```

| Type | Bound to an instance? | Appears where in Fiori | Can change data |
|---|---|---|---|
| **Instance action** | Yes | Table toolbar (enabled when rows are selected) + Object Page header | Yes |
| **Static action** | No | Table toolbar, always enabled | Yes |
| **Factory action** | Optionally | Table toolbar | Creates instances |
| **Internal action** | Yes | Nowhere — not exposed | Yes |
| **Function** | Yes or no | Usually not rendered by default; called via OData/EML | **No** |

---

## 13.3 Instance actions

### Declaration

```abap
action ( features : instance ) acceptTravel result [1] $self;
```

| Part | Meaning |
|---|---|
| `action` | Instance-bound |
| `( features : instance )` | Enable dynamic enable/disable per instance (Chapter 14) |
| `acceptTravel` | Name. Case matters in the MDE's `dataAction`. |
| `result [1] $self` | Returns one instance of the same entity. Makes the UI refresh automatically. |

### Result cardinality and type

| Declaration | Returns |
|---|---|
| *(nothing)* | Nothing. The UI refreshes only what `side effects` says. |
| `result [1] $self` | The changed instance itself — **the normal choice** |
| `result [0..*] $self` | Several instances of the same entity |
| `result [0..*] ZR_BookingTP` | Instances of a different entity |
| `result [1] ZE_ActionOutput` | A non-persistent abstract entity — for returning computed data |

**Why `result [1] $self` matters:** without a result, the Fiori UI does not know the instance
changed. You would need a `side effects` clause for every affected field. With `$self`, the changed
instance comes back in the response and the UI repaints it directly.

### Implementation

```abap
METHOD acceptTravel.

  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      UPDATE FIELDS ( OverallStatus )
      WITH VALUE #( FOR key IN keys
                    ( %tky          = key-%tky
                      OverallStatus = zbp_r_traveltp=>c_status-accepted ) )
    FAILED   DATA(modify_failed)
    REPORTED DATA(modify_reported).

  failed   = CORRESPONDING #( DEEP modify_failed ).
  reported = CORRESPONDING #( DEEP modify_reported ).

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  result = VALUE #( FOR travel IN travels ( %tky   = travel-%tky
                                            %param = travel ) ).
ENDMETHOD.
```

`%param` carries the returned instance. For `result [1] $self`, `%param` is typed as the entity's
structure. For `result [1] ZE_ActionOutput` it is that abstract entity's structure.

---

## 13.4 Actions with parameters (dialogs)

When the action needs input from the user, Fiori renders a **dialog**. The input structure is a CDS
**abstract entity**.

### The abstract entity

```abap
@EndUserText.label: 'Parameters for deductDiscount'
define abstract entity ZE_DeductDiscountParams
{
  @EndUserText.label: 'Discount %'
  @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_DiscountRates', element: 'Rate' } }]
  discount_percent : abap.int1;

  @EndUserText.label: 'Reason'
  reason_code      : zde_discount_reason;

  @EndUserText.label: 'Comment'
  comment          : abap.char(100);
}
```

Notes:

- `define abstract entity` — no `select from`, no persistence. It exists only as a type.
- Annotations on its fields drive the dialog: labels, value helps, mandatory flags.
- `@EndUserText.label` on the entity becomes the dialog title.

### The BDEF

```abap
action ( features : instance ) deductDiscount
  parameter ZE_DeductDiscountParams
  result [1] $self;
```

### The projection BDEF

```abap
use action deductDiscount;
```

### The implementation

```abap
METHOD deductDiscount.

  " keys carries both the instance key and the parameter values
  DATA update_lines TYPE TABLE FOR UPDATE zr_traveltp.

  " --- validate the parameter BEFORE touching data ---
  LOOP AT keys INTO DATA(key) WHERE %param-discount_percent IS INITIAL
                                 OR %param-discount_percent > 80.
    APPEND VALUE #( %tky = key-%tky ) TO failed-travel.
    APPEND VALUE #( %tky = key-%tky
                    %msg = new_message( id       = 'ZTRAVEL_MSG'
                                        number   = '030'
                                        severity = if_abap_behv_message=>severity-error )
                    %element-BookingFee = if_abap_behv=>mk-on ) TO reported-travel.
  ENDLOOP.

  DATA(valid_keys) = keys.
  DELETE valid_keys WHERE %param-discount_percent IS INITIAL
                       OR %param-discount_percent > 80.
  CHECK valid_keys IS NOT INITIAL.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( BookingFee )
      WITH CORRESPONDING #( valid_keys )
    RESULT DATA(travels).

  LOOP AT travels INTO DATA(travel).
    DATA(pct) = valid_keys[ KEY entity %tky = travel-%tky ]-%param-discount_percent.
    APPEND VALUE #( %tky       = travel-%tky
                    BookingFee = travel-BookingFee * ( 100 - pct ) / 100 ) TO update_lines.
  ENDLOOP.

  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      UPDATE FIELDS ( BookingFee )
      WITH update_lines
    REPORTED DATA(update_reported).

  reported = CORRESPONDING #( DEEP update_reported ).

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel ALL FIELDS WITH CORRESPONDING #( valid_keys )
    RESULT DATA(travels_after).

  result = VALUE #( FOR t IN travels_after ( %tky = t-%tky %param = t ) ).
ENDMETHOD.
```

**Always validate action parameters in the action itself.** There is no validation mechanism for
action input — `validation` only fires on entity fields.

### Deep parameters

For an action whose input contains a nested table (e.g. "create a Travel with a list of Bookings"):

```abap
" the abstract entity tree
define abstract entity ZE_TravelTemplate
{
  key template_id : abap.char(10);
  agency_id       : /dmo/agency_id;

  _Bookings : composition [0..*] of ZE_BookingTemplate;
}

define abstract entity ZE_BookingTemplate
{
  key seq        : abap.int2;
  carrier_id     : /dmo/carrier_id;
  connection_id  : /dmo/connection_id;
}
```

```abap
" an abstract BDEF is needed for the hierarchy
abstract;
define behavior for ZE_TravelTemplate
with hierarchy
{
  association _Bookings { with draft; }
}
```

```abap
" the action
action createFromTemplate deep parameter ZE_TravelTemplate result [1] $self;
```

Deep parameters are powerful but Fiori Elements cannot render a dialog for them. They are for
EML/API consumers. For a UI, use a flat parameter and let the user add children afterwards.

---

## 13.5 Static actions

Not bound to an instance — a global button.

```abap
static action archiveOldTravels parameter ZE_ArchiveParams;
```

```abap
METHODS archiveOldTravels FOR MODIFY
  IMPORTING keys FOR ACTION Travel~archiveOldTravels.
```

```abap
METHOD archiveOldTravels.

  " keys has ONE line, with %param filled from the dialog. No instance keys.
  DATA(params) = keys[ 1 ]-%param.

  SELECT FROM ztravel
    FIELDS travel_uuid
    WHERE end_date < @params-cutoff_date
      AND overall_status = 'A'
    INTO TABLE @DATA(uuids).

  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      UPDATE FIELDS ( OverallStatus )
      WITH VALUE #( FOR u IN uuids
                    ( %tky-TravelUUID = u-travel_uuid
                      %tky-%is_draft  = if_abap_behv=>mk-off
                      OverallStatus   = 'Z' ) )
    REPORTED DATA(update_reported).

  reported = CORRESPONDING #( DEEP update_reported ).
ENDMETHOD.
```

> The `SELECT` here is acceptable because we are **finding** instances to act on, not reading BO
> state for a decision. The subsequent change goes through EML.

In the MDE, a static action goes on the **entity level**, not on a field:

```abap
@UI: { lineItem: [ { type: #FOR_ACTION, dataAction: 'archiveOldTravels',
                     label: 'Archive Old Travels' } ] }
annotate entity ZC_TravelTP with { ... }
```

---

## 13.6 Factory actions

A factory action **creates** instances. The canonical use is "Copy".

```abap
factory action copyTravel [1];
```

`[1]` = one new instance per selected instance.

```abap
METHOD copyTravel.

  " 1. Read the source instances with their children
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel BY \_Booking
      ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(bookings).

  " 2. Build the create payloads
  DATA travel_create  TYPE TABLE FOR CREATE zr_traveltp.
  DATA booking_create TYPE TABLE FOR CREATE zr_traveltp\_Booking.

  LOOP AT travels INTO DATA(travel).
    DATA(cid) = |COPY_{ sy-tabix }|.

    APPEND VALUE #( %cid         = cid
                    AgencyId     = travel-AgencyId
                    CustomerId   = travel-CustomerId
                    BeginDate    = travel-BeginDate
                    EndDate      = travel-EndDate
                    BookingFee   = travel-BookingFee
                    CurrencyCode = travel-CurrencyCode
                    Description  = |Copy of { travel-Description }|
                    OverallStatus = zbp_r_traveltp=>c_status-open )
           TO travel_create.

    " children, linked to the new parent via %cid_ref
    DATA(children) = VALUE #( FOR b IN bookings
                              WHERE ( TravelUUID = travel-TravelUUID )
                              ( %cid          = |{ cid }_B{ b-BookingId }|
                                CustomerId    = b-CustomerId
                                CarrierId     = b-CarrierId
                                ConnectionId  = b-ConnectionId
                                FlightDate    = b-FlightDate
                                FlightPrice   = b-FlightPrice
                                CurrencyCode  = b-CurrencyCode
                                BookingStatus = 'N' ) ).

    IF children IS NOT INITIAL.
      APPEND VALUE #( %cid_ref = cid
                      %target  = children ) TO booking_create.
    ENDIF.
  ENDLOOP.

  " 3. Create - deep, in one call
  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      CREATE FIELDS ( AgencyId CustomerId BeginDate EndDate BookingFee
                      CurrencyCode Description OverallStatus )
      WITH travel_create
      CREATE BY \_Booking
        FIELDS ( CustomerId CarrierId ConnectionId FlightDate
                 FlightPrice CurrencyCode BookingStatus )
        WITH booking_create
    MAPPED   DATA(create_mapped)
    FAILED   DATA(create_failed)
    REPORTED DATA(create_reported).

  " 4. Report the new keys back to the consumer
  mapped-travel  = create_mapped-travel.
  mapped-booking = create_mapped-booking.
  failed   = CORRESPONDING #( DEEP create_failed ).
  reported = CORRESPONDING #( DEEP create_reported ).

ENDMETHOD.
```

### `%cid` and `%cid_ref` — how deep create works

The new instances have **no key yet** (the framework assigns UUIDs at create time). So how do you
link a child to its parent?

| Component | Meaning |
|---|---|
| `%cid` | *Content ID*. A string **you** invent to identify a not-yet-created instance within this request. |
| `%cid_ref` | On a child: "my parent is the instance whose `%cid` is this". |
| `%target` | On a `CREATE BY \_Assoc`: the table of children to create under that parent. |
| `mapped-travel[ %cid = 'X' ]-TravelUUID` | After the create, the framework reports the real key it assigned to `%cid = 'X'`. |

`%cid` values must be unique **within one EML statement**. They have no meaning afterwards.

**Filling `mapped` is mandatory in a factory action.** The consumer (and the UI) uses it to navigate
to the newly created instance. Without it the copy is created but the user is not taken to it.

---

## 13.7 Functions

A `function` is a **read-only** operation that returns data.

```abap
function getPriceBreakdown result [1..*] ZE_PriceLine;
```

```abap
METHODS getPriceBreakdown FOR READ
  IMPORTING keys FOR FUNCTION Travel~getPriceBreakdown RESULT result.
```

Note `FOR READ`, not `FOR MODIFY`. A function must not change data — the framework enforces this by
giving the method no write access.

| | Action | Function |
|---|---|---|
| Handler | `FOR MODIFY` | `FOR READ` |
| May change data | Yes | **No** |
| OData | `POST` to an action | `GET` on a function import |
| Fiori Elements renders a button | Yes | Not by default |
| Cacheable | No | Yes |

Use functions for "calculate and show me something" operations that a Web API consumer will call.
For a UI button, an action with `result` is usually the better fit because Fiori Elements renders
it natively.

---

## 13.8 Putting the button on screen — the MDE

### In the List Report table toolbar

```abap
@UI.lineItem: [ { position: 10, importance: #HIGH },
                { type: #FOR_ACTION, dataAction: 'acceptTravel', label: 'Accept' },
                { type: #FOR_ACTION, dataAction: 'rejectTravel', label: 'Reject' } ]
TravelId;
```

### In the Object Page header

```abap
@UI.identification: [ { position: 10 },
                      { type: #FOR_ACTION, dataAction: 'acceptTravel', label: 'Accept' },
                      { type: #FOR_ACTION, dataAction: 'rejectTravel', label: 'Reject' } ]
TravelId;
```

### In a specific Object Page section

Put the `#FOR_ACTION` entry in the `@UI.fieldGroup` of that section:

```abap
@UI.fieldGroup: [ { qualifier: 'PriceGroup', position: 10 },
                  { qualifier: 'PriceGroup', type: #FOR_ACTION,
                    dataAction: 'deductDiscount', label: 'Apply Discount' } ]
BookingFee;
```

### Properties of a `#FOR_ACTION` entry

| Property | Meaning |
|---|---|
| `type: #FOR_ACTION` | This entry is a button, not a column |
| `dataAction` | **The action name, exactly as in the BDEF.** Case-sensitive |
| `label` | Button text |
| `invocationGrouping` | `#CHANGE_SET` (all selected instances in one transaction — the default) or `#ISOLATED` (each independently) |
| `emphasized` | `true` makes it the primary (blue) button |
| `position` | Order among the buttons |

### `invocationGrouping` — worth understanding

| Value | Behaviour with 10 selected rows |
|---|---|
| `#CHANGE_SET` | One call with 10 keys. If one fails, **all** fail. |
| `#ISOLATED` | Ten separate calls. Failures are independent. |

For a "post to accounting" style action where partial success is wrong, use `#CHANGE_SET`.
For a "send reminder email" style action, `#ISOLATED` is friendlier.

### Making a button unavailable

- **Statically** (never available in this service) — omit `use action` in the projection BDEF.
- **Dynamically** (available but greyed out for some instances) — `( features : instance )` plus
  a `FOR INSTANCE FEATURES` handler. See Chapter 14.

---

## 13.9 Calling actions from ABAP

```abap
" instance action, no parameter
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE acceptTravel
    FROM VALUE #( ( %tky-TravelUUID = lv_uuid
                    %tky-%is_draft  = if_abap_behv=>mk-off ) )
  RESULT   DATA(action_result)
  FAILED   DATA(failed)
  REPORTED DATA(reported).

" instance action with a parameter
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE deductDiscount
    FROM VALUE #( ( %tky-TravelUUID = lv_uuid
                    %tky-%is_draft  = if_abap_behv=>mk-off
                    %param-discount_percent = 15
                    %param-reason_code      = 'LOYAL' ) )
  RESULT DATA(discount_result).

" static action
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE archiveOldTravels
    FROM VALUE #( ( %param-cutoff_date = '20240101' ) ).

" function
READ ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE getPriceBreakdown
    FROM VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
  RESULT DATA(breakdown).

COMMIT ENTITIES.
```

Note: **actions use `MODIFY ENTITIES ... EXECUTE`; functions use `READ ENTITIES ... EXECUTE`.**

---

## 13.10 Calling actions over OData

```http
POST /sap/opu/odata4/sap/zui_travel_o4/srvd/sap/zsd_travel/0001/
     Travel(TravelUUID=guid'ABC...',IsActiveEntity=true)/
     com.sap.gateway.srvd.zsd_travel.v0001.acceptTravel
Content-Type: application/json
{ }
```

With a parameter:
```json
{ "discount_percent": 15, "reason_code": "LOYAL" }
```

The fully qualified action name comes from `$metadata`. If you are building an external integration,
read it from `$metadata` rather than constructing it — the namespace segment changes with the
service name and version.

---

## 13.11 Actions and the save sequence

An action runs in the **interaction phase**. It changes the transactional buffer, not the database.

Consequences:

- After `acceptTravel`, the status is in the buffer. `COMMIT ENTITIES` (or the UI's implicit save)
  still has to happen.
- Validations declared `on save { field OverallStatus; }` **will** run after your action, and can
  reject it. That is correct: an action is not above the BO's rules.
- If your action must do something at save time (write a change document, raise an event, call an
  API), do **not** do it in the action handler. Flag the instances in a `CLASS-DATA` on the global
  ABP class and act in `save_modified` — see Chapter 16.

---

## 13.12 Troubleshooting

| Symptom | Cause |
|---|---|
| Button does not appear | `use action X;` missing in the projection BDEF (check this first); or `dataAction` spelling/case does not match; or browser cache |
| Button appears but is always greyed out | `( features : instance )` declared and `get_instance_features` returns nothing or `disabled`. Return `if_abap_behv=>fc-o-enabled` |
| Button works but the screen does not update | No `result [1] $self`, and no `side effects` declaration |
| *"Action ... is not implemented"* | Method missing in the behavior pool, or its signature does not match (regenerate with `Ctrl + 1`) |
| Parameter dialog does not appear | The abstract entity is not activated, or `parameter` is missing in the BDEF, or the abstract entity is not exposed where required |
| Parameter dialog appears with no fields | The abstract entity has no annotated fields, or the field types are not renderable |
| Action fails silently for some rows | You filled `failed` but not `reported` — the UI has nothing to display |
| `%param` is empty in the handler | The BDEF declares no `parameter`, or the consumer did not send one |
| Factory action creates the instance but the UI does not navigate to it | `mapped` not filled |
| Action changes data but a validation reverts the save | Correct behaviour — fix the data or the validation |

---

## 13.13 Interview answer

> **"How do you implement an action in RAP?"**
>
> Four steps, and missing any one fails differently. Declare it in the base behavior definition —
> `action acceptTravel result [1] $self;`, where `result [1] $self` returns the changed instance so
> the UI repaints without an extra round trip. Implement the handler method, generated with
> `Ctrl + 1`: read the instances, apply the change with `MODIFY ENTITIES ... IN LOCAL MODE`, fill
> `result`. Expose it in the projection behavior definition with `use action acceptTravel;`. And
> annotate it in the metadata extension with `@UI.lineItem: [{ type: #FOR_ACTION, dataAction:
> 'acceptTravel', ... }]`.
>
> The step people forget is the third — without `use action` the button never appears and there is
> no error anywhere.
>
> The variants are: `static action` for something not bound to an instance, `factory action` for
> creating instances, which must fill `mapped` or the UI cannot navigate to the new record,
> `internal action` for BO-internal mechanisms that are never exposed, and `function`, which is
> read-only and uses `FOR READ` rather than `FOR MODIFY`.
>
> An action can take a `parameter` typed by a CDS abstract entity, which Fiori renders as a dialog —
> and you must validate those parameters inside the action, because `validation` only fires on
> entity fields.
>
> One architectural point: an action runs in the interaction phase and changes the buffer, so the
> BO's own validations still run afterwards and can reject it. An action is not above the rules.

## 13.14 Production considerations

- **Prefer `result [1] $self` over a side effect** for refreshing after an action — one round trip
  instead of two.
- **Choose `invocationGrouping` deliberately.** `#CHANGE_SET` means all selected instances fail
  together; `#ISOLATED` means they fail independently. For a posting action, all-or-nothing is
  usually right; for a notification, isolated is friendlier.
- **Re-check business preconditions inside the action.** Feature control only greys out the button;
  an API caller can still invoke it.
- **Do not put save-time work in the action handler.** Flag the instances and act in `save_modified`
  (Chapter 16), because the action runs in the interaction phase where the save has not happened.
- **Validate action parameters explicitly** — nothing else does.
- **Mass actions need the same set-based discipline** as determinations: no `SELECT` per key.
- **Deep parameters cannot be rendered by Fiori Elements.** They are for EML and API consumers; use
  a flat parameter for a UI dialog.

---

[< Validations & Determinations](12-Validations-and-Determinations.md) | [Index](00-README.md) | [Next: Feature Control & Authorization >](14-Feature-Control-and-Authorization.md)
