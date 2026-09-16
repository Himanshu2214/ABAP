# Chapter 10 — Full CRUD Managed Application, Step by Step

[< Behavior Pool Classes](09-Behavior-Pool-Classes.md) | [Index](00-README.md) | [Next: Draft Handling >](11-Draft-Handling.md)

---

## 10.1 What this chapter builds

A complete, working, transactional Fiori app:

- List Report with filters and search
- Object Page with a General Information section and a Bookings table
- Create / Edit / Delete on Travel
- Create / Edit / Delete on Booking, inside the Travel
- Draft handling (auto-save, Cancel, Resume)
- Two validations, three determinations, two actions with buttons
- Optimistic and pessimistic locking
- Audit fields maintained automatically

**Total hand-written ABAP: roughly 200 lines.** Everything else is declaration.

---

## 10.2 Build order

Follow this order. Each step activates cleanly before you move on.

| Step | Object | Chapter reference |
|---|---|---|
| 1 | `ZTRAVEL`, `ZBOOKING` tables | [02](02-Data-Model-and-Tables.md) |
| 2 | `ZR_BookingTP`, then `ZR_TravelTP` | [03](03-Basic-Interface-View.md) |
| 3 | `ZTRAVEL_D`, `ZBOOKING_D` draft tables (ADT quick fix from the views) | [02](02-Data-Model-and-Tables.md) §2.5 |
| 4 | BDEF `ZR_TravelTP` | [08](08-Behavior-Definition.md) |
| 5 | Behavior pool `ZBP_R_TravelTP` (`Ctrl + 1`) | [09](09-Behavior-Pool-Classes.md) |
| 6 | Message class `ZTRAVEL_MSG` (SE91) + `ZCX_TRAVEL_MESSAGES` | [09](09-Behavior-Pool-Classes.md) §9.6 |
| 7 | Implement determinations, validations, actions | this chapter |
| 8 | `ZC_BookingTP`, then `ZC_TravelTP` | [04](04-Projection-View.md) |
| 9 | Projection BDEF `ZC_TravelTP` | [08](08-Behavior-Definition.md) §8.14 |
| 10 | Metadata extensions | [05](05-Metadata-Extension-and-UI-Annotations.md) |
| 11 | `ZSD_TRAVEL` + `ZUI_TRAVEL_O4`, Publish | [06](06-Service-Definition-and-Binding.md) |
| 12 | Preview and test | this chapter §10.8 |

> **Child before parent** in steps 2 and 8. The parent's `composition of` and
> `redirected to composition child` need the child to exist.

---

## 10.3 The three determinations

### `setInitialOverallStatus` — set a default on create

```abap
METHOD setInitialOverallStatus.

  " Read only the instances whose status is still empty
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( OverallStatus )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  DELETE travels WHERE OverallStatus IS NOT INITIAL.
  CHECK travels IS NOT INITIAL.

  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      UPDATE FIELDS ( OverallStatus )
      WITH VALUE #( FOR t IN travels
                    ( %tky          = t-%tky
                      OverallStatus = zbp_r_traveltp=>c_status-open ) )
    REPORTED DATA(update_reported).

  reported = CORRESPONDING #( DEEP update_reported ).

ENDMETHOD.
```

Points to note:

| Line | Why |
|---|---|
| `DELETE travels WHERE OverallStatus IS NOT INITIAL.` | Idempotency. A determination can be called more than once; never blindly overwrite. |
| `CHECK travels IS NOT INITIAL.` | Do not issue an empty `MODIFY`. |
| `zbp_r_traveltp=>c_status-open` | A constant in the global ABP class, not a literal `'O'` scattered through the code. |
| `reported = CORRESPONDING #( DEEP update_reported ).` | Propagate any messages the inner `MODIFY` produced. Skipping this swallows errors. |

Add the constants to the global class:

```abap
CLASS zbp_r_traveltp DEFINITION PUBLIC ABSTRACT FINAL FOR BEHAVIOR OF zr_traveltp.
  PUBLIC SECTION.
    CONSTANTS:
      BEGIN OF c_status,
        open      TYPE /dmo/overall_status VALUE 'O',
        accepted  TYPE /dmo/overall_status VALUE 'A',
        rejected  TYPE /dmo/overall_status VALUE 'X',
      END OF c_status.
ENDCLASS.
```

### `calculateTotalPrice` — a rollup from the children

```abap
METHOD calculateTotalPrice.

  " 1. Read the Travel headers (fee + currency)
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( BookingFee CurrencyCode )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  " 2. Read the Bookings by association (this is 'read by association', rba)
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel BY \_Booking
      FIELDS ( FlightPrice CurrencyCode )
      WITH CORRESPONDING #( travels )
    RESULT DATA(bookings).

  " 3. Sum per travel
  LOOP AT travels ASSIGNING FIELD-SYMBOL(<travel>).
    <travel>-TotalPrice = <travel>-BookingFee.
    LOOP AT bookings INTO DATA(booking)
         WHERE TravelUUID = <travel>-TravelUUID.
      IF booking-CurrencyCode = <travel>-CurrencyCode.
        <travel>-TotalPrice += booking-FlightPrice.
      ELSE.
        " Different currency -> convert. Never just add.
        <travel>-TotalPrice += zcl_travel_helper=>convert_currency(
                                 amount          = booking-FlightPrice
                                 source_currency = booking-CurrencyCode
                                 target_currency = <travel>-CurrencyCode ).
      ENDIF.
    ENDLOOP.
  ENDLOOP.

  " 4. Write back
  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      UPDATE FIELDS ( TotalPrice )
      WITH CORRESPONDING #( travels )
    REPORTED DATA(update_reported).

  reported = CORRESPONDING #( DEEP update_reported ).

ENDMETHOD.
```

**`READ ENTITIES ... BY \_Booking`** is the read-by-association form. It reads the children of the
given parents in one call, and the result carries the parent key (`TravelUUID`) so you can group.
This is how you do a header/item rollup in RAP. Do not `SELECT` from `ZBOOKING`.

The BDEF trigger:
```abap
determination calculateTotalPrice on modify { field BookingFee, CurrencyCode; }
```
For the rollup to also fire when a **Booking price** changes, add a determination on the **Booking**
entity that updates the parent — or, more simply, declare it on the Booking:

```abap
define behavior for ZR_BookingTP alias Booking
...
{
  determination calculateTotalPrice on modify { field FlightPrice, CurrencyCode; create; delete; }
}
```
with an implementation that reads `_Travel` and then triggers the parent's recalculation via an
`internal action`:

```abap
METHOD calculateTotalPrice.       " on the Booking handler
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Booking BY \_Travel
      FIELDS ( TravelUUID ) WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      EXECUTE recalculatePrices
      FROM CORRESPONDING #( travels )
    REPORTED DATA(exec_reported).
ENDMETHOD.
```
with `internal action recalculatePrices;` on the Travel entity. `internal` keeps it out of OData —
it is a BO-internal mechanism, not a user button.

### `setTravelId` — draw a number range number, on save

```abap
METHOD setTravelId.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( TravelId )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  " Only instances that do not yet have a number
  DELETE travels WHERE TravelId IS NOT INITIAL.
  CHECK travels IS NOT INITIAL.

  TRY.
      cl_numberrange_runtime=>number_get(
        EXPORTING nr_range_nr = '01'
                  object      = 'ZTRAVELID'
                  quantity    = CONV #( lines( travels ) )
        IMPORTING number      = DATA(number_range_key)
                  returncode  = DATA(number_range_return_code)
                  returned_quantity = DATA(number_range_returned_quantity) ).
    CATCH cx_number_ranges INTO DATA(lx_number_ranges).
      LOOP AT travels INTO DATA(travel).
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky = travel-%tky
                        %msg = lx_number_ranges ) TO reported-travel.
      ENDLOOP.
      RETURN.
  ENDTRY.

  " Distribute the block of numbers
  DATA(next) = number_range_key - number_range_returned_quantity.
  DATA update_lines TYPE TABLE FOR UPDATE zr_traveltp.
  LOOP AT travels INTO travel.
    next += 1.
    APPEND VALUE #( %tky     = travel-%tky
                    TravelId = next ) TO update_lines.
  ENDLOOP.

  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      UPDATE FIELDS ( TravelId )
      WITH update_lines
    REPORTED DATA(update_reported).

  reported = CORRESPONDING #( DEEP update_reported ).

ENDMETHOD.
```

