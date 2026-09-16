# Chapter 26 — Anti-Patterns: What Not To Do

[< Transport & Deployment](25-Transport-and-Deployment.md) | [Index](00-README.md) | [Next: Interview Preparation >](27-Interview-Preparation.md)

---

## 26.1 How to use this chapter

Every entry is a **wrong / right pair** with the symptom it produces. These are the defects that
actually appear in RAP code reviews, ordered roughly by how much damage they do.

Use it as a review checklist as well as a reading chapter.

| # | Anti-pattern | Damage |
|---|---|---|
| 1 | `COMMIT WORK` in a handler or saver | Corrupts the LUW |
| 2 | `COMMIT ENTITIES` inside a behavior implementation | Same |
| 3 | Database modification inside `FOR MODIFY` | Bypasses the buffer; split transaction |
| 4 | Calling a BAPI that commits itself | Corrupts the LUW |
| 5 | `SELECT` on the BO's own tables | Reads stale data |
| 6 | `SELECT` inside a loop | N round trips |
| 7 | Message without `failed` | Record saves despite the error |
| 8 | Ignoring `%control` | Silently wipes fields |
| 9 | EML without `IN LOCAL MODE` inside the pool | Recursion, blocked writes, slow |
| 10 | Authorization only in the UI | Security hole |
| 11 | `@UI` on a reusable interface view | Leaks layout into every consumer |
| 12 | Number range in an `on modify` determination | Permanent number gaps |
| 13 | Non-idempotent determination | Overwrites user input |
| 14 | State message without clearing the state area | Error stays after the fix |
| 15 | Unmanaged buffer not cleared in `cleanup` | Second save misbehaves |
| 16 | `%key` instead of `%tky` in a draft BO | Operates on the wrong copy |
| 17 | Business logic in the projection layer | Bypassed by other consumers |
| 18 | Choosing `unmanaged` because tables already exist | 10× the code for no benefit |

---

## 26.2 Transaction control

### 1. `COMMIT WORK` in a handler or saver

```abap
" WRONG
METHOD acceptTravel.
  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel UPDATE FIELDS ( OverallStatus ) WITH ...
  COMMIT WORK.                          " <-- never
ENDMETHOD.
```

```abap
" RIGHT
METHOD acceptTravel.
  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel UPDATE FIELDS ( OverallStatus ) WITH ...
  " no commit. The RAP runtime owns the transaction.
ENDMETHOD.
```

**Symptom:** runtime error *"COMMIT WORK is not allowed here"* under strict mode; on older releases,
a silently split LUW and half-saved documents.

**Why:** the behavior object is not the transaction owner. The consumer (Fiori runtime, or your
calling program) decides when to commit.

### 2. `COMMIT ENTITIES` inside a behavior implementation

```abap
" WRONG
METHOD createPurchaseRequisition.
  MODIFY ENTITIES OF i_purchaserequisitiontp ENTITY purchaserequisition CREATE ...
  COMMIT ENTITIES.                      " <-- never inside the BO
ENDMETHOD.
```

```abap
" RIGHT
METHOD createPurchaseRequisition.
  MODIFY ENTITIES OF i_purchaserequisitiontp ENTITY purchaserequisition CREATE ...
  " both BOs commit together, in the caller's single LUW
ENDMETHOD.
```

**Symptom:** the called BO commits while yours has not; a failure afterwards leaves the two out of
step and unrecoverable.

**The rule:** `COMMIT ENTITIES` belongs to whoever *started* the transaction — the RAP runtime for
OData, or your own report/job. Never to a handler or saver.

### 3. Database modification inside `FOR MODIFY`

```abap
" WRONG
METHOD acceptTravel.
  LOOP AT keys INTO DATA(key).
    UPDATE ztravel SET overall_status = 'A'
      WHERE travel_uuid = @key-TravelUUID.       " <-- interaction phase!
  ENDLOOP.
ENDMETHOD.
```

```abap
" RIGHT
METHOD acceptTravel.
  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      UPDATE FIELDS ( OverallStatus )
      WITH VALUE #( FOR key IN keys ( %tky = key-%tky OverallStatus = 'A' ) )
    REPORTED DATA(rep).
  reported = CORRESPONDING #( DEEP rep ).
ENDMETHOD.
```

**Symptom:** the change is written even when the user later cancels; in a draft app it writes to the
active instance while the user is editing a draft; the framework's own save then overwrites it or
conflicts.

**Why:** direct database modification belongs in the **late save phase** only (Chapter 17, §17.6).
In a managed BO you write no persistence code at all.

