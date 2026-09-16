# Chapter 15 — The Unmanaged Scenario

[< Feature Control & Authorization](14-Feature-Control-and-Authorization.md) | [Index](00-README.md) | [Next: Managed with Unmanaged Save >](16-Managed-With-Unmanaged-Save-and-Additional-Save.md)

---

> ## Status of the code in this chapter
>
> **The ABAP in this chapter is conceptual reference code. It has not been activated or executed in
> an SAP system.** It shows the shape of an unmanaged implementation — which methods exist, what
> each is responsible for, and how the pieces fit — and the structure is sound. The exact syntax of
> individual statements must be validated in your target release before use.
>
> Unmanaged RAP is the part of the model with the most hand-written framework-facing code, so it is
> also where small syntax differences bite hardest. Before adopting any example here, recheck:
>
> | Recheck | Why |
> |---|---|
> | `FOR READ`, `FOR MODIFY`, `FOR LOCK` method signatures | Generate them with `Ctrl + 1` from the BDEF rather than copying; the generated signature is authoritative for your release |
> | Read-by-association (`rba_*`) and create-by-association (`cba_*`) signatures | `FULL result_requested`, `LINK association_links`, `%target` handling all have exact forms |
> | `%tky` construction when building key tables by hand | Component names and whether `%is_draft` applies at all |
> | `CORRESPONDING ... MAPPING FROM ENTITY` / `MAPPING TO ENTITY` | Depends on a correct `mapping for` block; behaviour differs with `control` and `corresponding` |
> | `mapped` structures for create and create-by-association | Component names are the entity **aliases**, lower case |
> | Buffer access from the saver class | The saver is a *separate local class* from the handler — verify the visibility of whatever you share, and that singleton state is reachable and correctly reset |
> | Lock scope, `_scope` parameter and where `DEQUEUE` belongs | Lock-object generation and scope semantics are not RAP-specific but are easy to get wrong here |
> | Error handling after the point of no return | Whether you need `CL_ABAP_BEHAVIOR_SAVER_FAILED` rather than `CL_ABAP_BEHAVIOR_SAVER` |
> | Visibility sections of helper methods and types | Handler methods are `PRIVATE`, saver methods `PROTECTED`; helper classes and types have their own rules |
>
> The **managed** chapters (08–14, 16) follow documented declarative syntax that was verified against
> SAP's published material; this chapter is the one to treat with the most caution.
>
> The fastest way to get a known-good unmanaged implementation is to open the **ABAP Flight
> Reference Scenario** (`/DMO/` packages, shipped with the system) — it contains a complete,
> activated unmanaged BO for exactly this data model.

---

## 15.1 When unmanaged is the right answer

Unmanaged means: **you provide everything**. The transactional buffer, the read, the create, the
update, the delete, the lock, the save. RAP provides only the orchestration and the protocol.

Choose unmanaged when **all** of these are true:

- There is existing transactional logic (function modules, BAPIs, update-task modules) that you must
  reuse rather than reimplement.
- That logic owns its own locking and its own persistence.
- Reimplementing it in a managed BO would be a rewrite with regression risk.

Do **not** choose unmanaged because:

| Reason people give | Why it is wrong |
|---|---|
| "We already have tables" | Managed works on existing tables. `persistent table` accepts any table. |
| "The data model is complex" | Composition trees are a managed strength. |
| "We need custom validation logic" | Managed supports validations, determinations, actions. |
| "We need to call an API on save" | That is `with additional save` or `with unmanaged save` — Chapter 16, far less work. |
| "The key is not a UUID" | Managed supports semantic keys and external numbering. |

**If the only unmanaged thing you need is the save, use `managed with unmanaged save`
(Chapter 16), not a full unmanaged BO.** That is the single most useful piece of advice in this
chapter — it saves several hundred lines.

---

## 15.2 What you have to implement

