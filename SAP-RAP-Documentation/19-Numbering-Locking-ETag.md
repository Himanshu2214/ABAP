# Chapter 19 — Numbering, Locking and ETag

[< EML Reference](18-EML-Reference.md) | [Index](00-README.md) | [Next: Messages, Troubleshooting & Cheat Sheet >](20-Messages-Troubleshooting-and-Cheat-Sheet.md)

---

# Part 1 — Numbering

## 19.1 The two dimensions

Key assignment in RAP is described by two independent questions:

| **When** | |
|---|---|
| **Early numbering** | The final key is assigned during the create operation, in the **interaction phase** |
| **Late numbering** | The final key is assigned during the **save sequence**, in `adjust_numbers` |

| **By whom** | |
|---|---|
| **External numbering** | The **consumer** supplies the key |
| **Internal numbering** | The **provider** (framework or your code) supplies the key |

Combining them gives the scenarios below. **The default, when nothing is declared, is external
numbering** — the consumer must send a key.

---

## 19.2 The five numbering scenarios

### A) External early numbering (the default)

The consumer sends the key on create.

```abap
define behavior for ZR_MaterialTP alias Material
persistent table zmaterial
{
  create;
  field ( mandatory : create, readonly : update ) MaterialId;
}
```

- The consumer must guarantee uniqueness. A duplicate is rejected at save.
- Key fields should be `mandatory : create, readonly : update` — writable when creating,
  frozen afterwards.
- Use when an external system or a business rule dictates the number.

### B) Managed internal early numbering (UUID) — **the recommended default**

```abap
field ( numbering : managed, readonly ) TravelUUID;
```

- The framework generates a UUID at create time.
- Prerequisite: the key is a 16-byte field (`sysuuid_x16` / `RAW(16)`).
- `readonly` makes it fully internal. **Omitting `readonly`** gives *optional external numbering*:
  the framework fills it only if the consumer sends an initial value.
- Zero code.

This is why Chapter 02 recommends a UUID technical key: it makes numbering a one-word declaration.

### C) Unmanaged internal early numbering

You assign the key in the interaction phase, in a `FOR NUMBERING` handler.

```abap
" BDEF
define behavior for ZR_TravelTP alias Travel
persistent table ztravel
early numbering
{
  create;
  field ( readonly ) TravelId;
  association _Booking { create; }
}
```

```abap
METHODS earlynumbering_create FOR NUMBERING
  IMPORTING entities FOR CREATE Travel.

METHODS earlynumbering_cba_Booking FOR NUMBERING
  IMPORTING entities FOR CREATE Travel\_Booking.
```

```abap
METHOD earlynumbering_create.

  " only instances without a key
  DATA(entities_wo_id) = entities.
  DELETE entities_wo_id WHERE TravelId IS NOT INITIAL.
  CHECK entities_wo_id IS NOT INITIAL.

  TRY.
      cl_numberrange_runtime=>number_get(
        EXPORTING nr_range_nr = '01'
                  object      = 'ZTRAVELID'
                  quantity    = CONV #( lines( entities_wo_id ) )
        IMPORTING number              = DATA(number_range_key)
                  returned_quantity   = DATA(returned_quantity) ).
    CATCH cx_number_ranges INTO DATA(lx).
      LOOP AT entities_wo_id INTO DATA(e).
        APPEND VALUE #( %cid = e-%cid %key = e-%key ) TO failed-travel.
        APPEND VALUE #( %cid = e-%cid %key = e-%key %msg = lx ) TO reported-travel.
      ENDLOOP.
      RETURN.
  ENDTRY.

  DATA(next) = number_range_key - returned_quantity.
  LOOP AT entities_wo_id INTO DATA(entity).
    next += 1.
    APPEND VALUE #( %cid     = entity-%cid
                    TravelId = next ) TO mapped-travel.
  ENDLOOP.

ENDMETHOD.
```

**The key is reported through `mapped`, not written back into `entities`.** That is the contract of
`FOR NUMBERING`.

For children, the pattern is the same but the numbering is usually per-parent:

```abap
METHOD earlynumbering_cba_Booking.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel BY \_Booking
      FROM CORRESPONDING #( entities )
    LINK DATA(existing_links).

  LOOP AT entities INTO DATA(entity).

    " highest existing BookingId for this travel
    DATA(max_id) = REDUCE /dmo/booking_id(
      INIT m = CONV /dmo/booking_id( '0000' )
      FOR link IN existing_links WHERE ( source-%tky = entity-%tky )
      NEXT m = COND #( WHEN link-target-BookingId > m THEN link-target-BookingId ELSE m ) ).

    LOOP AT entity-%target INTO DATA(target).
      max_id += 10.
      APPEND VALUE #( %cid      = target-%cid
                      BookingId = max_id ) TO mapped-booking.
    ENDLOOP.
  ENDLOOP.
ENDMETHOD.
```

### D) Late numbering

The key only exists in the late save phase.

```abap
define behavior for ZR_TravelTP alias Travel
persistent table ztravel
late numbering
{ ... }
```

```abap
METHODS adjust_numbers REDEFINITION.      " in the saver class
```

```abap
METHOD adjust_numbers.
  LOOP AT mapped-travel ASSIGNING FIELD-SYMBOL(<travel>).
    " <travel>-%pid is the preliminary id
    <travel>-TravelId = zcl_travel_numbers=>get_next( ).
  ENDLOOP.
ENDMETHOD.
```

When to use it:

- The number must be **gap-free** (legal requirement for some document types). Drawing it at save
  time minimises gaps.
- The number comes from a system that only issues it at commit time.
- You are wrapping an API that itself uses late numbering.

Costs:

- Draft tables need an extra key field `draftuuid` (`RAW(16)`).
- The consumer receives `%pid` from `mapped`, not a real key, until after the commit.
- Resolving `%pid` requires `CONVERT KEY`, which is only legal inside `save_modified`.

### E) Optional external numbering

```abap
field ( numbering : managed ) TravelUUID;     " note: NO 'readonly'
```

The framework fills the key **only if** the consumer leaves it initial. Useful for a BO consumed both
by a UI (no key) and by a migration program (keys supplied).

---

## 19.3 `CONVERT KEY` — resolving a preliminary id

Only valid inside `save_modified`.

```abap
METHOD save_modified.

  LOOP AT zbp_r_traveltp=>mapped_purchase_requisition-purchaserequisition
       ASSIGNING FIELD-SYMBOL(<pr>).

    CONVERT KEY OF i_purchaserequisitiontp
      FROM <pr>-%pid
      TO   DATA(ls_pr_key).

    <pr>-purchaserequisition = ls_pr_key-purchaserequisition.
  ENDLOOP.

  " now write the real number into our own table
  ...
ENDMETHOD.
```

The full worked example — including the bridge variable in the global ABP class — is in
Chapter 16, §16.8. This is the single most common reason to choose `managed with unmanaged save`.

---

## 19.4 Choosing a numbering strategy

| Requirement | Strategy |
|---|---|
| New app, no external constraint | **B** — `field ( numbering : managed, readonly )` on a UUID key |
| A human-readable document number is also needed | **B** for the technical key + a **determination `on save`** for the business number (Chapter 10, §10.3) |
| The number must be gap-free by law | **D** — late numbering |
| An external system supplies the number | **A** — external |
| The number comes from a released API that uses late numbering | **D** + `managed with unmanaged save` + `CONVERT KEY` |
| Both UI and migration must create instances | **E** — optional external |
| Child items numbered 10, 20, 30 within a parent | **C** — `FOR NUMBERING` on the cba |

> **Do not draw a number range number in an `on modify` determination.** Every discarded draft burns
> a number. Use `on save`.

---

# Part 2 — Locking

## 19.5 Pessimistic locking

```abap
define behavior for ZR_TravelTP alias Travel
lock master                       " the root owns the lock

define behavior for ZR_BookingTP alias Booking
lock dependent by _Travel         " children delegate to the parent
```

| Declaration | Meaning |
|---|---|
| `lock master` | Managed: the framework acquires and releases the lock automatically |
| `lock master unmanaged` | You implement `FOR LOCK` yourself |
| `lock dependent by _Assoc` | The lock is the parent's |
| *(nothing)* | Not permitted under `strict ( 2 )` for modifiable entities |

### What the framework does

Before the first modification of an instance, a lock entry is written to the **global lock table**
(the same infrastructure as `ENQUEUE`). A second request for the same instance is rejected. The entry
is removed on commit, rollback, or session end.

The lock covers the **whole composition tree**: locking a Travel locks its Bookings, because they
are `lock dependent by _Travel`.

### Per-operation exemption

```abap
action ( lock : none ) printTravel;
```
For a read-only action that should not block other users.

### Manual locking with `SET LOCKS`

