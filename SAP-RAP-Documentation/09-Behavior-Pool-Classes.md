# Chapter 09 — Behavior Pool Classes (ABP), Line by Line

[< Behavior Definition](08-Behavior-Definition.md) | [Index](00-README.md) | [Next: CRUD Managed Walkthrough >](10-CRUD-Managed-Walkthrough.md)

---

## 9.1 Anatomy of a behavior pool

An **ABAP Behavior Pool (ABP)** is a global class declared `FOR BEHAVIOR OF <BDEF>`. Its real
content lives in its **local types** (the *Local Types* tab in ADT, the CCIMP include).

```
ZBP_R_TravelTP                            <- global class (usually almost empty)
  |
  +-- Local Types (CCIMP)
        |
        +-- lhc_Travel    : CL_ABAP_BEHAVIOR_HANDLER   <- interaction phase
        +-- lhc_Booking   : CL_ABAP_BEHAVIOR_HANDLER   <- one per entity (optional split)
        +-- lsc_ZR_TravelTP : CL_ABAP_BEHAVIOR_SAVER   <- save sequence (only if needed)
```

### Creating it

Open the BDEF, put the cursor on the class name in
`managed implementation in class ZBP_R_TravelTP unique;`, press **`Ctrl + 1`** →
*"Create behavior implementation class ZBP_R_TravelTP"*. ADT creates the global class with the
correct `FOR BEHAVIOR OF` clause.

Then put the cursor on each `validation` / `determination` / `action` name and press `Ctrl + 1`
again to generate the method. **Do this rather than typing signatures by hand.**

---

## 9.2 The global class

```abap
CLASS zbp_r_traveltp DEFINITION
  PUBLIC
  ABSTRACT
  FINAL
  FOR BEHAVIOR OF zr_traveltp.
ENDCLASS.

CLASS zbp_r_traveltp IMPLEMENTATION.
ENDCLASS.
```

| Clause | Why |
|---|---|
| `PUBLIC` | Required |
| `ABSTRACT FINAL` | It is never instantiated. The RAP runtime instantiates the *local* handler classes. `ABSTRACT FINAL` is ABAP's way of saying "static-only, no instances". |
| `FOR BEHAVIOR OF zr_traveltp` | Binds the pool to the BDEF. This is what grants the class privileged access to the BO. |

### When the global class is *not* empty

Use its `PUBLIC SECTION` for data that must be shared between the **handler** (interaction phase)
and the **saver** (save sequence). They are different classes with no other channel between them.

```abap
CLASS zbp_r_traveltp DEFINITION
  PUBLIC ABSTRACT FINAL
  FOR BEHAVIOR OF zr_traveltp.

  PUBLIC SECTION.
    " Bridge between interaction phase and save sequence.
    " Example: preliminary keys returned by a late-numbering API called in an action,
    " which must be resolved with CONVERT KEY inside save_modified.
    CLASS-DATA mapped_purchase_requisition TYPE RESPONSE FOR MAPPED i_purchaserequisitiontp.

    " Example: instances flagged during the interaction phase for extra processing at save.
    CLASS-DATA mt_travels_to_notify TYPE SORTED TABLE OF sysuuid_x16 WITH UNIQUE KEY table_line.

ENDCLASS.

CLASS zbp_r_traveltp IMPLEMENTATION.
ENDCLASS.
```

> **Caution.** `CLASS-DATA` in a behavior pool lives for the whole ABAP session, not just one RAP
> transaction. **Always clear it in `cleanup` and `cleanup_finalize`**, otherwise a second
> transaction in the same session inherits stale data. This is a real and hard-to-find bug class.

---

## 9.3 The handler class

