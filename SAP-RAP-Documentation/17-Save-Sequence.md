# Chapter 17 — The RAP Transaction and the Save Sequence

[< Managed with Unmanaged Save](16-Managed-With-Unmanaged-Save-and-Additional-Save.md) | [Index](00-README.md) | [Next: EML Reference >](18-EML-Reference.md)

---

## 17.1 The two phases of a RAP transaction

A RAP transaction has exactly **two** phases. The second splits into two sub-phases.

```
+=============================================================================+
|  1. INTERACTION PHASE                                                       |
|                                                                             |
|  RAP handler methods run (class inherits CL_ABAP_BEHAVIOR_HANDLER).         |
|  Instances are created in, or loaded into, the transactional buffer.        |
|  The buffer MAY be temporarily inconsistent. The database is untouched.     |
+=============================================================================+
                                    |
                     COMMIT ENTITIES  (implicit in Fiori/OData)
                                    v
+=============================================================================+
|  2. SAVE SEQUENCE                                                           |
|     RAP saver methods run (class inherits CL_ABAP_BEHAVIOR_SAVER).          |
|                                                                             |
|  2a. EARLY SAVE PHASE                                                       |
|      Goal: make sure every BO in this transaction is consistent.            |
|                                                                             |
|      1. finalize()            <- determinations 'on save' run here          |
|      2. check_before_save()   <- validations   'on save' run here           |
|      3. cleanup_finalize()    <- only if 1 or 2 failed; then back to (1)    |
|                                                                             |
|      Failure here: sy-subrc = 4 after COMMIT ENTITIES.                      |
|      The transaction RETURNS TO THE INTERACTION PHASE. Recoverable.         |
|                                                                             |
|  ===================== POINT OF NO RETURN =====================            |
|                                                                             |
|  2b. LATE SAVE PHASE                                                        |
|      Goal: write to the database.                                           |
|                                                                             |
|      4. adjust_numbers()      <- late numbering only                        |
|      5. save() / save_modified()                                            |
|         ... implicit COMMIT WORK ...                                        |
|      6. cleanup()             <- clears the transactional buffer            |
|                                                                             |
|      Failure here: either a runtime error, or (with                         |
|      CL_ABAP_BEHAVIOR_SAVER_FAILED) sy-subrc = 8 and a mandatory            |
|      ROLLBACK ENTITIES.                                                     |
+=============================================================================+
```

---

## 17.2 The saver methods, one by one

### `finalize`

| | |
|---|---|
| Phase | Early save |
| Purpose | Final calculations and data changes before the data can be persisted |
| May change data | **Yes** — this is the last place you can |
| May reject | Yes (via `failed`) |
| In managed scenarios | **Determinations declared `on save` are executed when this method is reached** |
| Scope | All BOs in the current RAP transaction |

Use it for a cross-instance calculation that needs every change to be in place first — e.g. a
document total across entities that no single determination can see.

```abap
METHOD finalize.
  " example: stamp a document version across the whole buffer
  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel ALL FIELDS WITH ... RESULT DATA(travels).
  " ... adjust ...
  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE ...
ENDMETHOD.
```

### `check_before_save`

| | |
|---|---|
| Phase | Early save — **the last gate before the point of no return** |
| Purpose | Check the consistency of the transactional buffer |
| May change data | **No** |
| May reject | **Yes** — this is its job |
| In managed scenarios | **Validations declared `on save` are executed when this method is reached** |
| On failure | `cleanup_finalize` is called and the transaction returns to the interaction phase |

```abap
METHOD check_before_save.
  " Anything that can make the save fail MUST be detected here, not later.
  " Example: a test-mode BAPI call.
  LOOP AT ... .
    CALL FUNCTION 'BAPI_X_CREATE'
      EXPORTING testrun = abap_true
      TABLES    return  = DATA(lt_return).
    LOOP AT lt_return INTO DATA(ls) WHERE type CA 'EA'.
      APPEND VALUE #( %tky = ... ) TO failed-travel.
      APPEND VALUE #( %tky = ... %msg = ... ) TO reported-travel.
    ENDLOOP.
  ENDLOOP.
ENDMETHOD.
```