| Handler | Mandatory | Purpose |
|---|---|---|
| `FOR READ` | Yes | Read instances from your buffer / persistence |
| `FOR MODIFY ... FOR CREATE` | If create is enabled | Create in the buffer |
| `FOR MODIFY ... FOR UPDATE` | If update is enabled | Update in the buffer |
| `FOR MODIFY ... FOR DELETE` | If delete is enabled | Mark for deletion in the buffer |
| `FOR LOCK` | Yes (unless `lock master unmanaged` is omitted) | Acquire the lock |
| `FOR READ ... \_Child` (rba) | If there are children | Read by association |
| `FOR MODIFY ... FOR CREATE ...\_Child` (cba) | If create-by-association is enabled | Create children |
| Saver `finalize` | Optional | Final adjustments |
| Saver `check_before_save` | Optional but recommended | Last consistency gate |
| Saver `save` | Yes | Persist the buffer |
| Saver `cleanup` | Yes | Clear the buffer |
| Saver `cleanup_finalize` | Yes | Clear the buffer after an early-save failure |
| Saver `adjust_numbers` | Only with `late numbering` | Assign final keys |

Plus: the transactional buffer itself, which you design.

---

## 15.3 The BDEF

```abap
unmanaged implementation in class ZBP_R_TravelTP_U unique;
strict ( 2 );

define behavior for ZR_TravelTP_U alias Travel
implementation in class ZBP_R_TravelTP_U unique
lock master
authorization master ( instance )
etag master LastChangedAt
{
  create;
  update;
  delete;

  field ( readonly ) TravelUUID, CreatedBy, CreatedAt, LastChangedBy, LastChangedAt;
  field ( mandatory ) AgencyId, CustomerId, BeginDate, EndDate;

  association _Booking { create; }

  action acceptTravel result [1] $self;

  mapping for ztravel
  {
    TravelUUID = travel_uuid;
    TravelId   = travel_id;
    ...
  }
}

define behavior for ZR_BookingTP_U alias Booking
implementation in class ZBP_R_TravelTP_U unique
lock dependent by _Travel
authorization dependent by _Travel
{
  update;
  delete;
  field ( readonly ) BookingUUID, TravelUUID;
  association _Travel;
}
```

### Differences from a managed BDEF

| | Managed | Unmanaged |
|---|---|---|
| Header | `managed implementation in class ...` | `unmanaged implementation in class ...` |
| `persistent table` | Required | **Not present** — there is no framework save |
| `draft table` | For draft | Draft in unmanaged is possible but significantly more work |
| `field ( numbering : managed )` | Available | **Not available** — you assign keys |
| `lock master` | Framework locks | You implement `FOR LOCK` |
| `mapping for` | Used by the framework's save | Only useful if you use `CORRESPONDING ... MAPPING FROM ENTITY` yourself |

---

## 15.4 The transactional buffer

Everything hinges on this. The buffer holds the state of the transaction between the interaction
phase and the save.

