# Chapter 11 — Draft Handling

[< CRUD Walkthrough](10-CRUD-Managed-Walkthrough.md) | [Index](00-README.md) | [Next: Validations & Determinations >](12-Validations-and-Determinations.md)

---

## 11.1 What a draft is

A **draft** is a second, parallel copy of an instance, stored in its own table, that the user edits
before committing. It is the RAP answer to "the user filled in half a form and their laptop died".

```
Active instance                   Draft instance
ZTRAVEL                           ZTRAVEL_D
TravelUUID = ABC                  TravelUUID = ABC
OverallStatus = 'O'               OverallStatus = 'O'
TotalPrice = 100                  TotalPrice = 250     <- being edited
IsActiveEntity = true             IsActiveEntity = false
```

Both rows have the **same key**. They are distinguished by `IsActiveEntity` — which is why the RAP
transactional key is `%tky` (= `%key` + `%is_draft`), not `%key`.

### What draft buys you

| Feature | Without draft | With draft |
|---|---|---|
| Unsaved work survives a browser crash | No | Yes |
| The user can leave and come back | No | Yes |
| Validation errors shown while editing | Only on save | Continuously, via `Prepare` |
| Two users editing the same object | Both can, last one wins | The second is told it is locked |
| "Cancel" discards changes cleanly | Needs UI-side state | Built in |
| Number of database tables | 1 per entity | 2 per entity |
| Locking complexity | Simple | Exclusive lock → optimistic lock transition |

### When draft is the *wrong* choice

- **APIs and background jobs.** Drafts are a UI concept. A machine consumer creates active
  instances directly.
- **High-frequency, single-field updates** (e.g. a "mark as read" toggle). The draft round trips
  cost more than the operation.
- **Objects with a very short edit lifetime**, where the user always completes the form in one go
  and a lost form is not expensive.
- **When you cannot afford the second table** — e.g. an entity with 200 columns and 500 million rows.

For a classic Fiori List Report / Object Page maintenance app: **use draft**. It is what the
floorplan expects, and the non-draft alternative ("direct edit") has a noticeably worse UX.

---

## 11.2 Everything you must declare

### 1. Draft tables (Chapter 02, §2.5)

One per draft-enabled entity. **Generate them with the ADT quick fix** (`Ctrl + 1` on the CDS
entity) rather than typing them — the required structure is release-dependent. Review the generated
result against the criteria in Chapter 02, §2.5.

### 2. In the base BDEF

```abap
managed implementation in class ZBP_R_TravelTP unique;
strict ( 2 );
with draft;                                  " <- 1. enable draft for the BO

define behavior for ZR_TravelTP alias Travel
persistent table ztravel
draft table ztravel_d                        " <- 2. the draft table
lock master
total etag LastChangedAt                     " <- 3. mandatory for draft
authorization master ( instance )
etag master LocalLastChangedAt
{
  ...
  association _Booking { create; with draft; }   " <- 4. every association

  draft action Activate optimized;               " <- 5. the four draft actions
  draft action Discard;
  draft action Edit;
  draft action Resume;
  draft determine action Prepare                 " <- 6. validations to run early
  {
    validation validateDates;
    validation validateCustomer;
    validation validateAgency;
  }
}

define behavior for ZR_BookingTP alias Booking
persistent table zbooking
draft table zbooking_d                       " <- child needs its own draft table
lock dependent by _Travel
authorization dependent by _Travel
etag master LastChangedAt
{
  ...
  association _Travel { with draft; }        " <- and its parent association
}
```

Note: the **child does not declare draft actions**. Draft actions live on the root only — a draft is
created for the whole composition tree.

### 3. In the projection BDEF

```abap
projection;
strict ( 2 );
use draft;                                   " <- expose draft in this service

define behavior for ZC_TravelTP alias Travel
use etag
{
  use create;
  use update;
  use delete;
  use association _Booking { create; with draft; }

  use action Activate;                       " <- all five must be exposed
  use action Discard;
  use action Edit;
  use action Resume;
  use action Prepare;
}
```

Missing any one of these five gives a subtly broken app: e.g. without `use action Prepare;`
validation messages do not appear until Save.

---

## 11.3 The draft lifecycle

