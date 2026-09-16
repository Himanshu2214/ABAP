# SAP RAP — Complete Developer Documentation

> ABAP RESTful Application Programming Model, end to end.
> Target platform: **SAP S/4HANA (on-premise / private cloud), ABAP Platform 2021+, HANA 2021, Eclipse ADT**.
> Everything here also applies to ABAP Cloud / BTP ABAP Environment unless explicitly marked *on-premise only*.

---

## Status of the code in this documentation

**Read this before copying anything into a system.**

The **declarative syntax** — behavior definition language, CDS annotations, BDEF keywords, the save
sequence, the phase rules — was verified against SAP's published material (see [Sources](#sources)).

The **ABAP code examples have not been activated or executed in an SAP system.** They are written to
be correct and idiomatic, and they show the right structure, but individual statements must be
validated in your target release before use. RAP syntax, generated method signatures and framework
class names differ across ABAP Platform releases.

| Confidence | Applies to |
|---|---|
| **High** — verified against SAP sources | BDEF syntax, save-sequence order, phase rules, `with additional save` / `with unmanaged save` placement, CDS annotation names |
| **Medium** — standard, widely documented patterns | Managed behavior pool code (Chapters 09–14, 16), EML statements |
| **Treat as conceptual reference** | [Chapter 15 — Unmanaged Scenario](15-Unmanaged-Scenario.md). See the notice at the top of that chapter and its recheck list |

Two habits that make the release question mostly go away:

1. **Generate, do not type.** Use `Ctrl + 1` for every handler and saver method signature, and for
   draft tables. The generated artifact is authoritative for your release; an example in a document
   is not.
2. **Activate as you go.** Build in the order given in [Chapter 10, §10.2](10-CRUD-Managed-Walkthrough.md),
   activating each object before the next.

The fastest source of known-good, activated code on your own system is the **ABAP Flight Reference
Scenario** (`/DMO/` packages) — it ships a complete managed *and* unmanaged implementation of the
same Travel/Booking model used throughout this guide.

---

## How to read this documentation

Read Chapters 01–20 in order the first time, then use the whole set as a reference.
Every chapter uses **one running example** (a Travel / Booking business object) so the same object
names carry from the database table to the Fiori button.

### Part I — Building blocks (read in order)

| # | Chapter | What you get |
|---|---------|--------------|
| 01 | [RAP Fundamentals](01-RAP-Fundamentals.md) | Architecture, every layer, managed vs unmanaged decision table, request lifecycle |
| 02 | [Data Model and Tables](02-Data-Model-and-Tables.md) | Tables, UUID vs semantic keys, admin fields, draft tables |
| 03 | [Basic / Interface View](03-Basic-Interface-View.md) | `ZR_TravelTP` **line by line** — composition vs association, `$projection`, `@Semantics` |
| 04 | [Projection View](04-Projection-View.md) | `ZC_TravelTP` line by line — `provider contract`, `redirected to`, virtual elements |
| 05 | [Metadata Extension & UI Annotations](05-Metadata-Extension-and-UI-Annotations.md) | Facets, line items, field groups, data points, criticality |
| 06 | [Service Definition & Binding](06-Service-Definition-and-Binding.md) | `expose`, V2/V4, UI vs Web API, publishing |
| 07 | [Read-Only Fiori Report](07-ReadOnly-Fiori-Report-Walkthrough.md) | Complete walkthrough — **no BDEF, no ABAP** |

### Part II — Behavior

| # | Chapter | What you get |
|---|---------|--------------|
| 08 | [Behavior Definition (BDEF)](08-Behavior-Definition.md) | **Every keyword**, base + projection |
| 09 | [Behavior Pool Classes](09-Behavior-Pool-Classes.md) | Global / handler / saver anatomy, every `FOR ...` signature, `failed` / `reported` / `mapped` |
| 10 | [CRUD Managed Walkthrough](10-CRUD-Managed-Walkthrough.md) | Full managed app, step by step |
| 11 | [Draft Handling](11-Draft-Handling.md) | Lifecycle, `%tky`, the two lock phases, `Prepare` |
| 12 | [Validations & Determinations](12-Validations-and-Determinations.md) | Triggers, worked implementations |
| 13 | [Actions, Functions & Buttons](13-Actions-Functions-and-Buttons.md) | Every action type, and how each becomes a **button** |
| 14 | [Feature Control & Authorization](14-Feature-Control-and-Authorization.md) | DCL vs global vs instance vs feature control, **end-to-end worked scenario** |

### Part III — Advanced implementation types

