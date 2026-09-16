# Chapter 27 — Interview Preparation

[< Anti-Patterns](26-Anti-Patterns.md) | [Index](00-README.md)

---

## 27.1 How to use this chapter

Two sections:

- **27.3 Core questions** — knowledge questions with a concise spoken answer, plus the follow-up the
  interviewer will ask next.
- **27.4 Experience questions** — "how did *you* do X". These are about **your** project, so what
  follows is the **shape** of a strong answer plus a worked example based on this guide's running
  scenario. Fill in your own specifics; do not recite someone else's project.

Three rules for delivery:

1. **Answer in three layers**: one sentence of definition, two or three of mechanism, one of
   trade-off or gotcha. Then stop. Interviewers interrupt when they want more.
2. **Name the failure mode.** Saying *"a validation that fills `reported` but not `failed` shows an
   error and saves anyway"* signals real experience more than any definition does.
3. **Say what you do not know.** "I have used managed and managed-with-unmanaged-save; I have read
   about full unmanaged but not built one" is a better answer than a confident wrong one.

---

## 27.2 The two-minute overview

If you get exactly one question, it will be this one.

> RAP is SAP's programming model for building OData services and Fiori apps on the ABAP platform.
> You define the data model in CDS, declare the transactional behavior in a behavior definition,
> and implement the business logic in an ABAP behavior pool. The framework handles the transaction,
> the buffer, locking, ETags, draft and the OData protocol.
>
> The layers are: database table, CDS interface view (the business object model), behavior
> definition plus behavior pool (the behavior), CDS projection view plus projection behavior
> definition (the service-specific subset), metadata extension (the UI layout), and service
> definition plus service binding (what is exposed, and over which protocol).
>
> The big shift from classic ABAP is that it is **declarative first**. Locking is one word,
> `lock master`. Optimistic concurrency is one word, `etag master`. Draft is one word. If you find
> yourself writing a lot of code for something RAP offers declaratively, you are fighting the
> framework.

---

## 27.3 Core questions

### 1. What is RAP?

> See 27.2. Keep it to the layer stack plus the "declarative first" point.

**Follow-up:** *"Which layer would you put a validation in?"* → the **base** behavior definition, so
every consumer gets it, not just one service.

---

### 2. Managed versus unmanaged RAP

> They are implementation types declared in the behavior definition header. The difference is who
> provides the **transactional buffer** and who performs the **save**.
>
> In a **managed** BO the framework does both. You declare `persistent table`, and create, update,
> delete and read work out of the box. You only write the business logic — validations,
> determinations, actions.
>
> In an **unmanaged** BO you provide everything: your own buffer, and handler methods for
> `FOR READ`, `FOR MODIFY` create/update/delete, `FOR LOCK`, read-by-association and
> create-by-association, plus a saver class that persists the buffer.
>
> Managed is for greenfield development. Unmanaged is for wrapping **existing transactional logic**
> you must reuse — existing locking, existing update-task modules. Existing *tables* are not a
> reason: `persistent table` accepts any table.
>
> There are also two hybrids: `managed with additional save`, where the framework still persists the
> BO and your `save_modified` does extra work such as change documents or business events, and
> `managed with unmanaged save`, where you take over persistence — for example to write through a
> BAPI — but keep the managed buffer, locking, ETag and draft.

**Follow-up:** *"How much more code is unmanaged?"* → roughly an order of magnitude for the same
CRUD. The field-selective `%control` handling alone is one `IF` block per field per entity.

---

### 3. Why use a projection view? / 4. Interface vs projection

> The interface view, `ZR_...`, is the business object model: the fields, the composition tree, the
> associations, the semantic annotations. It is neutral and reusable — no UI annotations, nothing
> service-specific.
>
> The projection view, `ZC_...`, is a **service-specific window** onto that model, written with
> `as projection on`. It exposes a subset of fields, carries the value helps and the
> `@Consumption` annotations, and is the attachment point for the metadata extension and the DCL.
>
> Three reasons for the split. First, one business object can serve several services with different
> fields and different enabled operations — a manager app and a self-service app. Second, you can
> add a field to the model without touching any running service. Third, it keeps business semantics
> and presentation in different layers.
>
> The projection behavior definition follows the same logic: it contains `use create`, `use update`,
> `use action X` and so on. An operation or action not listed there does not exist in that service,
> no matter what the base behavior definition says.

