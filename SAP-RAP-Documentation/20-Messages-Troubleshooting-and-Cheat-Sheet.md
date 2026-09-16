# Chapter 20 — Messages, Troubleshooting and Cheat Sheet

[< Numbering, Locking, ETag](19-Numbering-Locking-ETag.md) | [Index](00-README.md) | [Next: Side Effects >](21-Side-Effects.md)

---

# Part 1 — Messages

## 20.1 The three ways to produce a message

### A) `new_message_with_text( )` — prototyping only

```abap
APPEND VALUE #( %tky = key-%tky
                %msg = new_message_with_text(
                         severity = if_abap_behv_message=>severity-error
                         text     = 'End date must be after begin date' ) )
       TO reported-travel.
```

**Not translatable.** Fine while developing, never in a transport that leaves DEV.

### B) `new_message( )` — translatable, no exception class

```abap
APPEND VALUE #( %tky = key-%tky
                %msg = new_message( id       = 'ZTRAVEL_MSG'
                                    number   = '001'
                                    severity = if_abap_behv_message=>severity-error
                                    v1       = CONV #( travel-BeginDate )
                                    v2       = CONV #( travel-EndDate ) ) )
       TO reported-travel.
```

Points at a message in SE91 message class `ZTRAVEL_MSG`. `v1`..`v4` fill `&1`..`&4`.
**This is the pragmatic default** — translatable, and it needs no extra class.

### C) An exception class implementing `IF_ABAP_BEHV_MESSAGE` — the full pattern

```abap
APPEND VALUE #( %tky = key-%tky
                %msg = NEW zcx_travel_messages(
                         severity  = if_abap_behv_message=>severity-error
                         textid    = zcx_travel_messages=>end_before_begin
                         begindate = travel-BeginDate
                         enddate   = travel-EndDate ) )
       TO reported-travel.
```

Full class source: Chapter 09, §9.6.

Use it when:

- the same message is raised from many places and you want one typed constructor,
- you also need to `RAISE` the exception in non-RAP code,
- you want compile-time safety on the message parameters.

---

## 20.2 The four components of a message entry

```abap
APPEND VALUE #(
  %tky               = key-%tky                       " 1. which instance
  %state_area        = 'VALIDATE_DATES'               " 2. persistent message area
  %msg               = <the message object>           " 3. the message
  %element-BeginDate = if_abap_behv=>mk-on            " 4. which field to highlight
  %element-EndDate   = if_abap_behv=>mk-on
) TO reported-travel.
```

| Component | Effect in Fiori |
|---|---|
| `%tky` | Links the message to a row; clicking the message navigates to it |
| `%state_area` | Makes the message **persistent** until explicitly cleared |
| `%msg` | The text, severity and message class |
| `%element-<Field>` | The field is outlined in red and the message appears under it |

Without `%element`, the message only appears in the message popover — the user has to guess which
field is wrong.

---

## 20.3 Transient vs state messages

| | Transient | State |
|---|---|---|
| Declared with | `%msg` only | `%msg` + `%state_area` |
| Lifetime | The current request | Until the same `%state_area` is cleared |
| Use for | Action results, information | Validation errors on a draft |

### The mandatory clear-first pattern

```abap
LOOP AT travels INTO DATA(travel).

  " 1. ALWAYS clear the area for this instance
  APPEND VALUE #( %tky        = travel-%tky
                  %state_area = 'VALIDATE_DATES' ) TO reported-travel.

  " 2. Then add a message only if the check fails
  IF <check fails>.
    APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
    APPEND VALUE #( %tky        = travel-%tky
                    %state_area = 'VALIDATE_DATES'
                    %msg        = ...
                    %element-BeginDate = if_abap_behv=>mk-on ) TO reported-travel.
  ENDIF.
ENDLOOP.
```

Skipping step 1 leaves the error on screen after the user has fixed the data.
Use **one `%state_area` per validation** so validations do not clear each other's messages.

---

## 20.4 `failed` vs `reported`

