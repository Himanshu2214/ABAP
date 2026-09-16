# Chapter 23 — Testing and Debugging

[< Value Helps](22-Value-Helps-and-Text-Associations.md) | [Index](00-README.md) | [Next: Performance & Production Readiness >](24-Performance-and-Production-Readiness.md)

---

## 23.1 What is it?

A RAP application has four testable surfaces, and they fail in different ways:

```
  +--------------------------------------------------+
  | 4. UI          Fiori Elements preview / real app | layout, buttons, side effects
  +--------------------------------------------------+
  | 3. Service     OData: $metadata, GET, POST       | exposure, annotations, protocol
  +--------------------------------------------------+
  | 2. Behavior    EML from ABAP                     | validations, determinations, actions, save
  +--------------------------------------------------+
  | 1. Model       CDS views, Data Preview           | joins, fields, associations, DCL
  +--------------------------------------------------+
```

**Test from the bottom up.** A bug found at layer 1 costs a minute; the same bug found at layer 4
costs an afternoon, because the UI gives you almost no diagnostic information.

---

## 23.2 Why do we need it?

RAP's declarative parts fail *silently*. A missing `use action` produces no error anywhere — the
button simply is not there. A validation that fills `reported` but not `failed` shows a red message
and saves the record anyway. Neither is visible without a deliberate test.

And the Fiori preview is the **worst** place to discover this: it caches aggressively, it hides
server messages, and a stale browser cache looks exactly like a code defect.

---

## 23.3 Where is it used?

| Stage | Test |
|---|---|
| While writing a CDS view | Data Preview |
| While writing a behavior pool | EML console class (`IF_OO_ADT_CLASSRUN`) |
| Before committing to a transport | ABAP Unit + ATC |
| Before handing to QA | Fiori Elements preview, all flows |
| In QA | Real Launchpad app, real roles, real data volume |
| After go-live | SQL Monitor, application log, dump analysis |

---

## 23.4 Layer 1 — testing the CDS model

### Data Preview

Right-click the CDS view → **Open With → Data Preview** (or `F8`).

| Check | Why |
|---|---|
| Row count is plausible | A wrong association cardinality silently multiplies rows |
| No unexpected duplicates | The classic symptom of a `[0..1]` association that is really `[0..*]` |
| Amounts show a currency, quantities a unit | `@Semantics` annotations missing |
| Text fields populated | Path expression / association join condition wrong |
| Filter on a key returns exactly one row | Key definition wrong |

Data Preview runs **as you**, with DCL applied. To see whether DCL is the reason a row is missing,
compare with the same `SELECT` in a console class.

### Verifying DCL

```abap
" What the user actually sees (DCL applied)
SELECT FROM zc_traveltp FIELDS COUNT(*) INTO @DATA(with_dcl).

" What exists (interface view, no DCL if #NOT_REQUIRED)
SELECT FROM zr_traveltp FIELDS COUNT(*) INTO @DATA(without_dcl).

out->write( |visible: { with_dcl } of { without_dcl }| ).
```

If the two differ and you did not expect them to, the DCL is doing something you did not intend.

---

## 23.5 Layer 2 — the EML console class

**This is the single most valuable testing tool in RAP.** Before touching the UI, drive the business
object from ABAP where you can see `failed`, `reported` and `sy-subrc`.

```abap
CLASS zcl_travel_playground DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
ENDCLASS.

CLASS zcl_travel_playground IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.

    " ---------- CREATE ----------
    MODIFY ENTITIES OF zr_traveltp
      ENTITY Travel
        CREATE FIELDS ( AgencyId CustomerId BeginDate EndDate BookingFee CurrencyCode Description )
        WITH VALUE #( ( %cid         = 'C1'
                        AgencyId     = '070001'
                        CustomerId   = '000001'
                        BeginDate    = cl_abap_context_info=>get_system_date( ) + 30
                        EndDate      = cl_abap_context_info=>get_system_date( ) + 40
                        BookingFee   = '20.00'
                        CurrencyCode = 'EUR'
                        Description  = 'EML playground' ) )
      MAPPED   DATA(mapped)
      FAILED   DATA(failed)
      REPORTED DATA(reported).

    out->write( |--- after MODIFY ---| ).
    out->write( |failed:  { COND #( WHEN failed IS INITIAL THEN 'none' ELSE 'YES' ) }| ).
    out->write( reported ).

    IF failed IS NOT INITIAL.
      out->write( 'aborting - interaction phase rejected the create' ).
      RETURN.
    ENDIF.

    " ---------- COMMIT ----------
    COMMIT ENTITIES RESPONSE OF zr_traveltp
      FAILED   DATA(commit_failed)
      REPORTED DATA(commit_reported).

    out->write( |--- after COMMIT --- sy-subrc = { sy-subrc }| ).
    CASE sy-subrc.
      WHEN 0. out->write( |committed. UUID = { mapped-travel[ 1 ]-TravelUUID }| ).
      WHEN 4. out->write( 'EARLY SAVE rejected - a validation failed:' ).
              out->write( commit_reported ).
      WHEN 8. out->write( 'LATE SAVE failed - rolling back' ).
              ROLLBACK ENTITIES.
    ENDCASE.

  ENDMETHOD.
ENDCLASS.
```