**Follow-up:** *"What can a projection BDEF not do?"* → it can only subset. It cannot add `create` if
the base has none, and it cannot change locking, ETag, authorization or numbering.

---

### 5. Purpose of a behavior definition

> It is the contract of the business object, written in BDL. It declares the implementation type,
> the persistent and draft tables, locking, ETag, authorization, which operations exist, field
> characteristics such as `readonly` and `mandatory`, create-by-association, validations,
> determinations, actions, side effects, the draft actions, and the mapping between CDS element
> names and database field names.
>
> It is a declaration, not code. The behavior pool implements what it declares.

**Follow-up:** *"What does `strict ( 2 )` do?"* → turns on the strictest syntax and semantic checks:
mandatory lock and authorization declarations, `%tky` instead of `%key` in draft scenarios, stricter
feature control and EML checks. Every error it raises on a legacy BDEF is a real latent defect.

---

### 6. What is a behavior pool?

> A global class declared `FOR BEHAVIOR OF <bdef>`. It is `ABSTRACT FINAL` because the RAP runtime
> instantiates the local classes inside it, never the global class.
>
> The real content is in the local types: one or more **handler** classes inheriting
> `CL_ABAP_BEHAVIOR_HANDLER`, which implement the interaction phase — determinations, validations,
> actions, feature control, authorization — and, where needed, a **saver** class inheriting
> `CL_ABAP_BEHAVIOR_SAVER`, which implements the save sequence.
>
> The global class's public section is also the only supported channel between the handler and the
> saver, since they are separate classes. If you use `CLASS-DATA` for that, you have to clear it in
> both `cleanup` and `cleanup_finalize` — it lives for the whole session, not the transaction.

---

### 7. Validations and determinations

> Both are declared in the behavior definition with a trigger time and a trigger condition, and
> implemented in the behavior pool.
>
> A **determination** derives data: it fills a field automatically. A **validation** checks data and
> rejects it. A validation must never change data.
>
> The trigger time is `on modify` or `on save`. `on modify` runs during the interaction phase,
> immediately after the triggering change; `on save` runs in the early save phase — determinations
> when `finalize` is reached, validations when `check_before_save` is reached.
>
> Practically: determinations the user should see live are `on modify`; anything that consumes a
> scarce resource, like a number range, is `on save`, otherwise every discarded draft burns a
> number. Validations are almost always `on save`, because an `on modify` validation nags the user
> while they are still typing.
>
> The gotcha worth mentioning: a validation blocks the save by adding the key to **`failed`**.
> A message in `reported` alone shows a red error and saves the record anyway.

**Follow-up:** *"Is the order of two validations guaranteed?"* → no. Order within a phase is not
guaranteed, so validations must be independent of each other.

---

### 8. Draft handling

> A draft is a second copy of the instance, stored in its own draft table, that the user edits
> before committing. Both rows share the same key and are distinguished by `IsActiveEntity` — which
> is why the RAP transactional key is `%tky`, the key plus `%is_draft`.
>
> You enable it with `with draft;` in the header, a `draft table` per entity, `total etag`, and the
> four draft actions: `Edit`, `Activate`, `Discard`, `Resume`. Plus `draft determine action Prepare`,
> which lists the validations that should run **while** the draft is open so errors appear inline
> rather than only at save.
>
> Locking has two phases. From `Edit`, the active instance holds an **exclusive** lock that survives
> the session ending and expires on a timeout. After that the **optimistic** phase begins: others
> can edit, and when the original user resumes, RAP compares the draft's stored **total ETag** with
> the active instance's. If they differ, the draft is declared outdated. That is what `total etag`
> is for, and why it should be a different field from `etag master`.
>
> Draft is a UI concept. A background job or an API creates active instances directly.