```abap
CLASS lcl_buffer DEFINITION CREATE PRIVATE.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_travel_buffer,
             travel     TYPE ztravel,          " the data
             changed    TYPE abap_boolean,     " was it modified?
             created    TYPE abap_boolean,     " is it new?
             deleted    TYPE abap_boolean,     " marked for deletion?
             control    TYPE ztravel_x,        " which fields were sent (x-structure)
           END OF ty_travel_buffer,
           tt_travel_buffer TYPE SORTED TABLE OF ty_travel_buffer
                              WITH UNIQUE KEY travel-travel_uuid.

    TYPES: BEGIN OF ty_booking_buffer,
             booking TYPE zbooking,
             changed TYPE abap_boolean,
             created TYPE abap_boolean,
             deleted TYPE abap_boolean,
             control TYPE zbooking_x,
           END OF ty_booking_buffer,
           tt_booking_buffer TYPE SORTED TABLE OF ty_booking_buffer
                               WITH UNIQUE KEY booking-booking_uuid.

    CLASS-METHODS get_instance RETURNING VALUE(r_result) TYPE REF TO lcl_buffer.

    METHODS: load_travels  IMPORTING it_uuids TYPE ztravel_uuid_tab,
             get_travels   RETURNING VALUE(rt_result) TYPE tt_travel_buffer,
             get_bookings  RETURNING VALUE(rt_result) TYPE tt_booking_buffer,
             upsert_travel IMPORTING is_travel TYPE ty_travel_buffer,
             clear.

    DATA: mt_travels  TYPE tt_travel_buffer,
          mt_bookings TYPE tt_booking_buffer.

  PRIVATE SECTION.
    CLASS-DATA mo_instance TYPE REF TO lcl_buffer.
ENDCLASS.

CLASS lcl_buffer IMPLEMENTATION.

  METHOD get_instance.
    IF mo_instance IS NOT BOUND.
      mo_instance = NEW #( ).
    ENDIF.
    r_result = mo_instance.
  ENDMETHOD.

  METHOD load_travels.
    " Load only what is not already buffered. The buffer wins over the DB.
    DATA(lt_missing) = it_uuids.
    LOOP AT it_uuids INTO DATA(lv_uuid).
      IF line_exists( mt_travels[ travel-travel_uuid = lv_uuid ] ).
        DELETE lt_missing WHERE table_line = lv_uuid.
      ENDIF.
    ENDLOOP.
    CHECK lt_missing IS NOT INITIAL.

    SELECT * FROM ztravel
      FOR ALL ENTRIES IN @lt_missing
      WHERE travel_uuid = @lt_missing-table_line
      INTO TABLE @DATA(lt_db).

    LOOP AT lt_db INTO DATA(ls_db).
      INSERT VALUE #( travel = ls_db ) INTO TABLE mt_travels.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_travels.   rt_result = mt_travels.  ENDMETHOD.
  METHOD get_bookings.  rt_result = mt_bookings. ENDMETHOD.

  METHOD upsert_travel.
    DELETE mt_travels WHERE travel-travel_uuid = is_travel-travel-travel_uuid.
    INSERT is_travel INTO TABLE mt_travels.
  ENDMETHOD.

  METHOD clear.
    CLEAR: mt_travels, mt_bookings.
  ENDMETHOD.

ENDCLASS.
```

### Three non-negotiable buffer rules

1. **The buffer always wins over the database.** `load_travels` must not overwrite an instance that
   is already in the buffer — the buffered copy carries the user's uncommitted changes.
2. **The buffer must be cleared in `cleanup` and `cleanup_finalize`.** Otherwise the next
   transaction in the same session sees stale data. This is the most common unmanaged bug.
3. **Track the operation per instance** (`created` / `changed` / `deleted`) and the **field
   control** (`control`). Without the x-structure you cannot do a field-selective update, and a
   blanket `MODIFY` will overwrite fields the consumer never sent with initial values.

---

## 15.5 The handler methods

### `FOR READ`

```abap
METHOD read.

  DATA(lo_buffer) = lcl_buffer=>get_instance( ).
  lo_buffer->load_travels( VALUE #( FOR k IN keys ( k-TravelUUID ) ) ).

  LOOP AT keys INTO DATA(key).
    DATA(ls_buffered) = VALUE #( lo_buffer->mt_travels[ travel-travel_uuid = key-TravelUUID ]
                                 OPTIONAL ).

    IF ls_buffered IS INITIAL OR ls_buffered-deleted = abap_true.
      APPEND VALUE #( %tky        = key-%tky
                      %fail-cause = if_abap_behv=>cause-not_found ) TO failed-travel.
      CONTINUE.
    ENDIF.

    APPEND CORRESPONDING #( ls_buffered-travel MAPPING TO ENTITY ) TO result
           ASSIGNING FIELD-SYMBOL(<result>).
    <result>-%tky = key-%tky.
  ENDLOOP.
ENDMETHOD.
```

