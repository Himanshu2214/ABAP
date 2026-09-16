# Chapter 24 — Performance and Production Readiness

[< Testing & Debugging](23-Testing-and-Debugging.md) | [Index](00-README.md) | [Next: Transport & Deployment >](25-Transport-and-Deployment.md)

---

## 24.1 What is it?

The set of design and coding decisions that determine whether a RAP application that works in DEV
with 200 rows still works in PROD with 20 million.

Almost all RAP performance problems fall into five categories:

| # | Category | Typical cost |
|---|---|---|
| 1 | Row-by-row database access inside a loop | N round trips instead of 1 |
| 2 | Reading more than you need (`ALL FIELDS`, unfiltered lists) | Large result sets, memory |
| 3 | Work done per instance that could be done per set (authorization, feature control) | N `AUTHORITY-CHECK`s |
| 4 | Joins and associations with wrong cardinality | Row multiplication |
| 5 | Chatty UI (over-declared side effects, uncontrolled `$expand`) | Round trips |

---

## 24.2 Why do we need it?

Because RAP hides the database. The framework issues the SQL, so a developer can write a perfectly
reasonable-looking determination that turns into 5,000 `SELECT SINGLE`s at runtime and never notice
until a user opens the app with a full year of data.

---

## 24.3 Set-based reads and updates

### The rule

**Never access the database or the transactional buffer once per instance.** Collect keys, act once.

```abap
" ---------- WRONG: one SELECT per instance ----------
LOOP AT travels INTO DATA(travel).
  SELECT SINGLE customer_id FROM /dmo/customer
    WHERE customer_id = @travel-CustomerId
    INTO @DATA(found).
  IF sy-subrc <> 0.
    APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
  ENDIF.
ENDLOOP.
```

With 5,000 travels this is 5,000 database round trips.

```abap
" ---------- RIGHT: one SELECT for the whole set ----------
DATA(customers) = travels.
SORT customers BY CustomerId.
DELETE ADJACENT DUPLICATES FROM customers COMPARING CustomerId.
DELETE customers WHERE CustomerId IS INITIAL.

IF customers IS NOT INITIAL.
  SELECT FROM /dmo/customer
    FIELDS customer_id
    FOR ALL ENTRIES IN @customers
    WHERE customer_id = @customers-CustomerId
    INTO TABLE @DATA(valid_customers).
ENDIF.

LOOP AT travels INTO DATA(travel).
  IF NOT line_exists( valid_customers[ customer_id = travel-CustomerId ] ).
    APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
  ENDIF.
ENDLOOP.
```

One round trip, and the `LOOP` is now pure in-memory work.

> For very large key sets, prefer a **range table** (`FOR ALL ENTRIES` has its own pitfalls: it
> de-duplicates, it returns nothing for an empty driver table, and it can be split into several
> statements by the database interface). Always guard with `IF ... IS NOT INITIAL`.

### The same rule for EML

```abap
" WRONG - 5000 EML statements and 5000 save sequences
LOOP AT uuids INTO DATA(uuid).
  MODIFY ENTITIES OF zr_traveltp ENTITY Travel
    UPDATE FIELDS ( OverallStatus )
    WITH VALUE #( ( %tky-TravelUUID = uuid %tky-%is_draft = if_abap_behv=>mk-off
                    OverallStatus = 'A' ) ).
  COMMIT ENTITIES.
ENDLOOP.

" RIGHT - one statement, one save sequence
MODIFY ENTITIES OF zr_traveltp ENTITY Travel
  UPDATE FIELDS ( OverallStatus )
  WITH VALUE #( FOR u IN uuids ( %tky-TravelUUID = u
                                 %tky-%is_draft  = if_abap_behv=>mk-off
                                 OverallStatus   = 'A' ) ).
COMMIT ENTITIES.
```

### Internal table access

Inside the loop, `line_exists( tab[ key = x ] )` on a **standard** table is a linear scan — so the
"fixed" version above is still O(n×m). For large sets, use a sorted or hashed table:

```abap
DATA valid_customers TYPE HASHED TABLE OF /dmo/customer_id WITH UNIQUE KEY table_line.
" ... fill it once ...
IF line_exists( valid_customers[ table_line = travel-CustomerId ] ).   " O(1)
```

---

## 24.4 Reading only what you need

