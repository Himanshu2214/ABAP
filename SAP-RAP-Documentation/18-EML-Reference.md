# Chapter 18 — EML (Entity Manipulation Language) Reference

[< Save Sequence](17-Save-Sequence.md) | [Index](00-README.md) | [Next: Numbering, Locking, ETag >](19-Numbering-Locking-ETag.md)

---

## 18.1 What EML is

EML is the set of ABAP statements for calling a RAP business object from ABAP code. It is the
*only* supported way to talk to a RAP BO from ABAP — not SQL, not an OData HTTP call to yourself.

| Statement | Purpose |
|---|---|
| `READ ENTITIES` | Read instances, read by association, execute a function |
| `MODIFY ENTITIES` | Create / update / delete / create-by-association / execute an action |
| `COMMIT ENTITIES` | Trigger the save sequence and commit |
| `ROLLBACK ENTITIES` | Discard the transaction |
| `GET PERMISSIONS` | Ask what is allowed for given instances |
| `SET LOCKS` | Lock instances explicitly |
| `RAISE ENTITY EVENT` | Raise a RAP business event |
| `CONVERT KEY` | Resolve a preliminary id to a real key (late numbering, inside `save_modified`) |

Two consumers:

- **Outside the BO** (a report, a job, a class, another BO) — full statements, then `COMMIT ENTITIES`.
- **Inside the BO** (a behavior pool) — always with `IN LOCAL MODE`, and **never** `COMMIT ENTITIES`.

---

## 18.2 Derived types

The framework generates ABAP types from the BDEF. You never declare these structures by hand.

```abap
" --- instance data ---
DATA lt_create  TYPE TABLE FOR CREATE zr_traveltp.
DATA ls_create  TYPE STRUCTURE FOR CREATE zr_traveltp.
DATA lt_update  TYPE TABLE FOR UPDATE zr_traveltp.
DATA lt_delete  TYPE TABLE FOR DELETE zr_traveltp.
DATA lt_read    TYPE TABLE FOR READ IMPORT zr_traveltp.
DATA lt_result  TYPE TABLE FOR READ RESULT zr_traveltp.

" --- child entity (double backslash) ---
DATA lt_bcreate TYPE TABLE FOR CREATE zr_traveltp\\Booking.

" --- create by association (single backslash + association name) ---
DATA lt_cba     TYPE TABLE FOR CREATE zr_traveltp\_Booking.

" --- actions ---
DATA lt_action  TYPE TABLE FOR ACTION IMPORT zr_traveltp~acceptTravel.
DATA lt_ares    TYPE TABLE FOR ACTION RESULT zr_traveltp~acceptTravel.

" --- keys ---
DATA lt_keys    TYPE TABLE FOR KEY OF zr_traveltp.

" --- responses ---
DATA ls_mapped   TYPE RESPONSE FOR MAPPED   zr_traveltp.
DATA ls_failed   TYPE RESPONSE FOR FAILED   zr_traveltp.
DATA ls_reported TYPE RESPONSE FOR REPORTED zr_traveltp.

" --- for save_modified (additional / unmanaged save) ---
DATA ls_change   TYPE REQUEST FOR CHANGE zr_traveltp.
DATA ls_del      TYPE REQUEST FOR DELETE zr_traveltp.

" --- permissions ---
DATA ls_perm     TYPE RESPONSE FOR PERMISSIONS REQUEST zr_traveltp.
```

### The three separator characters

| Written | Means |
|---|---|
| `zr_traveltp` | The root entity |
| `zr_traveltp\\Booking` | A **child entity** of the BO (double backslash) |
| `zr_traveltp\_Booking` | The **association** `_Booking` from the root (single backslash) |
| `zr_traveltp~acceptTravel` | An **action** of the root (tilde) |
| `zr_traveltp\\Booking~someAction` | An action of a child entity |

Getting `\\` and `\_` confused is a frequent activation error. Mnemonic: a **single** backslash is a
**navigation step**; a **double** backslash is a **node name**.

---

## 18.3 Special components (`%` components)

These appear in every derived type. They are the RAP protocol.