```abap
SET LOCKS OF zr_traveltp
  ENTITY Travel
  FROM VALUE #( ( %tky-TravelUUID = lv_uuid %tky-%is_draft = if_abap_behv=>mk-off ) )
  FAILED DATA(lock_failed).
```
Use it to reserve instances before expensive preparation, so you fail fast instead of after doing
the work.

### Unmanaged locking

```abap
METHOD lock.
  LOOP AT keys INTO DATA(key).
    CALL FUNCTION 'ENQUEUE_EZTRAVEL'
      EXPORTING  travel_uuid  = key-TravelUUID
                 _scope       = '1'
      EXCEPTIONS foreign_lock = 1 OTHERS = 2.
    IF sy-subrc <> 0.
      APPEND VALUE #( %tky = key-%tky %fail-cause = if_abap_behv=>cause-locked )
             TO failed-travel.
    ENDIF.
  ENDLOOP.
ENDMETHOD.
```
Requires a lock object (SE11 → Lock Object `EZTRAVEL` over `ZTRAVEL`).
Release with `DEQUEUE_EZTRAVEL` in `save`.

---

## 19.6 Draft locking — the two phases

Covered in detail in Chapter 11, §11.5. In summary:

| Phase | Trigger | Behaviour |
|---|---|---|
| **Exclusive lock** | `Edit` / `Create` | Nobody else can edit. Survives the session ending. Expires after a configured timeout |
| **Optimistic lock** | Exclusive lock expired | Others may edit. On `Resume`, the draft's **total ETag** is compared with the active instance's. Mismatch → the draft is declared outdated |

This is why `total etag` is mandatory for draft-enabled BOs.

---

# Part 3 — ETag (optimistic concurrency)

## 19.7 What an ETag does

```
User A reads Travel 42          -> ETag = 2026-09-16T10:00:00
User B reads Travel 42          -> ETag = 2026-09-16T10:00:00
User B updates and saves        -> ETag becomes 2026-09-16T10:05:00
User A updates and saves        -> sends If-Match: 2026-09-16T10:00:00
                                -> MISMATCH -> rejected
                                   "Data has been changed by another user"
```

Without an ETag, User A's save silently overwrites User B's change. This is the *lost update*
problem, and it is the single most common data-integrity defect in hand-written CRUD applications.

## 19.8 Declaring it

```abap
define behavior for ZR_TravelTP alias Travel
lock master
total etag LastChangedAt              " draft resumability
etag master LocalLastChangedAt        " optimistic concurrency
{
  field ( readonly ) LastChangedAt, LocalLastChangedAt;
}

define behavior for ZR_BookingTP alias Booking
lock dependent by _Travel
etag master LastChangedAt             " children may have their own
```

| Declaration | Meaning |
|---|---|
| `etag master <field>` | This entity has its own ETag field |
| `etag dependent by _Assoc` | The ETag is taken from the parent |
| `total etag <field>` | Draft-only. Must come **after** `lock master`. Use a **different** field |

### Prerequisites

1. Field type `utclong`, `timestamp` or `timestampl`.
2. CDS annotation:
   - `@Semantics.systemDateTime.localInstanceLastChangedAt: true` for `etag master`
   - `@Semantics.systemDateTime.lastChangedAt: true` for `total etag`
3. `field ( readonly )` in the BDEF.

With all three in place, the **managed runtime maintains the ETag automatically**. No code.

### In the projection BDEF

```abap
define behavior for ZC_TravelTP alias Travel
use etag                              " <- without this, no optimistic locking in this service
{ ... }
```

Forgetting `use etag` silently disables the protection for that service.

## 19.9 Lock vs ETag — they are not alternatives

| | Lock (pessimistic) | ETag (optimistic) |
|---|---|---|
| Acquired | Before editing | Nothing is acquired |
| Checked | At acquisition | At save |
| Blocks other users | Yes | No |
| Protects against | Two users starting an edit | A stale overwrite |
| Fails when | Someone else is editing | Someone else already saved |
| Survives session end | Yes (draft: until timeout) | N/A |
| Needed in RAP | Yes | Yes |

**Use both.** A lock stops concurrent editing sessions; an ETag stops a stale write that slips
through when the lock has expired (the draft optimistic phase) or when there is no draft at all.

## 19.10 Unmanaged ETag handling

In an unmanaged BO the framework does nothing for you:

```abap
METHOD update.
  LOOP AT entities INTO DATA(entity).
    " 1. Compare the incoming ETag with what is stored
    SELECT SINGLE last_changed_at FROM ztravel
      WHERE travel_uuid = @entity-TravelUUID
      INTO @DATA(current_etag).

    IF entity-%control-LastChangedAt = if_abap_behv=>mk-on
       AND entity-LastChangedAt <> current_etag.
      APPEND VALUE #( %tky        = entity-%tky
                      %fail-cause = if_abap_behv=>cause-conflict ) TO failed-travel.
      CONTINUE.
    ENDIF.

    " 2. Apply the change and set a NEW ETag
    GET TIME STAMP FIELD DATA(new_etag).
    " ... write to the buffer with last_changed_at = new_etag ...
  ENDLOOP.
ENDMETHOD.
```

One more item on the list of what unmanaged costs you.

---

## 19.11 Troubleshooting

| Symptom | Cause |
|---|---|
| *"Data has been changed by another user"* on the first save | Stale `$metadata` in the browser, or the ETag field is not `readonly` so the client sends its own value |
| ETag has no effect | `use etag` missing in the projection BDEF |
| BDEF activation: *"ETag field must be of type timestamp"* | Wrong data element; use `abp_locinst_lastchange_tstmpl` |
| BDEF activation: *"Total ETag is missing"* | `with draft;` declared without `total etag <field>` |
| *"total etag must be specified after lock master"* | Order of the clauses |
| *"Object is locked by user X"* and X is the same user | An orphaned draft from an earlier session holds the exclusive lock. Discard the draft, or wait for the timeout |
| Duplicate key on save with external numbering | The consumer supplied a key that already exists — expected behaviour |
| Number range gaps | The number is drawn `on modify` instead of `on save` |
| `%pid` in `mapped` instead of a real key | Late numbering — resolve with `CONVERT KEY` in `save_modified` |
| `FOR NUMBERING` never called | `early numbering` missing in the BDEF |
| `adjust_numbers` never called | `late numbering` missing in the BDEF |

---

## 19.12 Interview answer

> **"How did you handle numbering, locking and ETags?"**
>
> Numbering is described by two independent questions: **when** the key is assigned — early, in the
> interaction phase, or late, in the save sequence — and **by whom** — the consumer, externally, or
> the provider, internally. The default with no declaration is external.
>
> I use managed internal early numbering for the technical key: a UUID with
> `field ( numbering : managed, readonly )`, which the framework generates with no code. The
> human-readable document number is separate, drawn from a number range in a determination declared
> **`on save`**, so discarded drafts do not consume numbers. Late numbering I would use only where
> the number must be gap-free by law, or where a called API itself uses late numbering — and then
> resolving the preliminary ID needs `CONVERT KEY` in `save_modified`, which forces
> `managed with unmanaged save`.
>
> Locking and ETags solve different problems and I use both. The **lock** is pessimistic —
> `lock master` on the root, `lock dependent by` on the children — and stops a second user starting
> an edit. The **ETag** is optimistic — `etag master LocalLastChangedAt` plus the matching
> `@Semantics` annotation and `readonly`, so the managed runtime maintains it — and stops a stale
> overwrite at the moment of saving. Plus `use etag` in the projection BDEF, without which the
> protection is silently off for that service.
>
> With draft there is a third: `total etag`, on a **different** field, which is what decides whether
> a draft is still resumable after the exclusive lock has expired and someone else may have changed
> the active instance.

## 19.13 Production considerations

- **Number range intervals are not transported.** Maintain them in `SNRO` per system and per client;
  a missing document number in QA is nearly always this.
- **Draw numbers `on save`.** Gaps from discarded drafts are an audit finding in regulated
  scenarios, not a cosmetic issue.
- **Number ranges commit on a secondary connection**, which is why they are legal in an `on save`
  determination — but handle `cx_number_ranges` and report it, or the save fails with no message.
- **Review the draft exclusive-lock timeout** against real editing times.
- **Use `( lock : none )` on read-only actions** so they do not block other users.
- **`SET LOCKS` before expensive preparation** in a job, so you fail fast.
- **Test the ETag conflict over HTTP** — the comparison happens in the OData layer, not in the
  buffer, so EML will not exercise it.
- **Lock table sizing matters for mass processing.** Every instance holds an entry until commit;
  chunk accordingly.

---

[< EML Reference](18-EML-Reference.md) | [Index](00-README.md) | [Next: Messages, Troubleshooting & Cheat Sheet >](20-Messages-Troubleshooting-and-Cheat-Sheet.md)