Why `on save` and not `on modify`:

- A number range is a **scarce, non-transactional resource**. A number drawn during editing is
  consumed even if the user cancels the draft — producing permanent gaps.
- `on save { create; }` draws the number once, at activation, for instances that are really saved.

Prerequisite: create number range object `ZTRAVELID` in transaction `SNRO`, with interval `01`.

> Number ranges commit on their own database connection, which is legal in RAP (secondary
> connections are allowed in all phases — see Chapter 17, section 17.6).

---

## 10.4 The validations

### `validateDates`

```abap
METHOD validateDates.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( BeginDate EndDate )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  LOOP AT travels INTO DATA(travel).

    " clear previous state messages for this instance
    APPEND VALUE #( %tky = travel-%tky %state_area = 'VALIDATE_DATES' ) TO reported-travel.

    IF travel-BeginDate IS INITIAL.
      APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
      APPEND VALUE #( %tky              = travel-%tky
                      %state_area       = 'VALIDATE_DATES'
                      %msg              = NEW zcx_travel_messages(
                                            severity = if_abap_behv_message=>severity-error
                                            textid   = zcx_travel_messages=>begin_date_missing )
                      %element-BeginDate = if_abap_behv=>mk-on ) TO reported-travel.

    ELSEIF travel-EndDate IS INITIAL.
      APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
      APPEND VALUE #( %tky            = travel-%tky
                      %state_area     = 'VALIDATE_DATES'
                      %msg            = NEW zcx_travel_messages(
                                          severity = if_abap_behv_message=>severity-error
                                          textid   = zcx_travel_messages=>end_date_missing )
                      %element-EndDate = if_abap_behv=>mk-on ) TO reported-travel.

    ELSEIF travel-EndDate < travel-BeginDate.
      APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
      APPEND VALUE #( %tky              = travel-%tky
                      %state_area       = 'VALIDATE_DATES'
                      %msg              = NEW zcx_travel_messages(
                                            severity  = if_abap_behv_message=>severity-error
                                            textid    = zcx_travel_messages=>end_before_begin
                                            begindate = travel-BeginDate
                                            enddate   = travel-EndDate )
                      %element-BeginDate = if_abap_behv=>mk-on
                      %element-EndDate   = if_abap_behv=>mk-on ) TO reported-travel.

    ELSEIF travel-BeginDate < cl_abap_context_info=>get_system_date( ).
      " a warning, not an error: no entry in 'failed'
      APPEND VALUE #( %tky              = travel-%tky
                      %state_area       = 'VALIDATE_DATES'
                      %msg              = NEW zcx_travel_messages(
                                            severity  = if_abap_behv_message=>severity-warning
                                            textid    = zcx_travel_messages=>begin_date_in_past
                                            begindate = travel-BeginDate )
                      %element-BeginDate = if_abap_behv=>mk-on ) TO reported-travel.
    ENDIF.

  ENDLOOP.
ENDMETHOD.
```

The **warning** branch shows the mechanism clearly: a message in `reported` with no entry in
`failed` is informational and does not block the save. That is exactly the difference.

### `validateCustomer`

