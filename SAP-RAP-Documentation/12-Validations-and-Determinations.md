# Chapter 12 — Validations and Determinations

[< Draft Handling](11-Draft-Handling.md) | [Index](00-README.md) | [Next: Actions & Buttons >](13-Actions-Functions-and-Buttons.md)

---

## 12.1 The distinction

| | Determination | Validation |
|---|---|---|
| Purpose | **Derive** data | **Check** data |
| May change data | Yes | **No** |
| May reject | No | Yes (`failed`) |
| Runs at | `finalize` (on save) or during interaction (on modify) | `check_before_save` (on save) or during interaction (on modify) |
| Handler signature | `FOR DETERMINE ON MODIFY` / `ON SAVE` | `FOR VALIDATE ON MODIFY` / `ON SAVE` |
| Typical | Fill `TotalPrice`, `CreatedBy`, a status, a number | Date range, referential integrity, business rules |

> A validation that changes data is a bug, even though the compiler allows it. RAP may execute
> validations in a different order, more than once, or skip them under `Activate optimized`.
> Data changed there can silently vanish.

---

## 12.2 Trigger syntax

```abap
determination <name> on modify { <condition>; }
determination <name> on save   { <condition>; }
validation    <name> on modify { <condition>; }
validation    <name> on save   { <condition>; }
```

### Conditions

| Condition | Fires when |
|---|---|
| `create` | The instance is created |
| `update` | The instance is updated |
| `delete` | The instance is deleted |
| `field F1, F2` | One of the named fields changes |
| `create; update;` | Either |
| `field F; create;` | F changes, **or** the instance is created |

Multiple conditions are combined with `;` and mean **OR**.

```abap
determination calculateTotalPrice on modify { field BookingFee, CurrencyCode; create; }
```
= "run when `BookingFee` changes, or when `CurrencyCode` changes, or when a Travel is created".

### `on modify` vs `on save` — the decision

| | `on modify` | `on save` |
|---|---|---|
| Runs | Immediately after the change, during the interaction phase | In the early save phase |
| User sees the result | Instantly (with a `side effects` declaration) | Only after saving |
| Can be triggered many times per transaction | Yes | Once per transaction |
| Sees the final document state | No — later changes may follow | Yes |
| Consumes external resources | Dangerous (number ranges, API calls) | Safe |

Rules of thumb:

- **Determinations that the user should see live** → `on modify`.
- **Determinations that consume a scarce resource** (number range, external ID) → `on save`.
- **Determinations that need the whole document** (a header total that depends on all items being
  final) → `on save`.
- **Validations** → almost always `on save`. An `on modify` validation nags the user mid-typing.

---

## 12.3 Determinations — worked examples

### A) Simple default on create

```abap
" BDEF
determination setBookingDate on modify { create; }
```

```abap
METHOD setBookingDate.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Booking
      FIELDS ( BookingDate )
      WITH CORRESPONDING #( keys )
    RESULT DATA(bookings).

  DELETE bookings WHERE BookingDate IS NOT INITIAL.     " idempotent
  CHECK bookings IS NOT INITIAL.

  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Booking
      UPDATE FIELDS ( BookingDate )
      WITH VALUE #( FOR b IN bookings
                    ( %tky        = b-%tky
                      BookingDate = cl_abap_context_info=>get_system_date( ) ) )
    REPORTED DATA(update_reported).

  reported = CORRESPONDING #( DEEP update_reported ).
ENDMETHOD.
```

### B) Derive from a foreign entity

Fill the flight price from the connection master data when carrier/connection/date change.

```abap
" BDEF
determination setFlightPrice on modify { field CarrierId, ConnectionId, FlightDate; }
```

