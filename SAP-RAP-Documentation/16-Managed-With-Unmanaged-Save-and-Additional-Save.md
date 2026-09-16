# Chapter 16 — Managed with Unmanaged Save, and Additional Save

[< Unmanaged Scenario](15-Unmanaged-Scenario.md) | [Index](00-README.md) | [Next: The Save Sequence >](17-Save-Sequence.md)

---

## 16.1 The two hybrid patterns

Between "the framework does everything" (managed) and "you do everything" (unmanaged) sit two
options that cover most real requirements:

| | `with additional save` | `with unmanaged save` |
|---|---|---|
| Who writes the BO's own table? | **The framework** | **You** |
| Your `save_modified` runs | **In addition** to the framework's save | **Instead of** the framework's save |
| `persistent table` in the BDEF | **Required** | **Forbidden** |
| Typical use | Change documents, application log, business events, calling a side-effect API | Persisting via a released API / BAPI, late numbering with `CONVERT KEY`, writing to a non-standard store |
| Everything else managed (buffer, lock, ETag, draft, field control, determinations, validations) | **Yes** | **Yes** |

Both are declared the same way and both are implemented in the same method: `save_modified`.

> **This is the answer to most "we need managed but the save is special" requirements.**
> Reach for a full unmanaged BO only if the *interaction phase* also has to be custom.

---

## 16.2 Declaring it

### In the BDEF header — applies to the whole BO

```abap
managed with additional save implementation in class ZBP_R_TravelTP unique;
strict ( 2 );
```

```abap
managed with unmanaged save implementation in class ZBP_R_TravelTP unique;
strict ( 2 );
```

### Per entity — applies to that entity only

```abap
define behavior for ZR_TravelTP alias Travel
//persistent table ztravel          <- must be removed for unmanaged save
draft table ztravel_d
etag master LocalLastChangedAt
lock master total etag LastChangedAt
authorization master ( global )
with unmanaged save
{ ... }
```

### Optional additions

```abap
managed with additional save with full data implementation in class ZBP_... unique;
managed with additional save and cleanup implementation in class ZBP_... unique;
```

| Addition | Effect |
|---|---|
| `with full data` | `save_modified` receives **all** instance fields, not just keys and changed fields. Saves you a `READ ENTITIES`. |
| `and cleanup` | You must also redefine `cleanup` in the saver class. Use it when you keep your own state that has to be reset. |

Both can be combined: `managed with additional save with full data and cleanup implementation in class ...`.

---

## 16.3 The three constraints that catch everyone

These are the practical rules, confirmed by SAP's own workshop material:

1. **`persistent table` and `with unmanaged save` cannot coexist.**
   Comment out or delete `persistent table ztravel` when you add `with unmanaged save`.
   Activation fails otherwise. (`with additional save` **keeps** `persistent table`.)

2. **With unmanaged/additional save, the behavior implementation class must be specified in the
   header, on the same line as `managed`.**
   If your BDEF currently has `implementation in class ... unique` on the *node* level (a common
   generated form), you must move it:

   ```abap
   " before
   managed implementation in class ZBP_R_TRAVELTP unique;
   define behavior for ZR_TravelTP alias Travel
   implementation in class ZBP_R_TRAVELTP unique       <- node level
   persistent table ztravel
   ...

   " after
   managed with unmanaged save implementation in class ZBP_R_TRAVELTP unique;
   define behavior for ZR_TravelTP alias Travel
   //implementation in class ZBP_R_TRAVELTP unique     <- removed
   //persistent table ztravel                          <- removed
   draft table ztravel_d
   ...
   ```

3. **For a field-selective update you need a control structure.**
   `save_modified` gives you `%control` per instance. To turn that into a field-selective
   `UPDATE`, declare an x-structure and extend the mapping:

   ```abap
   mapping for ZTRAVEL control ztravel_x corresponding
   ```

   with

   ```abap
   @EndUserText.label : 'Control structure for ZTRAVEL'
   @AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
   define structure ztravel_x {
     travel_id             : abap_boolean;
     agency_id             : abap_boolean;
     customer_id           : abap_boolean;
     begin_date            : abap_boolean;
     end_date              : abap_boolean;
     booking_fee           : abap_boolean;
     total_price           : abap_boolean;
     currency_code         : abap_boolean;
     description           : abap_boolean;
     overall_status        : abap_boolean;
     created_by            : abap_boolean;
     created_at            : abap_boolean;
     last_changed_by       : abap_boolean;
     last_changed_at       : abap_boolean;
     local_last_changed_at : abap_boolean;
   }
   ```