```
                     +-------------------+
                     |  Active instance  |
                     +-------------------+
                              |
              user presses "Edit"  -> draft action Edit
                              v
   +---------------------------------------------------------+
   |  Draft created (copy of active)                          |
   |  Active instance EXCLUSIVELY LOCKED                      |
   |  Draft auto-saved on every field change (PATCH)          |
   +---------------------------------------------------------+
        |                  |                    |
        | Save             | Cancel             | browser closed
        v                  v                    |
 draft action         draft action              |
 Activate             Discard                   |
        |                  |                    v
        |                  |     exclusive lock expires after timeout,
        |                  |     OPTIMISTIC LOCK phase begins
        |                  |                    |
        |                  |          user returns -> draft action Resume
        |                  |                    |
        |                  |     total etag of draft == total etag of active?
        |                  |          yes -> resume    no -> "draft is outdated"
        v                  v
 draft copied to      draft deleted,
 active, draft        lock released
 deleted, lock
 released
```

### The four draft actions

| Action | When | What it does |
|---|---|---|
| `Edit` | User presses **Edit** on an active instance | Copies active → draft, acquires the exclusive lock |
| `Activate` | User presses **Save** | Runs `Prepare`, then copies draft → active, deletes the draft, releases the lock |
| `Discard` | User presses **Cancel** | Deletes the draft, releases the lock. Active is untouched |
| `Resume` | User reopens an existing draft | Re-acquires the lock, checks total ETag, continues |

### `draft action Activate optimized;`

The `optimized` addition tells the framework it may skip re-running validations at activation
**because `Prepare` already ran them and the data has not changed since**. Measurably faster on
large documents.

Conditions:

- every validation relevant to activation is listed in `draft determine action Prepare`
- your validations do not have side effects (they must not change data — which they must not anyway)

Use it. The only reason not to is a legacy BDEF whose `Prepare` list is incomplete.

### `draft determine action Prepare`

```abap
draft determine action Prepare
{
  validation validateDates;
  validation validateCustomer;
  validation validateAgency;
  determination calculateTotalPrice;     " determinations may be listed too
}
```

When it runs:

- automatically **before** `Activate`
- whenever the UI calls it — Fiori Elements calls `Prepare` after edits, so messages appear inline
- explicitly, from EML

**Anything not listed here only runs at save time.** If a user complains "the app only tells me
about the error when I press Save", the fix is almost always "add the validation to `Prepare`".

Pair it with a side effect so the message list refreshes:
```abap
side effects
{
  determine action Prepare affects messages;
}
```

---

## 11.4 `%tky` — the single most important draft concept

```abap
" WRONG in a draft-enabled BO
READ ENTITIES OF zr_traveltp IN LOCAL MODE
  ENTITY Travel FIELDS ( TotalPrice )
  WITH VALUE #( ( TravelUUID = key-TravelUUID ) )   " <- which one? active or draft?
  RESULT DATA(travels).

" RIGHT
READ ENTITIES OF zr_traveltp IN LOCAL MODE
  ENTITY Travel FIELDS ( TotalPrice )
  WITH CORRESPONDING #( keys )                      " keys carries %tky
  RESULT DATA(travels).
```

`%tky` is a structure:

```
%tky = ( TravelUUID = ABC..., %is_draft = if_abap_behv=>mk-on )
```

| `%is_draft` value | Means |
|---|---|
| `if_abap_behv=>mk-on` (`'01'`) | The draft instance |
| `if_abap_behv=>mk-off` (`'00'`) | The active instance |

`strict ( 2 )` makes using `%key` in a draft-enabled BO a **syntax error** in most contexts, which is
exactly what you want. Under looser modes it compiles and then reads the wrong row at runtime —
a bug that looks like "my determination doesn't see the data".

**Rule: in a draft-enabled BO, always use `%tky`. Never `%key`.**

When you build a key table by hand:
```abap
DATA(keys_for_draft) = VALUE ztravel_tky_tab(
  ( TravelUUID = lv_uuid  %is_draft = if_abap_behv=>mk-on ) ).
```

---

## 11.5 Locking with draft — the two phases

This is the mechanism people find surprising, so it is worth stating precisely.

### Phase 1 — exclusive lock

From the moment `Edit` (or `Create`) runs, the active instance carries an **exclusive lock**.

- Another user attempting to edit gets *"Object is locked by user X"*.
- The lock survives the user's session ending. It is not a session lock.
- It expires after a configurable timeout (default in the range of hours; configured in the
  draft framework customizing, table `SDRAFT_...`, or via the parameter in the BDEF framework).

### Phase 2 — optimistic lock

After the exclusive lock expires:

- Another user **can** now edit the active instance.
- The original draft still exists.
- When the original user presses *Resume*, RAP compares the draft's stored **total ETag** with the
  active instance's current one.
  - Equal → nobody changed it → resume proceeds normally.
  - Different → *"The object has been changed by another user. Your draft is outdated."*

