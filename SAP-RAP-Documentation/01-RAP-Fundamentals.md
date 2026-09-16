# Chapter 01 — RAP Fundamentals

[< Index](00-README.md) | [Next: Data Model >](02-Data-Model-and-Tables.md)

---

## 1.1 What RAP actually is

RAP (ABAP RESTful Application Programming Model) is **a contract plus a runtime**.

- **The contract** — you *declare* what your business object can do (create, update, delete, actions,
  validations, locks, authorizations) in a dedicated language called **BDL** (Behavior Definition
  Language), in a file called a **Behavior Definition (BDEF)**.
- **The runtime** — the RAP framework reads that declaration and orchestrates everything around it:
  it parses the OData request, calls your code in a fixed order, manages a transactional buffer,
  handles locking, handles ETags, handles drafts, and finally commits.

The mental shift from classic ABAP is this:

| Classic ABAP (module pool / ALV / BAPI) | RAP |
|---|---|
| You write the flow: PBO, PAI, `CALL FUNCTION`, `COMMIT WORK` | The framework writes the flow. You fill in *handlers* |
| You decide when to read and when to save | The framework decides. You only implement phases |
| `COMMIT WORK` wherever you like | `COMMIT WORK` is **forbidden** in most phases |
| Locking via `ENQUEUE_E...` calls you write | `lock master` — one word |
| UI is SAP GUI / ALV, tightly coupled | UI is Fiori Elements, generated from annotations |

RAP is **declarative first, code second**. If you find yourself writing a lot of code for something
RAP already offers declaratively (locking, ETag, field read-only-ness, draft), you are fighting the
framework.

---

## 1.2 The full architecture stack

Read this diagram bottom-up. This is the order in which you build, and the order this documentation
follows.

```
   +--------------------------------------------------------------+
   |  SAP Fiori Elements App  (List Report / Object Page / ALP)   |   <- generated from annotations
   +--------------------------------------------------------------+
                               |  OData V4 (or V2)
   +--------------------------------------------------------------+
 7 |  Service Binding      ZUI_TRAVEL_O4                          |   protocol + version + publish
   +--------------------------------------------------------------+
 6 |  Service Definition   ZSD_TRAVEL                             |   which entities are exposed
   +--------------------------------------------------------------+
 5 |  Metadata Extension   ZC_TravelTP  (@UI annotations)         |   layout only, no data
   +--------------------------------------------------------------+
 4 |  Projection Layer                                            |
   |    CDS Projection View      ZC_TravelTP                      |   service-specific subset
   |    Projection BDEF          ZC_TravelTP                      |   'use create; use update; ...'
   +--------------------------------------------------------------+
 3 |  Behavior Layer                                              |
   |    Behavior Definition      ZR_TravelTP  (BDEF)              |   the contract
   |    Behavior Pool (class)    ZBP_R_TravelTP                   |   the implementation
   +--------------------------------------------------------------+
 2 |  Business Object Model (interface / root views)              |
   |    ZR_TravelTP  --composition--> ZR_BookingTP                |   data model + associations
   +--------------------------------------------------------------+
 1 |  Data Model: DDIC tables  ZTRAVEL / ZBOOKING (+ draft tables)|
   +--------------------------------------------------------------+
```

### What each layer is *for* (and why it exists separately)

| Layer | Purpose | Why not merge it into the one below? |
|---|---|---|
| **1 Tables** | Persistence | — |
| **2 Interface / root view** | The *single* canonical model of the business object. Field naming, associations, semantics. | One BO, many services. If you put UI annotations here, every consumer inherits them. |
| **3 BDEF + ABP** | The behavior contract and its implementation. Owned by the BO, not by a UI. | Validations must apply to *every* consumer — OData, EML from another app, background job. |
| **4 Projection** | A *service-specific view* of the BO. Only the fields and operations this app needs. | A "manager" app and an "employee" app can expose the same BO with different fields and different enabled actions. |
| **5 Metadata extension** | Pure layout. Which column where, which facet, which button. | Keeps 300 lines of `@UI` out of the projection view; can be transported/overridden separately. |
| **6 Service definition** | The published surface | You can publish two services (UI + API) from one projection. |
| **7 Service binding** | Protocol binding + activation | OData V2 for older Fiori, V4 for new; UI vs Web API. |

> **The rule of thumb:** *business semantics go down, presentation goes up.* Never put `@UI` in
> `ZR_`. Never put business logic in `ZC_`.

---

## 1.3 The two (really four) implementation types

The **first decision** in any RAP project, taken before a single line of code:

```abap
managed implementation in class ZBP_R_TravelTP unique;                    " 1
unmanaged implementation in class ZBP_R_TravelTP unique;                  " 2
managed with additional save implementation in class ZBP_R_TravelTP unique;   " 3
managed with unmanaged save implementation in class ZBP_R_TravelTP unique;    " 4
```

### Decision table