| | `failed` | `reported` |
|---|---|---|
| Purpose | "This instance could not be processed" | "Here is a message about it" |
| Effect on the save | **Blocks it** | None on its own |
| Visible to the user | No | Yes |

```abap
" ERROR that blocks the save
APPEND VALUE #( %tky = key-%tky ) TO failed-travel.
APPEND VALUE #( %tky = key-%tky %msg = ... severity-error ) TO reported-travel.

" WARNING that does not block
APPEND VALUE #( %tky = key-%tky %msg = ... severity-warning ) TO reported-travel.
```

**`failed` without `reported`** → the save is silently blocked and the user sees nothing. Worst case.
**`reported` without `failed`** → a red message appears and the record saves anyway. Second worst.

Always pair them for errors.

### `%fail-cause`

```abap
APPEND VALUE #( %tky        = key-%tky
                %fail-cause = if_abap_behv=>cause-unauthorized ) TO failed-travel.
```

| Cause | Use for |
|---|---|
| `unspecific` | Default |
| `unauthorized` | Authorization failure |
| `locked` | Lock failure |
| `disabled` | Blocked by feature control |
| `not_found` | Instance does not exist |
| `conflict` | ETag mismatch |
| `dependency` | A dependent object blocked it |

The consumer (and generic error handling) can react differently per cause.

---

## 20.5 Messages for a specific field of a child entity

```abap
APPEND VALUE #( %tky                = booking-%tky
                %msg                = ...
                %element-FlightDate = if_abap_behv=>mk-on ) TO reported-booking.
```

Note `reported-booking`, using the **alias in lower case**. For messages not tied to any instance:

```abap
APPEND VALUE #( %msg = ... ) TO reported-%other.
```

---

# Part 2 — Troubleshooting index

## 20.6 Symptom → cause, by area

### Activation errors

| Message | Cause |
|---|---|
| *"Entity must be a root entity"* | `root` missing on the CDS view |
| *"Association _X must be redirected"* | `redirected to composition child` / `parent` missing in the projection |
| *"No behavior definition found for ZC_..."* | `provider contract transactional_query` without a projection BDEF |
| *"Extension of view ... is not allowed"* | `@Metadata.allowExtensions: true` missing |
| *"Total ETag is missing"* | `with draft;` without `total etag` |
| *"ETag field must be of type timestamp"* | Wrong data element |
| *"persistent table is not allowed"* | `persistent table` together with `with unmanaged save` |
| *"Implementation class must be specified in the header"* | Class declared at node level while using additional/unmanaged save |
| *"Association must be draft enabled"* | `with draft;` missing on an association in a draft BO |
| *"Method ... is not implemented"* | Handler method missing — regenerate with `Ctrl + 1` |
| *"Method ... declared more than once"* | The same handler method in two handler classes |
| *"Use of ... not permitted in a projection view"* | A join or aggregation in an `as projection on` view |
| Draft table will not activate | Hand-typed rather than generated. Regenerate with the ADT quick fix; the required structure is release-dependent |

### UI behaves wrongly

| Symptom | Cause |
|---|---|
| Button does not appear | `use action X;` missing in the projection BDEF (check first); or `dataAction` spelling/case; or browser cache |
| Button greyed out for everyone | `get_instance_features` does not set `%action-X` |
| Button always enabled | `( features : instance )` missing |
| "+" missing in a child table | `association _Child { create; }` in the base, **and** `use association _Child { create; }` in the projection |
| Calculated field does not refresh | `side effects` not declared |
| Button enablement does not refresh | `field X affects permissions;` missing |
| Section renders empty | `targetQualifier` does not match any `qualifier` |
| Child table has no columns | The child MDE has no `@UI.lineItem` |
| Value help is empty | The value-help entity is not exposed in the service definition |
| Annotation change has no effect | Browser cache; MDE not activated; binding not re-published; annotated the wrong view |
| Mobile layout unusable | No `importance` on line items |
| List Report times out on open | No mandatory filter on a large table |

### Runtime / logic