---

## 16.4 Generating the saver class

After activating the BDEF, put the cursor on the keyword `unmanaged` (or `additional`) and press
**`Ctrl + 1`**. ADT adds the local saver class to the behavior pool's *Local Types*:

```abap
CLASS lsc_zr_traveltp DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
ENDCLASS.

CLASS lsc_zr_traveltp IMPLEMENTATION.
  METHOD save_modified.
  ENDMETHOD.
ENDCLASS.
```

---

## 16.5 The `save_modified` signature

```abap
METHODS save_modified
  IMPORTING create   TYPE DATA
            update   TYPE DATA
            delete   TYPE DATA
  CHANGING  reported TYPE DATA OPTIONAL
            failed   TYPE DATA OPTIONAL.
```

At runtime the parameters are typed:

| Parameter | Derived type | Contains |
|---|---|---|
| `create` | `REQUEST FOR CHANGE zr_traveltp` | Instances to create, per entity: `create-travel`, `create-booking` |
| `update` | `REQUEST FOR CHANGE zr_traveltp` | Instances to update, with `%control` |
| `delete` | `REQUEST FOR DELETE zr_traveltp` | Keys to delete |

Each is a **deep structure with one component per entity alias**, lowercase:

```abap
create-travel      " TABLE FOR CREATE zr_traveltp
create-booking     " TABLE FOR CREATE zr_traveltp\\Booking
update-travel
update-booking
delete-travel
delete-booking
```

By default `create` / `update` carry **keys plus changed fields only**. With `with full data` they
carry everything.

---

## 16.6 Unmanaged save — full implementation

```abap
CLASS lsc_zr_traveltp DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
    METHODS cleanup       REDEFINITION.
ENDCLASS.

CLASS lsc_zr_traveltp IMPLEMENTATION.

  METHOD save_modified.

    " ---------------- CREATE ----------------
    IF create-travel IS NOT INITIAL.
      DATA(lt_insert) = CORRESPONDING ztravel_tab( create-travel MAPPING FROM ENTITY ).
      INSERT ztravel FROM TABLE @lt_insert.
    ENDIF.

    IF create-booking IS NOT INITIAL.
      DATA(lt_binsert) = CORRESPONDING zbooking_tab( create-booking MAPPING FROM ENTITY ).
      INSERT zbooking FROM TABLE @lt_binsert.
    ENDIF.

    " ---------------- UPDATE ----------------
    IF update-travel IS NOT INITIAL.

      " data ...
      DATA(lt_update)  = CORRESPONDING ztravel_tab(   update-travel MAPPING FROM ENTITY ).
      " ... and the control flags, via the x-structure from the BDEF mapping
      DATA(lt_control) = CORRESPONDING ztravel_x_tab( update-travel MAPPING FROM ENTITY ).

      LOOP AT lt_update INTO DATA(ls_upd).
        DATA(ls_ctrl) = lt_control[ sy-tabix ].

        " Field-selective UPDATE SET. Only the fields the consumer actually sent.
        UPDATE ztravel
          SET agency_id      = COND #( WHEN ls_ctrl-agency_id   = abap_true
                                       THEN @ls_upd-agency_id   ELSE @agency_id ),
              customer_id    = COND #( WHEN ls_ctrl-customer_id = abap_true
                                       THEN @ls_upd-customer_id ELSE @customer_id ),
              begin_date     = COND #( WHEN ls_ctrl-begin_date  = abap_true
                                       THEN @ls_upd-begin_date  ELSE @begin_date ),
              end_date       = COND #( WHEN ls_ctrl-end_date    = abap_true
                                       THEN @ls_upd-end_date    ELSE @end_date ),
              description    = COND #( WHEN ls_ctrl-description = abap_true
                                       THEN @ls_upd-description ELSE @description ),
              last_changed_by = @ls_upd-last_changed_by,
              last_changed_at = @ls_upd-last_changed_at
          WHERE travel_uuid = @ls_upd-travel_uuid.
      ENDLOOP.
    ENDIF.

    " ---------------- DELETE ----------------
    IF delete-travel IS NOT INITIAL.
      LOOP AT delete-travel INTO DATA(ls_del).
        DELETE FROM ztravel  WHERE travel_uuid = @ls_del-TravelUUID.
        DELETE FROM zbooking WHERE travel_uuid = @ls_del-TravelUUID.   " cascade
        DELETE FROM ztravel_d  WHERE traveluuid = @ls_del-TravelUUID.  " draft rows
        DELETE FROM zbooking_d WHERE traveluuid = @ls_del-TravelUUID.
      ENDLOOP.
    ENDIF.

    IF delete-booking IS NOT INITIAL.
      LOOP AT delete-booking INTO DATA(ls_bdel).
        DELETE FROM zbooking WHERE booking_uuid = @ls_bdel-BookingUUID.
      ENDLOOP.
    ENDIF.

  ENDMETHOD.

  METHOD cleanup.
    CLEAR zbp_r_traveltp=>mapped_purchase_requisition.
    CLEAR zbp_r_traveltp=>mt_travels_to_notify.
  ENDMETHOD.

ENDCLASS.
```