```abap
CLASS lhc_Travel DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Travel RESULT result.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Travel RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Travel RESULT result.

    METHODS setTravelId             FOR DETERMINE ON SAVE
      IMPORTING keys FOR Travel~setTravelId.
    METHODS calculateTotalPrice     FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Travel~calculateTotalPrice.
    METHODS setInitialOverallStatus FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Travel~setInitialOverallStatus.

    METHODS validateDates    FOR VALIDATE ON SAVE IMPORTING keys FOR Travel~validateDates.
    METHODS validateCustomer FOR VALIDATE ON SAVE IMPORTING keys FOR Travel~validateCustomer.
    METHODS validateAgency   FOR VALIDATE ON SAVE IMPORTING keys FOR Travel~validateAgency.

    METHODS acceptTravel FOR MODIFY IMPORTING keys FOR ACTION Travel~acceptTravel RESULT result.
    METHODS rejectTravel FOR MODIFY IMPORTING keys FOR ACTION Travel~rejectTravel RESULT result.
    METHODS copyTravel   FOR MODIFY IMPORTING keys FOR ACTION Travel~copyTravel.

ENDCLASS.

CLASS lhc_Travel IMPLEMENTATION.
  METHOD get_instance_authorizations.
  ENDMETHOD.
  ...
ENDCLASS.
```

### Rules

| Rule | Detail |
|---|---|
| Inherits `CL_ABAP_BEHAVIOR_HANDLER` | Always |
| Implicitly `ABSTRACT FINAL` | You do not write it; the compiler applies it |
| Methods in `PRIVATE SECTION` | The runtime calls them through the framework, not through a normal reference |
| Method names are free | Except the predefined ones (`get_global_authorizations`, etc.). Match the BDEF name for readability |
| One handler class per entity | Not mandatory — one class can handle several entities — but strongly recommended |

### Naming convention

`lhc_<Alias>` — `lhc_Travel`, `lhc_Booking`. `lhc` = local handler class.
`lsc_<BDEF name>` — `lsc_ZR_TravelTP`. `lsc` = local saver class.
These are conventions ADT's quick fixes follow; stick to them so generated and hand-written code look alike.

---

## 9.4 Every handler method signature

### Determination

```abap
METHODS calculateTotalPrice FOR DETERMINE ON MODIFY
  IMPORTING keys FOR Travel~calculateTotalPrice.
```
```abap
METHODS setTravelId FOR DETERMINE ON SAVE
  IMPORTING keys FOR Travel~setTravelId.
```

| Parameter | Type | Contains |
|---|---|---|
| `keys` | `TABLE FOR DETERMINATION Travel~<name>` | The **keys only** of the triggered instances. Not the data — you must read it. |
| `reported` (implicit CHANGING) | `RESPONSE FOR REPORTED EARLY/LATE zr_traveltp` | Messages you want to return |
| `failed` (implicit CHANGING) | `RESPONSE FOR FAILED EARLY/LATE zr_traveltp` | Instances that failed |

### Validation

```abap
METHODS validateDates FOR VALIDATE ON SAVE
  IMPORTING keys FOR Travel~validateDates.
```
Same parameter shape. `keys` carries only keys.

### Action

```abap
" instance action with result
METHODS acceptTravel FOR MODIFY
  IMPORTING keys FOR ACTION Travel~acceptTravel RESULT result.

" instance action without result
METHODS recalculate FOR MODIFY
  IMPORTING keys FOR ACTION Travel~recalculate.

" static action
METHODS archiveOldTravels FOR MODIFY
  IMPORTING keys FOR ACTION Travel~archiveOldTravels.

" factory action
METHODS copyTravel FOR MODIFY
  IMPORTING keys FOR ACTION Travel~copyTravel.

" action with a parameter
METHODS deductDiscount FOR MODIFY
  IMPORTING keys FOR ACTION Travel~deductDiscount RESULT result.
```

| Parameter | Contains |
|---|---|
| `keys` | Keys of the selected instances, plus `%param` if the action has a `parameter` |
| `result` | What you return. Type `TABLE FOR ACTION RESULT Travel~<name>` |
| `mapped`, `failed`, `reported` | Implicit CHANGING |

### Feature control

```abap
METHODS get_instance_features FOR INSTANCE FEATURES
  IMPORTING keys REQUEST requested_features FOR Travel RESULT result.

METHODS get_global_features FOR GLOBAL FEATURES
  IMPORTING REQUEST requested_features FOR Travel RESULT result.
```

### Authorization

```abap
METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
  IMPORTING keys REQUEST requested_authorizations FOR Travel RESULT result.

METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
  IMPORTING REQUEST requested_authorizations FOR Travel RESULT result.
```