**Follow-up:** *"When would you not use draft?"* → APIs and jobs; high-frequency single-field
updates where the round trips cost more than the operation; very wide, very large entities where a
second table is expensive.

---

### 9. What is EML?

> Entity Manipulation Language — the ABAP statements for calling a RAP business object:
> `READ ENTITIES`, `MODIFY ENTITIES`, `COMMIT ENTITIES`, `ROLLBACK ENTITIES`, `GET PERMISSIONS`,
> `SET LOCKS`, `RAISE ENTITY EVENT`, and `CONVERT KEY` for late numbering.
>
> It is the only supported way to talk to a RAP BO from ABAP. You do not `SELECT` the BO's tables
> and you do not call your own OData service over HTTP.
>
> Inside a behavior pool you always add `IN LOCAL MODE`: it goes straight to the transactional
> buffer, skips authorization and feature control, and — importantly — lets you write `readonly`
> fields, which is how a determination sets a field the consumer may not touch. Outside the BO you
> never use it, because you want those checks.
>
> And `COMMIT ENTITIES` is only ever issued by whoever owns the transaction — the RAP runtime for
> OData, or your own report or job. Never inside a handler or saver.

---

### 10. `%cid`, `%tky`, `%pid`, `%control`

> `%cid` is the **content ID** — a name you invent for an instance that does not have a key yet. On
> create you send a `%cid`; the framework reports back through `mapped` which real key it assigned.
> In a deep create, the child uses `%cid_ref` to say which `%cid` is its parent, and `%target` to
> carry the children. That is how you create a document with its items in one statement.
>
> `%tky` is the **transactional key**: the key plus `%is_draft`. In a draft-enabled BO you always
> use `%tky`, never `%key`, because the same key exists twice — once active, once draft. Using
> `%key` reads the wrong copy, which usually looks like "my determination sees old data".
>
> `%pid` is a **preliminary ID** in late-numbering scenarios. The instance gets a real key only in
> the save sequence, and you resolve `%pid` to the real key with `CONVERT KEY`, which is only legal
> inside `save_modified`.
>
> `%control` is a set of **per-field flags** saying which fields the consumer actually sent, using
> `if_abap_behv=>mk-on` / `mk-off`. A managed BO honours it automatically. In an unmanaged BO or an
> unmanaged save you must respect it yourself — otherwise a user who edits one field has every other
> field overwritten with initial values.

---

### 11. `failed`, `reported`, `mapped`

> The three RAP response parameters. Every handler method has them as implicit changing parameters.
>
> **`failed`** says *which instances could not be processed*. Adding a key to `failed` is what
> actually blocks the operation.
>
> **`reported`** carries the *messages* — the text, severity, and optionally `%element-<Field>` so
> Fiori highlights the right field, and `%state_area` for messages that persist until cleared.
>
> **`mapped`** carries *key mapping information* — which real key was assigned to which `%cid`. It
> only applies to create operations. A managed BO fills it; in an unmanaged BO or a factory action
> you fill it yourself, and if you forget, the consumer cannot address the new instance and the UI
> cannot navigate to it.
>
> The pairing matters: for an error, fill both `failed` and `reported`. `failed` without `reported`
> blocks the save and tells the user nothing; `reported` without `failed` shows an error and saves
> anyway. For a warning, fill `reported` only — deliberately.

---

### 12. When do you use additional save?

> When the framework's persistence is correct and you need **extra work at save time**: writing a
> change document, an application log entry, raising a RAP business event, registering an
> update-task module, or enqueueing an outbound message. You declare
> `managed with additional save` and implement `save_modified`, which gives you the created, updated
> and deleted instances — including `%control`, so you can tell which fields actually changed.
>
> The contrast is `with unmanaged save`, where you take over persistence entirely: the framework
> does not write the table, and you must remove `persistent table` from the behavior definition.
> That is for persisting through a BAPI, into an external store, or when you need `CONVERT KEY` for
> a late-numbering API — because `CONVERT KEY` is only legal in `save_modified`.
>
> One rule applies to both: the late save phase must not fail. Anything that can fail belongs in
> `check_before_save`, while the transaction is still recoverable.