`CORRESPONDING #( ... MAPPING TO ENTITY )` uses the `mapping for` block in the BDEF to translate
DDIC field names to CDS element names. `MAPPING FROM ENTITY` goes the other way. These two RAP-specific
additions to `CORRESPONDING` are what make `mapping for` worth writing.

> **Respect `%control`.** A well-behaved `read` returns only the fields the consumer requested
> (`keys-%control`). Returning everything works but is wasteful on wide entities.

### `FOR MODIFY ... FOR CREATE`

```abap
METHOD create.

  DATA(lo_buffer) = lcl_buffer=>get_instance( ).

  LOOP AT entities INTO DATA(entity).

    " Unmanaged: YOU assign the key
    TRY.
        DATA(lv_uuid) = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        APPEND VALUE #( %cid = entity-%cid ) TO failed-travel.
        CONTINUE.
    ENDTRY.

    DATA(ls_travel) = CORRESPONDING ztravel( entity MAPPING FROM ENTITY ).
    ls_travel-travel_uuid     = lv_uuid.
    ls_travel-created_by      = cl_abap_context_info=>get_user_technical_name( ).
    GET TIME STAMP FIELD ls_travel-created_at.
    ls_travel-last_changed_by = ls_travel-created_by.
    ls_travel-last_changed_at = ls_travel-created_at.

    lo_buffer->upsert_travel( VALUE #( travel  = ls_travel
                                       created = abap_true ) ).

    " report the assigned key back to the consumer
    APPEND VALUE #( %cid       = entity-%cid
                    TravelUUID = lv_uuid ) TO mapped-travel.
  ENDLOOP.
ENDMETHOD.
```

**Filling `mapped` is mandatory.** The consumer sent a `%cid` and has no other way to learn the key.

### `FOR MODIFY ... FOR UPDATE`

```abap
METHOD update.

  DATA(lo_buffer) = lcl_buffer=>get_instance( ).
  lo_buffer->load_travels( VALUE #( FOR e IN entities ( e-TravelUUID ) ) ).

  LOOP AT entities INTO DATA(entity).

    ASSIGN lo_buffer->mt_travels[ travel-travel_uuid = entity-TravelUUID ]
           TO FIELD-SYMBOL(<buffered>).
    IF sy-subrc <> 0.
      APPEND VALUE #( %tky        = entity-%tky
                      %fail-cause = if_abap_behv=>cause-not_found ) TO failed-travel.
      CONTINUE.
    ENDIF.

    " FIELD-SELECTIVE update: only what %control says was sent
    IF entity-%control-AgencyId   = if_abap_behv=>mk-on.
      <buffered>-travel-agency_id   = entity-AgencyId.
      <buffered>-control-agency_id  = abap_true.
    ENDIF.
    IF entity-%control-CustomerId = if_abap_behv=>mk-on.
      <buffered>-travel-customer_id  = entity-CustomerId.
      <buffered>-control-customer_id = abap_true.
    ENDIF.
    IF entity-%control-BeginDate  = if_abap_behv=>mk-on.
      <buffered>-travel-begin_date  = entity-BeginDate.
      <buffered>-control-begin_date = abap_true.
    ENDIF.
    " ... one block per field ...

    <buffered>-travel-last_changed_by = cl_abap_context_info=>get_user_technical_name( ).
    GET TIME STAMP FIELD <buffered>-travel-last_changed_at.
    <buffered>-changed = abap_true.

  ENDLOOP.
ENDMETHOD.
```

**This is the code the managed runtime writes for you.** One `IF %control` block per field, for
every entity. On a 40-field entity that is 120 lines of mechanical code per entity. It is the
clearest single illustration of what managed RAP is worth.

A shorter form using the x-structure mapping (see Chapter 08, §8.12):

```abap
DATA(ls_x) = CORRESPONDING ztravel_x( entity MAPPING FROM ENTITY ).
" then use ls_x-agency_id etc. as the control flags
```

### `FOR MODIFY ... FOR DELETE`