### 4. Calling a BAPI that commits itself

```abap
" WRONG
METHOD save_modified.
  CALL FUNCTION 'BAPI_TRAVEL_CREATE' EXPORTING ... TABLES return = lt_return.
  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'.        " <-- never
ENDMETHOD.
```

```abap
" RIGHT
METHOD check_before_save.
  " surface errors while we can still go back
  CALL FUNCTION 'BAPI_TRAVEL_CREATE'
    EXPORTING testrun = abap_true
    TABLES    return  = DATA(lt_return).
  LOOP AT lt_return INTO DATA(ls) WHERE type CA 'EA'.
    APPEND VALUE #( %tky = ... ) TO failed-travel.
    APPEND VALUE #( %tky = ... %msg = ... ) TO reported-travel.
  ENDLOOP.
ENDMETHOD.

METHOD save_modified.
  CALL FUNCTION 'BAPI_TRAVEL_CREATE'
    EXPORTING testrun = abap_false
    TABLES    return  = DATA(lt_return).
  " no BAPI_TRANSACTION_COMMIT - RAP commits
ENDMETHOD.
```

**Symptom:** the BAPI's commit ends the LUW mid-save; the RAP framework's own write then belongs to
a different transaction.

**Also note the test run.** Without the `testrun = abap_true` call in `check_before_save`, a BAPI
error in `save_modified` occurs after the point of no return and becomes a dump.

---

## 26.3 Reading and writing the wrong way

### 5. `SELECT` on the BO's own tables

```abap
" WRONG
METHOD validateDates.
  LOOP AT keys INTO DATA(key).
    SELECT SINGLE begin_date, end_date FROM ztravel
      WHERE travel_uuid = @key-TravelUUID
      INTO @DATA(ls).                              " <-- reads the DATABASE
    ...
  ENDLOOP.
ENDMETHOD.
```

```abap
" RIGHT
METHOD validateDates.
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( BeginDate EndDate )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels).                          " <-- reads the BUFFER
  LOOP AT travels INTO DATA(travel).
    ...
  ENDLOOP.
ENDMETHOD.
```

**Symptom:** the validation passes on data the user just corrected, or fails on data they just
fixed. In a draft app it reads the *active* row while the user works on the *draft* — so it
validates values that are not on screen.

**The boundary:** `SELECT` on **other** tables (master data, customizing) is correct and normal.
`SELECT` on the BO's **own** persistent or draft tables is the defect.

### 6. `SELECT` inside a loop

```abap
" WRONG - 5000 travels = 5000 round trips
LOOP AT travels INTO DATA(travel).
  SELECT SINGLE customer_id FROM /dmo/customer
    WHERE customer_id = @travel-CustomerId INTO @DATA(found).
  IF sy-subrc <> 0.
    APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
  ENDIF.
ENDLOOP.
```

```abap
" RIGHT - one round trip, then O(1) lookups
DATA(customers) = travels.
SORT customers BY CustomerId.
DELETE ADJACENT DUPLICATES FROM customers COMPARING CustomerId.
DELETE customers WHERE CustomerId IS INITIAL.

IF customers IS NOT INITIAL.
  SELECT FROM /dmo/customer FIELDS customer_id
    FOR ALL ENTRIES IN @customers
    WHERE customer_id = @customers-CustomerId
    INTO TABLE @DATA(valid).
ENDIF.

LOOP AT travels INTO DATA(travel).
  IF NOT line_exists( valid[ customer_id = travel-CustomerId ] ).
    APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
  ENDIF.
ENDLOOP.
```

**Symptom:** the app is fine in DEV and unusable in PROD. Visible instantly in an `ST05` trace as
the same statement repeated N times.

### 9. EML without `IN LOCAL MODE` inside the behavior pool

```abap
" WRONG - inside a determination
MODIFY ENTITIES OF zr_traveltp                      " <-- no IN LOCAL MODE
  ENTITY Travel UPDATE FIELDS ( TotalPrice ) WITH ...
```

```abap
" RIGHT
MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
  ENTITY Travel UPDATE FIELDS ( TotalPrice ) WITH ...
```

**Symptoms, all three of them:**

- `TotalPrice` is `field ( readonly )`, so the write is **rejected** — the determination appears to
  do nothing;
- the call goes through the full BO stack, re-triggering authorization, feature control and
  potentially the determination itself (recursion);
- it is measurably slower.

**The rule:** inside a behavior pool, always `IN LOCAL MODE`. Outside it, never — you want the checks.