### Precheck

```abap
METHODS precheck_update FOR PRECHECK
  IMPORTING entities FOR UPDATE Travel.

METHODS precheck_delete FOR PRECHECK
  IMPORTING keys FOR DELETE Travel.

METHODS precheck_cba_Booking FOR PRECHECK
  IMPORTING entities FOR CREATE Travel\_Booking.
```
Runs **before** the data enters the transactional buffer. Requires `( precheck )` in the BDEF.

### Numbering (early numbering)

```abap
METHODS earlynumbering_create FOR NUMBERING
  IMPORTING entities FOR CREATE Travel.

METHODS earlynumbering_cba_Booking FOR NUMBERING
  IMPORTING entities FOR CREATE Travel\_Booking.
```

### Unmanaged-only methods

```abap
METHODS create FOR MODIFY IMPORTING entities FOR CREATE Travel.
METHODS update FOR MODIFY IMPORTING entities FOR UPDATE Travel.
METHODS delete FOR MODIFY IMPORTING keys     FOR DELETE Travel.
METHODS read   FOR READ   IMPORTING keys     FOR READ   Travel RESULT result.
METHODS lock   FOR LOCK   IMPORTING keys     FOR LOCK   Travel.

METHODS rba_Booking FOR READ
  IMPORTING keys_rba FOR READ Travel\_Booking FULL result_requested
  RESULT result LINK association_links.

METHODS cba_Booking FOR MODIFY
  IMPORTING entities_cba FOR CREATE Travel\_Booking.
```

Note the `\_Booking` syntax: in ABAP source, the composition is addressed as
`<Alias>\_<AssociationName>` with a **backslash**.

---

## 9.5 The three response parameters

Every handler method has these as implicit `CHANGING` parameters. You do not declare them; you just
use them.

### `reported` — messages

```abap
APPEND VALUE #( %tky = key-%tky
                %msg = NEW zcx_travel_messages(
                         severity = if_abap_behv_message=>severity-error
                         textid   = zcx_travel_messages=>begin_date_in_past
                         begindate = travel-BeginDate )
                %element-BeginDate = if_abap_behv=>mk-on )
       TO reported-travel.
```

| Component | Meaning |
|---|---|
| `%tky` | Which instance the message belongs to |
| `%msg` | The message object (must implement `IF_ABAP_BEHV_MESSAGE`) |
| `%element-<Field>` | Attaches the message to a **field**, so Fiori highlights it in red |
| `%state_area` | A named area for **state messages** (see below) |
| `%path` | For messages on a child, the path from the root |

`reported-travel` / `reported-booking` — one component per entity alias, lowercase.
`reported-%other` — for messages not tied to any instance.

### `failed` — rejection

```abap
APPEND VALUE #( %tky = key-%tky ) TO failed-travel.
```

Adding a key to `failed` tells the framework this instance could not be processed. In a validation,
this is what actually blocks the save. **A message in `reported` without an entry in `failed` does
not stop anything** — the user sees a red message and the document saves anyway. This is the single
most common validation bug.

Optional detail:
```abap
APPEND VALUE #( %tky = key-%tky
                %fail-cause = if_abap_behv=>cause-unauthorized ) TO failed-travel.
```

| `%fail-cause` | Meaning |
|---|---|
| `unspecific` | Default |
| `unauthorized` | Authorization failure |
| `locked` | Lock failure |
| `disabled` | Operation is disabled by feature control |
| `not_found` | Instance does not exist |
| `conflict` | ETag mismatch |
| `dependency` | A dependent object blocked it |

### `mapped` — key mapping

Only relevant for create operations.

```abap
APPEND VALUE #( %cid = entity-%cid
                TravelUUID = lv_new_uuid ) TO mapped-travel.
```

Tells the consumer "the instance you called `%cid = 'X'` now has key `TravelUUID = ...`".
In a **managed** BO this is filled by the framework. You fill it in unmanaged BOs and in factory
actions.

### `reported` EARLY vs LATE