> **The rule the whole design rests on:** *everything that can fail must fail here.*
> A failure after this point cannot be recovered from.

### `cleanup_finalize`

| | |
|---|---|
| Phase | Early save, on failure |
| Purpose | Roll back changes made in `finalize` |
| Called when | `finalize` or `check_before_save` reported a failure |
| After it | The transaction returns to the interaction phase |

If `finalize` changed anything outside the RAP buffer (your own state, a helper table), undo it here.
Also clear any `CLASS-DATA` bridge variables.

### `adjust_numbers`

| | |
|---|---|
| Phase | Late save |
| Purpose | Replace preliminary ids (`%pid`) with final keys |
| Available | **Only** when the entity declares `late numbering` |
| May reject | No — we are past the point of no return |

```abap
METHOD adjust_numbers.
  LOOP AT mapped-travel ASSIGNING FIELD-SYMBOL(<travel>).
    " draw the real number now
    <travel>-TravelId = zcl_travel_numbers=>next( ).
  ENDLOOP.
ENDMETHOD.
```

See Chapter 19 for the full late-numbering story.

### `save` / `save_modified`

| | `save` | `save_modified` |
|---|---|---|
| Used in | Unmanaged BOs | Managed BOs with `with additional save` or `with unmanaged save` |
| Parameters | none (read your own buffer) | `create`, `update`, `delete` |
| Job | Write the buffer to the database | Write / add to the write |

This is the **only** phase where database modifications are allowed. See Chapters 15 and 16.

After `save` returns successfully, the framework issues the **implicit `COMMIT WORK`**.

### `cleanup`

| | |
|---|---|
| Phase | After the save, and after `ROLLBACK ENTITIES` |
| Purpose | Clear the transactional buffer and any own state |
| Mandatory in | Unmanaged BOs; and anywhere you keep `CLASS-DATA` |

```abap
METHOD cleanup.
  lcl_buffer=>get_instance( )->clear( ).
  CLEAR zbp_r_traveltp=>mapped_purchase_requisition.
ENDMETHOD.
```

**Not clearing state here is one of the most common and most confusing RAP bugs.** The symptom is
"the second save in the same session does something strange".

---

## 17.3 Where determinations and validations actually run

This table is the practical answer to "when does my code run":

| BDEF declaration | Runs during | At which saver method |
|---|---|---|
| `determination X on modify` | Interaction phase | — (immediately after the triggering change) |
| `validation V on modify` | Interaction phase | — |
| `determination X on save` | Early save | when `finalize` is reached |
| `validation V on save` | Early save | when `check_before_save` is reached |
| `draft determine action Prepare` | Interaction phase (called by the UI), and before `Activate` | — |
| Action handler | Interaction phase | — |
| `FOR NUMBERING` (early numbering) | Interaction phase, at create | — |
| `adjust_numbers` (late numbering) | Late save | `adjust_numbers` |

So: **your `on save` determination runs before your `on save` validation**, because `finalize`
precedes `check_before_save`. That ordering is guaranteed. Ordering *within* a phase is not.

---

## 17.4 `COMMIT ENTITIES` and `ROLLBACK ENTITIES`

### `COMMIT ENTITIES`

Triggers the save sequence and the final database commit.

```abap
" short form
COMMIT ENTITIES.

" with response, per BO
COMMIT ENTITIES RESPONSE OF zr_traveltp
  FAILED   DATA(failed)
  REPORTED DATA(reported).

" with the overall result
COMMIT ENTITIES RESPONSES
  FAILED   DATA(failed)
  REPORTED DATA(reported).

" simulation - runs the early save phase only, then rolls back.
" Excellent for "check before you commit" scenarios.
COMMIT ENTITIES IN SIMULATION MODE
  RESPONSE OF zr_traveltp
  FAILED   DATA(sim_failed)
  REPORTED DATA(sim_reported).
```