```abap
METHOD setFlightPrice.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Booking
      FIELDS ( CarrierId ConnectionId FlightDate )
      WITH CORRESPONDING #( keys )
    RESULT DATA(bookings).

  DELETE bookings WHERE CarrierId IS INITIAL
                     OR ConnectionId IS INITIAL
                     OR FlightDate IS INITIAL.
  CHECK bookings IS NOT INITIAL.

  " ONE set-based read of the master data, outside the loop
  SELECT FROM /dmo/flight
    FIELDS carrier_id, connection_id, flight_date, price, currency_code
    FOR ALL ENTRIES IN @bookings
    WHERE carrier_id    = @bookings-CarrierId
      AND connection_id = @bookings-ConnectionId
      AND flight_date   = @bookings-FlightDate
    INTO TABLE @DATA(flights).

  DATA update_lines TYPE TABLE FOR UPDATE zr_traveltp\\Booking.

  LOOP AT bookings INTO DATA(booking).
    DATA(flight) = VALUE #( flights[ carrier_id    = booking-CarrierId
                                     connection_id = booking-ConnectionId
                                     flight_date   = booking-FlightDate ] OPTIONAL ).
    CHECK flight IS NOT INITIAL.
    APPEND VALUE #( %tky         = booking-%tky
                    FlightPrice  = flight-price
                    CurrencyCode = flight-currency_code ) TO update_lines.
  ENDLOOP.

  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Booking
      UPDATE FIELDS ( FlightPrice CurrencyCode )
      WITH update_lines
    REPORTED DATA(update_reported).

  reported = CORRESPONDING #( DEEP update_reported ).
ENDMETHOD.
```

Note `TYPE TABLE FOR UPDATE zr_traveltp\\Booking` — the **double backslash** addresses a child
entity of the BO in a derived type. A single backslash (`zr_traveltp\_Booking`) addresses the
*association*. Both appear in RAP code and they mean different things:

| Syntax | Means |
|---|---|
| `zr_traveltp\\Booking` | The **entity** `Booking` inside the BO `zr_traveltp` |
| `zr_traveltp\_Booking` | The **association** `_Booking` from the root |

### C) Header rollup from children

See Chapter 10, §10.3, `calculateTotalPrice`.

### D) Number range on save

See Chapter 10, §10.3, `setTravelId`.

### E) Child-to-parent propagation via an internal action

When a child change must update the parent, do **not** have the child determination write to the
parent directly — it creates an unclear dependency. Use an `internal action` on the parent:

```abap
" BDEF, Travel entity
internal action recalculatePrices;

" BDEF, Booking entity
determination notifyTravel on modify { field FlightPrice, CurrencyCode; create; delete; }
```

```abap
METHOD notifyTravel.                       " in lhc_Booking
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Booking BY \_Travel
      FIELDS ( TravelUUID )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      EXECUTE recalculatePrices
      FROM CORRESPONDING #( travels )
    REPORTED DATA(exec_reported).

  reported = CORRESPONDING #( DEEP exec_reported ).
ENDMETHOD.
```

`internal action` is never exposed in OData — it is a BO-internal mechanism.

---

## 12.4 Validations — worked examples

### A) Field-level check with a state message

See Chapter 10, §10.4, `validateDates`. The pattern:

```
1. READ the data
2. FOR EACH instance:
   a. APPEND a clearing entry for the %state_area
   b. IF the check fails:
        APPEND to failed
        APPEND to reported with %state_area, %msg, %element-<Field>
```

### B) Referential integrity, set-based

See Chapter 10, §10.4, `validateCustomer`. The pattern:

```
1. READ the data
2. Build a distinct list of foreign keys
3. ONE SELECT with FOR ALL ENTRIES
4. LOOP and check with line_exists( )
```

### C) Cross-entity validation (parent checks children)

"A Travel must have at least one Booking."

```abap
" BDEF, Travel entity
validation validateHasBookings on save { create; field OverallStatus; }
```

```abap
METHOD validateHasBookings.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel BY \_Booking
      FIELDS ( BookingUUID )
      WITH CORRESPONDING #( keys )
    LINK DATA(booking_links).

  LOOP AT keys INTO DATA(key).

    APPEND VALUE #( %tky = key-%tky %state_area = 'VALIDATE_BOOKINGS' ) TO reported-travel.

    IF NOT line_exists( booking_links[ source-%tky = key-%tky ] ).
      APPEND VALUE #( %tky = key-%tky ) TO failed-travel.
      APPEND VALUE #( %tky        = key-%tky
                      %state_area = 'VALIDATE_BOOKINGS'
                      %msg        = NEW zcx_travel_messages(
                                      severity = if_abap_behv_message=>severity-error
                                      textid   = zcx_travel_messages=>no_bookings ) )
             TO reported-travel.
    ENDIF.
  ENDLOOP.
ENDMETHOD.
```