```abap
CHANGING reported TYPE RESPONSE FOR REPORTED EARLY zr_traveltp   " interaction + early save
CHANGING reported TYPE RESPONSE FOR REPORTED LATE  zr_traveltp   " late save phase
```
`EARLY` messages can be shown to the user and the transaction can still be corrected.
`LATE` messages arrive after the point of no return — informational only.

### State messages — the right way to show a persistent validation error

A normal message disappears on the next round trip. A **state message** stays attached to the
instance until the validation clears it:

```abap
METHOD validateDates.
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel FIELDS ( BeginDate EndDate ) WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  LOOP AT travels INTO DATA(travel).

    " 1. ALWAYS clear the state area first for this instance
    APPEND VALUE #( %tky        = travel-%tky
                    %state_area = 'VALIDATE_DATES' )
           TO reported-travel.

    " 2. Then add the message only if the check fails
    IF travel-BeginDate > travel-EndDate.
      APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
      APPEND VALUE #( %tky        = travel-%tky
                      %state_area = 'VALIDATE_DATES'
                      %msg        = NEW zcx_travel_messages(
                                      severity = if_abap_behv_message=>severity-error
                                      textid   = zcx_travel_messages=>end_before_begin )
                      %element-BeginDate = if_abap_behv=>mk-on
                      %element-EndDate   = if_abap_behv=>mk-on )
             TO reported-travel.
    ENDIF.
  ENDLOOP.
ENDMETHOD.
```

**The "clear first, then add" pattern is mandatory.** Without the clearing entry, a message stays on
screen even after the user fixes the data. Every state-message validation must start with it.

---

## 9.6 The message class

Messages need a class implementing `IF_ABAP_BEHV_MESSAGE`. The standard pattern is an exception
class:

```abap
CLASS zcx_travel_messages DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_abap_behv_message.

    CONSTANTS:
      BEGIN OF end_before_begin,
        msgid TYPE symsgid VALUE 'ZTRAVEL_MSG',
        msgno TYPE symsgno VALUE '001',
        attr1 TYPE scx_attrname VALUE '',
        attr2 TYPE scx_attrname VALUE '',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF end_before_begin,

      BEGIN OF begin_date_in_past,
        msgid TYPE symsgid VALUE 'ZTRAVEL_MSG',
        msgno TYPE symsgno VALUE '002',
        attr1 TYPE scx_attrname VALUE 'BEGINDATE',
        attr2 TYPE scx_attrname VALUE '',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF begin_date_in_past,

      BEGIN OF customer_unknown,
        msgid TYPE symsgid VALUE 'ZTRAVEL_MSG',
        msgno TYPE symsgno VALUE '003',
        attr1 TYPE scx_attrname VALUE 'CUSTOMERID',
        attr2 TYPE scx_attrname VALUE '',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF customer_unknown.

    DATA: begindate  TYPE /dmo/begin_date,
          customerid TYPE /dmo/customer_id.

    METHODS constructor
      IMPORTING textid     LIKE if_t100_message=>t100key OPTIONAL
                severity   TYPE if_abap_behv_message=>t_severity DEFAULT if_abap_behv_message=>severity-error
                previous   LIKE previous OPTIONAL
                begindate  TYPE /dmo/begin_date OPTIONAL
                customerid TYPE /dmo/customer_id OPTIONAL.
ENDCLASS.

CLASS zcx_travel_messages IMPLEMENTATION.
  METHOD constructor.
    super->constructor( previous = previous ).
    me->begindate  = begindate.
    me->customerid = customerid.
    CLEAR me->textid.
    IF textid IS INITIAL.
      if_t100_message~t100key = if_t100_message=>default_textid.
    ELSE.
      if_t100_message~t100key = textid.
    ENDIF.
    me->if_abap_behv_message~m_severity = severity.
  ENDMETHOD.
ENDCLASS.
```

| Element | Purpose |
|---|---|
| `INTERFACES if_abap_behv_message` | Makes it usable as `%msg` |
| `CONSTANTS BEGIN OF ... msgid/msgno` | Points at a message in message class `ZTRAVEL_MSG` (SE91) |
| `attr1..attr4` | Names of **class attributes** whose values fill `&1`..`&4` in the message text |
| `DATA begindate` | The attribute referenced by `attr1` — **must be uppercase in `attr1`** |
| `m_severity` | `error` / `warning` / `information` / `success` |