---

### 13. What is the RAP save sequence?

> A RAP transaction has two phases. During the **interaction phase**, handler methods run and
> changes go into the transactional buffer; the database is untouched and the buffer may be
> temporarily inconsistent.
>
> Then `COMMIT ENTITIES` — issued implicitly by the RAP runtime in a Fiori scenario — triggers the
> **save sequence**, which splits in two.
>
> The **early save phase** runs `finalize`, where `on save` determinations execute and it is the
> last place data may be changed; then `check_before_save`, where `on save` validations execute and
> which is the last gate. If either reports a failure, `cleanup_finalize` runs and the transaction
> returns to the interaction phase — `sy-subrc` is 4 after `COMMIT ENTITIES` and it is recoverable.
>
> Then comes the **point of no return**, and the **late save phase**: `adjust_numbers` for late
> numbering, then `save` or `save_modified`, then the implicit `COMMIT WORK`, then `cleanup` clears
> the buffer.
>
> The design principle is that everything which can fail must fail in the early phase. A failure
> after the point of no return is a runtime error unless you inherit from
> `CL_ABAP_BEHAVIOR_SAVER_FAILED`, in which case `sy-subrc` is 8 and the consumer must issue an
> explicit `ROLLBACK ENTITIES`.

**Follow-up:** *"Where can you do database updates?"* → in the late save phase, and only where you
own persistence at all. In a plain managed BO you write no persistence code; the framework does it.
Reads are allowed everywhere; commits on a **secondary** connection — number ranges, application
logs — are allowed in every phase, which is why a number range is legal in an `on save` determination.

---

### 14. How do you implement actions?

> Four steps, and missing any one fails silently in a different way.
>
> One: declare it in the base behavior definition — `action acceptTravel result [1] $self;`.
> `result [1] $self` returns the changed instance so the UI repaints without an extra round trip.
> Two: implement the handler method, generated with `Ctrl + 1` — read the instances, apply the
> change with `MODIFY ENTITIES ... IN LOCAL MODE`, fill `result`. Three: expose it in the projection
> behavior definition with `use action acceptTravel;`. Four: annotate it in the metadata extension
> with `@UI.lineItem: [{ type: #FOR_ACTION, dataAction: 'acceptTravel', label: '...' }]`.
>
> The step people forget is three. Without `use action`, the button never appears and there is no
> error anywhere.
>
> Variants: `static action` is not bound to an instance; `factory action` creates instances and must
> fill `mapped`; `internal action` is callable only from inside the BO; a `function` is read-only
> and uses `FOR READ` rather than `FOR MODIFY`. An action can take a `parameter` typed by a CDS
> abstract entity, which Fiori renders as a dialog — and you must validate those parameters inside
> the action, because `validation` only fires on entity fields.
>
> Enabling and disabling per instance is `( features : instance )` plus a `FOR INSTANCE FEATURES`
> handler — but that is a UI hint, not security. Authorization for the action belongs in
> `FOR INSTANCE AUTHORIZATION`.

---

### 15. How do you handle authorization?