| Component | Meaning | Where |
|---|---|---|
| `%key` | The key fields | Everywhere |
| `%tky` | *Transactional key* = `%key` + `%is_draft`. **Use this, not `%key`, in draft BOs** | Everywhere |
| `%is_draft` | `mk-on` = draft, `mk-off` = active | Draft BOs |
| `%cid` | Content id — a name you invent for a not-yet-created instance | Create |
| `%cid_ref` | "My parent is the instance with this `%cid`" | Create-by-association |
| `%target` | The table of children to create | Create-by-association |
| `%control` | Per-field flags: which fields were actually sent (`mk-on` / `mk-off`) | Update, read, `save_modified` |
| `%param` | Action/function parameter, or the action result payload | Actions, functions |
| `%data` | The instance data (in some response structures) | Responses |
| `%msg` | A message object implementing `IF_ABAP_BEHV_MESSAGE` | `reported` |
| `%element` | Which **field** a message refers to (highlighted in the UI) | `reported` |
| `%state_area` | A named area for persistent state messages | `reported` |
| `%fail-cause` | Why an instance failed | `failed` |
| `%path` | The path from the root to a child instance | Deep responses |
| `%pid` | Preliminary id, late numbering | `mapped` |
| `%pky` | Preliminary key | Late numbering |
| `%assoc-_X` | Permission/feature for an association | `GET PERMISSIONS`, features |
| `%action-X` | Permission/feature for an action | `GET PERMISSIONS`, features |
| `%field-X` | Feature for a field | Features |
| `%update`, `%delete`, `%create` | Permission/feature for an operation | `GET PERMISSIONS`, features |
| `%other` | Messages not tied to any instance | `reported-%other` |

### Constants

```abap
if_abap_behv=>mk-on          " '01' - set / true / is draft
if_abap_behv=>mk-off         " '00' - not set / false / is active

if_abap_behv=>fc-o-enabled   " operation/action enabled
if_abap_behv=>fc-o-disabled  " operation/action disabled
if_abap_behv=>fc-f-unrestricted  " field editable
if_abap_behv=>fc-f-read_only     " field read-only
if_abap_behv=>fc-f-mandatory     " field mandatory

if_abap_behv=>auth-allowed
if_abap_behv=>auth-unauthorized

if_abap_behv=>cause-unspecific
if_abap_behv=>cause-unauthorized
if_abap_behv=>cause-locked
if_abap_behv=>cause-disabled
if_abap_behv=>cause-not_found
if_abap_behv=>cause-conflict
if_abap_behv=>cause-dependency

if_abap_behv_message=>severity-error
if_abap_behv_message=>severity-warning
if_abap_behv_message=>severity-information
if_abap_behv_message=>severity-success
```

---

## 18.4 `MODIFY ENTITIES` — create

### Short form (one entity, one operation)

```abap
MODIFY ENTITY zr_traveltp
  CREATE FIELDS ( AgencyId CustomerId BeginDate EndDate BookingFee CurrencyCode )
  WITH VALUE #( ( %cid         = 'CID_1'
                  AgencyId     = '070001'
                  CustomerId   = '000001'
                  BeginDate    = '20260601'
                  EndDate      = '20260610'
                  BookingFee   = '20.00'
                  CurrencyCode = 'EUR' ) )
  MAPPED   DATA(mapped)
  FAILED   DATA(failed)
  REPORTED DATA(reported).
```

Note `MODIFY ENTITY` (singular) in the short form, `MODIFY ENTITIES` (plural) in the long form.

### Long form (several entities / operations in one statement)

```abap
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    CREATE FIELDS ( AgencyId CustomerId BeginDate EndDate CurrencyCode )
    WITH VALUE #( ( %cid = 'T1' AgencyId = '070001' CustomerId = '000001'
                    BeginDate = '20260601' EndDate = '20260610' CurrencyCode = 'EUR' ) )
  ENTITY Travel
    UPDATE FIELDS ( Description )
    WITH VALUE #( ( %tky-TravelUUID = lv_existing_uuid
                    %tky-%is_draft  = if_abap_behv=>mk-off
                    Description     = 'updated' ) )
  MAPPED   DATA(mapped)
  FAILED   DATA(failed)
  REPORTED DATA(reported).
```