> Message text in SE91, message class `ZTRAVEL_MSG`, number `002`:
> `Begin date &1 must not be in the past`.
> `&1` is filled from the `BEGINDATE` attribute because `attr1 = 'BEGINDATE'`.

### The quick alternative for messages without parameters

```abap
APPEND VALUE #( %tky = key-%tky
                %msg = new_message_with_text(
                         severity = if_abap_behv_message=>severity-error
                         text     = 'End date must be after begin date' ) )
       TO reported-travel.
```

`new_message_with_text( )` is inherited from `CL_ABAP_BEHAVIOR_HANDLER`. Convenient for prototyping.
**Not translatable** — do not ship it.

There is also:
```abap
%msg = new_message( id = 'ZTRAVEL_MSG' number = '002'
                    severity = if_abap_behv_message=>severity-error
                    v1 = travel-BeginDate )
```
which is translatable and needs no exception class. Good middle ground.

---

## 9.7 The saver class

```abap
CLASS lsc_ZR_TravelTP DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS finalize          REDEFINITION.
    METHODS check_before_save REDEFINITION.
    METHODS adjust_numbers    REDEFINITION.   " late numbering only
    METHODS save              REDEFINITION.   " unmanaged BOs
    METHODS save_modified     REDEFINITION.   " managed + additional/unmanaged save
    METHODS cleanup           REDEFINITION.
    METHODS cleanup_finalize  REDEFINITION.
ENDCLASS.
```

| | Detail |
|---|---|
| Inherits | `CL_ABAP_BEHAVIOR_SAVER` (or `CL_ABAP_BEHAVIOR_SAVER_FAILED` — see below) |
| Section | `PROTECTED SECTION` — these are redefinitions of protected methods |
| Implicitly | `ABSTRACT FINAL` |
| When needed | Unmanaged BOs; managed BOs with `with additional save` or `with unmanaged save`; any BO with `late numbering` |
| Not needed | A plain managed BO with no save enhancement — **do not create an empty saver class** |

**Saver methods receive no instance data as parameters** (except `save_modified`). In an unmanaged
BO you read your own transactional buffer. That asymmetry is deliberate: the saver operates on the
whole transaction, not on a request.

### `CL_ABAP_BEHAVIOR_SAVER_FAILED`

If your save can genuinely fail in the **late** phase — e.g. it calls a BAPI that may return
errors — inherit from `CL_ABAP_BEHAVIOR_SAVER_FAILED` instead. It gives `save_modified` access to
`failed` and `reported`, so the consumer learns what went wrong. `sy-subrc = 8` after
`COMMIT ENTITIES` signals a late-phase failure, and the consumer must issue an explicit
`ROLLBACK ENTITIES` before doing anything else.

Chapter 17 covers the full sequence.

---

## 9.8 The universal handler-method pattern

Almost every method you write follows the same four steps.

```abap
METHOD acceptTravel.

  " 1. READ - handler methods get keys, not data
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( OverallStatus BeginDate )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels)
    FAILED DATA(read_failed).

  " 2. DECIDE - pure business logic, no DB access
  DATA update_lines TYPE TABLE FOR UPDATE zr_traveltp.
  LOOP AT travels INTO DATA(travel).
    IF travel-OverallStatus = 'X'.
      APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
      APPEND VALUE #( %tky = travel-%tky
                      %msg = new_message( id = 'ZTRAVEL_MSG' number = '010'
                                          severity = if_abap_behv_message=>severity-error ) )
             TO reported-travel.
      CONTINUE.
    ENDIF.
    APPEND VALUE #( %tky = travel-%tky OverallStatus = 'A' ) TO update_lines.
  ENDLOOP.

  " 3. MODIFY - write back into the transactional buffer, never to the DB
  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      UPDATE FIELDS ( OverallStatus )
      WITH update_lines
    REPORTED DATA(update_reported).

  " 4. FILL RESULT - so the UI refreshes
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travels_after).

  result = VALUE #( FOR t IN travels_after ( %tky   = t-%tky
                                             %param = t ) ).
ENDMETHOD.
```