Run with **`F9`**. Output appears in the ADT console.

### Why this beats the UI for diagnosis

| | Fiori preview | EML console class |
|---|---|---|
| See `failed` | No | Yes |
| See `reported` in full | Partly (popover) | Yes, complete |
| See `sy-subrc` after commit | No | Yes |
| Reproducible | No (cache, drafts, session) | Yes |
| Debuggable with `F9` | Awkward (external breakpoints) | Directly |
| Becomes a regression test | No | Yes — promote it to ABAP Unit |

### Useful playground snippets

```abap
" --- test a validation in isolation, without committing ------------------
COMMIT ENTITIES IN SIMULATION MODE
  RESPONSE OF zr_traveltp
  FAILED DATA(sim_failed) REPORTED DATA(sim_reported).
out->write( sim_reported ).          " all on-save validations ran; nothing was written

" --- test a determination: read the buffer after the modify ---------------
READ ENTITIES OF zr_traveltp
  ENTITY Travel ALL FIELDS
  WITH VALUE #( ( %tky-TravelUUID = uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
  RESULT DATA(after).
out->write( after ).                 " is TotalPrice what you expect?

" --- test an action -------------------------------------------------------
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel EXECUTE acceptTravel
  FROM VALUE #( ( %tky-TravelUUID = uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
  RESULT DATA(action_result) FAILED DATA(af) REPORTED DATA(ar).
out->write( action_result ).

" --- test feature control / authorization without attempting the operation -
READ ENTITIES OF zr_traveltp
  ENTITY Travel
    REQUEST VALUE #( %update = if_abap_behv=>mk-on
                     %delete = if_abap_behv=>mk-on
                     %action-acceptTravel = if_abap_behv=>mk-on )
    GET PERMISSIONS
    FROM VALUE #( ( %tky-TravelUUID = uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
  RESULT DATA(perms).
out->write( perms ).                 " exactly what the UI uses to enable buttons
```

`GET PERMISSIONS` is the honest answer to "why is my button greyed out" — it returns precisely what
Fiori asked for.

---

## 23.6 ABAP Unit — isolating the behavior

### The test doubles

| Class | Replaces | Use for |
|---|---|---|
| `cl_cds_test_environment` | The tables behind a **CDS entity** | Testing a RAP BO against in-memory data |
| `cl_osql_test_environment` | **Database tables** directly | Testing plain SQL / helper classes |
| RAP BO test double framework (BOTD) | A **dependent RAP BO** you call via EML | Testing code that calls `I_PurchaseRequisitionTP` without creating real documents |

> The BOTD class names differ by release (they are in the `CL_BOTD_*` family). Look them up with
> `Ctrl + Shift + A` in your system before using them; the concept below is stable, the names are
> what to verify.

### Skeleton