| Instead of | Write | Saves |
|---|---|---|
| `ALL FIELDS WITH ...` | `FIELDS ( F1 F2 ) WITH ...` | Columns, memory, network |
| `RESULT DATA(children)` when you only need existence | `LINK DATA(links)` | The entire child read |
| Exposing 60 fields in the projection | Expose the 15 the app uses | Every read, every `$expand` |
| Several `READ ENTITIES` statements | One statement with several `ENTITY` blocks | Framework round trips |

```abap
" one statement, two reads
READ ENTITIES OF zr_traveltp IN LOCAL MODE
  ENTITY Travel
    FIELDS ( BookingFee CurrencyCode ) WITH CORRESPONDING #( keys )
    RESULT DATA(travels)
  ENTITY Travel BY \_Booking
    FIELDS ( FlightPrice CurrencyCode ) WITH CORRESPONDING #( keys )
    RESULT DATA(bookings)
  FAILED DATA(failed).
```

`ALL FIELDS` is correct in exactly one common place: building an action `result` that must return
the complete instance.

---

## 24.5 Filtering, paging and the List Report

### Mandatory filters

The single highest-value performance annotation in a report:

```abap
@Consumption.filter: { selectionType: #INTERVAL, mandatory: true }
CreationDate,
```

Without it, opening the List Report issues an unrestricted `SELECT` on the base table. On `VBAP`
that is the difference between 0.4 seconds and a timeout.

Make mandatory the field that is **most selective and most natural** for the user — usually a date
range, a plant, or a sales organisation.

### Paging

OData paging (`$top` / `$skip`) is automatic and is pushed to the database. You do not implement it.
What you can break:

| Breaks paging | Why |
|---|---|
| Sorting or filtering on a **virtual element** | Calculated in ABAP after the read, so the full result set must be fetched first |
| A projection `where` clause on a non-indexed field | Full scan before paging |
| Client-side aggregation | Same |

**Virtual elements are display-only.** If a field must be filterable or sortable, calculate it in
the interface view in CDS so HANA can push it down.

### `$expand`

`GET /Travel?$expand=_Booking` reads every child of every travel on the page. On a header with
hundreds of items this is expensive, and Fiori Elements does it automatically for an Object Page.

- Keep child projections narrow.
- Do not expose grandchildren in a service that does not display them.
- Check the actual request in DevTools → Network; the `$expand` the UI sends is often wider than
  you assumed.

### Search annotations

```abap
@Search.searchable: true
@Search.defaultSearchElement: true
@Search.fuzzinessThreshold: 0.8
```

Fuzzy search is a real HANA feature and costs real CPU. Enable it on the one or two text fields
where it helps (a description, a name) — not on codes, dates or every field in the view.

---

## 24.6 Associations vs joins

| | Association | Join |
|---|---|---|
| Executed | Only when used (lazy) | Always |
| Cost when unused | **Zero** | Full |
| Risk of row multiplication | Only when used, and visible | Silent |
| Use for | Optional navigation, value help, texts | Fields needed on **every** row |

Exposing ten associations on an interface view costs nothing. Adding ten `LEFT OUTER JOIN`s costs
every read.

### The cardinality trap

```abap
association [0..1] to ZI_Something as _S on ...    " declared 0..1
```

If the underlying data actually has several matching rows, CDS does **not** enforce the `[0..1]`.
Using the association in a path expression then **multiplies rows** — silently. Row counts that
are a suspiciously round multiple of what you expect are the symptom.

Verify cardinalities with Data Preview and a `COUNT(*)` comparison (Chapter 23, §23.4).

---

## 24.7 Authorization and feature-control performance

These handlers run for **every instance the user touches** — including every row a List Report
displays, when the UI asks about permissions. They are the most commonly overlooked hot path in RAP.

```abap
" WRONG - one AUTHORITY-CHECK per row
LOOP AT travels INTO DATA(travel).
  AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH'
    ID 'AGENCY_ID' FIELD travel-AgencyId
    ID 'ACTVT'     FIELD '02'.
  ...
ENDLOOP.
```