### Why `IN LOCAL MODE`

```abap
READ ENTITIES OF zr_traveltp IN LOCAL MODE
```

| Without `IN LOCAL MODE` | With `IN LOCAL MODE` |
|---|---|
| The call goes through the **full** BO stack: authorization checks, feature control, projection restrictions | The call goes **directly** to the transactional buffer |
| Read-only fields cannot be written | Read-only fields **can** be written |
| Recursion risk (determination triggers itself through the public interface) | No recursion through the public layer |
| Slower | Fast |

**Inside a behavior pool, always use `IN LOCAL MODE`** unless you specifically want the full checks.
Writing a `readonly` field like `OverallStatus` from an action is only possible with it.

### Why `FIELDS ( ... )` instead of `ALL FIELDS`

`ALL FIELDS` reads every field of every instance. On a wide entity in a mass action, that is
measurable. Read what you need.

Use `ALL FIELDS` when you are building a `result` that must return the full instance.

---

## 9.9 Splitting handler classes

One class per entity is the default. For a large root entity you can go further:

```abap
CLASS lhc_travel_validations DEFINITION INHERITING FROM cl_abap_behavior_handler. ... ENDCLASS.
CLASS lhc_travel_actions     DEFINITION INHERITING FROM cl_abap_behavior_handler. ... ENDCLASS.
CLASS lhc_travel_auth        DEFINITION INHERITING FROM cl_abap_behavior_handler. ... ENDCLASS.
```

The framework finds the method wherever it is, as long as each method is declared exactly once
across all handler classes in the pool. Declaring the same method twice is an activation error.

---

## 9.10 Auxiliary classes

For reusable logic that several handler methods share, and that needs privileged BO access:

```abap
" BDEF:
define behavior for ZR_TravelTP alias Travel
...
auxiliary class ZCL_TRAVEL_HELPER;
{ ... }
```

```abap
CLASS zcl_travel_helper DEFINITION
  PUBLIC
  FINAL
  FOR BEHAVIOR OF zr_traveltp.

  PUBLIC SECTION.
    CLASS-METHODS calculate_total_price
      IMPORTING travel_uuid TYPE sysuuid_x16
      RETURNING VALUE(total) TYPE /dmo/total_price.
ENDCLASS.
```

`FOR BEHAVIOR OF` gives the class the right to use `IN LOCAL MODE` and `PRIVILEGED` EML against
this BO. A plain class cannot.

**Do not move whole handler implementations into auxiliary classes.** SAP explicitly advises
against it: the handler methods are the framework's entry points and hollowing them out adds a call
layer without benefit. Use auxiliary classes for genuinely shared sub-logic.

---

## 9.11 What is forbidden in a behavior pool

| Forbidden | Why | Instead |
|---|---|---|
| `COMMIT WORK` / `ROLLBACK WORK` | RAP owns the transaction. Breaks the LUW; runtime error under strict mode | Let RAP commit; `COMMIT ENTITIES` only from outside the BO |
| Direct `INSERT`/`UPDATE`/`DELETE` on the persistent table | Bypasses the buffer; the framework will then overwrite or conflict | EML `MODIFY ENTITIES ... IN LOCAL MODE` |
| `SELECT` from the persistent table for BO data | Returns the **database** state, not the buffer. In a draft app you get the active row while the user is editing a draft | `READ ENTITIES ... IN LOCAL MODE` |
| `MESSAGE` without `INTO`, `WRITE`, `CALL SCREEN`, `LEAVE`, `STOP` | Dynpro statements. Runtime error | `reported` |
| `CALL TRANSACTION`, `SUBMIT` | Same | — |
| `WAIT`, `CALL FUNCTION ... DESTINATION` in the **late** save phase | Would break the single database transaction | Do it in the interaction or early save phase |
| `CALL FUNCTION ... IN UPDATE TASK` outside the late save phase | Cannot be unregistered; breaks draft | Only in the late save phase |
| Reading the **draft table** with SQL | Framework-owned structure | EML |