```abap
CLASS ltc_travel DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    CLASS-DATA cds_env TYPE REF TO if_cds_test_environment.

    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS teardown.

    METHODS create_valid_travel          FOR TESTING RAISING cx_static_check.
    METHODS end_before_begin_rejected    FOR TESTING RAISING cx_static_check.
    METHODS unknown_customer_rejected    FOR TESTING RAISING cx_static_check.
    METHODS total_price_is_rolled_up     FOR TESTING RAISING cx_static_check.
    METHODS accept_sets_status           FOR TESTING RAISING cx_static_check.
    METHODS accept_disabled_when_accepted FOR TESTING RAISING cx_static_check.
ENDCLASS.

CLASS ltc_travel IMPLEMENTATION.

  METHOD class_setup.
    cds_env = cl_cds_test_environment=>create( i_for_entity = 'ZR_TRAVELTP' ).
  ENDMETHOD.

  METHOD class_teardown.
    cds_env->destroy( ).
  ENDMETHOD.

  METHOD setup.
    cds_env->clear_doubles( ).
  ENDMETHOD.

  METHOD teardown.
    ROLLBACK ENTITIES.
  ENDMETHOD.
  ...
ENDCLASS.
```

`ROLLBACK ENTITIES` in `teardown` is important: it clears the transactional buffer between tests.
Without it, one test's uncommitted instances leak into the next.

### Testing a validation

```abap
METHOD end_before_begin_rejected.

  MODIFY ENTITIES OF zr_traveltp
    ENTITY Travel
      CREATE FIELDS ( AgencyId CustomerId BeginDate EndDate CurrencyCode )
      WITH VALUE #( ( %cid         = 'T1'
                      AgencyId     = '070001'
                      CustomerId   = '000001'
                      BeginDate    = '20260601'
                      EndDate      = '20260501'      " <-- before begin
                      CurrencyCode = 'EUR' ) )
    FAILED   DATA(failed)
    REPORTED DATA(reported).

  " The interaction phase accepts it; the ON SAVE validation rejects it.
  cl_abap_unit_assert=>assert_initial(
    act = failed
    msg = 'create itself should not fail - validateDates is ON SAVE' ).

  COMMIT ENTITIES RESPONSE OF zr_traveltp
    FAILED   DATA(commit_failed)
    REPORTED DATA(commit_reported).

  cl_abap_unit_assert=>assert_equals(
    exp = 4  act = sy-subrc
    msg = 'early save phase should have rejected the document' ).

  cl_abap_unit_assert=>assert_not_initial(
    act = commit_failed-travel
    msg = 'validateDates should have filled failed-travel' ).

  cl_abap_unit_assert=>assert_not_initial(
    act = commit_reported-travel
    msg = 'validateDates should also have produced a message' ).

ENDMETHOD.
```

> Asserting on **both** `failed` and `reported` is deliberate. It is exactly the defect described in
> Chapter 20, §20.4: a validation that reports without failing lets the record save. A test that
> only checks `sy-subrc` will not catch the reverse case — a validation that fails silently with no
> message.

### Testing a determination

```abap
METHOD total_price_is_rolled_up.

  MODIFY ENTITIES OF zr_traveltp
    ENTITY Travel
      CREATE FIELDS ( AgencyId CustomerId BeginDate EndDate BookingFee CurrencyCode )
      WITH VALUE #( ( %cid = 'T1' AgencyId = '070001' CustomerId = '000001'
                      BeginDate = '20260601' EndDate = '20260610'
                      BookingFee = '20.00' CurrencyCode = 'EUR' ) )
      CREATE BY \_Booking
        FIELDS ( CarrierId ConnectionId FlightDate FlightPrice CurrencyCode )
        WITH VALUE #( ( %cid_ref = 'T1'
                        %target = VALUE #(
                          ( %cid = 'B1' CarrierId = 'LH' ConnectionId = '0400'
                            FlightDate = '20260601' FlightPrice = '200.00' CurrencyCode = 'EUR' )
                          ( %cid = 'B2' CarrierId = 'LH' ConnectionId = '0401'
                            FlightDate = '20260610' FlightPrice = '210.00' CurrencyCode = 'EUR' ) ) ) )
    MAPPED DATA(mapped)
    FAILED DATA(failed).

  cl_abap_unit_assert=>assert_initial( act = failed ).

  " read the BUFFER - no commit needed to test an ON MODIFY determination
  READ ENTITIES OF zr_traveltp
    ENTITY Travel
      FIELDS ( TotalPrice )
      WITH VALUE #( ( %tky-TravelUUID = mapped-travel[ 1 ]-TravelUUID
                      %tky-%is_draft  = if_abap_behv=>mk-off ) )
    RESULT DATA(travels).

  cl_abap_unit_assert=>assert_equals(
    exp = CONV /dmo/total_price( '430.00' )     " 20 fee + 200 + 210
    act = travels[ 1 ]-TotalPrice
    msg = 'calculateTotalPrice should roll up the booking prices' ).

ENDMETHOD.
```