| # | Chapter | What you get |
|---|---------|--------------|
| 15 | [Unmanaged Scenario](15-Unmanaged-Scenario.md) | Own buffer, all handlers, own lock, own save *(conceptual reference code)* |
| 16 | [Managed with Unmanaged Save / Additional Save](16-Managed-With-Unmanaged-Save-and-Additional-Save.md) | Both hybrids, `save_modified`, the late-numbering pattern |
| 17 | [The Save Sequence](17-Save-Sequence.md) | Phases, point of no return, the allowed/forbidden matrix |
| 18 | [EML Reference](18-EML-Reference.md) | Every statement, derived types, `%cid` / `%tky` / `%pid` / `%control` |
| 19 | [Numbering, Locking, ETag](19-Numbering-Locking-ETag.md) | Five numbering scenarios, lock vs ETag, `total etag` |

### Part IV — Making it work in practice

| # | Chapter | What you get |
|---|---------|--------------|
| 20 | [Messages, Troubleshooting & Cheat Sheet](20-Messages-Troubleshooting-and-Cheat-Sheet.md) | Message classes, state messages, symptom→cause index, one-page cheat sheet |
| 21 | [Side Effects](21-Side-Effects.md) | Why the UI shows stale values, and the one-line fix |
| 22 | [Value Helps & Text Associations](22-Value-Helps-and-Text-Associations.md) | Complete F4 example: searchable, dependent, with write-back |
| 23 | [Testing & Debugging](23-Testing-and-Debugging.md) | EML console classes, ABAP Unit, `$metadata`, breakpoints, `ST05` / `SAT` / `SQLM` |
| 24 | [Performance & Production Readiness](24-Performance-and-Production-Readiness.md) | Set-based access, paging, mass EML, go-live checklist |
| 25 | [Transport & Deployment](25-Transport-and-Deployment.md) | DEV → QA → PROD, what does **not** transport, post-import checklist |
| 26 | [Anti-Patterns](26-Anti-Patterns.md) | 18 wrong/right pairs, and a review checklist |
| 27 | [Interview Preparation](27-Interview-Preparation.md) | Core and senior questions with spoken answers, plus a revision sheet |

A single concatenated file is also generated — **SAP-RAP-Complete-Guide.md** — and a PDF,
**SAP-RAP-Complete-Developer-Guide.pdf**.

---

## How each chapter is structured

From Chapter 01 onwards, every chapter follows the same shape so you can navigate by position:

| Section | Answers |
|---|---|
| **What is it?** | Definition, in the first paragraph |
| **Why do we need it?** | The problem it solves |
| **Where is it used?** | Which layer / which object |
| **Syntax** | The declarations, with every option |
| **Complete example** | Working code in the running Travel scenario |
| **Runtime behavior** | What actually happens, and when |
| **Common errors** | Symptom → cause → fix |
| **Interview answer** | A concise spoken answer |
| **Production considerations** | What matters once real users and real volume arrive |

Chapters 21–27 follow it strictly. Chapters 01–20 were written before the format was fixed, so the
first sections appear under topic-specific headings, but each one ends with **Interview answer** and
**Production considerations**, and most also carry a **Checklist**.

---

## The running example

```
ZR_TravelTP   (root)          <- a trip booked by an agency for a customer
   +-- _Booking               <- composition (child)
       ZR_BookingTP           <- the individual flight bookings
```

Plus read-only associations to master data: Agency, Customer, Currency, Carrier.

---

## Object naming used throughout (and why)

RAP does not force a naming convention, but SAP's own reference applications use the pattern below.
Using it consistently is the single biggest readability win in a RAP project, because the prefix
tells you **which layer** an object belongs to before you open it.

| Prefix | Layer | Example | Notes |
|--------|-------|---------|-------|
| `Z...` (table) | Database | `ZTRAVEL` | DDIC table or CDS table entity |
| `ZI_` | Basic **I**nterface view | `ZI_Agency` | Reusable, no UI annotations, no behavior |
| `ZR_` + `TP` | **R**oot / interface view for **T**ransactional **P**rocessing | `ZR_TravelTP` | The BO model layer |
| `ZC_` + `TP` | **C**onsumption / projection view | `ZC_TravelTP` | One per service. UI-facing |
| `ZP_` | Alternative for projection | `ZP_TravelTP` | Some teams use `ZP_`; pick one and stay with it |
| `ZBP_` | **B**ehavior **P**ool (ABAP class) | `ZBP_R_TravelTP` | Mirrors the BDEF name |
| `ZSD_` | **S**ervice **D**efinition | `ZSD_TRAVEL` | What is exposed |
| `ZUI_`...`_O4` | Service **B**inding, OData **V4**, **UI** | `ZUI_TRAVEL_O4` | `_O2` for V2, `ZAPI_` for Web API |
| `Z..._D` | Draft table | `ZTRAVEL_D` | One per draft-enabled entity |
| `ZE_` | CDS abstract entity | `ZE_TravelParams` | Action parameters, event payloads |
| `ZI_..._VH` | Value-help provider view | `ZI_AgencyVH` | Chapter 22 |