### `CREATE FIELDS ( ... )` vs `CREATE SET FIELDS WITH` vs `CREATE AUTO FILL CID`

| Form | Meaning |
|---|---|
| `CREATE FIELDS ( A B C ) WITH tab` | Only fields A, B, C are sent. `%control` is derived from this list. **Preferred** — explicit. |
| `CREATE SET FIELDS WITH tab` | The `%control` values in `tab` decide what is sent. Use when you build `%control` dynamically. |
| `CREATE AUTO FILL CID WITH tab` | The framework generates `%cid` values for you. Convenient when you do not need to reference the created instances afterwards. |
| `CREATE AUTO FILL CID SET FIELDS WITH tab` | Both. |

### Deep create — parent and children in one statement

```abap
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    CREATE FIELDS ( AgencyId CustomerId BeginDate EndDate CurrencyCode )
    WITH VALUE #( ( %cid       = 'T1'
                    AgencyId   = '070001'
                    CustomerId = '000001'
                    BeginDate  = '20260601'
                    EndDate    = '20260610'
                    CurrencyCode = 'EUR' ) )

    CREATE BY \_Booking
      FIELDS ( CustomerId CarrierId ConnectionId FlightDate FlightPrice CurrencyCode )
      WITH VALUE #( ( %cid_ref = 'T1'                       " <- links to the parent above
                      %target  = VALUE #(
                        ( %cid = 'B1' CustomerId = '000001' CarrierId = 'LH'
                          ConnectionId = '0400' FlightDate = '20260601'
                          FlightPrice = '200.00' CurrencyCode = 'EUR' )
                        ( %cid = 'B2' CustomerId = '000001' CarrierId = 'LH'
                          ConnectionId = '0401' FlightDate = '20260610'
                          FlightPrice = '210.00' CurrencyCode = 'EUR' ) ) ) )
  MAPPED   DATA(mapped)
  FAILED   DATA(failed)
  REPORTED DATA(reported).

COMMIT ENTITIES.

" the real keys the framework assigned
DATA(travel_uuid)  = mapped-travel[  %cid = 'T1' ]-TravelUUID.
DATA(booking1_uuid) = mapped-booking[ %cid = 'B1' ]-BookingUUID.
```

This is the mechanism behind "create a document with its items in one transaction". `%cid` /
`%cid_ref` / `%target` is the whole trick.

---

## 18.5 `MODIFY ENTITIES` — update and delete

```abap
" UPDATE
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    UPDATE FIELDS ( Description BookingFee )
    WITH VALUE #( ( %tky-TravelUUID = lv_uuid
                    %tky-%is_draft  = if_abap_behv=>mk-off
                    Description     = 'new text'
                    BookingFee      = '25.00' ) )
  FAILED   DATA(failed)
  REPORTED DATA(reported).

" UPDATE with explicit %control (dynamic field selection)
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    UPDATE SET FIELDS
    WITH VALUE #( ( %tky-TravelUUID = lv_uuid
                    %tky-%is_draft  = if_abap_behv=>mk-off
                    Description     = 'new text'
                    %control-Description = if_abap_behv=>mk-on
                    %control-BookingFee  = if_abap_behv=>mk-off ) ).

" DELETE
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    DELETE FROM VALUE #( ( %tky-TravelUUID = lv_uuid
                           %tky-%is_draft  = if_abap_behv=>mk-off ) )
  FAILED   DATA(failed)
  REPORTED DATA(reported).
```

Deleting a root **cascades** to its compositions in a managed BO. You do not delete the Bookings
separately.

---

## 18.6 `MODIFY ENTITIES` — actions

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

" with a parameter
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

" draft actions
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE Edit     FROM VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-off ) ).
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE Activate FROM VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-on ) ).
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE Discard  FROM VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-on ) ).
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE Resume   FROM VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-on ) ).
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE Prepare  FROM VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-on ) )
  REPORTED DATA(prepare_reported).
```

---

## 18.7 `READ ENTITIES`

```abap
" read one entity
READ ENTITIES OF zr_traveltp
  ENTITY Travel
    FIELDS ( TravelId AgencyId TotalPrice OverallStatus )
    WITH VALUE #( ( %tky-TravelUUID = lv_uuid
                    %tky-%is_draft  = if_abap_behv=>mk-off ) )
  RESULT   DATA(travels)
  FAILED   DATA(failed)
  REPORTED DATA(reported).