### Notes

- **`CORRESPONDING ... MAPPING FROM ENTITY`** uses the BDEF's `mapping for` block to convert CDS
  element names to DDIC field names. Without a `mapping for`, this does nothing useful.
- **A simpler `MODIFY ztravel FROM TABLE @lt_update`** is possible and is what SAP's own workshop
  example uses. It is correct **only when the payload carries all fields** — i.e. with
  `with full data`, or when you first read the full instance. Without that, unsent fields are
  written as initial. The `COND` form above is the safe default; `with full data` +
  `MODIFY ... FROM TABLE` is the simpler one.
- **Draft rows must be deleted too.** The managed runtime does this; when you take over the save you
  inherit the responsibility.
- **No `COMMIT WORK`.** RAP commits after `save_modified` returns.

---

## 16.7 Additional save — full implementation

Here the framework still writes `ztravel`. Your method adds side effects.

```abap
CLASS lsc_zr_traveltp DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
    METHODS cleanup       REDEFINITION.
ENDCLASS.

CLASS lsc_zr_traveltp IMPLEMENTATION.

  METHOD save_modified.

    " ---- 1. Application log ----
    DATA(lo_log) = zcl_travel_applog=>get( ).
    LOOP AT create-travel INTO DATA(ls_created).
      lo_log->add_info( |Travel created: { ls_created-TravelUUID }| ).
    ENDLOOP.
    LOOP AT update-travel INTO DATA(ls_updated).
      lo_log->add_info( |Travel changed: { ls_updated-TravelUUID }| ).
    ENDLOOP.
    LOOP AT delete-travel INTO DATA(ls_deleted).
      lo_log->add_warning( |Travel deleted: { ls_deleted-TravelUUID }| ).
    ENDLOOP.
    lo_log->save( ).           " BAL_DB_SAVE - registered for the update task

    " ---- 2. Change documents ----
    LOOP AT update-travel INTO DATA(ls_chg).
      zcl_travel_changedoc=>write( travel_uuid = ls_chg-TravelUUID
                                   control     = CORRESPONDING ztravel_x( ls_chg
                                                   MAPPING FROM ENTITY ) ).
    ENDLOOP.

    " ---- 3. RAP business event ----
    LOOP AT update-travel INTO DATA(ls_evt)
         WHERE %control-OverallStatus = if_abap_behv=>mk-on.
      RAISE ENTITY EVENT zr_traveltp~TravelStatusChanged
        FROM VALUE #( ( %key-TravelUUID = ls_evt-TravelUUID
                        %param = VALUE #( travel_uuid = ls_evt-TravelUUID
                                          new_status  = ls_evt-OverallStatus ) ) ).
    ENDLOOP.

    " ---- 4. Notify an external system (flagged during the interaction phase) ----
    IF zbp_r_traveltp=>mt_travels_to_notify IS NOT INITIAL.
      zcl_travel_outbound=>enqueue( zbp_r_traveltp=>mt_travels_to_notify ).
    ENDIF.

  ENDMETHOD.

  METHOD cleanup.
    CLEAR zbp_r_traveltp=>mt_travels_to_notify.
  ENDMETHOD.

ENDCLASS.
```