```abap
METHOD validateCustomer.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( CustomerId )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  " Collect the distinct customers once, then check with one SELECT.
  " Checking inside the LOOP would be a SELECT per row.
  DATA(customers) = travels.
  SORT customers BY CustomerId.
  DELETE ADJACENT DUPLICATES FROM customers COMPARING CustomerId.
  DELETE customers WHERE CustomerId IS INITIAL.

  IF customers IS NOT INITIAL.
    SELECT FROM /dmo/customer
      FIELDS customer_id
      FOR ALL ENTRIES IN @customers
      WHERE customer_id = @customers-CustomerId
      INTO TABLE @DATA(valid_customers).
  ENDIF.

  LOOP AT travels INTO DATA(travel).

    APPEND VALUE #( %tky = travel-%tky %state_area = 'VALIDATE_CUSTOMER' ) TO reported-travel.

    IF travel-CustomerId IS INITIAL
       OR NOT line_exists( valid_customers[ customer_id = travel-CustomerId ] ).
      APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
      APPEND VALUE #( %tky               = travel-%tky
                      %state_area        = 'VALIDATE_CUSTOMER'
                      %msg               = NEW zcx_travel_messages(
                                             severity   = if_abap_behv_message=>severity-error
                                             textid     = zcx_travel_messages=>customer_unknown
                                             customerid = travel-CustomerId )
                      %element-CustomerId = if_abap_behv=>mk-on ) TO reported-travel.
    ENDIF.
  ENDLOOP.
ENDMETHOD.
```

**Read master data in one set-based `SELECT`, outside the loop.** A validation runs on every save of
every instance; a `SELECT SINGLE` inside a loop over a mass update is the classic RAP performance
defect. Reading `/dmo/customer` with `SELECT` is correct here — it is *not* the BO's own data.

---

## 10.5 The actions

```abap
METHOD acceptTravel.

  " Set the status in the buffer
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

  " Read back and fill the action result so the UI refreshes
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  result = VALUE #( FOR travel IN travels ( %tky   = travel-%tky
                                            %param = travel ) ).
ENDMETHOD.
```

`rejectTravel` is identical with `c_status-rejected`.

The `result` with `%param` is what makes `result [1] $self` in the BDEF useful: the UI receives the
changed instance and repaints without an extra round trip.

Chapter 13 covers actions in depth, including parameters, dialogs and button placement.

---

## 10.6 The complete file inventory

| Object | Type | Lines (approx.) |
|---|---|---|
| `ZTRAVEL`, `ZBOOKING` | DDIC tables | 2 × 20 |
| `ZTRAVEL_D`, `ZBOOKING_D` | Draft tables | 2 × 22 (generated) |
| `ZR_TravelTP`, `ZR_BookingTP` | CDS view entities | 55 + 45 |
| `ZR_TravelTP` | BDEF | 90 |
| `ZBP_R_TravelTP` + local types | ABAP classes | **~200 (the only real code)** |
| `ZCX_TRAVEL_MESSAGES` | Exception class | 60 |
| `ZTRAVEL_MSG` | Message class | — (SE91) |
| `ZC_TravelTP`, `ZC_BookingTP` | CDS projections | 50 + 35 |
| `ZC_TravelTP` | Projection BDEF | 30 |
| `ZC_TravelTP`, `ZC_BookingTP` | Metadata extensions | 120 + 60 |
| `ZSD_TRAVEL` | Service definition | 10 |
| `ZUI_TRAVEL_O4` | Service binding | — (generated) |

---

## 10.7 What the framework did that you did not write

Worth listing explicitly, because it is the return on the declarative investment:

- `INSERT` / `UPDATE` / `DELETE` on both tables
- Reading with paging, filtering, sorting and `$expand`
- UUID key generation
- `CreatedBy`, `CreatedAt`, `LastChangedBy`, `LastChangedAt`, `LocalLastChangedAt`
- Lock acquisition and release, on the root, covering the children
- ETag generation and `If-Match` comparison
- Draft creation, auto-save, discard, resume, and the exclusive/optimistic lock transition
- Cascading delete of Bookings when a Travel is deleted
- Transaction boundaries, buffer management, `COMMIT`
- The whole OData V4 protocol implementation
- The whole Fiori UI

---

## 10.8 Testing

### In the Fiori Elements preview