" all fields
READ ENTITIES OF zr_traveltp
  ENTITY Travel
    ALL FIELDS WITH VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
  RESULT DATA(travels_full).

" read by association: the children of given parents
READ ENTITIES OF zr_traveltp
  ENTITY Travel BY \_Booking
    FIELDS ( BookingId FlightPrice CurrencyCode )
    WITH VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
  RESULT DATA(bookings).

" read by association: only the LINKS, no data (cheaper)
READ ENTITIES OF zr_traveltp
  ENTITY Travel BY \_Booking
    FROM VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
  LINK DATA(booking_links).

" read the parent from a child
READ ENTITIES OF zr_traveltp
  ENTITY Booking BY \_Travel
    FIELDS ( TravelId OverallStatus )
    WITH VALUE #( ( %tky-BookingUUID = lv_booking_uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
  RESULT DATA(parent_travels).

" several reads in one statement
READ ENTITIES OF zr_traveltp
  ENTITY Travel
    FIELDS ( TravelId TotalPrice ) WITH CORRESPONDING #( keys )
    RESULT DATA(travels2)
  ENTITY Travel BY \_Booking
    FIELDS ( FlightPrice ) WITH CORRESPONDING #( keys )
    RESULT DATA(bookings2)
  FAILED DATA(failed2).

" execute a function
READ ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE getPriceBreakdown
    FROM VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
  RESULT DATA(breakdown).
```

### `WITH CORRESPONDING #( keys )`

Inside a handler method you receive `keys` typed for that specific operation.
`WITH CORRESPONDING #( keys )` maps it to the type `READ ENTITIES` expects. It is the idiom you will
write hundreds of times; it also carries `%tky` across correctly, which hand-built key tables often
do not.

---

## 18.8 `IN LOCAL MODE` and `PRIVILEGED`

```abap
READ ENTITIES OF zr_traveltp IN LOCAL MODE ...
MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE ...
```

| | Without | With `IN LOCAL MODE` |
|---|---|---|
| Authorization checks | Run | **Skipped** |
| Feature control | Applied | **Skipped** |
| `readonly` field restrictions | Enforced | **Lifted** — you can write them |
| Projection restrictions | Applied | Skipped |
| Recursion risk | Yes | No |
| Performance | Slower | Faster |

**Inside a behavior pool, always use `IN LOCAL MODE`.** Outside, never — you want the checks.

```abap
READ ENTITIES OF zr_traveltp PRIVILEGED ...
MODIFY ENTITIES OF zr_traveltp PRIVILEGED ...
```

`PRIVILEGED` skips authorization checks from **outside** the BO. Only available in classes declared
`FOR BEHAVIOR OF` (behavior pools and auxiliary classes). Use it for background jobs that must
operate with full rights — and document why, every time.

```abap
" both
MODIFY ENTITIES OF zr_traveltp PRIVILEGED IN LOCAL MODE ...
```

### `AUGMENTING`

```abap
MODIFY AUGMENTING ENTITY zc_traveltp ...
```

Used in a **projection** behavior pool to enrich an incoming request before it reaches the base BO —
for example to fill a field the UI does not send. Declared in the projection BDEF with `augment`.
Niche but occasionally the clean answer.

---

## 18.9 `GET PERMISSIONS`

Ask the BO what is currently allowed, without attempting it.

```abap
READ ENTITIES OF zr_traveltp
  ENTITY Travel
    REQUEST VALUE #( %update              = if_abap_behv=>mk-on
                     %delete              = if_abap_behv=>mk-on
                     %action-acceptTravel = if_abap_behv=>mk-on
                     %assoc-_Booking      = if_abap_behv=>mk-on
                     %field-BeginDate     = if_abap_behv=>mk-on )
    GET PERMISSIONS
    FROM VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
  RESULT DATA(permissions)
  FAILED DATA(failed).

LOOP AT permissions-instances INTO DATA(perm).
  IF perm-%action-acceptTravel = if_abap_behv=>fc-o-enabled.
    " the Accept button would work for this instance
  ENDIF.
ENDLOOP.
```