**The `SELECT` rule deserves emphasis.** It is the most frequent real-world defect in RAP code:

```abap
" WRONG - reads the database, ignores everything the user just typed
SELECT SINGLE * FROM ztravel WHERE travel_uuid = @key-TravelUUID INTO @DATA(ls).

" RIGHT - reads the transactional buffer, sees uncommitted changes
READ ENTITIES OF zr_traveltp IN LOCAL MODE
  ENTITY Travel ALL FIELDS WITH VALUE #( ( %tky = key-%tky ) )
  RESULT DATA(travels).
```

Reading **other** tables (master data, customizing) with `SELECT` is fine and normal. The rule is
about the BO's own data.

---

## 9.12 Checklist

- [ ] Global class is `PUBLIC ABSTRACT FINAL FOR BEHAVIOR OF <bdef>`.
- [ ] Handler classes inherit `CL_ABAP_BEHAVIOR_HANDLER`; methods in `PRIVATE SECTION`.
- [ ] Saver class inherits `CL_ABAP_BEHAVIOR_SAVER`; methods in `PROTECTED SECTION`; only created if needed.
- [ ] Every method signature was generated by `Ctrl + 1`, not typed.
- [ ] Every validation that rejects fills **both** `failed` and `reported`.
- [ ] State messages clear their `%state_area` before adding.
- [ ] All EML inside the pool uses `IN LOCAL MODE`.
- [ ] No `SELECT` on the BO's own persistent or draft tables.
- [ ] No `COMMIT WORK`.
- [ ] `CLASS-DATA` in the global class is cleared in `cleanup` and `cleanup_finalize`.

---

## 9.13 Interview answer

> **"What is a behavior pool, and what is the difference between `failed`, `reported` and `mapped`?"**
>
> A behavior pool is a global class declared `FOR BEHAVIOR OF <bdef>`. It is implicitly
> `ABSTRACT FINAL` because the RAP runtime instantiates the local classes inside it, never the
> global class. The content lives in the local types: handler classes inheriting
> `CL_ABAP_BEHAVIOR_HANDLER` for the interaction phase, and — only where needed — a saver class
> inheriting `CL_ABAP_BEHAVIOR_SAVER` for the save sequence.
>
> The three response parameters are implicit changing parameters on every handler method.
> **`failed`** says which instances could not be processed — adding a key there is what actually
> blocks the operation. **`reported`** carries the messages, optionally with `%element-<Field>` so
> Fiori highlights the right field and `%state_area` for messages that persist until cleared.
> **`mapped`** carries key-mapping information for create operations — which real key was assigned
> to which `%cid`.
>
> The pairing is the part that catches people. For an error you fill **both** `failed` and
> `reported`: `failed` alone blocks the save and tells the user nothing, `reported` alone shows a
> red error and saves the record anyway. For a warning you fill `reported` only, deliberately.
>
> And inside the pool every EML call uses `IN LOCAL MODE` — it goes straight to the buffer, skips
> authorization and feature control, and lets you write `readonly` fields, which is how a
> determination sets a field the consumer may not touch.

## 9.14 Production considerations

- **Never `SELECT` the BO's own persistent or draft tables.** In a draft app that reads the active
  row while the user edits the draft.
- **Never `COMMIT WORK` or `COMMIT ENTITIES`** inside the pool. The BO is not the transaction owner.
- **Clear `CLASS-DATA` in both `cleanup` and `cleanup_finalize`.** Class data survives the whole
  session; `cleanup_finalize` is the path taken when the early save phase rejects the save.
- **Do not create an empty saver class** "just in case" — only when a saver method is actually
  needed.
- **Use a translatable message mechanism.** `new_message_with_text( )` is for prototyping; grep for
  it as a release check.
- **State-message validations must clear their `%state_area` first**, or the error stays on screen
  after the user fixes the data.
- **Split handler classes per entity.** It keeps the pool readable, and each method may be declared
  only once across all handler classes.

---

[< Behavior Definition](08-Behavior-Definition.md) | [Index](00-README.md) | [Next: CRUD Managed Walkthrough >](10-CRUD-Managed-Walkthrough.md)