This is exactly why `total etag` is mandatory for draft, and why it must be a field that changes on
**any** change in the composition tree (`LastChangedAt`, annotated with
`@Semantics.systemDateTime.lastChangedAt: true`).

### Checking lock state yourself

```abap
READ ENTITIES OF zr_traveltp IN LOCAL MODE
  ENTITY Travel
    FIELDS ( TravelId )
    WITH CORRESPONDING #( keys )
  RESULT DATA(travels).

" %is_draft tells you which copy you are on
LOOP AT travels INTO DATA(travel).
  IF travel-%is_draft = if_abap_behv=>mk-on.
    " we are working on a draft
  ENDIF.
ENDLOOP.
```

And to request a lock explicitly from outside the BO:
```abap
SET LOCKS OF zr_traveltp
  ENTITY Travel
  WITH VALUE #( ( TravelUUID = lv_uuid %is_draft = if_abap_behv=>mk-off ) )
  FAILED DATA(lock_failed).
```

---

## 11.6 Drafts and EML

```abap
" 1. Create an ACTIVE instance directly (typical for a job or an API)
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    CREATE FIELDS ( AgencyId CustomerId BeginDate EndDate CurrencyCode )
    WITH VALUE #( ( %cid = 'C1' AgencyId = '070001' ... ) )
  MAPPED DATA(mapped).
COMMIT ENTITIES.
```
No draft is involved. `%is_draft` defaults to off.

```abap
" 2. Work the way the UI does: Edit -> change -> Activate
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE Edit FROM VALUE #( ( %tky-TravelUUID = lv_uuid
                                 %tky-%is_draft  = if_abap_behv=>mk-off ) )
  MAPPED DATA(mapped_edit)
  FAILED DATA(failed_edit).

MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    UPDATE FIELDS ( Description )
    WITH VALUE #( ( %tky-TravelUUID = lv_uuid
                    %tky-%is_draft  = if_abap_behv=>mk-on
                    Description     = 'changed in the draft' ) ).

MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE Activate FROM VALUE #( ( %tky-TravelUUID = lv_uuid
                                     %tky-%is_draft  = if_abap_behv=>mk-on ) )
  FAILED   DATA(failed_act)
  REPORTED DATA(reported_act).

COMMIT ENTITIES.
```

Note that `Edit` is executed **against the active instance** (`%is_draft = off`) and everything after
it against the **draft** (`%is_draft = on`).

```abap
" 3. Discard a draft
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE Discard FROM VALUE #( ( %tky-TravelUUID = lv_uuid
                                    %tky-%is_draft  = if_abap_behv=>mk-on ) ).
COMMIT ENTITIES.
```

```abap
" 4. Run Prepare explicitly to collect validation messages without saving
MODIFY ENTITIES OF zr_traveltp
  ENTITY Travel
    EXECUTE Prepare FROM VALUE #( ( %tky-TravelUUID = lv_uuid
                                    %tky-%is_draft  = if_abap_behv=>mk-on ) )
  REPORTED DATA(prepare_reported).
```
Useful in a test class: assert that the expected messages come back **without** committing anything.

---

## 11.7 Reading drafts

In OData the key gains `IsActiveEntity`:

```
GET /Travel(TravelUUID=guid'ABC...',IsActiveEntity=true)     <- the active instance
GET /Travel(TravelUUID=guid'ABC...',IsActiveEntity=false)    <- the draft
GET /Travel?$filter=IsActiveEntity eq false                  <- all drafts
```

Fiori Elements handles this automatically and shows a **"Draft"** marker in the list, plus a
"My Drafts" filter.

The `DraftAdministrativeData` navigation gives you who owns a draft and when it was last changed:

```
GET /Travel(TravelUUID=guid'...',IsActiveEntity=false)?$expand=DraftAdministrativeData
```

---

## 11.8 Cleaning up orphaned drafts

Drafts left behind by users accumulate. Two mechanisms:

1. **Automatic expiry.** The draft framework has a configurable retention. Expired drafts are
   removed by the standard clean-up job. On-premise, schedule report
   `R_DRAFT_ENTITIES_DELETE` / the *Draft Clean-Up* application job template (the exact name varies
   by release — search for "draft" in the *Application Jobs* app or in `SJOBREPO`).