| Question | managed | managed + additional save | managed + unmanaged save | unmanaged |
|---|---|---|---|---|
| Who provides the transactional buffer? | Framework | Framework | Framework | **You** |
| Who writes to the database? | Framework | Framework + you | **You** | **You** |
| Who implements CRUD handlers? | Nobody (automatic) | Nobody | Nobody | **You** (`FOR MODIFY`, `FOR READ`, `FOR LOCK`) |
| Draft support | Yes, declarative | Yes | Yes | Only with extra work |
| `persistent table` in BDEF | Required | Required | **Forbidden** | Not applicable |
| Typical use | Greenfield app on Z-tables | Greenfield + change docs / app log / events | Greenfield but save must call an API / late numbering | Wrapping existing BAPI / function-module logic |
| Effort | Lowest | Low | Medium | Highest |

### How to choose — in plain terms

- **Greenfield, own Z tables, no legacy logic** → **managed**. This covers ~80% of custom developments.
- **Managed, but on save I also need to write a change document, an application log, fire a business
  event, or call a BAdI** → **managed with additional save**. The framework still writes your table;
  your `save_modified` runs *in addition*.
- **Managed, but the actual persistence has to go through a released API / BAPI, or I need
  `CONVERT KEY` for late numbering** → **managed with unmanaged save**. You get all the managed
  goodies (buffer, lock, ETag, draft, field control) but **you** write the DB.
- **There is 15 years of existing logic in function modules with its own locking and update task,
  and I must not reimplement it** → **unmanaged**. You wrap it.

> **Common mistake:** choosing `unmanaged` because "we have existing tables". Existing *tables* are
> fine for managed. Choose unmanaged only when there is existing *transactional logic* you must reuse.

---

## 1.4 Vocabulary you must be fluent in

| Term | Meaning |
|---|---|
| **BO (Business Object)** | The whole composition tree: root + all children + behavior. `ZR_TravelTP` *is* the BO. |
| **Root entity** | The top of the composition tree. Exactly one per BO. Owns the lock and the authorization by default. |
| **Child entity** | Part of the BO via `composition`. Cannot exist without its parent. Deleted when the parent is deleted. |
| **Composition** | A **parent-owns-child** relationship. Defines the BO boundary. `composition [0..*] of ZR_BookingTP as _Booking` |
| **Association** | A plain reference to *another* BO or master data. Does **not** extend the BO. `association [0..1] to ZI_Agency as _Agency` |
| **Transactional buffer** | In-memory area where all changes live until save. Nothing touches the DB before the late save phase. |
| **Interaction phase** | The phase where the consumer creates/reads/modifies. Buffer may be temporarily inconsistent. |
| **Save sequence** | The phase triggered by `COMMIT ENTITIES` that makes buffer → database. |
| **ABP (ABAP Behavior Pool)** | The global class `ZBP_...` holding local handler and saver classes. |
| **Handler class** | `lhc_...`, inherits `CL_ABAP_BEHAVIOR_HANDLER`. Implements the interaction phase. |
| **Saver class** | `lsc_...`, inherits `CL_ABAP_BEHAVIOR_SAVER`. Implements the save sequence. |
| **EML** | Entity Manipulation Language. ABAP statements (`READ ENTITIES`, `MODIFY ENTITIES`, ...) to call a RAP BO from ABAP. |
| **Derived type** | `TYPE TABLE FOR CREATE ZR_TravelTP` etc. — ABAP types the framework generates from the BDEF. |
| **`%cid`** | Content ID. A consumer-chosen temporary identifier used before a key exists. |
| **`%key`** | The key fields of an instance. |
| **`%tky`** | *Transactional key* = `%key` + `%is_draft`. **Always use `%tky`, not `%key`,** in draft scenarios. |
| **`%pid`** | Preliminary ID in late-numbering scenarios; resolved to a real key via `CONVERT KEY`. |
| **`%control`** | Per-field flags saying which fields the consumer actually sent (`if_abap_behv=>mk-on/off`). |
| **`mapped` / `failed` / `reported`** | The three RAP response parameters. Mapping info, failed keys, messages. |
| **Determination** | Code that *changes* data automatically when a trigger condition occurs. |
| **Validation** | Code that *checks* data and rejects it with a message. Never changes data. |
| **Action** | An operation beyond CRUD, exposed as a button or an API call. |
| **Draft** | An auto-saved, not-yet-active copy of an instance, stored in a separate draft table. |
| **Strict mode** | `strict ( 1 )` / `strict ( 2 )` — turns on stricter syntax checks. Always use the highest available. |

---

## 1.5 The RAP request lifecycle (what happens when a user presses Save)

Understanding this sequence explains 90% of "why doesn't my code run" questions.