`permissions` has three parts:

- `permissions-global` — global authorization + global features
- `permissions-instances` — per-instance authorization + features
- `permissions-permissions` — the combined result

This is exactly what the Fiori UI calls to decide button enablement. Use it in a batch job to filter
the instances you can actually act on, instead of attempting each and handling failures.

---

## 18.10 `SET LOCKS`

```abap
SET LOCKS OF zr_traveltp
  ENTITY Travel
  FROM VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
  FAILED   DATA(lock_failed)
  REPORTED DATA(lock_reported).

IF lock_failed IS NOT INITIAL.
  " someone else holds the lock
ENDIF.
```

Normally the framework locks automatically on modify. Use `SET LOCKS` when you want to reserve
instances **before** doing expensive preparation, so you fail fast.

---

## 18.11 `RAISE ENTITY EVENT`

```abap
" BDEF
define behavior for ZR_TravelTP alias Travel
{
  ...
  event TravelStatusChanged parameter ZE_TravelStatusEvent;
}
```

```abap
" in save_modified (the recommended place for a managed BO with additional save)
RAISE ENTITY EVENT zr_traveltp~TravelStatusChanged
  FROM VALUE #( ( %key-TravelUUID = ls-TravelUUID
                  %param = VALUE #( travel_uuid = ls-TravelUUID
                                    new_status  = ls-OverallStatus ) ) ).
```

Events are raised in the **late save phase** so that subscribers only see committed state. SAP's
guidance is to define the BO `with additional save` and raise events in `save_modified`.

---

## 18.12 Complete patterns

### A) Background job: mass update with error handling

```abap
CLASS zcl_travel_mass_accept DEFINITION PUBLIC FINAL CREATE PUBLIC
  FOR BEHAVIOR OF zr_traveltp.          " needed for PRIVILEGED

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
ENDCLASS.

CLASS zcl_travel_mass_accept IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.

    " 1. find candidates with plain SQL (finding, not reading BO state)
    SELECT FROM ztravel
      FIELDS travel_uuid
      WHERE overall_status = 'O'
        AND end_date < @sy-datum
      INTO TABLE @DATA(candidates)
      UP TO 1000 ROWS.

    CHECK candidates IS NOT INITIAL.

    DATA(keys) = VALUE ztravel_tky_tab(
      FOR c IN candidates ( TravelUUID = c-travel_uuid
                            %is_draft  = if_abap_behv=>mk-off ) ).

    " 2. ask what is actually permitted, rather than failing per instance
    READ ENTITIES OF zr_traveltp PRIVILEGED
      ENTITY Travel
        REQUEST VALUE #( %action-acceptTravel = if_abap_behv=>mk-on )
        GET PERMISSIONS
        FROM CORRESPONDING #( keys )
      RESULT DATA(perms).

    DATA(allowed) = VALUE ztravel_tky_tab( ).
    LOOP AT perms-instances INTO DATA(p)
         WHERE %action-acceptTravel = if_abap_behv=>fc-o-enabled.
      APPEND VALUE #( TravelUUID = p-TravelUUID
                      %is_draft  = if_abap_behv=>mk-off ) TO allowed.
    ENDLOOP.
    CHECK allowed IS NOT INITIAL.

    " 3. execute
    MODIFY ENTITIES OF zr_traveltp PRIVILEGED
      ENTITY Travel
        EXECUTE acceptTravel FROM CORRESPONDING #( allowed )
      FAILED   DATA(failed)
      REPORTED DATA(reported).

    " 4. commit and check
    COMMIT ENTITIES RESPONSE OF zr_traveltp
      FAILED   DATA(commit_failed)
      REPORTED DATA(commit_reported).

    CASE sy-subrc.
      WHEN 0.
        out->write( |Accepted { lines( allowed ) - lines( commit_failed-travel ) } travels| ).
      WHEN 4.
        out->write( 'Early save failed:' ).
        out->write( commit_reported ).
      WHEN 8.
        out->write( 'Late save failed - rolling back' ).
        ROLLBACK ENTITIES.
    ENDCASE.

  ENDMETHOD.
ENDCLASS.
```

### B) Calling a released SAP BO (Purchase Requisition)