| `sy-subrc` after `COMMIT ENTITIES` | Meaning |
|---|---|
| `0` | Success. Committed. |
| `4` | **Early save phase** failed. The transaction is back in the interaction phase. You can correct and retry. |
| `8` | **Late save phase** failed (only possible with `CL_ABAP_BEHAVIOR_SAVER_FAILED`). You **must** issue `ROLLBACK ENTITIES` before any further RAP operation. |

**Always check `sy-subrc` or `failed`.** A silent `COMMIT ENTITIES.` that fails looks exactly like
one that succeeded.

### `ROLLBACK ENTITIES`

```abap
ROLLBACK ENTITIES.
```
Discards everything in the current RAP transaction, calls `cleanup`, and implicitly triggers
`ROLLBACK WORK`.

### `COMMIT ENTITIES` vs `COMMIT WORK`

| | `COMMIT ENTITIES` | `COMMIT WORK` |
|---|---|---|
| Triggers the RAP save sequence | Yes | Yes |
| On an early-save failure | Returns to the interaction phase, `sy-subrc = 4` | **Runtime error** |
| RAP responses available | Yes (`FAILED`, `REPORTED`) | No |
| Key conversion for late numbering | Yes (`CONVERT KEY`) | No |
| Simulation mode | Yes | No |
| Update mode | Local update, falling back to synchronous. Never asynchronous | Consumer's choice |

**Use `COMMIT ENTITIES`.** `COMMIT WORK` only behaves identically in the best case, and turns a
recoverable situation into a dump in every other case.

`ROLLBACK ENTITIES` and `ROLLBACK WORK` are interchangeable in RAP.

---

## 17.5 Who calls `COMMIT ENTITIES`

| Consumer | Who commits |
|---|---|
| Fiori / OData | **The RAP runtime engine, implicitly.** You never write it. |
| Your own ABAP class / report / job | **You**, explicitly, after your EML |
| A RAP handler or saver method | **Nobody.** Committing inside the BO is forbidden |

This is why a handler method must never contain `COMMIT ENTITIES` or `COMMIT WORK`: the BO is not
the transaction owner.

---

## 17.6 What is allowed in which phase

### First, separate the concerns

"Database writes only happen in one method" is a useful slogan, but it compresses several different
things. Keep these apart:

| Concern | The actual rule |
|---|---|
| **1. RAP transactional processing** | Changes to *this BO's business data* are made in the **transactional buffer** during the interaction phase, via EML. They are not database writes at all at that point. |
| **2. Direct SQL restrictions per phase** | `INSERT`/`UPDATE`/`DELETE`/`MODIFY` issued directly by your code against the **standard database connection** belong in the **late save phase**. Earlier phases would create additional database transactions and break the single SAP LUW. Reads (`SELECT`) are allowed in every phase. |
| **3. Framework-managed persistence** | In a plain **managed** BO, *you write no persistence code at all*. The framework converts the buffer into `INSERT`/`UPDATE`/`DELETE` on `persistent table` during the late save phase. Concern 2 simply does not arise. |
| **4. Additional save** | The framework still persists the BO. Your `save_modified` runs **in addition**, in the late save phase, for side-effect work (change documents, application log, events). |
| **5. Unmanaged save / unmanaged BO** | **You** perform the persistence, in `save_modified` / `save`, in the late save phase. This is the case where concern 2 is your direct responsibility. |
| **6. External APIs, update task, secondary connections** | Governed by their own per-phase rules (matrix below), not by the "database writes" rule. A number range commits on a secondary connection and is legal in every phase; an update-task registration is legal only in the late save phase; a synchronous RFC is legal everywhere *except* the late save phase. |

So the precise statement is:

> In RAP, business data changes are performed through the RAP transactional buffer during the
> interaction phase, and persistence is finalized by the RAP save sequence. Direct database
> modifications on the standard connection outside the late save phase can break transactional
> consistency and should be avoided.

Not: "you may only ever write to the database in one method." In a managed BO you write to the
database nowhere; in an unmanaged save you write in `save_modified`; and side-channel writes on a
secondary connection (logs, number ranges, traces) follow different rules entirely.

### The matrix

This comes from SAP's RAP BO contract. Violating it produces either a runtime error (under strict
mode) or, worse, silent data inconsistency. Treat it as the authoritative version of the slogan
above, and check it against your release's documentation for anything unusual.

| Statement / operation | Interaction | Early save | Late save | Note |
|---|---|---|---|---|
| Database **read** (`SELECT`) | yes | yes | yes | On the BO's own data use EML, not SELECT |
| Database **modification** (`INSERT`/`UPDATE`/`DELETE`/`MODIFY`) | **no** | **no** | **yes** | Only the late phase, so there is exactly one DB transaction |
| Database commit on a **secondary connection** | yes | yes | yes | Legal for number ranges, application logs, traces |
| Database commit on the **standard connection** | yes | yes | **no** | Would split the LUW |
| `CALL FUNCTION ... IN UPDATE TASK` | **no** | **no** | **yes** | Cannot be unregistered; registering earlier breaks draft |
| `CALL FUNCTION ... DESTINATION` (sRFC) | yes | yes | **no** | Not in the late phase |
| `CALL FUNCTION ... STARTING NEW TASK` (aRFC) | yes | yes | **no** | Same |
| `CALL FUNCTION ... IN BACKGROUND UNIT` (bgRFC) | **no** | **no** | **yes** | |
| `CALL FUNCTION ... IN BACKGROUND TASK` (tRFC/qRFC) | **no** | **no** | **no** | Obsolete |
| `PERFORM ON COMMIT` / `ON ROLLBACK` | (possible) | (possible) | yes | Signals poor RAP integration; prefer EML |
| `COMMIT WORK` / `ROLLBACK WORK` | **no** | **no** | **no** | Not where RAP is the transaction owner |
| `WAIT` | yes | yes | **no** | Implies a DB commit |
| Dynpro statements: `MESSAGE` without `INTO`, `WRITE`, `CALL SCREEN`, `SET SCREEN`, `LEAVE SCREEN`, `STOP`, `SUPPRESS DIALOG` | **no** | **no** | **no** | Runtime error |
| `CALL TRANSACTION`, `LEAVE TRANSACTION`, `SUBMIT` | **no** | **no** | **no** | |
| `EXIT FROM STEP-LOOP`, `LEAVE TO LIST-PROCESSING` | **no** | **no** | **no** | |

### The two rules worth memorising

1. **Business data changes go through the transactional buffer; persistence is finalized by the
   save sequence.** Where you write direct SQL at all (unmanaged, unmanaged save), it belongs in
   the late save phase, on the standard connection. Side-channel writes on a secondary connection
   are a separate case.
2. **Nothing that can fail should be left to the late save phase.** Detect it in
   `check_before_save`, while the transaction is still recoverable.

Rule 2 is close to absolute — it is the whole point of the early/late split. Rule 1 has the
legitimate exceptions listed in the matrix, so read it as a default with known carve-outs rather
than as a prohibition.

### Secondary connections — the useful exception

A number range object commits on its own connection. That is why
`cl_numberrange_runtime=>number_get( )` is legal in an `on save` determination even though it
performs a commit: it does not touch the standard connection and therefore does not split your LUW.

The same applies to application logs written with `BAL_DB_SAVE` when configured for a secondary
connection, and to trace/monitoring writes.

---

## 17.7 Failures in the late save phase

Normally, a failure after the point of no return is a runtime error. RAP offers a controlled escape
for cases where it is genuinely unavoidable — e.g. wrapping a BAPI whose behaviour you cannot fully
predict.