Note: **no `COMMIT ENTITIES`.** An `on modify` determination has already run; reading the buffer is
enough and keeps the test fast.

### Testing an action and its feature control

```abap
METHOD accept_disabled_when_accepted.

  DATA(uuid) = create_accepted_travel( ).      " helper that creates + accepts

  READ ENTITIES OF zr_traveltp
    ENTITY Travel
      REQUEST VALUE #( %action-acceptTravel = if_abap_behv=>mk-on )
      GET PERMISSIONS
      FROM VALUE #( ( %tky-TravelUUID = uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
    RESULT DATA(perms).

  cl_abap_unit_assert=>assert_equals(
    exp = if_abap_behv=>fc-o-disabled
    act = perms-instances[ 1 ]-%action-acceptTravel
    msg = 'an already-accepted travel must not be acceptable again' ).

ENDMETHOD.
```

### Testing draft behaviour

```abap
METHOD draft_edit_change_activate.

  DATA(uuid) = create_active_travel( ).

  " Edit: on the ACTIVE instance
  MODIFY ENTITIES OF zr_traveltp
    ENTITY Travel
      EXECUTE Edit FROM VALUE #( ( %tky-TravelUUID = uuid
                                   %tky-%is_draft  = if_abap_behv=>mk-off ) )
    FAILED DATA(edit_failed).
  cl_abap_unit_assert=>assert_initial( act = edit_failed msg = 'Edit should succeed' ).

  " Change: on the DRAFT
  MODIFY ENTITIES OF zr_traveltp
    ENTITY Travel
      UPDATE FIELDS ( Description )
      WITH VALUE #( ( %tky-TravelUUID = uuid
                      %tky-%is_draft  = if_abap_behv=>mk-on
                      Description     = 'changed in draft' ) ).

  " The ACTIVE instance must still be unchanged at this point
  READ ENTITIES OF zr_traveltp
    ENTITY Travel FIELDS ( Description )
      WITH VALUE #( ( %tky-TravelUUID = uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
    RESULT DATA(active_before).
  cl_abap_unit_assert=>assert_differs(
    exp = 'changed in draft' act = active_before[ 1 ]-Description
    msg = 'the active instance must not change before Activate' ).

  " Prepare: collect validation messages without activating
  MODIFY ENTITIES OF zr_traveltp
    ENTITY Travel
      EXECUTE Prepare FROM VALUE #( ( %tky-TravelUUID = uuid
                                      %tky-%is_draft  = if_abap_behv=>mk-on ) )
    REPORTED DATA(prepare_reported).

  " Activate: on the DRAFT
  MODIFY ENTITIES OF zr_traveltp
    ENTITY Travel
      EXECUTE Activate FROM VALUE #( ( %tky-TravelUUID = uuid
                                       %tky-%is_draft  = if_abap_behv=>mk-on ) )
    FAILED DATA(act_failed).
  cl_abap_unit_assert=>assert_initial( act = act_failed ).

  COMMIT ENTITIES.

  READ ENTITIES OF zr_traveltp
    ENTITY Travel FIELDS ( Description )
      WITH VALUE #( ( %tky-TravelUUID = uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
    RESULT DATA(active_after).
  cl_abap_unit_assert=>assert_equals(
    exp = 'changed in draft' act = active_after[ 1 ]-Description ).

ENDMETHOD.
```

The assertion in the middle — that the active instance is **not** changed before `Activate` — is the
one that catches a genuinely broken draft setup.

### Testing failed save and rollback

```abap
METHOD failed_save_leaves_db_clean.

  SELECT COUNT(*) FROM ztravel INTO @DATA(before).

  " create something a validation will reject
  MODIFY ENTITIES OF zr_traveltp
    ENTITY Travel
      CREATE FIELDS ( AgencyId CustomerId BeginDate EndDate CurrencyCode )
      WITH VALUE #( ( %cid = 'BAD' AgencyId = '070001' CustomerId = 'NOPE'
                      BeginDate = '20260601' EndDate = '20260610' CurrencyCode = 'EUR' ) ).

  COMMIT ENTITIES RESPONSE OF zr_traveltp FAILED DATA(cf).

  cl_abap_unit_assert=>assert_equals( exp = 4 act = sy-subrc ).

  SELECT COUNT(*) FROM ztravel INTO @DATA(after).
  cl_abap_unit_assert=>assert_equals(
    exp = before act = after
    msg = 'a rejected save must not have written anything' ).

  ROLLBACK ENTITIES.
ENDMETHOD.
```