### `%control` in `update`

`ls_evt-%control-OverallStatus = if_abap_behv=>mk-on` tells you **which fields actually changed**.
That is the difference between "log every save" and "log only status changes". It is the single most
useful part of the `update` payload.

### What belongs in `save_modified` and what does not

| Belongs | Does not belong |
|---|---|
| Writing an application log | Business validation (→ `check_before_save`) |
| Change documents | Data derivation (→ a determination, or `finalize`) |
| Raising a business event | Anything that can fail and must be able to abort the save |
| Registering an update-task function module | `COMMIT WORK` |
| Enqueuing an outbound message | Synchronous RFC or `WAIT` (forbidden in the late phase) |
| `CONVERT KEY` for late numbering | A long-running HTTP call |

**The late save phase must not fail.** Everything that can be checked must be checked in
`check_before_save`.

---

## 16.8 The late-numbering pattern — the real reason for unmanaged save

This is SAP's own motivating example, and it is worth understanding because it is not obvious.

**The problem:** an action calls a released API (`I_PurchaseRequisitionTP`) that uses **late
numbering**. The API returns a *preliminary* id (`%pid`), not the real document number. The real
number only exists after the save sequence. And `CONVERT KEY` — the statement that resolves a
`%pid` to a real key — **can only be called inside `save_modified`**.

So: the action runs in the interaction phase and gets a `%pid`; the real number is available in the
save sequence; and you must write it into your own table. That forces `with unmanaged save`
(with `with additional save` you cannot write your own table — the framework already did).

### Step 1 — a bridge variable in the global ABP class

```abap
CLASS zbp_r_traveltp DEFINITION
  PUBLIC ABSTRACT FINAL
  FOR BEHAVIOR OF zr_traveltp.

  PUBLIC SECTION.
    CLASS-DATA mapped_purchase_requisition
      TYPE RESPONSE FOR MAPPED i_purchaserequisitiontp.
ENDCLASS.
```

The handler and the saver are separate classes. A `CLASS-DATA` on the global ABP class is the
supported channel between them.

### Step 2 — the action stores the preliminary ids

```abap
METHOD createPurchaseRequisition.

  " ... build the payload from the selected Travels ...

  MODIFY ENTITIES OF i_purchaserequisitiontp
    ENTITY purchaserequisition
      CREATE FIELDS ( purchaserequisitiontype )
      WITH purchase_requisitions
      CREATE BY \_purchaserequisitionitem
        FIELDS ( plant requestedquantity material ... )
        WITH purchase_requisition_items
    MAPPED   DATA(mapped_create_pr)
    FAILED   DATA(failed_create_pr)
    REPORTED DATA(reported_create_pr).

  " hand the preliminary ids to the save sequence
  zbp_r_traveltp=>mapped_purchase_requisition-purchaserequisition
    = mapped_create_pr-purchaserequisition.

  " update our own instance so that the save sequence is actually triggered
  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      UPDATE FIELDS ( OverallStatus PurchRqnCreationDate )
      WITH update_lines
    REPORTED reported FAILED failed MAPPED mapped.

ENDMETHOD.
```

Note the last `MODIFY`: without changing something on our own BO, our `save_modified` would never
be called and the `CONVERT KEY` would never run.

### Step 3 — resolve the key in `save_modified`