| Test | Expect |
|---|---|
| Open the app | List Report, empty or with data |
| **Create** | Object Page in edit mode, a draft is created immediately |
| Leave `BeginDate` empty and press **Create** | Error message, save blocked, field highlighted |
| `EndDate` before `BeginDate` | Error on both fields |
| Enter a `BookingFee` | `TotalPrice` updates — **only if `side effects` is declared** |
| Add a Booking with "+" | Works — **only if `association _Booking { create; }`** is in the BDEF and `use association _Booking { create; }` in the projection BDEF |
| Press **Create** with valid data | Saves; `TravelId` gets a number; `CreatedBy`/`CreatedAt` are filled |
| Press **Accept Travel** | Status becomes Accepted, the column turns green |
| Open the same Travel in a second browser session and edit | *"Object is locked by user ..."* |
| Edit, close the browser, reopen | The draft is offered for resume |
| Delete a Travel that has Bookings | Both are deleted |

### With EML from an ABAP class

Do not rely only on the UI. A console app catches logic errors faster and can be kept as a test.

```abap
CLASS zcl_test_travel DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
ENDCLASS.

CLASS zcl_test_travel IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.

    MODIFY ENTITIES OF zr_traveltp
      ENTITY Travel
        CREATE FIELDS ( AgencyId CustomerId BeginDate EndDate BookingFee CurrencyCode Description )
        WITH VALUE #( ( %cid         = 'CID_1'
                        AgencyId     = '070001'
                        CustomerId   = '000001'
                        BeginDate    = cl_abap_context_info=>get_system_date( ) + 30
                        EndDate      = cl_abap_context_info=>get_system_date( ) + 40
                        BookingFee   = '20.00'
                        CurrencyCode = 'EUR'
                        Description  = 'Created from a test class' ) )
      MAPPED   DATA(mapped)
      FAILED   DATA(failed)
      REPORTED DATA(reported).

    IF failed IS NOT INITIAL.
      out->write( 'CREATE failed' ).
      out->write( reported ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES RESPONSE OF zr_traveltp
      FAILED   DATA(commit_failed)
      REPORTED DATA(commit_reported).

    IF commit_failed IS NOT INITIAL.
      out->write( 'COMMIT failed - a validation rejected it' ).
      out->write( commit_reported ).
      RETURN.
    ENDIF.

    out->write( |Created TravelUUID: { mapped-travel[ 1 ]-TravelUUID }| ).

  ENDMETHOD.
ENDCLASS.
```

Run with `F9` in ADT. Chapter 18 explains every statement here.

> **Note on draft:** the EML above creates an **active** instance directly, bypassing the draft.
> That is legal and is how background jobs and APIs should write to a draft-enabled BO.
> Drafts are a UI concept.

### ABAP Unit with the RAP test double framework

```abap
CLASS ltc_travel DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    CLASS-DATA environment TYPE REF TO if_cds_test_environment.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS validate_dates_rejects FOR TESTING RAISING cx_static_check.
ENDCLASS.

CLASS ltc_travel IMPLEMENTATION.

  METHOD class_setup.
    environment = cl_cds_test_environment=>create( i_for_entity = 'ZR_TRAVELTP' ).
  ENDMETHOD.

  METHOD class_teardown.
    environment->destroy( ).
  ENDMETHOD.

  METHOD setup.
    environment->clear_doubles( ).
  ENDMETHOD.

  METHOD validate_dates_rejects.
    MODIFY ENTITIES OF zr_traveltp
      ENTITY Travel
        CREATE FIELDS ( AgencyId CustomerId BeginDate EndDate CurrencyCode )
        WITH VALUE #( ( %cid       = 'T1'
                        AgencyId   = '070001'
                        CustomerId = '000001'
                        BeginDate  = '20260101'
                        EndDate     = '20250101'      " end before begin
                        CurrencyCode = 'EUR' ) )
      FAILED DATA(failed).

    COMMIT ENTITIES RESPONSE OF zr_traveltp FAILED DATA(commit_failed).

    cl_abap_unit_assert=>assert_not_initial(
      act = commit_failed
      msg = 'Validation validateDates should have rejected the save' ).
  ENDMETHOD.

ENDCLASS.
```