### Testing authorization — an honest note

Authorization is the hardest RAP layer to unit-test, because `AUTHORITY-CHECK` evaluates the
**running user's** profile and there is no supported way to impersonate another user inside ABAP Unit.

Practical options, best first:

1. **Extract the decision.** Put the rule in a small class with an injectable checker:
   ```abap
   INTERFACE zif_travel_auth_check.
     METHODS may_change IMPORTING agency_id TYPE /dmo/agency_id
                        RETURNING VALUE(r)  TYPE abap_bool.
   ENDINTERFACE.
   ```
   The handler calls the interface; the test injects a double (`cl_abap_testdouble`). You then unit-test
   the *mapping* from check result to `%update` / `%action-X`, which is where the bugs actually are.
2. **Integration-test with real users** in QA: one test user per role, a checklist per role.
   This is the only way to test the PFCG role content itself.
3. **Test DCL separately** by comparing row counts as different users (23.4).

Do not pretend a unit test covers authorization when it only covers the code path.

### Running the tests

| Action | Shortcut |
|---|---|
| Run ABAP Unit for the current object | `Ctrl + Shift + F10` |
| Run with coverage | `Ctrl + Shift + F11` |
| Run ATC checks | Right-click → *Run As → ABAP Test Cockpit* |

---

## 23.7 Layer 3 — testing the OData service

### `$metadata` is the source of truth

```
GET /sap/opu/odata4/sap/zui_travel_o4/srvd/sap/zsd_travel/0001/$metadata
```

If something is missing here, the problem is in CDS or the BDEF — **stop looking at the UI.**

| Look for | Confirms |
|---|---|
| The `EntityType` and its properties | Projection view exposure |
| `<Action Name="acceptTravel">` | Base BDEF action **and** `use action` in the projection |
| `Common.SideEffects` annotations | `side effects` block |
| `Common.ValueList` annotations | `@Consumption.valueHelpDefinition` **and** the entity is exposed |
| `UI.LineItem` / `UI.Facets` | Metadata extension activated |
| `IsActiveEntity` in the key | Draft is enabled |
| `Core.OptimisticConcurrency` / ETag on the entity | `use etag` in the projection BDEF |

### Request checklist

| Request | Checks |
|---|---|
| `GET .../Travel?$top=5` | Read, DCL |
| `GET .../Travel?$filter=OverallStatus eq 'O'` | Filtering pushed to HANA |
| `GET .../Travel?$expand=_Booking` | Composition, redirection |
| `GET .../Travel?$select=TravelId,TotalPrice` | Projection |
| `POST .../Travel` | Create, determinations, mandatory field control |
| `PATCH .../Travel(...)` | Update, ETag (`If-Match`) |
| `POST .../Travel(...)/...acceptTravel` | Action |
| `DELETE .../Travel(...)` | Delete, cascade |

### Testing an ETag conflict

This is one of the few things you **cannot** properly test through EML — the ETag comparison happens
in the OData layer, not in the transactional buffer. Test it over HTTP:

1. `GET` an instance; note the `ETag` response header.
2. `PATCH` it once with `If-Match: <that etag>` → succeeds, and the ETag changes.
3. `PATCH` again with the **old** ETag → expect **HTTP 412 Precondition Failed**.

In the UI the equivalent is: open the same object in two browser sessions, change and save in the
first, then save in the second. The second must be refused.

### Testing concurrency / locking

Two ADT sessions, or two browser sessions with different users:

| Test | Expected |
|---|---|
| User A presses Edit, user B presses Edit | B gets *"Object is locked by user A"* |
| A discards, B presses Edit | B succeeds |
| A edits and closes the browser; B waits for the lock timeout, then Edits | B succeeds (optimistic phase) |
| A returns and presses Resume after B has saved | A is told the draft is outdated |

---

## 23.8 Layer 4 — testing the UI

### The Fiori Elements preview

Service binding → select the entity set → **Preview**.