> **Project note:** keep the existing system's Z/Y prefix habits. If your package already uses
> e.g. `ZGUL_`, prepend it: `ZGUL_R_TravelTP`. Consistency inside the package beats matching SAP demos.

---

## Development objects you will create

For a **full transactional app** with draft, 13 objects:

| # | Object type | ADT: *New ->* | Name in this guide |
|---|---|---|---|
| 1–2 | Database tables | Database Table | `ZTRAVEL`, `ZBOOKING` |
| 3–4 | Draft tables | Database Table *(via `Ctrl + 1` quick fix)* | `ZTRAVEL_D`, `ZBOOKING_D` |
| 5–6 | CDS view entities | Data Definition | `ZR_TravelTP`, `ZR_BookingTP` |
| 7 | Behavior Definition | Behavior Definition | `ZR_TravelTP` |
| 8 | Behavior Implementation class | *(quick fix from BDEF)* | `ZBP_R_TravelTP` |
| 9–10 | CDS projection views | Data Definition | `ZC_TravelTP`, `ZC_BookingTP` |
| 11 | Projection Behavior Definition | Behavior Definition | `ZC_TravelTP` |
| 12 | Metadata Extension | Metadata Extension | `ZC_TravelTP` |
| 13 | Service Definition + Binding | Service Definition / Binding | `ZSD_TRAVEL` / `ZUI_TRAVEL_O4` |

Plus a message class (SE91) and an exception class for translatable messages.
For a **read-only report**, 5 objects and no ABAP — see [Chapter 07](07-ReadOnly-Fiori-Report-Walkthrough.md).

---

## Prerequisites and tooling

- **Eclipse** with ABAP Development Tools (ADT). RAP artifacts (BDEF, service binding, metadata
  extension) **cannot** be created in SAP GUI. SE80 is not an option.
- ABAP Platform **2020+** for managed RAP with draft; **2021+** for `strict ( 2 )`, entity-level
  `with unmanaged save`, and RAP business events.
- `S_DEVELOP` plus a transport request, and a real development package — not `$TMP`.
- For the Fiori Elements preview: the service binding's **Publish** then **Preview**.

### The three keyboard shortcuts that matter

| Shortcut | What it does |
|---|---|
| `Ctrl + 1` | Quick Fix — generates behavior pools, handler and saver methods, draft tables |
| `Ctrl + Shift + A` | Open ABAP development object |
| `F3` | Navigate to definition — follow `redirected to`, associations, includes |

`Ctrl + 1` is not optional knowledge. **Almost every method skeleton in RAP is generated by it**, and
the generated artifact is authoritative for your release in a way that a document cannot be.

---

## Sources

The declarative syntax in this documentation was verified against:

- [SAP Help — ABAP RESTful Application Programming Model](https://help.sap.com/docs/abap-cloud/abap-rap)
- [SAP-samples/abap-cheat-sheets — RAP Behavior Definition Language](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/36_RAP_Behavior_Definition_Language.md)
- [SAP-samples/abap-cheat-sheets — EML / ABAP for RAP](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/08_EML_ABAP_for_RAP.md)
- [SAP-samples/abap-platform-rap-workshops — RAP610 unmanaged save exercise](https://github.com/SAP-samples/abap-platform-rap-workshops/blob/main/rap6xx/rap610/exercises/ex4/README.md)
- [SAP Help — Defining Unmanaged Save in the Behavior Definition](https://help.sap.com/docs/abap-cloud/abap-rap/defining-unmanaged-save-in-behavior-definition)
- [SAP Help — Save Options](https://help.sap.com/docs/abap-cloud/abap-rap/save-options)
- [SAP Help — Implementing the Interaction Phase and the Save Sequence](https://help.sap.com/docs/abap-cloud/abap-rap/implementing-interaction-phase-and-save-sequence)
- [ABAP Keyword Documentation — check_before_save, RAP Saver Method](https://help.sap.com/doc/abapdocu_cp_index_htm/CLOUD/en-US/abensaver_check_before_save.htm)
- The **ABAP Flight Reference Scenario** (`/DMO/` packages) shipped with the system