```abap
" RIGHT - one check per DISTINCT agency, then a hashed lookup
DATA(agencies) = travels.
SORT agencies BY AgencyId.
DELETE ADJACENT DUPLICATES FROM agencies COMPARING AgencyId.

DATA authorized TYPE HASHED TABLE OF /dmo/agency_id WITH UNIQUE KEY table_line.
LOOP AT agencies INTO DATA(agency).
  AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH'
    ID 'AGENCY_ID' FIELD agency-AgencyId
    ID 'ACTVT'     FIELD '02'.
  IF sy-subrc = 0.
    INSERT agency-AgencyId INTO TABLE authorized.
  ENDIF.
ENDLOOP.

LOOP AT travels INTO DATA(travel).
  DATA(ok) = xsdbool( line_exists( authorized[ table_line = travel-AgencyId ] ) ).
  ...
ENDLOOP.
```

Also:

- **Guard on `requested_authorizations`/`requested_features`.** The framework asks about only what
  it needs; evaluating everything on every call is wasted work.
- **Declare `affects permissions` sparingly.** Each one triggers a permissions round trip
  (Chapter 21, §21.9).

---

## 24.8 Determinations and validations

| Rule | Why |
|---|---|
| Move expensive checks to `on save` | They then run **once per transaction**, not after every change |
| Make determinations idempotent (`DELETE tab WHERE <already set>`) | Fewer writes, and correctness |
| `CHECK tab IS NOT INITIAL` before `MODIFY ENTITIES` | An empty modify still costs a framework round trip |
| One determination triggered by several fields, not several determinations | Fewer framework callbacks |
| Never call an external service (HTTP, RFC) from `on modify` | Runs on every keystroke-level change |
| Avoid indirect determination cycles | A → B → A loops until the iteration limit, then dumps |

---

## 24.9 Draft, locking and EML at scale

### Draft

- Drafts accumulate. **Schedule the standard draft clean-up job** — see Chapter 11, §11.8. Without
  it the draft tables grow without bound.
- Never `SELECT` or `DELETE` on a draft table directly; use `EXECUTE Discard`.
- For an entity with very many columns and rows, weigh the cost of the second table before enabling
  draft.

### Lock duration

- A draft holds an **exclusive lock** from Edit until Save/Cancel, and beyond — it survives the
  session ending and expires on a timeout. A user who opens a document and goes to lunch blocks
  everyone else.
- Keep the lock timeout aligned with how long an edit realistically takes.
- Use `( lock : none )` on read-only actions so they do not lock.
- `SET LOCKS` before expensive preparation, so you fail fast rather than after doing the work.

### Large-volume EML processing

```abap
DATA(chunk_size) = 1000.
DATA(offset) = 0.

WHILE offset < lines( all_uuids ).
  DATA(chunk) = VALUE ztravel_tky_tab( ).
  LOOP AT all_uuids INTO DATA(u) FROM offset + 1 TO offset + chunk_size.
    APPEND VALUE #( TravelUUID = u %is_draft = if_abap_behv=>mk-off ) TO chunk.
  ENDLOOP.

  MODIFY ENTITIES OF zr_traveltp PRIVILEGED
    ENTITY Travel EXECUTE acceptTravel FROM chunk
    FAILED DATA(failed) REPORTED DATA(reported).

  COMMIT ENTITIES RESPONSE OF zr_traveltp FAILED DATA(commit_failed).
  IF sy-subrc = 8.
    ROLLBACK ENTITIES.
  ENDIF.

  " log per chunk, then continue
  offset += chunk_size.
ENDWHILE.
```

Why chunk:

| Reason | Detail |
|---|---|
| Buffer size | The whole chunk lives in memory until commit |
| Lock table | Every instance holds a lock entry until commit; a 500,000-row commit can exhaust it |
| Restartability | A failure loses one chunk, not the whole run |
| Progress reporting | A job with no visible progress is unsupportable |

1,000–5,000 is a reasonable starting range; tune with measurement, not intuition.

### Background jobs

- Use `PRIVILEGED` deliberately, and document why — it bypasses authorization.
- Use `GET PERMISSIONS` **before** acting to filter out instances the job may not touch, rather than
  attempting each and handling failures.
- Never create drafts from a job. Jobs write active instances directly.
- Write an application log (`SLG1`) per run: started, chunk results, failures, finished.
- Make the job restartable and idempotent — re-running after a failure must not double-process.

---

## 24.10 A performance checklist for go-live