`LINK DATA(booking_links)` returns the **association links** — pairs of (source key, target key) —
without reading the child data. Cheaper than reading the children when all you need is "does one
exist".

This is where a `composition [1..*]` cardinality would *not* have helped: cardinality is metadata,
not a constraint. This validation is the enforcement.

### D) Validation on delete

```abap
" BDEF
validation validateDeletable on save { delete; }
```

```abap
METHOD validateDeletable.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( OverallStatus TravelId )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  LOOP AT travels INTO DATA(travel).
    IF travel-OverallStatus = zbp_r_traveltp=>c_status-accepted.
      APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
      APPEND VALUE #( %tky = travel-%tky
                      %msg = new_message( id       = 'ZTRAVEL_MSG'
                                          number   = '020'
                                          severity = if_abap_behv_message=>severity-error
                                          v1       = travel-TravelId ) ) TO reported-travel.
    ENDIF.
  ENDLOOP.
ENDMETHOD.
```

> **Note on deletes:** in a `validation ... on save { delete; }` the instance is already marked for
> deletion in the buffer. `READ ENTITIES` still returns its data, which is what you need for the
> message. This works; it is one of the less obvious guarantees of the RAP buffer.

A `precheck` handler is the alternative when you want to reject the delete *before* it enters the
buffer at all — see Chapter 14.

---

## 12.5 Execution order

Within one save, the order is:

```
INTERACTION PHASE
  ...consumer changes...
  determinations 'on modify'  (after each triggering change)
  validations    'on modify'  (after each triggering change)

EARLY SAVE PHASE
  finalize()
     -> determinations 'on save' run here
  check_before_save()
     -> validations 'on save' run here
  [ if failed -> cleanup_finalize(), back to interaction phase ]

=== POINT OF NO RETURN ===

LATE SAVE PHASE
  adjust_numbers()
  save() / save_modified()
  cleanup()
```

### Order *within* a phase is not guaranteed

RAP does not promise that `validateDates` runs before `validateCustomer`. If validation B depends on
validation A having passed, that is a design smell — restructure so each validation is independent,
or merge them into one.

The same applies to determinations. If determination B needs the result of determination A:

- Either make A `on modify` and B `on save` (ordering by phase is guaranteed), or
- merge them, or
- have A trigger B via an `internal action`.

### Determinations can trigger determinations

A determination that changes field X will trigger any determination declared
`on modify { field X; }`. RAP handles this and re-runs the dependent determination. It also
**detects direct self-triggering** and raises an error.

It does **not** detect indirect cycles:

```
determination A on modify { field X; }  ->  changes Y
determination B on modify { field Y; }  ->  changes X
```

This loops until the framework's iteration limit and then dumps. Draw the graph.

---

## 12.6 Performance rules

These matter because determinations and validations run on **every** save, on **every** instance.

| Rule | Why |
|---|---|
| Never `SELECT SINGLE` inside a `LOOP AT keys` | A mass update of 5000 rows becomes 5000 round trips |
| Collect keys → one `SELECT ... FOR ALL ENTRIES` (or a range table) → `line_exists( )` | One round trip |
| `FIELDS ( ... )` in `READ ENTITIES`, not `ALL FIELDS` | Reads less |
| `CHECK <table> IS NOT INITIAL` before `MODIFY ENTITIES` | An empty modify still costs a framework round trip |
| `DELETE <table> WHERE <already set>` before writing | Idempotency **and** fewer writes |
| Use `LINK DATA(...)` instead of `RESULT DATA(...)` when you only need existence | Avoids reading child data |
| Prefer one determination triggered by several fields over several determinations | Fewer framework callbacks |
| Move expensive checks to `on save` | They then run once per transaction, not once per keystroke |

---

## 12.7 Debugging determinations and validations

### Setting a breakpoint that actually gets hit

The Fiori preview runs in a **different session** from your ADT debugger. Two options:

1. **External breakpoint** — in ADT, set the breakpoint, then right-click → *ABAP Debugger* →
   check that the *external* user matches the user running the browser. This is the normal way to
   debug from the Fiori preview.
2. **Drive the BO with EML from a class run** (`IF_OO_ADT_CLASSRUN`) and debug that with `F9`.
   Faster, reproducible, and it becomes a test. **Prefer this.**

### Checking what actually ran

Add a temporary message with the method name:

```abap
APPEND VALUE #( %tky = key-%tky
                %msg = new_message_with_text(
                         severity = if_abap_behv_message=>severity-information
                         text     = |calculateTotalPrice ran for { key-TravelUUID }| ) )
       TO reported-travel.
```
It appears in the Fiori message popover. Remove before transport.

### The four questions when "my determination does not run"

1. Is the trigger condition right? `field BookingFee` does not fire when `TotalPrice` changes.
2. Is it `on save` when you expected `on modify` (or vice versa)?
3. In a draft app: did the change happen on the **draft**, and are you reading with `%tky`?
4. Did you `DELETE` the instances out of your internal table with an over-eager idempotency check?

### The three questions when "my validation does not block"

1. Did you fill `failed`? A message alone does not block.
2. Is the validation listed in `draft determine action Prepare`? (Otherwise it only runs at Activate.)
3. Is the trigger condition ever true? `on save { create; }` does not fire on update.

---

## 12.8 Checklist

- [ ] Every determination is idempotent (checks whether the value is already set).
- [ ] Every determination ends with `reported = CORRESPONDING #( DEEP ... )`.
- [ ] No validation changes data.
- [ ] Every rejecting validation fills **both** `failed` and `reported`.
- [ ] Every validation with a state message clears its `%state_area` first.
- [ ] Number ranges and external calls are in `on save`, never `on modify`.
- [ ] No `SELECT` inside a loop.
- [ ] No `SELECT` on the BO's own tables at all.
- [ ] Every validation the user should see early is in `draft determine action Prepare`.
- [ ] No indirect determination cycles.

---

## 12.9 Interview answer

> **"What are validations and determinations, and when do they run?"**
>
> Both are declared in the behavior definition with a trigger time and a trigger condition, and
> implemented in the behavior pool. A **determination** derives data — it fills a field
> automatically. A **validation** checks data and rejects it, and must never change data.
>
> The trigger time is `on modify` or `on save`. `on modify` runs in the interaction phase
> immediately after the triggering change; `on save` runs in the early save phase — determinations
> when `finalize` is reached, validations when `check_before_save` is reached. So an `on save`
> determination is guaranteed to run before an `on save` validation, but the order of two
> validations within the same phase is **not** guaranteed, which means they must be independent.
>
> Practically: determinations the user should see live are `on modify`, and anything that consumes
> a scarce resource like a number range is `on save`, otherwise every discarded draft burns a
> number. Validations are almost always `on save`, because an `on modify` validation complains
> while the user is still typing.
>
> Two things I always check. A validation blocks the save by adding the key to **`failed`** — a
> message in `reported` alone shows a red error and saves the record anyway. And a determination
> must be **idempotent**, because it can be called more than once in a transaction.

## 12.10 Production considerations

- **Declare them in the base BDEF**, not the projection — a projection-level rule is bypassed by
  EML callers, jobs and any second service.
- **No `SELECT` inside a loop.** These run on every save of every instance; a mass update turns a
  `SELECT SINGLE` into thousands of round trips.
- **No external calls from `on modify`.** An HTTP or RFC call there fires on every field change.
- **Clear the `%state_area` first** in every state-message validation, and use one area per
  validation so they do not clear each other's messages.
- **List every user-visible validation in `draft determine action Prepare`**, or the user only
  learns about the problem when they press Save.
- **Draw the determination dependency graph** before adding the second determination to an entity.
  RAP detects direct self-triggering but not an indirect A→B→A cycle, which dumps.
- **Declare a `side effect` for every field a determination derives**, or the value is right on the
  server and stale on screen.

---

[< Draft Handling](11-Draft-Handling.md) | [Index](00-README.md) | [Next: Actions & Buttons >](13-Actions-Functions-and-Buttons.md)