**Before you conclude anything, clear the cache.** `F12` → right-click reload →
*Empty cache and hard reload*. More than half of "the annotation has no effect" reports are this.

### UI test checklist

| Area | Test |
|---|---|
| List Report | Filter bar fields present; mandatory filters enforced; search works; export to spreadsheet works |
| Create | Object Page opens in edit mode; a draft row appears |
| Mandatory fields | Empty mandatory field blocks save, field marked |
| Validation | Bad data shows a message **on the right field**; fixing it clears the message |
| Determination | Calculated field updates without a manual refresh (if not → side effect missing, Chapter 21) |
| Child table | "+" adds a row; delete removes it; the parent total updates |
| Actions | Buttons present, enabled/disabled per status, message shown on failure |
| Draft | Cancel discards; reopening offers Resume; two sessions conflict correctly |
| Delete | Parent delete removes children |
| Responsive | Resize to phone width — only `#HIGH` importance columns remain |
| Messages | Message popover lists everything; clicking a message navigates to the field |

### Where UI errors actually surface

| Tool | Shows |
|---|---|
| Browser DevTools → **Network** | The real OData request and the **full JSON error body** — far more detail than the UI toast |
| Browser DevTools → **Console** | UI5 errors, annotation problems |
| `/IWFND/ERROR_LOG` | Gateway errors (mainly OData V2; still useful on-premise) |
| `ST22` | Short dumps from the backend |
| `SLG1` | Your own application log |

**The Network tab is the most under-used RAP debugging tool.** A failed `POST` returns a JSON body
containing the full `reported` message list, including the ones the UI chose not to display.

---

## 23.9 Debugging

### Getting a breakpoint to fire from the Fiori preview

The preview runs in a different session from your ADT debugger. You need an **external breakpoint**:

1. Set the breakpoint in ADT.
2. Check the breakpoint is external: ADT → *Window → Preferences → ABAP Development → Debug* →
   confirm the external debugging user matches the user running the browser.
3. Trigger the action in the browser.

If it still does not fire, the code is not being reached — which is itself the answer.

**Better: skip the browser.** Reproduce with an EML console class and debug with `F9`. Faster,
repeatable, and it becomes a test.

### Conditional breakpoints for mass scenarios

In a determination processing 5000 instances, a plain breakpoint is useless. Right-click the
breakpoint → *Breakpoint Properties* → condition:

```abap
travel-TravelId = '00000042'
```

### Breakpoints worth knowing

| Where | Tells you |
|---|---|
| Start of each determination/validation | Whether it runs at all, and with which keys |
| `finalize` | Early save started; `on save` determinations are running |
| `check_before_save` | The final buffer state, before the point of no return |
| `cleanup_finalize` | Something rejected the save — inspect `failed` |
| `save` / `save_modified` | What is actually written |
| `cleanup` | The transaction completed |
| `get_instance_features` | Why a button is enabled or disabled |

### Temporary message tracing

```abap
APPEND VALUE #( %tky = key-%tky
                %msg = new_message_with_text(
                         severity = if_abap_behv_message=>severity-information
                         text     = |calculateTotalPrice: { lines( keys ) } keys| ) )
       TO reported-travel.
```

Appears in the Fiori message popover. **Remove before transport** — and add an ATC exemption-free
check for `new_message_with_text` in your review, because it is not translatable.

---

## 23.10 Performance tracing tools

| Tool | Transaction | Use for |
|---|---|---|
| **SQL Trace** | `ST05` | The actual SQL a CDS view or EML call issues. Start trace → run → stop → display |
| **Runtime Analysis** | `SAT` | Where ABAP time goes inside a behavior pool |
| **SQL Monitor** | `SQLM` / `SQLMD` | Production-safe, always-on statement statistics. The right tool for "which statement is slow in PROD" |
| **SQL Performance Tuning Worklist** | `SWLT` | Combines SQLM data with ATC findings to rank what to fix |
| **ABAP Profiler** | ADT | Profile an EML console class directly (*Run As → ABAP Application (Profiling)*) |
| **ATC** | ADT / `ATC` | Static checks including HANA-readiness and nested-SELECT findings |
| **Application Log** | `SLG1` | Your own logs written in `save_modified` |
| **Short dumps** | `ST22` | Late-save-phase failures, `COMMIT WORK` violations |
| **Gateway error log** | `/IWFND/ERROR_LOG` | OData-layer errors (on-premise) |