---

## 26.4 Getting the RAP contract wrong

### 7. A message without a `failed` entry

```abap
" WRONG - the user sees a red error and the record saves anyway
IF travel-EndDate < travel-BeginDate.
  APPEND VALUE #( %tky = travel-%tky
                  %msg = new_message( id = 'ZTRAVEL_MSG' number = '001'
                                      severity = if_abap_behv_message=>severity-error ) )
         TO reported-travel.
ENDIF.
```

```abap
" RIGHT - failed blocks the save, reported explains why
IF travel-EndDate < travel-BeginDate.
  APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.          " <-- blocks
  APPEND VALUE #( %tky = travel-%tky
                  %msg = new_message( id = 'ZTRAVEL_MSG' number = '001'
                                      severity = if_abap_behv_message=>severity-error )
                  %element-BeginDate = if_abap_behv=>mk-on
                  %element-EndDate   = if_abap_behv=>mk-on )
         TO reported-travel.                                       " <-- explains
ENDIF.
```

**The inverse is just as bad:** `failed` without `reported` blocks the save and tells the user
nothing. For an error, always fill **both**. For a warning, fill `reported` only — deliberately.

### 8. Ignoring `%control`

```abap
" WRONG - in an unmanaged update or save_modified
LOOP AT entities INTO DATA(entity).
  <buffered>-travel = CORRESPONDING #( entity MAPPING FROM ENTITY ).
ENDLOOP.
```

The consumer sent only `Description`. Every other field in `entity` is initial — so this writes
blanks over `AgencyId`, `CustomerId`, `BeginDate` and the rest.

```abap
" RIGHT - apply only what was actually sent
LOOP AT entities INTO DATA(entity).
  IF entity-%control-Description = if_abap_behv=>mk-on.
    <buffered>-travel-description = entity-Description.
  ENDIF.
  IF entity-%control-AgencyId = if_abap_behv=>mk-on.
    <buffered>-travel-agency_id = entity-AgencyId.
  ENDIF.
  " ... one block per field ...
ENDLOOP.
```

Or, with a control structure declared in the BDEF
(`mapping for ztravel control ztravel_x corresponding`), map `%control` into an x-structure and
drive a field-selective `UPDATE SET` — see Chapter 16, §16.6.

**Symptom:** a user edits one field and unrelated fields are wiped. Reported as "data loss", which
it is.

**This does not apply to managed BOs** — the framework honours `%control` for you. It is an
unmanaged / unmanaged-save concern.

### 14. State message without clearing the state area

```abap
" WRONG - the error stays on screen after the user fixes the data
LOOP AT travels INTO DATA(travel).
  IF travel-EndDate < travel-BeginDate.
    APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
    APPEND VALUE #( %tky = travel-%tky %state_area = 'VALIDATE_DATES' %msg = ... )
           TO reported-travel.
  ENDIF.
ENDLOOP.
```

```abap
" RIGHT - clear the area first, unconditionally, then add if still invalid
LOOP AT travels INTO DATA(travel).

  APPEND VALUE #( %tky = travel-%tky %state_area = 'VALIDATE_DATES' ) TO reported-travel.

  IF travel-EndDate < travel-BeginDate.
    APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
    APPEND VALUE #( %tky = travel-%tky %state_area = 'VALIDATE_DATES' %msg = ... )
           TO reported-travel.
  ENDIF.
ENDLOOP.
```

Use **one `%state_area` per validation**, or validations will clear each other's messages.

### 16. `%key` instead of `%tky` in a draft BO

```abap
" WRONG
READ ENTITIES OF zr_traveltp IN LOCAL MODE
  ENTITY Travel FIELDS ( TotalPrice )
  WITH VALUE #( ( TravelUUID = key-TravelUUID ) )     " which copy? active or draft?
  RESULT DATA(travels).
```

```abap
" RIGHT
READ ENTITIES OF zr_traveltp IN LOCAL MODE
  ENTITY Travel FIELDS ( TotalPrice )
  WITH CORRESPONDING #( keys )                        " keys carries %tky
  RESULT DATA(travels).
```

**Symptom:** the determination reads the *active* instance while the user is editing the *draft*,
so it sees old values, or returns nothing at all. `strict ( 2 )` catches most of these at
activation — another reason to switch it on.

### 13. Non-idempotent determination

```abap
" WRONG - overwrites whatever the user typed, every time it runs
METHOD setInitialOverallStatus.
  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel UPDATE FIELDS ( OverallStatus )
    WITH VALUE #( FOR key IN keys ( %tky = key-%tky OverallStatus = 'O' ) ).
ENDMETHOD.
```