```abap
METHOD delete.
  DATA(lo_buffer) = lcl_buffer=>get_instance( ).
  lo_buffer->load_travels( VALUE #( FOR k IN keys ( k-TravelUUID ) ) ).

  LOOP AT keys INTO DATA(key).
    ASSIGN lo_buffer->mt_travels[ travel-travel_uuid = key-TravelUUID ]
           TO FIELD-SYMBOL(<buffered>).
    IF sy-subrc <> 0.
      APPEND VALUE #( %tky        = key-%tky
                      %fail-cause = if_abap_behv=>cause-not_found ) TO failed-travel.
      CONTINUE.
    ENDIF.
    <buffered>-deleted = abap_true.
  ENDLOOP.
ENDMETHOD.
```

Mark, do not remove. The saver needs to know a delete is pending. Removing it from the buffer means
the row survives on the database.

### `FOR LOCK`

```abap
METHOD lock.
  LOOP AT keys INTO DATA(key).
    CALL FUNCTION 'ENQUEUE_EZTRAVEL'
      EXPORTING  travel_uuid    = key-TravelUUID
                 _scope         = '1'          " keep until COMMIT/DEQUEUE by us
      EXCEPTIONS foreign_lock   = 1
                 system_failure = 2
                 OTHERS         = 3.
    IF sy-subrc <> 0.
      APPEND VALUE #( %tky        = key-%tky
                      %fail-cause = if_abap_behv=>cause-locked ) TO failed-travel.
      APPEND VALUE #( %tky = key-%tky
                      %msg = new_message( id = 'ZTRAVEL_MSG' number = '070'
                                          severity = if_abap_behv_message=>severity-error
                                          v1 = sy-msgv1 ) ) TO reported-travel.
    ENDIF.
  ENDLOOP.
ENDMETHOD.
```

Prerequisite: a lock object `EZTRAVEL` created in SE11 over table `ZTRAVEL`.

### Read by association (rba)

```abap
METHOD rba_Booking.

  DATA(lo_buffer) = lcl_buffer=>get_instance( ).
  lo_buffer->load_bookings_for_travels( VALUE #( FOR k IN keys_rba ( k-TravelUUID ) ) ).

  LOOP AT keys_rba INTO DATA(key).
    LOOP AT lo_buffer->mt_bookings INTO DATA(ls_booking)
         WHERE booking-travel_uuid = key-TravelUUID
           AND deleted = abap_false.

      " the LINK table: which parent maps to which child
      APPEND VALUE #( source-%tky-TravelUUID  = key-TravelUUID
                      target-%tky-BookingUUID = ls_booking-booking-booking_uuid )
             TO association_links.

      " the data, only if the consumer asked for it
      IF result_requested = abap_true.
        APPEND CORRESPONDING #( ls_booking-booking MAPPING TO ENTITY ) TO result
               ASSIGNING FIELD-SYMBOL(<res>).
        <res>-%tky-BookingUUID = ls_booking-booking-booking_uuid.
      ENDIF.
    ENDLOOP.
  ENDLOOP.
ENDMETHOD.
```

Two outputs:

- `association_links` — **always** filled. The parent→child mapping.
- `result` — only when `result_requested = abap_true`. The child data.

The consumer may want only the links (e.g. to count children). Honouring `result_requested` is part
of the RAP BO contract.

### Create by association (cba)

```abap
METHOD cba_Booking.

  DATA(lo_buffer) = lcl_buffer=>get_instance( ).

  LOOP AT entities_cba INTO DATA(entity_cba).

    " entity_cba-%tky identifies the PARENT
    " entity_cba-%target holds the children to create
    LOOP AT entity_cba-%target INTO DATA(target).

      TRY.
          DATA(lv_uuid) = cl_system_uuid=>create_uuid_x16_static( ).
        CATCH cx_uuid_error.
          APPEND VALUE #( %cid = target-%cid ) TO failed-booking.
          CONTINUE.
      ENDTRY.

      DATA(ls_booking) = CORRESPONDING zbooking( target MAPPING FROM ENTITY ).
      ls_booking-booking_uuid = lv_uuid.
      ls_booking-travel_uuid  = entity_cba-TravelUUID.    " link to the parent

      INSERT VALUE #( booking = ls_booking created = abap_true )
             INTO TABLE lo_buffer->mt_bookings.

      APPEND VALUE #( %cid        = target-%cid
                      BookingUUID = lv_uuid ) TO mapped-booking.
    ENDLOOP.
  ENDLOOP.
ENDMETHOD.
```