> Four mechanisms, and the interview point is that they are not interchangeable.
>
> **DCL** — CDS access control — filters **reads**. `@AccessControl.authorizationCheck: #CHECK` plus
> a role with `aspect pfcg_auth(...)` restricts which rows a user sees. Which layer it goes on
> depends on the design: projection-level when different services need different restrictions,
> interface-level when the restriction is an invariant of the model. DCL does **not** stop an update
> or a delete.
>
> **Global authorization**, `FOR GLOBAL AUTHORIZATION`, answers "may this user create at all" —
> instance-independent.
>
> **Instance authorization**, `FOR INSTANCE AUTHORIZATION`, answers "may this user change *this*
> instance" — typically an `AUTHORITY-CHECK` on a field of the row. It returns `auth-allowed` or
> `auth-unauthorized` per operation, per action, per association.
>
> **Feature control** is different in kind. It answers "does this apply right now" — an accepted
> document cannot be accepted again. It uses the `fc-o-` and `fc-f-` constants and it is a **UI
> hint only**: the OData call still reaches the backend and still succeeds. Never implement a
> security rule as feature control.
>
> Performance is worth mentioning: instance authorization runs for every row the list displays, so
> do one `AUTHORITY-CHECK` per distinct value and then a hashed lookup, and guard on
> `requested_authorizations` so you only evaluate what the framework asked about.

---

### 16. How do you expose a RAP BO through OData V4?

> Two objects. A **service definition** lists what is exposed — `expose ZC_TravelTP as Travel;` —
> including every child entity and every value-help and text entity, otherwise the F4 comes back
> empty. Then a **service binding** of type *OData V4 - UI* over that definition, which you activate
> and then **Publish**; publishing generates the runtime artifacts and the service URL, and gives you
> the Fiori Elements preview.
>
> One service definition can feed several bindings — for example a V4 UI binding for a Fiori app and
> a V4 Web API binding for machine-to-machine integration, where the UI annotations are stripped out.
>
> The prerequisite on the CDS side is `provider contract transactional_query` on the root projection
> and a projection behavior definition. Leave the contract off and you get a read-only service, which
> is exactly what you want for a report.
>
> For deployment, the binding object transports but I treat **publishing in the target system** as an
> explicit post-import step, and on-premise you also need the ICF node active and the Launchpad
> content and roles in place.

---

## 27.4 Experience questions

These are about your project. Below is the **shape** of a strong answer, then a worked example based
on this guide's scenario. Replace the example with yours.

---

### Why did you choose managed RAP for your project?

**Shape:** state the decision criteria, then how your project scored against them, then what you would
have chosen otherwise.

> The deciding question is whether there is existing **transactional logic** to reuse — an existing
> buffer, existing locking, existing update-task modules. If there is, unmanaged. If not, managed.
> Existing tables on their own are not a reason, because `persistent table` accepts any table.
>
> In our case it was greenfield on our own Z tables with no legacy logic, so managed. That gave us
> CRUD, UUID key generation, the five admin fields, locking, ETag and draft declaratively, and we
> only wrote the business logic — three determinations, three validations and two actions, about
> 200 lines. Unmanaged would have been roughly an order of magnitude more code for the same result.
>
> We did use `managed with additional save` for one piece: writing an application log entry and
> raising an event on status change, which has to happen in the late save phase. And if the
> persistence itself had needed to go through a released API, the answer would have been
> `managed with unmanaged save` rather than a full unmanaged BO.

---

### Why not SEGW?

> SEGW is the classic Gateway Service Builder. It generates an OData **V2** service where you
> implement CRUD by redefining methods in a `DPC_EXT` class — `GET_ENTITYSET`, `CREATE_ENTITY` and
> so on. There is no transactional framework: no buffer, no draft, no declarative locking or ETag,
> no validation or determination concept. Everything is hand-written, and the Fiori annotations live
> in a separate annotation model rather than coming from CDS.
>
> RAP gives all of that declaratively, targets OData V4, and is the model that is ABAP Cloud
> compliant — SEGW is not available in the restricted ABAP language scope, so anything built in it
> is a dead end for a move to the cloud or a clean-core strategy.
>
> The honest caveat is that SEGW still exists for maintaining older services, and if you have to
> extend an existing V2 service consumed by an app you do not control, you extend it rather than
> rewrite. But for new development there is no case for it.

---

### How did you handle locking and ETags?

**Shape:** say they solve different problems, then name your declarations, then the draft nuance.