### The one trace worth running on every new RAP app

`ST05` around a single List Report page load. Look for:

- a `SELECT` without a `WHERE` on a large table → missing mandatory filter
- the **same** statement repeated N times → a `SELECT` inside a loop in a determination or
  instance-authorization handler
- a join returning far more rows than the page displays → wrong association cardinality

---

## 23.11 Common errors

| Symptom | Cause |
|---|---|
| Breakpoint never fires from the preview | Not an external breakpoint, or the code genuinely is not reached |
| Test passes but the UI misbehaves | The defect is in the projection BDEF (`use ...`), the MDE, or the browser cache — none of which EML exercises |
| UI works but the test fails | The test calls the BO without `IN LOCAL MODE` and hits authorization/feature control, which the UI passed |
| Test data leaks between tests | `clear_doubles( )` missing in `setup`, or `ROLLBACK ENTITIES` missing in `teardown` |
| `cl_cds_test_environment` create fails | Entity name must be upper case and must exist; check nested CDS dependencies |
| Determination "not running" in a test | It is `on save` and the test never commits — use `COMMIT ENTITIES IN SIMULATION MODE` |
| Everything passes in DEV, fails in QA | Data-dependent logic, missing transport object, or different roles — see Chapter 25 |
| Cannot reproduce a user's error | Ask for the exact time, then check `ST22` and `SLG1` for that window |

---

## 23.12 Interview answer

> **"How did you test your RAP application?"**
>
> On four levels.
>
> First the CDS model, with Data Preview — checking row counts, no duplicates from wrong
> association cardinalities, and that DCL filters what I expect.
>
> Second, and most importantly, the behavior through **EML from a console class implementing
> `IF_OO_ADT_CLASSRUN`**. That is the only place you can actually see `failed`, `reported` and
> `sy-subrc` after `COMMIT ENTITIES`. `sy-subrc = 4` means the early save phase rejected it and it
> is recoverable; `8` means a late-phase failure needing an explicit rollback. I also use
> `COMMIT ENTITIES IN SIMULATION MODE` to run the on-save validations without writing anything.
>
> Those console classes then become **ABAP Unit tests** with `cl_cds_test_environment`, which
> replaces the underlying tables with in-memory doubles so the tests are fast and touch no real
> data. For validations I assert on both `failed` and `reported` — a validation that reports
> without failing lets the record save, which is a bug a `sy-subrc` check alone would miss.
> For feature control I assert via `GET PERMISSIONS`, which is exactly what the UI calls.
>
> Third, the OData service: `$metadata` first. If an action or annotation is not in `$metadata`,
> the problem is in CDS or the BDEF and there is no point looking at the UI.
>
> Fourth, the Fiori Elements preview for the flows — always after clearing the browser cache,
> because a stale cache looks exactly like a code defect. ETag conflicts and locking I test over
> HTTP or with two browser sessions, since those happen above the EML layer.
>
> For performance I use `ST05` on a page load to catch SELECTs inside loops, and `SQLM` in
> production.

---

## 23.13 Production considerations

- **Promote every playground class to an ABAP Unit test** before you delete it. The cost is minutes;
  the value is a regression suite.
- **Keep unit tests `RISK LEVEL HARMLESS` and `DURATION SHORT`** so they can run in a CI/transport
  gate. Tests that write real data cannot.
- **Run ATC before every transport release**, with the HANA-readiness and security check variants.
- **Do not ship `new_message_with_text`.** It is not translatable. Grep for it as a release check.
- **Test with production-like volumes.** A List Report that is fine with 200 rows in DEV can time
  out with 2 million in PROD. Copy a realistic data subset into QA.
- **Test with real roles, not `SAP_ALL`.** Authorization defects are the single most common
  "worked in DEV" failure, and a developer with wide authorizations will never see them.
- **Enable `SQLM` in production for a window after go-live.** It is low-overhead and it will tell
  you what actually needs tuning, rather than what you guessed.
- **Write down a per-role UI test checklist** and re-run it after every transport to QA. The
  declarative parts of RAP fail silently; only a checklist catches a missing `use action`.

---

[< Value Helps](22-Value-Helps-and-Text-Associations.md) | [Index](00-README.md) | [Next: Performance & Production Readiness >](24-Performance-and-Production-Readiness.md)