```abap
CLASS lsc_zr_traveltp DEFINITION INHERITING FROM cl_abap_behavior_saver_failed.
  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
ENDCLASS.
```

`CL_ABAP_BEHAVIOR_SAVER_FAILED` gives `save_modified` access to `failed` and `reported`, which the
plain base class does not have in the late phase.

Consumer side:

```abap
COMMIT ENTITIES RESPONSE OF zr_traveltp
  FAILED   DATA(failed)
  REPORTED DATA(reported).

CASE sy-subrc.
  WHEN 0.
    " committed
  WHEN 4.
    " early save failed - correctable, we are back in the interaction phase
  WHEN 8.
    " LATE save failed. A further RAP operation would dump.
    ROLLBACK ENTITIES.
ENDCASE.
```

Use this sparingly. It is a mitigation, not a design pattern. The right answer is almost always to
move the check into `check_before_save`.

---

## 17.8 A full trace of one save

User edits a Travel in Fiori and presses Save. With draft enabled:

```
  1  PATCH /Travel(...,IsActiveEntity=false)  BookingFee = 30
       -> interaction phase
       -> determination calculateTotalPrice (on modify)  -> TotalPrice = 30 + sum(bookings)
       -> side effect tells the UI to re-read TotalPrice

  2  POST .../Prepare
       -> draft determine action Prepare
       -> validation validateDates      runs -> ok
       -> validation validateCustomer   runs -> ok
       -> validation validateAgency     runs -> ok
       -> messages returned, UI shows none

  3  POST .../Activate
       -> RAP runtime issues COMMIT ENTITIES implicitly

  4  EARLY SAVE
       finalize()
         -> determination setTravelId (on save) runs
              -> cl_numberrange_runtime=>number_get( )   [secondary connection: legal]
              -> TravelId = 00000042
       check_before_save()
         -> validations on save re-run (skipped if 'Activate optimized' and Prepare covered them)
         -> no failures

  5  ===== POINT OF NO RETURN =====

  6  LATE SAVE
       adjust_numbers()      [not called - no late numbering declared]
       save()                [managed: framework writes ZTRAVEL and ZBOOKING,
                              deletes the draft rows from ZTRAVEL_D / ZBOOKING_D]
       implicit COMMIT WORK
       cleanup()             [buffer cleared, lock released]

  7  HTTP 200 with the activated instance -> UI leaves edit mode
```

---

## 17.9 Debugging the save sequence

### Breakpoints that are worth setting

| Where | Tells you |
|---|---|
| `finalize` | Did the early save start? Are `on save` determinations running? |
| `check_before_save` | Is the buffer what you expect at the last gate? |
| `cleanup_finalize` | Something rejected the save. Inspect `failed` from the previous method |
| `save` / `save_modified` | What is actually being written |
| `cleanup` | Did the transaction complete? |

### The diagnostic that answers most questions

```abap
COMMIT ENTITIES RESPONSE OF zr_traveltp
  FAILED   DATA(failed)
  REPORTED DATA(reported).

out->write( |sy-subrc: { sy-subrc }| ).
out->write( failed ).
out->write( reported ).
```

`failed` tells you *which instance* was rejected; `reported` tells you *why*. Run this from an
`IF_OO_ADT_CLASSRUN` class rather than through the UI — it is faster and reproducible.

### Simulation mode

```abap
COMMIT ENTITIES IN SIMULATION MODE
  RESPONSE OF zr_traveltp
  FAILED DATA(sim_failed) REPORTED DATA(sim_reported).
```

Runs the early save phase (so all `on save` determinations and validations execute) and then rolls
back. Nothing is written. Perfect for a "check document" button and for tests.

---

## 17.10 Common save-sequence problems