> They are complementary, not alternatives. The lock is **pessimistic** — it stops a second user
> starting an edit. The ETag is **optimistic** — it stops a stale write at the moment of saving.
>
> We declared `lock master` on the root and `lock dependent by _Travel` on the child, so the whole
> composition tree locks together, and the managed runtime acquires and releases it automatically.
>
> For the ETag, `etag master LocalLastChangedAt`, with
> `@Semantics.systemDateTime.localInstanceLastChangedAt: true` on the field and `readonly` in the
> behavior definition, so the framework maintains it. The client gets it as an HTTP ETag and sends
> it back in `If-Match`; a stale value is rejected. And `use etag` in the projection behavior
> definition — without that the protection is silently off for that service.
>
> Because we use draft we also needed `total etag LastChangedAt`, on a **different** field. That
> covers draft resumability: the exclusive lock expires after a timeout, and after that RAP compares
> the draft's stored total ETag against the active instance to decide whether the draft is still
> resumable.
>
> We tested the ETag case over HTTP rather than through EML, because the comparison happens in the
> OData layer — `GET`, `PATCH` with the current ETag, then `PATCH` again with the old one and expect
> a 412.

---

### How did you prevent duplicate processing?

**Shape:** name the layer each mechanism sits in — key uniqueness, business-key validation, status
guard, idempotent job design.

> On several levels, because they fail differently.
>
> The technical key is a UUID with `numbering : managed`, so duplicates are impossible at that
> level. The **business** key is a separate concern: we draw it from a number range in a
> determination declared `on save`, not `on modify`, so a discarded draft does not consume a number
> and we do not get gaps.
>
> Against duplicate business documents we used a validation on save checking the natural key against
> existing records — set-based, one `SELECT ... FOR ALL ENTRIES` outside the loop, not a
> `SELECT SINGLE` per instance.
>
> For the action that creates a follow-on document, the guard is a **status field** plus feature
> control: once the document is created the status changes, the instance authorization and feature
> control disable the action, and the action implementation itself re-reads the status and skips
> instances that already have a follow-on — because feature control is only a UI hint and an API
> caller can still invoke the action.
>
> For background processing we made the job idempotent: it selects by status, so a re-run after a
> failure picks up only what is still open, and it commits in chunks so a failure loses one chunk
> rather than the whole run.

---

### How did you implement validations and determinations?

> Declared in the base behavior definition so every consumer gets them, not in the projection —
> a projection-level validation is bypassed by EML callers, jobs and any second service.
>
> Validations `on save`, so the user is not nagged mid-typing, and every one of them listed in
> `draft determine action Prepare` so the messages appear while the draft is open rather than only
> at activation. Each one fills **both** `failed` and `reported`, and uses a `%state_area` that it
> clears at the start of the loop — otherwise the message stays on screen after the user fixes the
> data. Messages carry `%element-<Field>` so Fiori highlights the right field.
>
> Determinations: `on modify` for anything the user should see immediately, like the price roll-up,
> and `on save` for the number range. All of them idempotent — they read first and skip instances
> where the value is already set, because a determination can be called more than once.
>
> Everything reads the buffer with `READ ENTITIES ... IN LOCAL MODE`, never `SELECT` on our own
> tables, because in a draft app a `SELECT` reads the active row while the user is editing the
> draft. Master-data lookups are `SELECT`, but set-based and outside the loop.
>
> And for every calculated field we declared a `side effect`, otherwise the value is correct on the
> server and stale on screen — which looks exactly like a broken determination.

---

### How did you debug a failed save?

**Shape:** describe a method, not a tool list.