```abap
DATA pr_headers TYPE TABLE FOR CREATE i_purchaserequisitiontp.
DATA pr_items   TYPE TABLE FOR CREATE i_purchaserequisitiontp\_PurchaseRequisitionItem.

APPEND VALUE #( %cid                    = 'PR1'
                purchaserequisitiontype = 'NB'
                PurReqnDescription      = 'From the Travel app' ) TO pr_headers.

APPEND VALUE #( %cid_ref = 'PR1'
                %target  = VALUE #( ( %cid                      = 'PR1_I1'
                                      plant                     = '1010'
                                      accountassignmentcategory = 'U'
                                      requestedquantity         = 1
                                      baseunit                  = 'EA'
                                      material                  = 'TG11'
                                      materialgroup             = 'L001'
                                      purchasinggroup           = '001'
                                      purchasingorganization    = '1010'
                                      DeliveryDate              = sy-datum + 30 ) ) )
       TO pr_items.

MODIFY ENTITIES OF i_purchaserequisitiontp
  ENTITY purchaserequisition
    CREATE FIELDS ( purchaserequisitiontype PurReqnDescription )
    WITH pr_headers
    CREATE BY \_purchaserequisitionitem
      FIELDS ( plant accountassignmentcategory requestedquantity baseunit
               material materialgroup purchasinggroup purchasingorganization DeliveryDate )
      WITH pr_items
  MAPPED   DATA(pr_mapped)
  FAILED   DATA(pr_failed)
  REPORTED DATA(pr_reported).

IF pr_failed IS NOT INITIAL.
  " handle
ENDIF.

COMMIT ENTITIES RESPONSE OF i_purchaserequisitiontp FAILED DATA(pr_commit_failed).
```

`I_PurchaseRequisitionTP` uses **late numbering** — `pr_mapped` carries `%pid`, not the real
document number. Resolving it requires `CONVERT KEY` inside `save_modified`. See Chapter 16, §16.8.

### C) Reading a released BO instead of its tables

```abap
" instead of SELECT FROM ekko / ekpo
READ ENTITIES OF i_purchaseordertp
  ENTITY PurchaseOrder
    FIELDS ( PurchaseOrder Supplier PurchaseOrderDate )
    WITH VALUE #( ( PurchaseOrder = '4500000123' ) )
  RESULT DATA(pos)
  FAILED DATA(failed).
```

Reading via the BO honours its authorizations and its released contract. Reading `EKKO` directly
does not, and is not a released API in ABAP Cloud.

---

## 18.13 EML performance

| Rule | Why |
|---|---|
| One EML statement with many instances, never one per instance in a loop | Each statement is a framework round trip |
| `FIELDS ( ... )` rather than `ALL FIELDS` | Reads less |
| `LINK DATA( )` rather than `RESULT DATA( )` when you only need existence | Avoids reading child data |
| `IN LOCAL MODE` inside the pool | Skips authorization and feature control |
| Combine reads into one `READ ENTITIES ... ENTITY A ... ENTITY B ...` | One round trip |
| `GET PERMISSIONS` once for the whole set, before acting | Avoids attempt-and-fail per instance |
| `COMMIT ENTITIES` once per logical unit, not per instance | One save sequence |
| Chunk very large sets (e.g. 1000 instances per commit) | Keeps the buffer and the lock table bounded |

### The anti-pattern

```abap
" WRONG - 5000 EML statements and 5000 save sequences
LOOP AT lt_uuids INTO DATA(lv_uuid).
  MODIFY ENTITIES OF zr_traveltp ENTITY Travel
    UPDATE FIELDS ( OverallStatus )
    WITH VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-off
                    OverallStatus = 'A' ) ).
  COMMIT ENTITIES.
ENDLOOP.

" RIGHT - one statement, one commit
MODIFY ENTITIES OF zr_traveltp ENTITY Travel
  UPDATE FIELDS ( OverallStatus )
  WITH VALUE #( FOR u IN lt_uuids ( %tky-TravelUUID = u
                                    %tky-%is_draft  = if_abap_behv=>mk-off
                                    OverallStatus   = 'A' ) ).
COMMIT ENTITIES.
```

---

## 18.14 EML troubleshooting