```
User in Fiori presses "Create"
   |
   v
[1] OData V4 POST arrives at the service binding
   |
   v
[2] RAP runtime resolves projection -> base BDEF, checks 'use create;'
   |
   v
[3] INTERACTION PHASE
      - global authorization check      (FOR GLOBAL AUTHORIZATION)
      - instance authorization check    (FOR INSTANCE AUTHORIZATION)
      - lock                            (managed: automatic)
      - create in transactional buffer  (managed: automatic)
      - determinations 'on modify'      <- your code
      - validations 'on modify'         <- your code
      - feature control                 (FOR FEATURES / FOR INSTANCE FEATURES)
      ...user keeps editing; repeat...
   |
   v  (user presses Save -> RAP runtime issues COMMIT ENTITIES implicitly)
[4] EARLY SAVE PHASE
      - determinations 'on save'        <- your code   (run when finalize is reached)
      - finalize()                      <- your code
      - validations 'on save'           <- your code   (run when check_before_save is reached)
      - check_before_save()             <- your code
      - if anything failed -> cleanup_finalize() and return to [3]
   |
   v   ======= POINT OF NO RETURN =======
[5] LATE SAVE PHASE
      - adjust_numbers()                <- your code (late numbering only)
      - save() / save_modified()        <- framework and/or your code
      - implicit COMMIT WORK
      - cleanup()                       <- clears the buffer
   |
   v
[6] OData response returned to Fiori
```

Chapter 17 covers each phase in full, including what ABAP statements are legal in each.

---

## 1.6 Managed vs unmanaged — what code you actually write

Same business object, two implementation types. This is the clearest way to see the difference.

**Managed** — the behavior pool for a plain CRUD BO can be literally empty:

```abap
CLASS lhc_travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    " nothing - create, update, delete, read, lock all work already
ENDCLASS.

CLASS lhc_travel IMPLEMENTATION.
ENDCLASS.
```

**Unmanaged** — for the *same* CRUD you must implement, at minimum:

```abap
CLASS lhc_travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS create        FOR MODIFY IMPORTING entities FOR CREATE Travel.
    METHODS update        FOR MODIFY IMPORTING entities FOR UPDATE Travel.
    METHODS delete        FOR MODIFY IMPORTING keys     FOR DELETE Travel.
    METHODS read          FOR READ   IMPORTING keys     FOR READ   Travel RESULT result.
    METHODS lock          FOR LOCK   IMPORTING keys     FOR LOCK   Travel.
    METHODS rba_Booking   FOR READ   IMPORTING keys_rba FOR READ   Travel\_Booking FULL result_requested RESULT result LINK association_links.
    METHODS cba_Booking   FOR MODIFY IMPORTING entities_cba FOR CREATE Travel\_Booking.
ENDCLASS.
```

...plus a saver class with `finalize`, `check_before_save`, `save`, `cleanup`, plus your own
buffer (a global internal table in the ABP), plus your own lock objects.

That is the entire argument for managed.

---

## 1.7 Where RAP fits vs. the alternatives

| You need | Use |
|---|---|
| A read-only analytical/operational report on Fiori | RAP read-only (CDS + service, no BDEF) — **Chapter 07** |
| A transactional Fiori app on custom tables | RAP managed — **Chapter 10** |
| A REST/OData API for another system to call | RAP + Web API service binding — **Chapter 06** |
| To call an existing SAP BO (e.g. Purchase Requisition) from your code | EML against the released `I_...TP` interface — **Chapter 18** |
| A classic report with SAP GUI output | Still a classic ABAP report. RAP is not for SAP GUI. |
| A batch job that mass-updates a RAP BO | ABAP class + EML + `COMMIT ENTITIES` — **Chapter 18** |

---

## 1.8 Interview answer

> **"What is RAP, and what is the difference between managed and unmanaged?"**
>
> RAP is SAP's programming model for building OData services and Fiori apps on the ABAP platform.
> The data model is CDS, the transactional behavior is declared in a behavior definition, and the
> business logic is implemented in an ABAP behavior pool. The framework owns the transaction, the
> buffer, locking, ETags, draft and the OData protocol.
>
> Managed and unmanaged are **implementation types**, and the difference is who provides the
> transactional buffer and who performs the save. Managed: the framework does both, and you only
> write business logic. Unmanaged: you provide your own buffer and implement `FOR READ`,
> `FOR MODIFY`, `FOR LOCK`, read- and create-by-association, plus a saver class.
>
> The decision criterion is existing **transactional logic**, not existing tables — `persistent
> table` accepts any table. There are also two hybrids: `managed with additional save` for extra
> work at save time, and `managed with unmanaged save` when only the persistence is custom.

Full set of interview questions and answers: [Chapter 27](27-Interview-Preparation.md).

## 1.9 Production considerations

- **Record the implementation-type decision and why.** It is the one architectural choice that is
  expensive to reverse, and the next developer will otherwise assume it was arbitrary.
- **Do not mix implementation types across a composition tree** unless you have a specific reason;
  the save behaviour applies to the whole business object.
- **Check release availability before you design.** `strict ( 2 )`, entity-level `with unmanaged
  save` and RAP business events need ABAP Platform 2021+. DEV, QA and PROD must be on the same
  release, or code that activates in DEV will not activate in PROD.
- **Plan for more than one consumer from day one.** Even a "single Fiori app" usually acquires a
  background job and an API later; that is what keeps business logic in the base BDEF rather than
  the projection.

---

[< Index](00-README.md) | [Next: Data Model >](02-Data-Model-and-Tables.md)