| Symptom | Cause |
|---|---|
| Runtime error *"COMMIT WORK is not allowed here"* | `COMMIT WORK` inside a handler or saver |
| Runtime error in the late phase | Something that can fail was left in `save`. Move it to `check_before_save` |
| Data saved but a field is empty | The determination that fills it is `on modify` and its trigger never fired; or `mapping for` is incomplete |
| Second save in the same session behaves oddly | `CLASS-DATA` or an unmanaged buffer not cleared in `cleanup` / `cleanup_finalize` |
| `sy-subrc = 4` and nothing in `reported` | A validation filled `failed` without a message |
| `sy-subrc = 8` | Late-phase failure. `ROLLBACK ENTITIES` is mandatory before continuing |
| Number range gaps | `setTravelId` is `on modify`; every discarded draft burned a number |
| `save_modified` never called | Nothing on **this** BO changed in the transaction |
| Update task function module never executes | Registered outside the late save phase |
| Everything works via EML but not via Fiori | Draft: your code uses `%key` instead of `%tky`, so it operates on the active instance |

---

## 17.11 Interview answer

> **"Explain the RAP save sequence."**
>
> A RAP transaction has two phases. In the **interaction phase**, handler methods run and changes go
> into the transactional buffer. The database is untouched, and the buffer is allowed to be
> temporarily inconsistent.
>
> `COMMIT ENTITIES` — issued implicitly by the RAP runtime in a Fiori scenario — then triggers the
> **save sequence**, which splits in two.
>
> The **early save phase** runs `finalize`, where `on save` determinations execute and it is the last
> point at which data may be changed; then `check_before_save`, where `on save` validations execute
> and which is the last gate. If either reports a failure, `cleanup_finalize` runs and the
> transaction returns to the interaction phase — `sy-subrc` is 4 and it is recoverable.
>
> Then the **point of no return**, and the **late save phase**: `adjust_numbers` for late numbering,
> then `save` or `save_modified`, then the implicit `COMMIT WORK`, then `cleanup` clears the buffer.
>
> The design principle is that everything which can fail must fail in the early phase. A failure
> after the point of no return is a runtime error, unless you inherit from
> `CL_ABAP_BEHAVIOR_SAVER_FAILED`, in which case `sy-subrc` is 8 and the consumer must issue an
> explicit `ROLLBACK ENTITIES`.
>
> On phase rules: business data changes go through the buffer, and persistence is finalized by the
> save sequence. Where you write direct SQL at all — unmanaged, or unmanaged save — it belongs in
> the late phase on the standard connection. There are documented carve-outs: reads are allowed
> everywhere, and commits on a **secondary** connection, such as a number range or an application
> log, are legal in every phase. That is why drawing a number range in an `on save` determination
> does not break the LUW.
>
> And `COMMIT ENTITIES` rather than `COMMIT WORK`: on an early-save failure `COMMIT WORK` dumps,
> whereas `COMMIT ENTITIES` returns you to the interaction phase with a usable `failed` and
> `reported`.

## 17.12 Production considerations

- **Check `sy-subrc` after every `COMMIT ENTITIES`.** A silent commit that failed looks exactly like
  one that succeeded.
- **`sy-subrc = 8` requires an explicit `ROLLBACK ENTITIES`** before any further RAP operation, or
  the next call dumps.
- **Move every failure-capable check into `check_before_save`**, including test-mode BAPI calls.
  This is the single most important production rule in the whole model.
- **`COMMIT ENTITIES IN SIMULATION MODE`** is the right implementation for a "check document"
  button, and for tests — it runs the whole early phase and writes nothing.
- **Clear all own state in `cleanup` and `cleanup_finalize`.** The second transaction in a session
  is where stale state surfaces.
- **Never register an update-task module outside the late save phase** — it cannot be unregistered
  and it breaks draft.
- **Document the phase rules for the team.** This is where a well-meaning `COMMIT WORK` added later
  does the most damage.

---

[< Managed with Unmanaged Save](16-Managed-With-Unmanaged-Save-and-Additional-Save.md) | [Index](00-README.md) | [Next: EML Reference >](18-EML-Reference.md)