| Symptom | Cause |
|---|---|
| *"Entity does not exist"* at activation | Wrong separator: `\\` vs `\_` vs `~` |
| `RESULT` is empty | Wrong key. In a draft BO, `%key` was used instead of `%tky` |
| Create succeeds but `mapped` is empty | `%cid` not set, or `AUTO FILL CID` used and you looked for your own cid |
| Child created without a parent link | `%cid_ref` missing or pointing at a `%cid` that is not in the same statement |
| Update silently ignored | Field not listed in `FIELDS ( ... )`, so `%control` is off for it |
| *"Operation not allowed"* | `use update;` missing in the projection BDEF (if you called the projection), or feature control disabled it |
| Works with `IN LOCAL MODE`, fails without | An authorization check or feature control is rejecting it — which is correct behaviour |
| Nothing is saved | `COMMIT ENTITIES` missing |
| `COMMIT ENTITIES` "works" but nothing is in the table | `sy-subrc` was 4 and you did not check it |
| *"COMMIT not allowed"* | `COMMIT ENTITIES` inside a behavior pool |
| Deep create fails with "parent not found" | `%cid_ref` refers to an instance created in a *different* EML statement. It must be the same one |

---

## 18.15 Interview answer

> **"What is EML, and explain `%cid`, `%tky`, `%pid` and `%control`."**
>
> EML — Entity Manipulation Language — is the set of ABAP statements for calling a RAP business
> object: `READ ENTITIES`, `MODIFY ENTITIES`, `COMMIT ENTITIES`, `ROLLBACK ENTITIES`,
> `GET PERMISSIONS`, `SET LOCKS`, `RAISE ENTITY EVENT` and `CONVERT KEY`. It is the only supported
> way to reach a RAP BO from ABAP — you do not `SELECT` its tables and you do not call your own
> OData service over HTTP.
>
> `%cid` is the **content ID**: a name you invent for an instance that has no key yet. You send it
> on create and the framework tells you through `mapped` which real key it assigned. In a deep
> create the child uses `%cid_ref` to name its parent's `%cid`, and `%target` to carry the children
> — that is how you create a document and its items in one statement.
>
> `%tky` is the **transactional key** — the key plus `%is_draft`. In a draft-enabled BO the same key
> exists twice, active and draft, so `%key` alone is ambiguous. Using `%key` there reads the wrong
> copy, which usually presents as "my determination sees old data". `strict ( 2 )` makes it a syntax
> error.
>
> `%pid` is a **preliminary ID** in late-numbering scenarios, resolved to the real key with
> `CONVERT KEY` inside `save_modified`.
>
> `%control` is the set of per-field flags saying which fields the consumer actually sent. A managed
> BO honours it automatically; in an unmanaged BO or an unmanaged save you must respect it yourself,
> or a user who edits one field has every other field overwritten with initial values.
>
> One more thing worth saying: inside a behavior pool every EML call takes `IN LOCAL MODE` — buffer
> direct, skips authorization and feature control, and lets you write `readonly` fields. Outside the
> BO, never, because you want those checks.

## 18.16 Production considerations

- **One statement for many instances, never one per instance in a loop.** Each EML statement is a
  framework round trip, and a commit per instance is a save sequence per instance.
- **Chunk mass processing** (around 1,000 instances) so the buffer and the lock table stay bounded
  and the job is restartable.
- **`GET PERMISSIONS` before acting** in a batch, rather than attempting each instance and handling
  failures.
- **`PRIVILEGED` bypasses authorization.** Use it only where a job genuinely needs it, and document
  why each time.
- **`FIELDS ( ... )` not `ALL FIELDS`; `LINK` not `RESULT`** when only existence matters.
- **Always check `sy-subrc` / `failed` after `COMMIT ENTITIES`.**
- **Never `COMMIT ENTITIES` inside a behavior pool** — the BO is not the transaction owner.
- **Read released BOs through EML, not their tables.** In ABAP Cloud the tables are not released
  APIs, and EML honours the BO's own authorizations.

---

[< Save Sequence](17-Save-Sequence.md) | [Index](00-README.md) | [Next: Numbering, Locking, ETag >](19-Numbering-Locking-ETag.md)