2. **Your own job**, if you have retention rules of your own. Use EML `Discard`, never
   `DELETE FROM ztravel_d`:
   ```abap
   MODIFY ENTITIES OF zr_traveltp
     ENTITY Travel
       EXECUTE Discard FROM lt_old_draft_keys.
   COMMIT ENTITIES.
   ```
   Deleting the draft table row directly leaves the lock entry and the draft admin data behind.

---

## 11.9 Non-draft transactional apps

If you decide against draft, remove `with draft;`, the draft tables, `total etag`, the four draft
actions, `Prepare`, and every `with draft;` on associations. The projection BDEF drops `use draft;`
and the five `use action` lines.

What changes for the user:

| | Draft app | Non-draft app |
|---|---|---|
| Edit mode | Implicit; every change auto-saved to the draft | Explicit; changes held in the browser |
| Cancel | Discards the draft server-side | Discards the client-side model |
| Crash recovery | Full | None |
| Validation feedback | Continuous (via `Prepare`) | On Save only |
| Lock | Held from Edit to Save/Cancel | Held only during the Save request |

Non-draft is the right choice for simple, single-screen edits and for services consumed by machines.

---

## 11.10 Draft troubleshooting

| Symptom | Cause |
|---|---|
| Draft table activation fails | Hand-typed structure. Regenerate with the ADT quick fix rather than adjusting field by field — the exact required structure is release-dependent (see Chapter 02, section 2.5) |
| *"Total ETag is missing"* at BDEF activation | `with draft;` without `total etag <field>` |
| *"Association must be draft enabled"* | A `with draft;` is missing on an association |
| Edit button does nothing | `use action Edit;` missing in the projection BDEF |
| Validation messages only appear on Save | Validation not listed in `draft determine action Prepare` |
| Messages do not refresh after Prepare | `determine action Prepare affects messages;` missing from `side effects` |
| *"Draft is outdated"* on Resume | Correct behaviour — the active instance changed. The user must discard and start again |
| Two users can edit the same object | The exclusive lock expired (normal), or `lock master` is missing |
| `READ ENTITIES` returns nothing in a determination | Used `%key` instead of `%tky`, so it read the active instance while the user is on the draft |
| Drafts pile up in the database | No clean-up job scheduled |
| `TravelId` numbers have huge gaps | `setTravelId` is `on modify` instead of `on save` — every discarded draft burned a number |

---

## 11.11 Interview answer

> **"Explain draft handling in RAP."**
>
> A draft is a second copy of the instance in its own draft table, which the user edits before
> committing. Both rows share the same key and are distinguished by `IsActiveEntity` — which is why
> the RAP transactional key is `%tky`, the key plus `%is_draft`, and why using `%key` in a
> draft-enabled BO reads the wrong copy.
>
> You enable it with `with draft;` in the header, a `draft table` per entity, `total etag`, and the
> four draft actions `Edit`, `Activate`, `Discard`, `Resume`, plus `draft determine action Prepare`,
> which lists the validations that should run while the draft is open so errors appear inline rather
> than only at save. All five must also be exposed with `use action` in the projection BDEF.
>
> Locking has two phases, and this is the part worth explaining. From `Edit`, the active instance
> holds an **exclusive** lock which survives the session ending and expires on a timeout. After that
> the **optimistic** phase begins: others may edit, and when the original user resumes, RAP compares
> the draft's stored **total ETag** against the active instance. If they differ the draft is
> declared outdated. That is what `total etag` exists for, and why it should be a different field
> from `etag master`.
>
> Draft is a UI concept. Background jobs and APIs create active instances directly.

## 11.12 Production considerations

- **Schedule the draft clean-up job before go-live.** Orphaned drafts accumulate indefinitely
  otherwise.
- **Never touch a draft table with ABAP SQL** — not for reporting, not for clean-up. Use
  `EXECUTE Discard`; deleting the row directly leaves the lock entry and the draft admin data.
- **Review the exclusive lock timeout** against how long an edit realistically takes. Too long and a
  user who goes to lunch blocks the document; too short and legitimate resumes fail.
- **Use `draft action Activate optimized`** and keep the `Prepare` list complete — it is measurably
  faster on large documents.
- **Generate draft tables with the ADT quick fix** and regenerate after an upgrade rather than
  patching them field by field.
- **Test the two-session conflict** as part of every QA cycle; it is the behaviour users complain
  about and the one least likely to be covered by a unit test.
- **Weigh the second table** for very wide or very high-volume entities before enabling draft.

---

[< CRUD Walkthrough](10-CRUD-Managed-Walkthrough.md) | [Index](00-README.md) | [Next: Validations & Determinations >](12-Validations-and-Determinations.md)