---

## 15.6 The saver class

```abap
CLASS lsc_ZR_TravelTP_U DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS finalize          REDEFINITION.
    METHODS check_before_save REDEFINITION.
    METHODS save              REDEFINITION.
    METHODS cleanup           REDEFINITION.
    METHODS cleanup_finalize  REDEFINITION.
ENDCLASS.

CLASS lsc_ZR_TravelTP_U IMPLEMENTATION.

  METHOD finalize.
    " last chance to adjust data. Runs BEFORE check_before_save.
    " e.g. recalculate a total across the whole buffer.
  ENDMETHOD.

  METHOD check_before_save.
    DATA(lo_buffer) = lcl_buffer=>get_instance( ).
    LOOP AT lo_buffer->mt_travels INTO DATA(ls)
         WHERE deleted = abap_false
           AND ( created = abap_true OR changed = abap_true ).
      IF ls-travel-begin_date > ls-travel-end_date.
        APPEND VALUE #( %tky-TravelUUID = ls-travel-travel_uuid ) TO failed-travel.
        APPEND VALUE #( %tky-TravelUUID = ls-travel-travel_uuid
                        %msg = new_message( id = 'ZTRAVEL_MSG' number = '001'
                                            severity = if_abap_behv_message=>severity-error ) )
               TO reported-travel.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD save.
    " LATE SAVE PHASE - the only place database changes are allowed
    DATA(lo_buffer) = lcl_buffer=>get_instance( ).

    DATA: lt_insert TYPE STANDARD TABLE OF ztravel,
          lt_update TYPE STANDARD TABLE OF ztravel,
          lt_delete TYPE STANDARD TABLE OF ztravel.

    LOOP AT lo_buffer->mt_travels INTO DATA(ls).
      CASE abap_true.
        WHEN ls-deleted. APPEND ls-travel TO lt_delete.
        WHEN ls-created. APPEND ls-travel TO lt_insert.
        WHEN ls-changed. APPEND ls-travel TO lt_update.
      ENDCASE.
    ENDLOOP.

    IF lt_insert IS NOT INITIAL.
      INSERT ztravel FROM TABLE @lt_insert.
    ENDIF.
    IF lt_update IS NOT INITIAL.
      UPDATE ztravel FROM TABLE @lt_update.
    ENDIF.
    IF lt_delete IS NOT INITIAL.
      DELETE ztravel FROM TABLE @lt_delete.
      " cascade: the children of a deleted parent
      DELETE FROM zbooking
        FOR ALL ENTRIES IN @lt_delete
        WHERE travel_uuid = @lt_delete-travel_uuid.
    ENDIF.

    " ... same for bookings ...

    " Release the locks
    LOOP AT lo_buffer->mt_travels INTO ls.
      CALL FUNCTION 'DEQUEUE_EZTRAVEL'
        EXPORTING travel_uuid = ls-travel-travel_uuid.
    ENDLOOP.
  ENDMETHOD.

  METHOD cleanup.
    lcl_buffer=>get_instance( )->clear( ).
  ENDMETHOD.

  METHOD cleanup_finalize.
    " called when finalize or check_before_save failed
    lcl_buffer=>get_instance( )->clear( ).
  ENDMETHOD.

ENDCLASS.
```

### Notes on `save`