| Symptom | Cause |
|---|---|
| Determination reads stale data | Used `SELECT` instead of `READ ENTITIES ... IN LOCAL MODE` |
| `READ ENTITIES` returns nothing in a draft BO | Used `%key` instead of `%tky` |
| Validation message shown but the record saves | `failed` not filled |
| Validation message persists after the fix | `%state_area` not cleared first |
| Validation only fires at Save | Not listed in `draft determine action Prepare` |
| Cannot write a `readonly` field from a determination | Missing `IN LOCAL MODE` |
| Second save in the session misbehaves | `CLASS-DATA` / unmanaged buffer not cleared in `cleanup` and `cleanup_finalize` |
| *"COMMIT WORK not allowed"* | `COMMIT WORK` / `COMMIT ENTITIES` inside a behavior pool |
| Runtime error in the late save phase | A failure-capable operation left in `save`; move the check to `check_before_save` |
| `save_modified` never called | Nothing on **this** BO changed |
| Number range gaps | Number drawn `on modify` instead of `on save` |
| Update wipes untouched fields | `%control` ignored (unmanaged / unmanaged save) |
| Nothing is persisted | `COMMIT ENTITIES` missing, or `sy-subrc = 4` unchecked |
| Determination loops / dumps | Indirect determination cycle (A changes B, B's determination changes A) |
| Works in EML but not in Fiori | Draft: `%key` vs `%tky`, or a missing `use` in the projection BDEF |
| Works in Fiori but not in EML | Authorization / feature control — EML without `IN LOCAL MODE` runs the full checks |

## 20.7 The diagnostic sequence

When something does not work, go through this in order. It resolves most cases within three steps.

1. **Re-activate in dependency order**: tables → interface views (child first) → BDEF → ABP →
   projection views (child first) → projection BDEF → MDE → service definition → service binding →
   **Publish**.
2. **Clear the browser cache** (`F12` → *Empty cache and hard reload*).
3. **Look at `$metadata`.** If the field / action / annotation is not there, the problem is in CDS
   or the BDEF, not the UI.
4. **Drive the BO from an `IF_OO_ADT_CLASSRUN` class with EML** and print `failed` / `reported` /
   `sy-subrc`. This separates "the BO is wrong" from "the UI is wrong".
5. **Set a breakpoint** in the handler method and run the class with `F9`.
6. **Check the projection BDEF** for a missing `use`.

---

# Part 3 — Cheat Sheet

## 20.8 Object naming

| Prefix | Layer |
|---|---|
| `ZTRAVEL` | DDIC table |
| `ZTRAVEL_D` | Draft table |
| `ZI_` | Basic interface view |
| `ZR_...TP` | RAP root / interface view |
| `ZC_...TP` | Projection / consumption view |
| `ZBP_R_...TP` | Behavior pool |
| `ZSD_` | Service definition |
| `ZUI_..._O4` | Service binding, OData V4, UI |
| `ZE_` | CDS abstract entity |
| `lhc_<Alias>` | Local handler class |
| `lsc_<BDEF>` | Local saver class |

## 20.9 BDEF skeleton

```abap
managed implementation in class ZBP_R_TravelTP unique;
strict ( 2 );
with draft;

define behavior for ZR_TravelTP alias Travel
persistent table ztravel
draft table ztravel_d
lock master
total etag LastChangedAt
authorization master ( instance )
etag master LocalLastChangedAt
{
  create; update; delete;

  field ( numbering : managed, readonly ) TravelUUID;
  field ( readonly )  CreatedBy, CreatedAt, LastChangedBy, LastChangedAt, LocalLastChangedAt;
  field ( mandatory ) AgencyId, CustomerId, BeginDate, EndDate;

  association _Booking { create; with draft; }

  determination setTravelId on save { create; }
  validation validateDates  on save { field BeginDate, EndDate; create; }
  action ( features : instance ) acceptTravel result [1] $self;

  side effects { field BookingFee affects field TotalPrice; }

  draft action Activate optimized;
  draft action Discard;
  draft action Edit;
  draft action Resume;
  draft determine action Prepare { validation validateDates; }

  mapping for ztravel corresponding;
}
```

## 20.10 Handler method signatures

```abap
FOR DETERMINE ON MODIFY IMPORTING keys FOR Travel~<det>.
FOR DETERMINE ON SAVE   IMPORTING keys FOR Travel~<det>.
FOR VALIDATE ON MODIFY  IMPORTING keys FOR Travel~<val>.
FOR VALIDATE ON SAVE    IMPORTING keys FOR Travel~<val>.
FOR MODIFY IMPORTING keys FOR ACTION Travel~<act> RESULT result.
FOR READ   IMPORTING keys FOR FUNCTION Travel~<fn> RESULT result.
FOR INSTANCE FEATURES       IMPORTING keys REQUEST requested_features       FOR Travel RESULT result.
FOR GLOBAL FEATURES         IMPORTING      REQUEST requested_features       FOR Travel RESULT result.
FOR INSTANCE AUTHORIZATION  IMPORTING keys REQUEST requested_authorizations FOR Travel RESULT result.
FOR GLOBAL AUTHORIZATION    IMPORTING      REQUEST requested_authorizations FOR Travel RESULT result.
FOR PRECHECK IMPORTING entities FOR UPDATE Travel.
FOR NUMBERING IMPORTING entities FOR CREATE Travel.
FOR MODIFY IMPORTING entities FOR CREATE Travel.
FOR MODIFY IMPORTING entities FOR UPDATE Travel.
FOR MODIFY IMPORTING keys     FOR DELETE Travel.
FOR READ   IMPORTING keys     FOR READ   Travel RESULT result.
FOR LOCK   IMPORTING keys     FOR LOCK   Travel.
FOR READ   IMPORTING keys_rba FOR READ Travel\_Booking FULL result_requested
             RESULT result LINK association_links.
FOR MODIFY IMPORTING entities_cba FOR CREATE Travel\_Booking.
```

## 20.11 Saver methods

| Method | Phase | Purpose |
|---|---|---|
| `finalize` | Early save | Final data changes. `on save` determinations run here |
| `check_before_save` | Early save | Last gate. `on save` validations run here |
| `cleanup_finalize` | Early save, on failure | Undo `finalize` |
| `adjust_numbers` | Late save | Late numbering |
| `save` | Late save | Persist (unmanaged) |
| `save_modified` | Late save | Persist / add to persist (additional / unmanaged save) |
| `cleanup` | After save or rollback | Clear the buffer and own state |

## 20.12 EML quick reference

```abap
READ ENTITIES OF <bo> [IN LOCAL MODE] [PRIVILEGED]
  ENTITY <Alias> FIELDS ( F1 F2 ) WITH CORRESPONDING #( keys ) RESULT DATA(r)
  ENTITY <Alias> ALL FIELDS WITH ... RESULT DATA(r2)
  ENTITY <Alias> BY \_Child FIELDS ( ... ) WITH ... RESULT DATA(c)
  ENTITY <Alias> BY \_Child FROM ... LINK DATA(links)
  ENTITY <Alias> EXECUTE <function> FROM ... RESULT DATA(fr)
  FAILED DATA(f) REPORTED DATA(rep).

MODIFY ENTITIES OF <bo> [IN LOCAL MODE] [PRIVILEGED]
  ENTITY <Alias> CREATE FIELDS ( ... ) WITH tab
                 CREATE BY \_Child FIELDS ( ... ) WITH cba_tab
  ENTITY <Alias> UPDATE FIELDS ( ... ) WITH tab
  ENTITY <Alias> DELETE FROM tab
  ENTITY <Alias> EXECUTE <action> FROM tab RESULT DATA(ar)
  MAPPED DATA(m) FAILED DATA(f) REPORTED DATA(rep).

COMMIT ENTITIES [RESPONSE OF <bo>] [IN SIMULATION MODE]
  FAILED DATA(f) REPORTED DATA(rep).

ROLLBACK ENTITIES.

READ ENTITIES OF <bo> ENTITY <Alias>
  REQUEST VALUE #( %update = if_abap_behv=>mk-on )
  GET PERMISSIONS FROM tab RESULT DATA(perm).

SET LOCKS OF <bo> ENTITY <Alias> FROM tab FAILED DATA(lf).

RAISE ENTITY EVENT <bo>~<Event> FROM tab.

CONVERT KEY OF <bo> FROM <pid> TO DATA(key).   " only inside save_modified
```

`sy-subrc` after `COMMIT ENTITIES`: `0` ok · `4` early save failed (recoverable) · `8` late save
failed (`ROLLBACK ENTITIES` required).

## 20.13 Constants

```abap
if_abap_behv=>mk-on / mk-off
if_abap_behv=>fc-o-enabled / fc-o-disabled                       " operations & actions
if_abap_behv=>fc-f-unrestricted / fc-f-read_only / fc-f-mandatory " fields
if_abap_behv=>auth-allowed / auth-unauthorized
if_abap_behv=>cause-unauthorized / locked / disabled / not_found / conflict / dependency
if_abap_behv_message=>severity-error / warning / information / success
```

## 20.14 Derived-type separators

| Written | Means |
|---|---|
| `zr_traveltp` | Root entity |
| `zr_traveltp\\Booking` | Child **entity** |
| `zr_traveltp\_Booking` | **Association** |
| `zr_traveltp~acceptTravel` | **Action** |

## 20.15 The rules that prevent most bugs

1. **Never `SELECT` the BO's own tables** from a behavior pool. Use `READ ENTITIES ... IN LOCAL MODE`.
2. **Never `COMMIT WORK`** in a behavior pool.
3. **Database writes only in the late save phase.**
4. **Everything that can fail must fail in `check_before_save`.**
5. **Always use `%tky`** in a draft BO, never `%key`.
6. **Always `IN LOCAL MODE`** inside a behavior pool.
7. **A rejecting validation fills both `failed` and `reported`.**
8. **State messages clear their `%state_area` first.**
9. **Determinations must be idempotent.**
10. **`use ...` in the projection BDEF for every operation, association and action** the app needs.
11. **`side effects`** for every calculated field and every state-driven button.
12. **Clear `CLASS-DATA` and unmanaged buffers** in `cleanup` and `cleanup_finalize`.
13. **`strict ( 2 )`** on every new BDEF.
14. **No `SELECT` inside a loop.** One set-based read outside it.
15. **Generate method signatures with `Ctrl + 1`**, never by hand.

## 20.16 Build order

```
tables -> draft tables -> interface views (child first) -> BDEF -> behavior pool
  -> message class -> projection views (child first) -> projection BDEF
  -> metadata extensions -> service definition -> service binding -> Publish
```

---

## 20.17 Further reading

- [SAP Help — ABAP RESTful Application Programming Model](https://help.sap.com/docs/abap-cloud/abap-rap)
- [SAP Help — Save Options (additional / unmanaged save)](https://help.sap.com/docs/abap-cloud/abap-rap/save-options)
- [SAP Help — Implementing the Interaction Phase and the Save Sequence](https://help.sap.com/docs/abap-cloud/abap-rap/implementing-interaction-phase-and-save-sequence)
- [SAP-samples/abap-cheat-sheets — RAP Behavior Definition Language](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/36_RAP_Behavior_Definition_Language.md)
- [SAP-samples/abap-cheat-sheets — EML / ABAP for RAP](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/08_EML_ABAP_for_RAP.md)
- [SAP-samples/abap-platform-rap-workshops](https://github.com/SAP-samples/abap-platform-rap-workshops)
- [SAP Help — Defining Unmanaged Save in the Behavior Definition](https://help.sap.com/docs/abap-cloud/abap-rap/defining-unmanaged-save-in-behavior-definition)
- [ABAP Keyword Documentation — RAP saver methods](https://help.sap.com/doc/abapdocu_cp_index_htm/CLOUD/en-US/abensaver_check_before_save.htm)
- ADT: the **ABAP Flight Reference Scenario** (`/DMO/` packages) — a complete, activatable managed
  *and* unmanaged implementation of exactly this model, shipped with the system.

---

[< Numbering, Locking, ETag](19-Numbering-Locking-ETag.md) | [Index](00-README.md) | [Next: Side Effects >](21-Side-Effects.md)