> The first thing is to get out of the browser. I reproduce it in a console class implementing
> `IF_OO_ADT_CLASSRUN`, driving the BO with EML, and print `failed`, `reported` and `sy-subrc` after
> `COMMIT ENTITIES`. That immediately tells me which half of the problem I have: `sy-subrc = 4`
> means the **early save phase** rejected it and it is recoverable — a validation — and `reported`
> names which one. `sy-subrc = 8` means a **late-phase** failure, which needs an explicit
> `ROLLBACK ENTITIES` and means something that could fail was left in `save_modified` instead of
> `check_before_save`.
>
> `COMMIT ENTITIES IN SIMULATION MODE` is very useful here: it runs the whole early save phase,
> including all the on-save validations, and rolls back, so I can iterate without writing data.
>
> If `failed` is filled but `reported` is empty, the validation is rejecting without a message —
> that is the defect, not the data.
>
> For phase-level problems I set breakpoints in `finalize`, `check_before_save` and
> `cleanup_finalize`. Landing in `cleanup_finalize` tells me the early phase rejected the save, and
> `failed` from the previous method tells me which instance.
>
> From the UI side, the browser Network tab is underused: a failed `POST` returns a JSON body with
> the full message list, including messages the UI chose not to display.
>
> One real case: a determination appeared not to run. It ran; the field was `readonly` and the EML
> call was missing `IN LOCAL MODE`, so the write was silently rejected.

---

### How did you handle external API integration?

**Shape:** phase rules first, then error handling, then idempotency.

> The constraint that drives the design is the phase rules. Synchronous RFC and HTTP calls are **not
> allowed in the late save phase**, and update-task registration is only allowed there. So a
> synchronous call to an external system cannot sit in `save_modified`.
>
> What we did depended on the direction. For calling another RAP BO — a released `I_...TP` API — we
> used EML in the action handler, in the interaction phase, so both business objects commit in the
> same LUW and there is no `COMMIT ENTITIES` inside our behavior pool.
>
> That API used **late numbering**, so it returned a preliminary ID rather than a document number.
> Resolving it needs `CONVERT KEY`, which is only legal inside `save_modified` — which is precisely
> why that BO had to be `managed with unmanaged save`. We passed the preliminary IDs from the action
> to the saver through a `CLASS-DATA` on the global behavior pool class, resolved them in
> `save_modified`, wrote the real number into our table, and cleared the variable in both `cleanup`
> and `cleanup_finalize` — because class data survives the transaction and would otherwise leak into
> the next save.
>
> For outbound calls to a non-SAP system we did **not** call synchronously during the save. We wrote
> the payload to an outbound queue in `save_modified` under `with additional save`, and a separate
> job processes it with retry, timeout handling and idempotency keys, so a failed call does not roll
> back the business document and a retry does not create duplicates.
>
> Where a call had to influence whether the save is allowed at all, the check went in
> `check_before_save` — a test-mode call — so the transaction was still recoverable.

---

### How did you transport and activate the service in QA and production?

> See Chapter 25, §25.12 for the full answer. The compressed version: all repository objects on
> transport requests from a real development package, never `$TMP`; import order following the build
> order if the change set is split; then the non-transportable steps — **publishing the service
> binding** in each system, number range **intervals**, ICF activation, Launchpad catalog and tiles,
> role assignment, job scheduling. Then a post-import checklist run as a **business test user**, not
> as a developer, and UAT on the real Launchpad app rather than the ADT preview.

---

### How did you optimize CDS and EML performance?

> See Chapter 24, §24.12. The compressed version: associations rather than joins because
> associations are lazy; calculations in the interface view rather than virtual elements because
> virtual elements are computed in ABAP and cannot be filtered or sorted on HANA; a mandatory
> selective filter on any List Report over a large table; no `SELECT` inside a loop — collect
> distinct keys, one `FOR ALL ENTRIES`, hashed lookup; `AUTHORITY-CHECK` per distinct value rather
> than per row, because instance authorization runs for every row the list displays; `FIELDS ( )`
> instead of `ALL FIELDS`; `LINK` instead of `RESULT` when only existence matters; and chunked
> commits for mass EML so the buffer and lock table stay bounded and the job is restartable. `ST05`
> on a page load finds SELECTs in loops immediately; `SQLM` in production tells you what is actually
> slow.

---

### How did you test the application?