`CL_CDS_TEST_ENVIRONMENT` replaces the underlying tables with in-memory doubles, so the test does
not touch real data and runs in milliseconds. For BO-level testing there is also
`CL_BUSINESS_OBJECT_ENVIRONMENT` / the RAP BO test double framework, which lets you mock a
*dependent* BO your code calls via EML.

---

## 10.9 Things that will go wrong the first time

| Symptom | Cause | Fix |
|---|---|---|
| "+" button missing in the Bookings table | `association _Booking { create; }` missing in base BDEF, or `use association _Booking { create; }` missing in the projection BDEF | Add both |
| Action button missing | `use action X;` missing in the projection BDEF | Add it |
| Action button present but greyed out | `features : instance` declared but `get_instance_features` returns `disabled`, or returns nothing | Return `%action-X = if_abap_behv=>fc-o-enabled` |
| `TotalPrice` does not refresh on screen | `side effects` not declared | `field BookingFee affects field TotalPrice;` |
| Validation message appears but the record saves | `failed` not filled | `APPEND VALUE #( %tky = ... ) TO failed-travel.` |
| Validation message stays after the user fixes the data | `%state_area` not cleared first | Add the clearing entry at the start of the loop |
| Determination reads old values | Used `SELECT` instead of `READ ENTITIES` | Use EML |
| Draft table activation fails | Hand-typed structure does not match what the draft runtime expects on this release | Delete it and regenerate with the ADT quick fix (`Ctrl + 1` on the CDS entity); take the generated version as correct |
| *"Entity does not support CREATE"* | `create;` missing, or the projection lacks `use create;` | Add it |
| Runtime error *"COMMIT WORK not allowed"* | `COMMIT WORK` inside a handler | Remove it |
| Saved data does not appear in the list | A `where` clause in the projection filters it out | See Chapter 04, §4.7 |

---

## 10.10 Interview answer

> **"Walk me through building a transactional Fiori app with RAP."**
>
> Bottom up, in dependency order, activating each step before moving on: tables, then draft tables
> generated with the ADT quick fix, then the interface views — child before parent, because the
> parent's `composition of` needs the child to exist. Then the behavior definition and the behavior
> pool, generated with `Ctrl + 1`. Then the projection views, again child first, the projection
> behavior definition with its `use` statements, the metadata extensions, and finally the service
> definition and binding, which you publish.
>
> The business logic in a typical app is small — in this example three determinations, three
> validations and two actions, around 200 lines. Everything else is declaration: the framework
> provides CRUD on both tables, UUID key generation, the five admin fields, locking, ETags, draft
> with cancel and resume, cascading delete, the transaction boundary and the whole OData protocol.
>
> I test it with an EML console class before ever opening the UI, because that is the only place
> you can see `failed`, `reported` and `sy-subrc` after `COMMIT ENTITIES`.
>
> The failures to expect first time are all declarative: a missing `use action` so the button never
> appears, a missing `association _Booking { create; }` so the "+" is greyed out, a missing
> `side effects` so the calculated total looks stale, and a validation that fills `reported` but not
> `failed` so the record saves despite the error.

## 10.11 Production considerations

- **Constants, not literals.** Status values belong in the global ABP class, not scattered as `'A'`
  and `'O'` through the pool.
- **`reported = CORRESPONDING #( DEEP ... )` after every inner `MODIFY`**, or messages disappear.
- **Determinations must be idempotent** — they can run more than once per transaction.
- **Number ranges `on save`**, never `on modify`, or discarded drafts burn numbers.
- **Set-based master-data reads.** One `SELECT ... FOR ALL ENTRIES` outside the loop, never a
  `SELECT SINGLE` inside it.
- **Promote the playground class to an ABAP Unit test** rather than deleting it.
- **Run the full UI checklist (§10.8) after every transport to QA**, not just after the first — the
  declarative parts fail silently and only a checklist catches them.

---

[< Behavior Pool Classes](09-Behavior-Pool-Classes.md) | [Index](00-README.md) | [Next: Draft Handling >](11-Draft-Handling.md)