```abap
" RIGHT - only fill what is still empty
METHOD setInitialOverallStatus.
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel FIELDS ( OverallStatus ) WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  DELETE travels WHERE OverallStatus IS NOT INITIAL.
  CHECK travels IS NOT INITIAL.

  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel UPDATE FIELDS ( OverallStatus )
    WITH VALUE #( FOR t IN travels ( %tky = t-%tky OverallStatus = 'O' ) ).
ENDMETHOD.
```

A determination can be called more than once in a transaction. Assume it will be.

### 12. Number range in an `on modify` determination

```abap
" WRONG
determination setTravelId on modify { create; }
```

```abap
" RIGHT
determination setTravelId on save { create; }
```

**Symptom:** permanent gaps in the document numbering, because every draft the user discards has
already consumed a number. In regulated scenarios that is an audit finding, not a cosmetic issue.

### 15. Unmanaged buffer / `CLASS-DATA` not cleared

```abap
" WRONG - cleanup implemented, cleanup_finalize forgotten
METHOD cleanup.
  lcl_buffer=>get_instance( )->clear( ).
ENDMETHOD.
```

```abap
" RIGHT - both paths clear the state
METHOD cleanup.
  lcl_buffer=>get_instance( )->clear( ).
  CLEAR zbp_r_traveltp=>mapped_purchase_requisition.
ENDMETHOD.

METHOD cleanup_finalize.
  lcl_buffer=>get_instance( )->clear( ).
  CLEAR zbp_r_traveltp=>mapped_purchase_requisition.
ENDMETHOD.
```

`CLASS-DATA` lives for the whole ABAP session, not the transaction. `cleanup_finalize` is the path
taken when the early save phase **rejects** the save — exactly the case where stale state then leaks
into the user's next attempt.

---

## 26.5 Architecture and layering

### 10. Authorization only in the UI

```abap
" WRONG - the only 'protection' is feature control
METHOD get_instance_features.
  result = VALUE #( FOR t IN travels
    ( %tky = t-%tky
      %action-acceptTravel = COND #( WHEN user_is_manager( ) THEN fc-o-enabled
                                                             ELSE fc-o-disabled ) ) ).
ENDMETHOD.
```

**Feature control only greys out the button.** A `POST` to the action URL still reaches the backend
and still succeeds. Anyone who can open DevTools can execute it.

```abap
" RIGHT - authorization enforces, feature control informs
METHOD get_instance_authorizations.
  " ... AUTHORITY-CHECK ...
  APPEND VALUE #( %tky = travel-%tky
                  %action-acceptTravel = COND #( WHEN authorized = abap_true
                                                 THEN if_abap_behv=>auth-allowed
                                                 ELSE if_abap_behv=>auth-unauthorized ) )
         TO result.
ENDMETHOD.

METHOD get_instance_features.
  " business state only: an accepted travel cannot be accepted again
  APPEND VALUE #( %tky = travel-%tky
                  %action-acceptTravel = COND #( WHEN travel-OverallStatus = 'A'
                                                 THEN if_abap_behv=>fc-o-disabled
                                                 ELSE if_abap_behv=>fc-o-enabled ) )
         TO result.
ENDMETHOD.
```

**The distinction to hold on to:**

| | Authorization | Feature control |
|---|---|---|
| Question | "May you?" | "Does it apply right now?" |
| Enforced by the framework | Yes | No — UI hint only |
| Bypassable by an API caller | No | Yes |
| Constants | `auth-allowed` / `auth-unauthorized` | `fc-o-enabled` / `fc-o-disabled` |

And remember DCL covers **reads** only. A user who can see nothing can still `PATCH` a guessed key
unless BDEF authorization stops them.

### 11. `@UI` annotations on a reusable interface view

```abap
" WRONG - in ZR_TravelTP
@UI.lineItem: [ { position: 10, importance: #HIGH } ]
travel_id as TravelId,
```

Every projection over this model now inherits that layout, including services built by other teams
years later.

```abap
" RIGHT - ZR_ stays neutral
@Metadata.ignorePropagatedAnnotations: true
define root view entity ZR_TravelTP ...
{
  travel_id as TravelId,
}
```
with the layout in the **metadata extension** on `ZC_TravelTP`.

**The layering rule:** business semantics go **down** (`@Semantics`, criticality calculations,
associations); presentation goes **up** (`@UI`, `@Search` for one app, value helps for one service).