- **This is the only place `INSERT`/`UPDATE`/`DELETE` on the database is legal.** In any other
  phase it breaks the SAP LUW (Chapter 17, §17.6).
- **No `COMMIT WORK`.** The framework commits after `save` returns.
- **Set-based writes.** `INSERT ... FROM TABLE` once, not one `INSERT` per row.
- **Cascade deletes explicitly.** The managed runtime does this for you; unmanaged does not.
- **Do not raise exceptions.** A failure here is after the point of no return. If your save can
  genuinely fail, inherit from `CL_ABAP_BEHAVIOR_SAVER_FAILED` instead.

---

## 15.7 Wrapping an existing BAPI

The most common real reason for unmanaged. The shape:

```abap
METHOD create.
  " Interaction phase: buffer only. Do NOT call the BAPI here.
  LOOP AT entities INTO DATA(entity).
    lcl_buffer=>get_instance( )->add_pending_create( entity ).
    APPEND VALUE #( %cid = entity-%cid ) TO mapped-travel.   " key comes later
  ENDLOOP.
ENDMETHOD.

METHOD check_before_save.
  " Early save: run the BAPI in TEST MODE to surface errors while we can still go back.
  LOOP AT lcl_buffer=>get_instance( )->mt_pending INTO DATA(ls).
    CALL FUNCTION 'BAPI_TRAVEL_CREATE'
      EXPORTING  travel_data = ls-data
                 testrun     = abap_true
      TABLES     return      = DATA(lt_return).
    LOOP AT lt_return INTO DATA(ls_ret) WHERE type CA 'EAX'.
      APPEND VALUE #( %cid = ls-cid ) TO failed-travel.
      APPEND VALUE #( %cid = ls-cid
                      %msg = new_message( id = ls_ret-id number = ls_ret-number
                                          severity = if_abap_behv_message=>severity-error
                                          v1 = ls_ret-message_v1 ) ) TO reported-travel.
    ENDLOOP.
  ENDLOOP.
ENDMETHOD.

METHOD save.
  " Late save: the real call. No COMMIT WORK - RAP owns the commit.
  LOOP AT lcl_buffer=>get_instance( )->mt_pending INTO DATA(ls).
    CALL FUNCTION 'BAPI_TRAVEL_CREATE'
      EXPORTING  travel_data = ls-data
                 testrun     = abap_false
      IMPORTING  travelid    = DATA(lv_id)
      TABLES     return      = DATA(lt_return).
    " do NOT call BAPI_TRANSACTION_COMMIT
  ENDLOOP.
ENDMETHOD.
```

### The three rules for BAPI wrapping

1. **Run the BAPI in test mode during `check_before_save`.** That is your only chance to reject
   before the point of no return. Skipping this means a BAPI error in `save` becomes a dump.
2. **Never call `BAPI_TRANSACTION_COMMIT`.** RAP commits. A nested commit corrupts the LUW.
3. **If the BAPI can still fail in `save` despite the test run**, use
   `CL_ABAP_BEHAVIOR_SAVER_FAILED` so you can report it, and expect `sy-subrc = 8` on the
   consumer's `COMMIT ENTITIES`.

If the BAPI assigns the key (late numbering), see Chapter 19 — `adjust_numbers` plus `CONVERT KEY`.

---

## 15.8 Unmanaged vs managed — the honest comparison

| | Managed | Unmanaged |
|---|---|---|
| Lines of ABAP for plain CRUD on 2 entities | ~0 | ~600–900 |
| Buffer | Framework | You |
| Locking | `lock master` | `FOR LOCK` + lock object |
| ETag | `etag master F` | Manual, in read + save |
| Draft | `with draft` + a table | Substantial extra work |
| Key generation | `numbering : managed` | `cl_system_uuid` in `create` |
| Cascade delete | Automatic | Manual |
| Admin fields | `@Semantics` + `readonly` | Manual, in create and update |
| Field-selective update | Automatic | One `IF %control` block per field |
| Where bugs live | Your validations | Your buffer |