```abap
METHOD save_modified.

  " ... normal create / update / delete handling of ztravel ...

  IF zbp_r_traveltp=>mapped_purchase_requisition IS NOT INITIAL
     AND update-travel IS NOT INITIAL.

    LOOP AT zbp_r_traveltp=>mapped_purchase_requisition-purchaserequisition
         ASSIGNING FIELD-SYMBOL(<pr_mapped>).

      " Only legal inside save_modified
      CONVERT KEY OF i_purchaserequisitiontp
        FROM <pr_mapped>-%pid
        TO   DATA(ls_pr_key).

      <pr_mapped>-purchaserequisition = ls_pr_key-purchaserequisition.
    ENDLOOP.

    LOOP AT update-travel INTO DATA(ls_travel)
         WHERE %control-OverallStatus = if_abap_behv=>mk-on.
      UPDATE ztravel
        SET purchase_requisition    = @ls_pr_key-purchaserequisition,
            purch_rqn_creation_date = @sy-datum
        WHERE travel_uuid = @ls_travel-TravelUUID.
    ENDLOOP.

  ENDIF.

ENDMETHOD.
```

### Step 4 — clear the bridge

```abap
METHOD cleanup.
  CLEAR zbp_r_traveltp=>mapped_purchase_requisition.
ENDMETHOD.

METHOD cleanup_finalize.
  CLEAR zbp_r_traveltp=>mapped_purchase_requisition.
ENDMETHOD.
```

**Do not skip this.** `CLASS-DATA` survives the transaction. A second save in the same session would
otherwise re-process stale preliminary ids.

---

## 16.9 Choosing between the four options — a worked decision

### The one-line distinction

- **`with additional save`** — the framework persists the BO; your code performs **extra
  save-related work** alongside it.
- **`with unmanaged save`** — **your implementation is responsible for persistence**; the framework
  does not write the BO's table.

### By business requirement

| Requirement | Suitable approach | Why |
|---|---|---|
| Write an application log entry after a successful RAP save | **Additional save** | The BO's own persistence is unchanged; you are adding a side effect |
| Create a change document (who changed which field) | **Additional save** | Needs the `%control` flags from `update`, which `save_modified` provides, plus the framework's own write |
| Publish a RAP business event / notify a downstream process | **Additional save** | Events should fire on committed state; `save_modified` is the documented place |
| Register an update-task function module for an asynchronous follow-on | **Additional save** | Update-task registration is only legal in the late save phase |
| Write an outbound queue / IDoc / webhook payload | **Additional save** | Enqueue in the late phase, after the BO is known to be saving |
| Persist through a legacy BAPI instead of writing the table | **Unmanaged save**, or full **unmanaged RAP** if the reads must also go through legacy logic | The framework must not also write the table, or you get a double write |
| Persist into a non-RAP external store (external DB, REST API, file) | **Unmanaged save**, with careful error handling | No `persistent table` exists to be framework-managed |
| Call a released API that uses **late numbering** and store its key in your table | **Unmanaged save** | `CONVERT KEY` is only legal inside `save_modified`, and you need to write the resolved key yourself (§16.8) |
| Persist to a table whose layout does not match the BO 1:1 (splitting, denormalising, archiving) | **Unmanaged save** | The framework's 1:1 mapping cannot express it |
| Reuse existing **interaction and locking** logic, not just the save | **Full unmanaged RAP** | The interaction phase is custom too, so `managed` provides nothing you can use |
| Reads must go through existing function modules rather than the table | **Full unmanaged RAP** | You need `FOR READ` |
| Plain CRUD on your own Z tables | **`managed`** | Add nothing |

### Two cases worth spelling out

**"Publish an event or call a side-effect process"** is listed as *usually* additional save, and the
qualifier matters. It is additional save when the side effect must happen **because the BO was
saved** and must see committed state. It is **not** additional save when:

- the side effect can fail and should abort the save → the check belongs in `check_before_save`,
  and only the irreversible part in `save_modified`;
- the side effect is synchronous and slow (an HTTP call, an RFC) → synchronous RFC is **not**
  allowed in the late save phase; enqueue it instead and process it asynchronously;
- the side effect is really a data derivation → that is a determination, not a save enhancement.

**"Persist through a legacy BAPI"** splits by how much of the legacy logic you need:

| You need | Choose |
|---|---|
| Only the BAPI's write, with your own model and buffer | `managed with unmanaged save` |
| The BAPI's write **and** its read/lock semantics | full `unmanaged` |