### 17. Business logic in the projection layer

```abap
" WRONG - a validation only in the projection BDEF
projection;
define behavior for ZC_TravelTP alias Travel
{
  validation validateCreditLimit on save { create; }   " <-- only this service checks it
}
```

The rule is then **not** applied to an EML caller, a background job, a second service, or an API
binding over the same BO.

```abap
" RIGHT - the rule lives with the business object
managed implementation in class ZBP_R_TravelTP unique;
define behavior for ZR_TravelTP alias Travel
{
  validation validateCreditLimit on save { create; }   " every consumer
}
```

Projection-level validations and determinations are legitimate — but only for genuinely
**service-specific** behaviour (a default that only makes sense in this app). A business invariant
belongs in the base BDEF.

### 18. Choosing `unmanaged` because tables already exist

```abap
" WRONG reasoning: "we have existing tables, so we must go unmanaged"
unmanaged implementation in class ZBP_R_TravelTP unique;
```

```abap
" RIGHT: existing tables are fine for managed
managed implementation in class ZBP_R_TravelTP unique;
...
persistent table ztravel
```

`persistent table` accepts any DDIC table. What forces unmanaged is existing **transactional
logic** — an existing buffer, existing locking, existing update-task modules — not existing data.

Cost of getting this wrong: roughly 600–900 lines of hand-written buffer, lock, read, create,
update, delete and save code that the managed runtime would have provided for nothing
(Chapter 15, §15.8).

And if only the **save** is special, use `managed with unmanaged save` (Chapter 16), not a full
unmanaged BO.

---

## 26.6 Smaller but common

| Anti-pattern | Instead |
|---|---|
| `new_message_with_text( )` in production code | `new_message( id = ... number = ... )` — translatable |
| Hard-coded status literals (`'A'`, `'O'`) scattered through the pool | Constants in the global ABP class |
| `reported = CORRESPONDING #( DEEP ... )` omitted after an inner `MODIFY` | Always propagate; otherwise messages vanish |
| `ALL FIELDS` everywhere | `FIELDS ( ... )` except when returning a full instance |
| `RESULT DATA( )` when only existence matters | `LINK DATA( )` |
| Empty `MODIFY ENTITIES` with no rows | `CHECK tab IS NOT INITIAL` first |
| An empty saver class "just in case" | Do not create one unless a saver method is actually needed |
| Validation declared `on modify` | `on save` — `on modify` nags the user mid-typing |
| Validation not listed in `draft determine action Prepare` | List it, or errors appear only at Save |
| Calculated field with no `side effects` declaration | Declare it, or the UI shows a stale value |
| Hand-typed handler method signatures | Generate with `Ctrl + 1` |
| Hand-designed draft tables | Generate with the ADT quick fix |
| BDEF without `strict ( 2 )` | Add it; every error it raises is a real latent defect |
| Developing in `$TMP` | Create the package first |
| UAT signed off on the ADT preview | Use the real Launchpad app |
| Authorization tested as a developer | Test with a real business role |

---

## 26.7 Review checklist

Run this over any RAP change before it leaves DEV:

- [ ] No `COMMIT WORK` / `ROLLBACK WORK` / `COMMIT ENTITIES` anywhere in the behavior pool.
- [ ] No database modification outside the late save phase.
- [ ] No `SELECT` on the BO's own persistent or draft tables.
- [ ] No `SELECT` inside a loop.
- [ ] Every EML call inside the pool uses `IN LOCAL MODE`.
- [ ] Every rejecting validation fills **both** `failed` and `reported`.
- [ ] Every state message clears its `%state_area` first.
- [ ] Every determination is idempotent.
- [ ] `reported = CORRESPONDING #( DEEP ... )` after every inner `MODIFY`.
- [ ] `%control` respected in unmanaged / unmanaged-save update logic.
- [ ] `%tky` used throughout in draft-enabled BOs.
- [ ] Number ranges drawn `on save`, never `on modify`.
- [ ] `cleanup` **and** `cleanup_finalize` clear all own state.
- [ ] Authorization enforced in `FOR ... AUTHORIZATION`, not only in feature control.
- [ ] No `@UI` annotations on interface views.
- [ ] Business invariants in the base BDEF, not the projection.
- [ ] `strict ( 2 )` on.
- [ ] No `new_message_with_text` left in the code.
- [ ] No objects in `$TMP`.

---

[< Transport & Deployment](25-Transport-and-Deployment.md) | [Index](00-README.md) | [Next: Interview Preparation >](27-Interview-Preparation.md)