**Unmanaged is roughly an order of magnitude more code for the same CRUD.** That is the honest
number, and it is why the decision in Chapter 01, §1.3 matters so much.

---

## 15.9 Unmanaged pitfalls

| Pitfall | Consequence | Fix |
|---|---|---|
| Buffer not cleared in `cleanup` / `cleanup_finalize` | The next transaction sees stale data; phantom saves | Clear in both |
| `load` overwrites buffered instances | The user's changes disappear | Load only what is missing |
| Ignoring `%control` in `update` | Fields the consumer never sent are overwritten with initial values | One `IF %control` block per field |
| `mapped` not filled in `create` | The consumer cannot address the new instance; the UI cannot navigate to it | Fill `mapped` with `%cid` → key |
| `DELETE` removes from the buffer instead of marking | The row survives on the database | Set a `deleted` flag |
| Database writes outside `save` | LUW broken; partial commits | Only in `save` |
| `COMMIT WORK` anywhere | Runtime error / corrupted LUW | Remove |
| Locks never released | Users blocked until the lock expires | `DEQUEUE` in `save` (and rely on `_scope = '1'` semantics) |
| Children not deleted with the parent | Orphan rows | Cascade explicitly in `save` |
| `association_links` not filled in rba | Navigation silently returns nothing | Always fill it |
| `result_requested` ignored | Unnecessary reads | Honour it |
| Errors first detected in `save` | Dump after the point of no return | Move the check to `check_before_save` |

---

## 15.10 Interview answer

> **"When would you build an unmanaged RAP business object?"**
>
> When there is existing **transactional logic** that must be reused rather than reimplemented — an
> existing buffer, existing locking, existing update-task modules, reads that have to go through
> existing function modules. Typically a brownfield wrap of a module that has fifteen years of
> behaviour in it.
>
> Not because the tables already exist. `persistent table` accepts any DDIC table, so existing data
> is perfectly fine for a managed BO. That is the mistake I would push back on in a design review,
> because unmanaged is roughly an order of magnitude more code for the same CRUD: your own
> transactional buffer, `FOR READ`, `FOR MODIFY` create/update/delete, `FOR LOCK`, read- and
> create-by-association, plus a saver class — and you also take over ETag maintenance, cascading
> delete, admin fields, key generation, and the field-selective `%control` handling, which alone is
> one `IF` block per field per entity.
>
> And if only the **save** is special — persisting through a BAPI, or an API with late numbering —
> the right answer is `managed with unmanaged save`, not a full unmanaged BO. You keep the managed
> buffer, locking, ETag and draft, and only take over persistence.
>
> The two failure modes I would watch for in unmanaged code are the buffer not being cleared in both
> `cleanup` and `cleanup_finalize`, and `%control` being ignored on update, which silently wipes
> fields the user never touched.

## 15.11 Production considerations

- **Validate every example against your release before adopting it** — see the notice at the top of
  this chapter. Generate signatures with `Ctrl + 1`.
- **Start from the ABAP Flight Reference Scenario** (`/DMO/` packages). It ships an activated,
  working unmanaged BO for this exact model.
- **The buffer is where the bugs live.** Clear it in `cleanup` **and** `cleanup_finalize`, and never
  let a load overwrite a buffered instance.
- **Respect `%control` on update**, or users lose data they never edited.
- **Fill `mapped` on create**, or the consumer cannot address the new instance.
- **Cascade deletes explicitly.** The managed runtime does it for you; unmanaged does not.
- **Detect failures in `check_before_save`, not in `save`.** A test-mode BAPI call there is the
  difference between a clean rejection and a dump after the point of no return.
- **Budget honestly.** Plan unmanaged as a multiple of the managed effort, including test effort.

---

[< Feature Control & Authorization](14-Feature-Control-and-Authorization.md) | [Index](00-README.md) | [Next: Managed with Unmanaged Save >](16-Managed-With-Unmanaged-Save-and-Additional-Save.md)