### Decision order

Work down this list and stop at the first match:

1. Is the **interaction phase** (read, lock, buffer) custom? → **unmanaged**.
2. Is the **persistence** custom (BAPI, external store, non-1:1 layout, late-numbering key)?
   → **managed with unmanaged save**.
3. Do you need **extra work at save time** on top of normal persistence? → **managed with
   additional save**.
4. Otherwise → **managed**.

Notice how far down the list you get before a full unmanaged BO is justified.

---

## 16.10 Troubleshooting

| Symptom | Cause |
|---|---|
| *"persistent table is not allowed"* | `persistent table` left in place together with `with unmanaged save` |
| *"Implementation class must be specified in the header"* | The class is declared at node level; move it next to `managed` |
| `save_modified` never called | Nothing on **your** BO changed — an action that only calls another BO does not trigger your save. Add an update to your own instance |
| Data saved but fields are blank | `mapping for` missing, or `MODIFY ... FROM TABLE` used without `with full data` |
| Update wipes fields the user did not touch | `%control` ignored; use the x-structure and a field-selective `UPDATE SET` |
| `CONVERT KEY` raises an exception | Called outside `save_modified`; it is only legal there |
| Second save in the same session behaves oddly | `CLASS-DATA` not cleared in `cleanup` / `cleanup_finalize` |
| Draft rows remain after delete | With unmanaged save you must delete the draft table rows yourself |
| Dump after the point of no return | Something that can fail was left in `save_modified` instead of `check_before_save` |
| `create-travel` is empty although a Travel was created | You are looking at the wrong component — the component name is the **alias**, lowercase |

---

## 16.11 Interview answer

> **"What is the difference between additional save and unmanaged save, and when do you use each?"**
>
> Both are declared on a **managed** business object and both are implemented in `save_modified`, so
> you keep the managed buffer, locking, ETag, draft and field control. The difference is
> persistence.
>
> With **`with additional save`**, the framework still writes the BO's table. Your `save_modified`
> runs **in addition**, for save-related side effects — change documents, an application log entry,
> raising a RAP business event, registering an update-task module, enqueueing an outbound message.
> `persistent table` stays.
>
> With **`with unmanaged save`**, **you** are responsible for persistence. The framework does not
> write the table, and `persistent table` must be removed from the behavior definition — the two
> cannot coexist. That is for persisting through a BAPI, into an external store, or into a layout
> that is not 1:1 with the BO.
>
> The case that forces unmanaged save is **late numbering**. If you call a released API that only
> returns a preliminary ID, resolving it needs `CONVERT KEY`, which is legal only inside
> `save_modified` — and you need to write the resolved number into your own table, which additional
> save cannot do because the framework has already written it.
>
> `save_modified` gives you `create`, `update` and `delete`, and `update` carries `%control`, so you
> can tell exactly which fields changed — that is what makes change documents and
> status-change events practical.
>
> One rule applies to both: the late save phase must not fail. Anything that can fail belongs in
> `check_before_save`.

## 16.12 Production considerations

- **Two constraints that fail at activation:** `persistent table` cannot coexist with
  `with unmanaged save`, and the behavior pool class must be declared in the **header**, on the same
  line as `managed`, not at node level.
- **Clear every `CLASS-DATA` bridge variable in `cleanup` and `cleanup_finalize`.** Class data
  survives the session, and `cleanup_finalize` is the path taken when the save is rejected.
- **With unmanaged save you inherit the draft-table clean-up** — the framework no longer deletes
  draft rows on activation. Do it yourself.
- **Respect `%control` on update**, or use `with full data`, or you will write initial values over
  fields the user never touched.
- **No synchronous RFC or HTTP in `save_modified`** — it runs in the late save phase. Enqueue
  instead, and process asynchronously with retry and idempotency.
- **Raise business events here, not in the action**, so subscribers only see committed state.
- **Test the second save in the same session.** Stale bridge state is the classic defect and only
  shows up on the second transaction.

---

[< Unmanaged Scenario](15-Unmanaged-Scenario.md) | [Index](00-README.md) | [Next: The Save Sequence >](17-Save-Sequence.md)