> See Chapter 23, §23.12. The compressed version: four levels — Data Preview for the CDS model, EML
> console classes for the behavior (the only place you see `failed`, `reported` and `sy-subrc`),
> those promoted to ABAP Unit tests with `cl_cds_test_environment`, `$metadata` for the service, and
> the Fiori preview for the flows. Validations asserted on **both** `failed` and `reported`; feature
> control asserted via `GET PERMISSIONS`; ETag and locking tested over HTTP or with two sessions
> because they happen above the EML layer; and authorization integration-tested with real roles,
> because there is no supported way to impersonate a user in ABAP Unit.

---

## 27.5 Questions to ask them

Asking good questions is part of a senior interview. These are specific enough to show you have
built something:

- Is the landscape ABAP Cloud / clean core, or classic on-premise with unrestricted ABAP?
- Are new developments managed RAP, or are you wrapping a lot of existing logic unmanaged?
- Do you use draft, and who owns the draft clean-up job?
- How do you handle service binding publication in QA and production — do developers have
  authorization there, or is it a Basis hand-off?
- Is there an existing convention for package layout and for `ZR_`/`ZC_` naming?
- Do you run ATC and ABAP Unit as a gate on transport release?
- How is authorization tested — is there a set of role-specific test users in QA?

---

## 27.6 Ten-minute revision sheet

| Term | One line |
|---|---|
| **RAP layers** | table → interface view → BDEF + ABP → projection + projection BDEF → MDE → service definition → binding |
| **managed** | framework provides buffer and save |
| **unmanaged** | you provide buffer, CRUD handlers, lock and save |
| **additional save** | framework saves; your `save_modified` does extra work |
| **unmanaged save** | you save, in `save_modified`; no `persistent table` |
| **Interface view** | the BO model; neutral, reusable, no `@UI` |
| **Projection view** | service-specific subset; `as projection on`; value helps, DCL, MDE attach here |
| **BDEF** | the contract: implementation type, tables, lock, etag, auth, operations, validations, determinations, actions |
| **ABP** | `FOR BEHAVIOR OF`; local handler (`CL_ABAP_BEHAVIOR_HANDLER`) + local saver (`CL_ABAP_BEHAVIOR_SAVER`) |
| **Determination** | derives data; `on modify` or `on save` |
| **Validation** | checks data; must not change it; blocks via `failed` |
| **Action** | operation beyond CRUD; needs `use action` in the projection BDEF to exist |
| **Side effect** | tells the UI what to re-read; declarative; no handler |
| **Draft** | second copy in a draft table; `%tky`; `total etag`; Edit/Activate/Discard/Resume/Prepare |
| **Save sequence** | finalize → check_before_save → [point of no return] → adjust_numbers → save → cleanup |
| **`sy-subrc` after COMMIT ENTITIES** | 0 ok · 4 early save failed (recoverable) · 8 late save failed (rollback required) |
| **`%cid`** | consumer-invented id before a key exists |
| **`%tky`** | key + `%is_draft`; always use it in draft BOs |
| **`%pid`** | preliminary id, late numbering; resolve with `CONVERT KEY` in `save_modified` |
| **`%control`** | which fields the consumer sent |
| **`failed`** | blocks the operation |
| **`reported`** | carries the messages |
| **`mapped`** | reports the assigned keys (create only) |
| **DCL** | filters reads; does not stop writes |
| **BDEF authorization** | controls modification; `auth-allowed` / `auth-unauthorized` |
| **Feature control** | UI hint only; `fc-o-` for operations, `fc-f-` for fields |
| **EML** | `READ`/`MODIFY`/`COMMIT`/`ROLLBACK ENTITIES`, `GET PERMISSIONS`, `SET LOCKS` |
| **`IN LOCAL MODE`** | inside the pool, always: buffer-direct, skips checks, allows writing `readonly` fields |
| **`strict ( 2 )`** | strictest checks; always on for new development |

---

[< Anti-Patterns](26-Anti-Patterns.md) | [Index](00-README.md)