- [ ] At least one **mandatory, selective filter** on every List Report over a large table.
- [ ] No `SELECT` inside a `LOOP` anywhere in the behavior pool.
- [ ] No `SELECT` on the BO's own tables at all (use EML).
- [ ] `FIELDS ( ... )` rather than `ALL FIELDS` except where the full instance is genuinely needed.
- [ ] `LINK DATA( )` where only existence is needed.
- [ ] `AUTHORITY-CHECK` performed per distinct value, not per row.
- [ ] Handlers guard on `requested_authorizations` / `requested_features`.
- [ ] Virtual elements are display-only; nothing filterable or sortable depends on one.
- [ ] Association cardinalities verified against real data (no row multiplication).
- [ ] Expensive logic is `on save`, not `on modify`.
- [ ] No external calls (HTTP/RFC) in `on modify`, and none at all in the late save phase.
- [ ] `side effects` targets are as narrow as possible; `affects permissions` used sparingly.
- [ ] EML mass processing is chunked and restartable.
- [ ] Draft clean-up job scheduled.
- [ ] `ST05` trace of one List Report page load reviewed.
- [ ] ATC run with the HANA-readiness variant, findings triaged.
- [ ] `SQLM` enabled for a window after go-live.
- [ ] Tested with production-like data volume in QA.

---

## 24.11 Common errors

| Symptom | Likely cause |
|---|---|
| List Report times out on open | No mandatory filter |
| App fast in DEV, slow in PROD | Data volume; or DCL adding an expensive filter on a non-indexed field |
| Save is slow with many items | `SELECT` inside a loop in a determination or validation |
| Opening the list is slow but scrolling is fast | Instance authorization / feature control running per row |
| Row counts are a multiple of what you expect | Association cardinality wrong |
| Sorting on one column is far slower than others | It is a virtual element |
| Memory dump (`TSV_TNEW_PAGE_ALLOC_FAILED`) in a job | Unchunked mass EML |
| Lock table overflow | Commit interval too large |
| Draft tables enormous | No clean-up job |
| UI feels laggy on every keystroke | Over-declared side effects |

---

## 24.12 Interview answer

> **"How did you optimize CDS and EML performance?"**
>
> Mainly by keeping everything set-based and pushing work to the database.
>
> In CDS: associations rather than joins, because an association is lazy and costs nothing when it
> is not used; calculations in the interface view rather than as virtual elements, because a virtual
> element is computed in ABAP after the read and therefore cannot be filtered or sorted on HANA;
> and a mandatory, selective filter on any List Report over a large table — that one annotation is
> usually the difference between a sub-second report and a timeout.
>
> In the behavior pool: no `SELECT` inside a loop. I collect the distinct foreign keys, do one
> `SELECT ... FOR ALL ENTRIES`, and then use a hashed internal table for the lookup. The same
> applies to `AUTHORITY-CHECK` — one check per distinct authorization value, not per row, because
> instance authorization and feature control run for every row the list displays.
>
> In EML: one statement for many instances rather than a statement per instance, `FIELDS ( )`
> instead of `ALL FIELDS`, `LINK` instead of `RESULT` when I only need to know whether children
> exist, and chunked commits — around a thousand instances — for mass processing, so the
> transactional buffer and the lock table stay bounded and the job is restartable.
>
> To find problems I use `ST05` on a single page load — repeated identical statements immediately
> expose a SELECT in a loop — and `SQLM` in production because it is low-overhead and tells you
> what is actually slow rather than what you guessed.

---

## 24.13 Production considerations

Beyond performance, the things that decide whether an app survives contact with production:

| Area | Requirement |
|---|---|
| **Volume testing** | QA must hold a production-like data subset. A 200-row DEV test proves nothing |
| **Real roles** | Test with the actual PFCG roles, never `SAP_ALL` |
| **Monitoring** | Application log per background job; `SQLM` window after go-live; a dump-check routine |
| **Housekeeping** | Draft clean-up job; application-log deletion job; archiving strategy for the BO's own tables |
| **Restartability** | Every job restartable and idempotent |
| **Error visibility** | Failures must reach a human — a job that logs to `SLG1` and nothing else will be ignored |
| **Capacity** | Lock table sizing if you do mass processing; work-process availability for long jobs |
| **Documentation** | The commit chunk size, the mandatory filter, and the lock timeout are all decisions the next developer must not undo blindly |

---

[< Testing & Debugging](23-Testing-and-Debugging.md) | [Index](00-README.md) | [Next: Transport & Deployment >](25-Transport-and-Deployment.md)
