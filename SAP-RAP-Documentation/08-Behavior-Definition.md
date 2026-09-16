# Chapter 08 — The Behavior Definition (BDEF), Keyword by Keyword

[< Read-Only Report](07-ReadOnly-Fiori-Report-Walkthrough.md) | [Index](00-README.md) | [Next: Behavior Pool Classes >](09-Behavior-Pool-Classes.md)

---

## 8.1 What the BDEF is

The Behavior Definition is written in **BDL** (Behavior Definition Language). It is a *declaration*,
not code. It says what the business object can do; the behavior pool says how.

- It has the **same name as the CDS entity** it belongs to (`ZR_TravelTP`).
- ADT: right-click the root CDS view → *New Behavior Definition*, or `Ctrl + 1` on the view name.
- One BDEF covers the **whole composition tree** — root and all children in one file.

There are two BDEFs in a full RAP app:

| BDEF | On | Contains |
|---|---|---|
| **Base BDEF** | `ZR_TravelTP` | The real contract: operations, locks, validations, determinations, actions |
| **Projection BDEF** | `ZC_TravelTP` | Only `use ...` statements — which of the base capabilities this service exposes |

---

## 8.2 The complete base BDEF for our example

```abap
managed implementation in class ZBP_R_TravelTP unique;
strict ( 2 );
with draft;

define behavior for ZR_TravelTP alias Travel
persistent table ztravel
draft table ztravel_d
lock master
total etag LastChangedAt
authorization master ( instance )
etag master LocalLastChangedAt
{
  create;
  update;
  delete;

  field ( numbering : managed, readonly ) TravelUUID;
  field ( readonly ) TravelId, CreatedBy, CreatedAt, LastChangedBy, LastChangedAt,
                     LocalLastChangedAt, TotalPrice, OverallStatus;
  field ( mandatory ) AgencyId, CustomerId, BeginDate, EndDate, CurrencyCode;

  association _Booking { create; with draft; }

  determination setTravelId            on save { create; }
  determination calculateTotalPrice    on modify { field BookingFee, CurrencyCode; }
  determination setInitialOverallStatus on modify { create; }

  validation validateDates    on save { field BeginDate, EndDate; create; }
  validation validateCustomer on save { field CustomerId;          create; }
  validation validateAgency   on save { field AgencyId;            create; }

  action ( features : instance ) acceptTravel result [1] $self;
  action ( features : instance ) rejectTravel result [1] $self;
  action createTravelByTemplate [1] result [1] $self;
  factory action copyTravel [1];

  internal action recalculatePrices;

  side effects
  {
    field BookingFee affects field TotalPrice;
    action acceptTravel affects field OverallStatus;
  }

  draft action Activate optimized;
  draft action Discard;
  draft action Edit;
  draft action Resume;
  draft determine action Prepare
  {
    validation validateDates;
    validation validateCustomer;
    validation validateAgency;
  }

  mapping for ztravel
  {
    TravelUUID          = travel_uuid;
    TravelId            = travel_id;
    AgencyId            = agency_id;
    CustomerId          = customer_id;
    BeginDate           = begin_date;
    EndDate             = end_date;
    BookingFee          = booking_fee;
    TotalPrice          = total_price;
    CurrencyCode        = currency_code;
    Description         = description;
    OverallStatus       = overall_status;
    CreatedBy           = created_by;
    CreatedAt           = created_at;
    LastChangedBy       = last_changed_by;
    LastChangedAt       = last_changed_at;
    LocalLastChangedAt  = local_last_changed_at;
  }
}

define behavior for ZR_BookingTP alias Booking
persistent table zbooking
draft table zbooking_d
lock dependent by _Travel
authorization dependent by _Travel
etag master LastChangedAt
{
  update;
  delete;

  field ( numbering : managed, readonly ) BookingUUID;
  field ( readonly ) TravelUUID, BookingId, LastChangedAt;
  field ( mandatory ) CustomerId, CarrierId, ConnectionId, FlightDate;

  association _Travel { with draft; }

  determination setBookingId     on save   { create; }
  determination setBookingDate   on modify { create; }
  validation    validateFlight   on save   { field CarrierId, ConnectionId, FlightDate; create; }

  mapping for zbooking
  {
    BookingUUID   = booking_uuid;
    TravelUUID    = travel_uuid;
    BookingId     = booking_id;
    BookingDate   = booking_date;
    CustomerId    = customer_id;
    CarrierId     = carrier_id;
    ConnectionId  = connection_id;
    FlightDate    = flight_date;
    FlightPrice   = flight_price;
    CurrencyCode  = currency_code;
    BookingStatus = booking_status;
    LastChangedAt = last_changed_at;
  }
}
```

The rest of this chapter explains every one of those lines.

---

## 8.3 The header

```abap
managed implementation in class ZBP_R_TravelTP unique;
strict ( 2 );
with draft;
```

### `managed implementation in class ... unique;`

The **implementation type**. See Chapter 01, section 1.3 for the decision.

| Form | Meaning |
|---|---|
| `managed implementation in class ZBP_R_TravelTP unique;` | Framework provides buffer + save |
| `unmanaged implementation in class ZBP_R_TravelTP unique;` | You provide everything |
| `managed with additional save implementation in class ... unique;` | Framework saves, **plus** your `save_modified` |
| `managed with additional save with full data implementation in class ... unique;` | Same, but full instance data is passed to `save_modified` |
| `managed with unmanaged save implementation in class ... unique;` | **You** save, in `save_modified` |
| `abstract;` | No persistence at all — used for action parameter structures |
| `projection;` | This is a projection BDEF (see 8.10) |
| `interface;` | An interface BDEF for reuse between projections |

`unique` means: this class is the *only* implementation of this behavior. Always specify it; it lets
the framework do compile-time dispatch instead of a lookup.

> **Alternative placement.** You can instead specify the class per entity:
> ```abap
> define behavior for ZR_TravelTP alias Travel
> implementation in class ZBP_R_TRAVELTP unique
> persistent table ztravel
> ```
> This is useful when a large BO has one behavior pool per node. **But**: if you use
> `with unmanaged save` or `with additional save`, the class must be specified in the **header**,
> on the same line as `managed`. This is a real constraint that catches people converting an
> existing managed BO to unmanaged save.

### `strict ( 2 );`

Turns on stricter syntax and semantic checks. There are three levels:

| Level | Effect |
|---|---|
| *(omitted)* | Legacy mode. Do not use for new development. |
| `strict ( 1 )` | Enforces basic rules: `%tky` instead of `%key` in draft scenarios, mandatory `mapping` when names differ, etc. |
| `strict ( 2 )` | Everything in level 1 plus: mandatory `lock`, mandatory `authorization`, stricter feature control, stricter EML checks, `draft action Prepare` consistency |

**Always use the highest level your release supports.** `strict ( 2 )` turns runtime surprises into
activation errors. It is available from ABAP Platform 2021.

Converting an old BDEF to `strict ( 2 )` will produce a list of errors. Every one of them is a real
latent defect.

### `with draft;`

Enables **draft handling** for the whole BO. Consequences:

- Every entity needs a `draft table`.
- The root needs `total etag`.
- The projection BDEF needs `use draft;`.
- The OData key gains a component `IsActiveEntity`.
- `%tky` (key + `%is_draft`) must be used everywhere instead of `%key`.
- `draft action Activate / Discard / Edit / Resume` must be declared.

Omit it for a non-draft (direct-save) app. See Chapter 11 for the full draft story and for when
draft is the wrong choice.

---

## 8.4 The entity behavior header

```abap
define behavior for ZR_TravelTP alias Travel
persistent table ztravel
draft table ztravel_d
lock master
total etag LastChangedAt
authorization master ( instance )
etag master LocalLastChangedAt
```

### `define behavior for <CDS entity> alias <Alias>`

| Part | Meaning |
|---|---|
| `ZR_TravelTP` | The CDS entity this behavior belongs to |
| `alias Travel` | A short name used **everywhere else**: in handler method signatures, in EML, in nested `association _Booking { }`, in derived types |

The alias is not cosmetic. `METHODS validateDates FOR VALIDATE ON SAVE IMPORTING keys FOR Travel~validateDates.` uses it. Choose a clean noun.

Optional additions:
```abap
define behavior for ZR_TravelTP alias Travel
  external 'Trip'                      " the name exposed in OData metadata
  implementation in class ZBP_X unique " per-entity behavior pool
```

### `persistent table ztravel`

The DDIC table (or CDS table entity) the managed runtime writes to.

- **Only for managed BOs.** An unmanaged BO has no `persistent table`.
- **Forbidden together with `with unmanaged save`** — see Chapter 16.
- The table's fields must map 1:1 to the entity's elements, either by identical names or via
  `mapping for`.

### `draft table ztravel_d`

The draft table. Required when `with draft;` is set. See Chapter 02, section 2.5 for the naming rules.

### `lock master`

**Pessimistic locking.** Declares that this entity owns the lock for the whole BO.

| Form | Where | Meaning |
|---|---|---|
| `lock master` | Root entity | This entity manages the lock. Managed RAP acquires and releases it automatically for update, delete, create-by-association and actions. |
| `lock master unmanaged` | Root entity | You implement locking yourself in a `FOR LOCK` handler method. |
| `lock dependent by _Travel` | Child entity | Locking is delegated to the parent via the named `association to parent`. |
| *(none)* | — | Not allowed under `strict ( 2 )` for entities that support modification. |

What the framework actually does: before the first modification it writes an entry to the global
lock table (the same infrastructure as `ENQUEUE`). A second user's modify request is then rejected
with *"Object is locked by user X"*.

A per-operation escape hatch exists: `action ( lock : none ) someAction;` — useful for an action
that only reads.

### `total etag LastChangedAt`

**Draft-only, and mandatory for draft.** Used to decide whether a draft is still *resumable*.

Scenario: you start editing a Travel (a draft is created, the active instance is exclusively
locked). You close the browser. The exclusive lock expires after its configured timeout. Now
another user could change the active instance. When you come back and press *Resume*, RAP compares
the draft's stored total-ETag with the active instance's current one:

- equal → the active instance has not changed → resume is allowed
- different → your draft is stale → RAP tells you so

It must be declared **after** `lock master`, and it should use a **different field** than
`etag master`. Requires `@Semantics.systemDateTime.lastChangedAt: true` on the field.

### `authorization master ( instance )`

Declares which authorization checks the framework will call.

| Form | Calls | Use when |
|---|---|---|
| `authorization master ( global )` | `FOR GLOBAL AUTHORIZATION` | "May this user create Travels at all?" — instance-independent |
| `authorization master ( instance )` | `FOR INSTANCE AUTHORIZATION` | "May this user change *this* Travel?" — depends on the data |
| `authorization master ( global, instance )` | Both | Most real apps |
| `authorization master ( none )` | Nothing | Only when authorization is genuinely not needed. Under `strict ( 2 )` you must state this explicitly rather than omit it. |
| `authorization dependent by _Travel` | Delegates to the parent | Child entities |

Per-operation overrides live in the entity body:
```abap
update ( authorization : global );
action ( authorization : none ) recalculate;
```

> **Remember:** `authorization` in the BDEF controls **modification**. DCL (`@AccessControl`)
> controls **read**. You need both.

### `etag master LocalLastChangedAt`

**Optimistic concurrency control.**

On read, the framework sends the field value to the client as an HTTP `ETag`. On the next write,
the client sends it back in `If-Match`. If the stored value has changed in the meantime, RAP
rejects the write with *"Data has been changed by another user"*.

| Form | Meaning |
|---|---|
| `etag master <field>` | This entity carries its own ETag |
| `etag dependent by _Travel` | ETag is taken from the parent |

Requirements: field type `utclong` / `timestamp` / `timestampl`, plus
`@Semantics.systemDateTime.localInstanceLastChangedAt: true` in the CDS view, plus `readonly` in
the BDEF. The managed runtime then maintains it for you.

**Lock vs ETag — they solve different problems:**

| | Lock (pessimistic) | ETag (optimistic) |
|---|---|---|
| When | Before editing starts | At the moment of saving |
| Prevents | A second user starting an edit | A second user's stale overwrite |
| Cost | Blocks others | No blocking |
| Needed in RAP | Yes | Yes |

Use both. They are complementary, not alternatives.

---

## 8.5 The entity body — operations

```abap
{
  create;
  update;
  delete;
  ...
}
```

| Statement | Enables |
|---|---|
| `create;` | `POST` — creating a new root instance |
| `update;` | `PATCH` |
| `delete;` | `DELETE` |
| *(read)* | **There is no `read;` statement.** Read is always available and is not declared. |

Restrictions can be attached:

```abap
create ( authorization : global );
update ( features : instance );
delete ( precheck );
```

| Addition | Meaning |
|---|---|
| `( authorization : global \| instance \| none )` | Which authorization check runs for this operation |
| `( features : instance \| global )` | Enables dynamic feature control for this operation (Chapter 14) |
| `( precheck )` | Calls a `FOR PRECHECK` handler **before** the data enters the buffer. Lets you reject bad input early — e.g. reject a delete before the framework loads the instance |

### Child entity operations

Note the child in our example has `update; delete;` but **no `create;`**.

That is deliberate: a Booking is never created standalone — it is created *through the parent*, via
`association _Booking { create; }`. Declaring `create;` on the child would expose a top-level
"create booking" operation that has no valid parent.

---

## 8.6 `field ( ... )` — field characteristics

```abap
field ( numbering : managed, readonly ) TravelUUID;
field ( readonly ) TravelId, CreatedBy, CreatedAt, LastChangedBy, LastChangedAt,
                   LocalLastChangedAt, TotalPrice, OverallStatus;
field ( mandatory ) AgencyId, CustomerId, BeginDate, EndDate, CurrencyCode;
```

| Characteristic | Meaning | UI effect |
|---|---|---|
| `readonly` | Consumer may never send a value. Framework rejects it. | Field rendered as display-only |
| `readonly : update` | Writable on create, locked afterwards | Editable in create, display-only in edit |
| `mandatory` | A value must be supplied | Red asterisk; save blocked if empty |
| `mandatory : create` | Required only on create | |
| `mandatory : update` | Required only on update | |
| `numbering : managed` | The framework generates a UUID for this key field | |
| `suppress` | The field exists in the CDS view but is completely hidden from the BO and from OData | Not in `$metadata` at all |
| `features : instance` | Enables **dynamic** field control (Chapter 14) | Read-only / mandatory computed per instance |

Several can be combined in one parenthesis: `field ( readonly, features : instance ) OverallStatus;`

### The three things this section really does

1. **`numbering : managed` on the UUID key** — this single word is what makes "the framework fills
   my key" true. Without it you must supply a key on create, or implement `FOR NUMBERING`.
2. **`readonly` on the five admin fields** — combined with the `@Semantics` annotations from
   Chapter 03, this gives you complete, code-free audit fields.
3. **`readonly` on derived fields (`TotalPrice`, `OverallStatus`)** — these are set by
   determinations and actions. Making them readonly stops a consumer from sending an inconsistent
   value, and stops the corresponding determination from looping.

> **A common mistake:** marking a field `readonly` and then trying to change it from a
> determination. That *works* — `readonly` restricts the **consumer**, not the provider. Your
> determination can set a readonly field via `MODIFY ENTITIES ... IN LOCAL MODE`.

### `suppress` vs `readonly` vs `@UI.hidden`

| | Visible in `$metadata` | Readable via OData | Writable |
|---|---|---|---|
| nothing | yes | yes | yes |
| `@UI.hidden: true` | yes | yes | yes (just not shown by default) |
| `field ( readonly )` | yes | yes | **no** |
| `field ( suppress )` | **no** | no | no |

Use `suppress` for technical fields that must never leave the backend.

---

## 8.7 `association ... { }` — enabling operations across the composition

```abap
association _Booking { create; with draft; }
```

| Part | Meaning |
|---|---|
| `association _Booking` | The composition from the CDS view |
| `{ create; }` | Enables **create-by-association** (`cba`): a Booking can be created *through* its Travel. This is what makes the "+" button work in the Bookings table on the Object Page. |
| `{ with draft; }` | The association also works on draft instances. **Required for every association inside a draft-enabled BO.** |

On the child side:
```abap
association _Travel { with draft; }
```
The parent association needs `with draft;` too, but no `create;` — you never create a parent through
a child.

**If the "+" button in the child table is greyed out or missing, this is the first place to look.**

---

## 8.8 Determinations

```abap
determination setTravelId             on save   { create; }
determination calculateTotalPrice     on modify { field BookingFee, CurrencyCode; }
determination setInitialOverallStatus on modify { create; }
```

Syntax: `determination <name> on <trigger-time> { <trigger-condition>; }`

| Trigger time | Runs |
|---|---|
| `on modify` | During the **interaction phase**, immediately after the triggering change |
| `on save` | During the **early save phase**, when `finalize` is reached |

| Trigger condition | Fires when |
|---|---|
| `create` | An instance is created |
| `update` | An instance is updated |
| `delete` | An instance is deleted |
| `field F1, F2` | One of the listed fields is changed |
| `create; update;` | Either |

### `on modify` vs `on save` — how to choose

| Use `on modify` when | Use `on save` when |
|---|---|
| The user should see the result **immediately** (a total recalculating as they type) | The value is only needed at save time |
| The determination depends only on the current instance | The determination needs the *final* state of the whole document |
| Example: `calculateTotalPrice` | Example: `setTravelId` (a number range should not be consumed for drafts that get discarded) |

`setTravelId on save { create; }` is the canonical pattern: the human-readable number is drawn from
the number range **only when the document is really saved**, so discarded drafts do not burn numbers.

> **Determination loop warning.** A determination that changes field X, triggered by
> `field X`, will call itself. RAP detects direct self-triggering and raises an error, but it
> cannot detect a two-step cycle (A changes B, B's determination changes A). Draw the dependency
> graph before writing the second determination on an entity.

Full implementations: Chapter 12.

---

## 8.9 Validations

```abap
validation validateDates    on save { field BeginDate, EndDate; create; }
validation validateCustomer on save { field CustomerId;          create; }
```

Same trigger syntax as determinations. Differences:

| | Determination | Validation |
|---|---|---|
| May change data | **Yes** | **No** |
| May reject | No | **Yes** (via `failed` + `reported`) |
| `on modify` allowed | Yes | Yes |
| `on save` runs at | `finalize` | `check_before_save` |

**Validations should almost always be `on save`.** An `on modify` validation fires on every
keystroke-level change and makes the UI complain while the user is still typing. Use `on save` and
let the user finish.

The one exception is a validation whose failure must block an *action* mid-interaction.

Full implementations: Chapter 12.

---

## 8.10 Actions

```abap
action ( features : instance ) acceptTravel result [1] $self;
action createTravelByTemplate [1] result [1] $self;
factory action copyTravel [1];
internal action recalculatePrices;
```

Full treatment in Chapter 13. The syntax skeleton:

```abap
[static|factory|internal] action [ ( <specs> ) ] <name>
    [ <input-cardinality> ]
    [ parameter <abstract-entity> ]
    [ result [ <result-cardinality> ] ( $self | <entity> ) ]
    [ deep ] ;
```

| Element | Meaning |
|---|---|
| `action name;` | **Instance action** — operates on selected instances |
| `static action name;` | Not bound to an instance — a global button |
| `factory action name [1];` | Creates new instances (e.g. "copy") |
| `internal action name;` | Callable only from inside the BO (EML `IN LOCAL MODE`), never exposed in OData |
| `[1]` after the name | Input cardinality: how many instances the action processes |
| `result [1] $self` | Returns the (changed) instance itself — makes the UI refresh automatically |
| `result [0..*] ZR_BookingTP` | Returns other entities |
| `parameter ZE_TravelParams` | Opens a **dialog** in Fiori to collect input |
| `( features : instance )` | The action can be enabled/disabled per instance |
| `( authorization : none )` | Skip the authorization check for this action |
| `( lock : none )` | Do not acquire a lock (read-only actions) |
| `deep` | The parameter structure contains nested tables (deep action) |

---

## 8.11 `side effects`

```abap
side effects
{
  field BookingFee affects field TotalPrice;
  action acceptTravel affects field OverallStatus;
  determine action Prepare affects messages;
}
```

Tells the **UI** what to re-read after a change. Without side effects the Fiori app does not know
that changing `BookingFee` altered `TotalPrice` on the server, so the screen shows a stale total
until the user refreshes.

| Form | Meaning |
|---|---|
| `field A affects field B;` | Changing A requires re-reading B |
| `field A affects entity _Booking;` | Changing A requires re-reading the child table |
| `action X affects field F;` | After the action, re-read F |
| `action X affects entity _Booking;` | After the action, re-read the children |
| `action X affects messages;` | After the action, re-fetch messages |
| `field A affects permissions;` | Re-evaluate feature control (button enablement) |
| `determine action Prepare affects messages;` | Standard for draft — refresh the message list after Prepare |

**This is the fix for "my calculated field does not update on screen".** People spend hours
debugging the determination when the determination was fine and the UI simply never asked again.

Side effects can be declared in the base BDEF or the projection BDEF. Put UI-driven ones in the
projection.

---

## 8.12 `mapping for`

```abap
mapping for ztravel
{
  TravelUUID = travel_uuid;
  TravelId   = travel_id;
  ...
}
```

Maps **CDS element names** to **DDIC field names**.

- Needed whenever the names differ (`TravelUUID` vs `travel_uuid`) — which, with the naming
  conventions in this guide, is always.
- Omitting it produces a syntax-check warning and, at runtime, silently unfilled fields.
- Short form when all names match apart from case and underscores:
  ```abap
  mapping for ztravel corresponding;
  ```
  `corresponding` does the name matching automatically. Convenient, but the explicit list is
  self-documenting and survives a field rename with a clear error rather than a silent gap.

### The `control` variant

```abap
mapping for ztravel control ztravel_x corresponding;
```

`ztravel_x` is a structure with one `abap_boolean` field per data field:

```abap
define structure ztravel_x {
  travel_id     : abap_boolean;
  agency_id     : abap_boolean;
  customer_id   : abap_boolean;
  ...
}
```

This is needed when you implement `save_modified` yourself (unmanaged save / additional save) and
want to map `%control` into an x-structure so you can issue a field-selective `UPDATE`. Chapter 16
shows this in use.

---

## 8.13 Draft actions

```abap
draft action Activate optimized;
draft action Discard;
draft action Edit;
draft action Resume;
draft determine action Prepare
{
  validation validateDates;
  validation validateCustomer;
  validation validateAgency;
}
```

| Action | Triggered by | Does |
|---|---|---|
| `Edit` | The user presses **Edit** on an active instance | Creates a draft copy and locks the active instance |
| `Activate` | The user presses **Save** | Copies the draft onto the active instance and deletes the draft |
| `Discard` | The user presses **Cancel** | Deletes the draft, releases the lock |
| `Resume` | The user reopens an existing draft | Re-locks and continues editing |
| `Prepare` | The framework, before Activate, and on demand | Runs the listed validations so errors appear **in the draft**, before activation |

### `optimized`

`draft action Activate optimized;` enables the **optimized draft activation**: the framework
re-uses the already-validated draft data instead of re-reading and re-validating everything.
Significantly faster. Requirements: all validations must be listed in `Prepare`, and they must be
side-effect free. Use it; there is rarely a reason not to.

### Why `Prepare` matters

Without `draft determine action Prepare`, validations only run at Activate. The user fills a long
form, presses Save, and gets a wall of errors. With `Prepare`, the same validations run while the
draft is open and the messages appear inline as the user works.

**Every validation you want the user to see before saving must be listed inside `Prepare`.**
Listing it is not automatic.

You can also list determinations in `Prepare`:
```abap
draft determine action Prepare
{
  validation validateDates;
  determination calculateTotalPrice;
}
```

---

## 8.14 The projection BDEF

Object: *Behavior Definition* on `ZC_TravelTP`. It is short by design.

```abap
projection;
strict ( 2 );
use draft;

define behavior for ZC_TravelTP alias Travel
use etag
{
  use create;
  use update;
  use delete;

  use association _Booking { create; with draft; }

  use action acceptTravel;
  use action rejectTravel;
  use action createTravelByTemplate;
  use action copyTravel;

  use action Activate;
  use action Discard;
  use action Edit;
  use action Resume;
  use action Prepare;
}

define behavior for ZC_BookingTP alias Booking
use etag
{
  use update;
  use delete;

  use association _Travel { with draft; }
}
```

### Line by line

| Line | Meaning |
|---|---|
| `projection;` | Declares this as a projection BDEF. Not `managed`. |
| `strict ( 2 );` | Same level as the base. |
| `use draft;` | Expose draft handling in this service. Required if the base has `with draft;` **and** you want drafts in this service. |
| `define behavior for ZC_TravelTP alias Travel` | The projection entity. Alias should match the base alias. |
| `use etag` | Expose the base entity's ETag. Without it, no optimistic locking on this service. |
| `use create; use update; use delete;` | Expose the operations. **Omitting one makes it unavailable** — this is how you build a read-only service over a transactional BO. |
| `use association _Booking { create; with draft; }` | Expose the composition and create-by-association. |
| `use action X;` | Expose an action. **An action not listed here does not appear in the service, no matter what the base BDEF or the MDE say.** |
| `use action Activate/Discard/Edit/Resume/Prepare;` | The draft actions must be explicitly exposed too. |

### What a projection BDEF can and cannot do

**Can:**

- Omit operations, actions, associations (subsetting)
- Add **new** determinations and validations that are specific to this service:
  ```abap
  determination setDefaultForThisApp on modify { create; }
  ```
- Add its own `side effects`
- Override field characteristics:
  ```abap
  field ( readonly ) BookingFee;   " read-only in this service, editable in another
  ```
- Add a **new** action that only this service has

**Cannot:**

- Add `create` if the base does not have it
- Change lock, ETag, authorization, or numbering
- Change the persistent table

> **The single most common projection-BDEF bug:** you implement an action in the behavior pool,
> annotate the button in the MDE, and the button never appears — because you forgot
> `use action <name>;`. Check this before debugging anything else.

---

## 8.15 Full keyword reference

### Header

| Keyword | Purpose |
|---|---|
| `managed` / `unmanaged` / `abstract` / `projection` / `interface` | Implementation type |
| `with additional save` / `with unmanaged save` | Save enhancement (Chapter 16) |
| `with full data` | Pass full instance data to `save_modified` |
| `and cleanup` | Requires redefining `cleanup` in the saver |
| `implementation in class X unique` | The behavior pool |
| `strict ( 1 \| 2 )` | Syntax-check strictness |
| `with draft` | Enable draft |
| `extensible` | Allow BDEF extensions |

### Entity level

| Keyword | Purpose |
|---|---|
| `define behavior for E alias A` | Start an entity behavior |
| `external 'Name'` | OData-exposed name |
| `persistent table T` | Active data table (managed) |
| `draft table T_D` | Draft table |
| `lock master` / `lock master unmanaged` / `lock dependent by _A` | Pessimistic locking |
| `etag master F` / `etag dependent by _A` | Optimistic locking |
| `total etag F` | Draft resumability |
| `authorization master ( global \| instance \| none )` / `authorization dependent by _A` | Modification authorization |
| `early numbering` / `late numbering` | Key assignment strategy (Chapter 19) |
| `with additional save` / `with unmanaged save` | Per-entity save enhancement |
| `implementation in class X unique` | Per-entity behavior pool |

### Entity body

| Keyword | Purpose |
|---|---|
| `create;` `update;` `delete;` | CRUD |
| `field ( ... ) F1, F2;` | Field characteristics |
| `association _A { create; with draft; }` | Composition operations |
| `determination D on modify \| on save { ... }` | Auto-derivation |
| `validation V on modify \| on save { ... }` | Checks |
| `action` / `static action` / `factory action` / `internal action` | Operations beyond CRUD |
| `function` | Read-only operation with a result |
| `side effects { ... }` | UI refresh hints |
| `mapping for T { ... }` / `mapping for T corresponding` | Element-to-field mapping |
| `draft action Activate \| Discard \| Edit \| Resume` | Draft lifecycle |
| `draft determine action Prepare { ... }` | Pre-activation validation set |
| `event <name> parameter <abstract entity>;` | RAP business event |
| `auxiliary class ZCL_X;` | Helper class with privileged BO access |
| `precheck` | Call a `FOR PRECHECK` handler |
| `augment` | Modify a request in a projection before it reaches the base BO |

---

## 8.16 Checklist

- [ ] `strict ( 2 );` present.
- [ ] Implementation type consciously chosen (Chapter 01, section 1.3).
- [ ] `lock master` on the root, `lock dependent by` on every child.
- [ ] `authorization master ( ... )` on the root, `authorization dependent by` on every child.
- [ ] `etag master` + `total etag` (if draft), on **different** fields.
- [ ] UUID key has `field ( numbering : managed, readonly )`.
- [ ] All five admin fields are `readonly`.
- [ ] Every association has `with draft;` if the BO is draft-enabled.
- [ ] `mapping for` present and complete for every entity.
- [ ] Every validation the user should see early is listed in `draft determine action Prepare`.
- [ ] `side effects` declared for every calculated field.
- [ ] Projection BDEF has a `use` for every operation, association and action the app needs.

---

## 8.17 Interview answer

> **"What is a behavior definition and what goes in it?"**
>
> It is the contract of the business object, written in BDL — a declaration, not code. It covers the
> implementation type and the behavior pool class; `strict ( 2 )`; whether draft is on; and then per
> entity the persistent and draft tables, `lock master` or `lock dependent by`, `etag master` and
> `total etag`, `authorization master`, which operations exist, field characteristics such as
> `readonly`, `mandatory` and `numbering : managed`, create-by-association, validations,
> determinations, actions, side effects, the draft actions, and the mapping between CDS element
> names and database field names.
>
> There are two behavior definitions in a full app. The **base** one on `ZR_` holds the real
> contract. The **projection** one on `ZC_` contains only `use` statements — `use create`,
> `use update`, `use action X`, `use association _Booking { create; }`. An operation or action not
> listed there does not exist in that service, and that is the single most common cause of a button
> that never appears, with no error anywhere.
>
> The value of `strict ( 2 )` is worth mentioning: it makes lock and authorization declarations
> mandatory, enforces `%tky` instead of `%key` in draft scenarios, and turns a class of runtime
> surprises into activation errors.

## 8.18 Production considerations

- **`strict ( 2 )` on every new BDEF.** Converting a legacy BDEF will produce a list of errors;
  every one of them is a real latent defect.
- **Business invariants belong in the base BDEF.** A validation declared only in the projection is
  bypassed by EML callers, jobs and any second service.
- **`etag master` and `total etag` should be different fields**, and `total etag` must come after
  `lock master`.
- **Use `mapping for ... corresponding` sparingly.** The explicit field list is self-documenting and
  fails loudly on a rename, where `corresponding` fails silently.
- **Audit `side effects` whenever you add a determination.** A new derived field without one shows
  stale data on screen.
- **Every validation the user should see before saving must be listed in `draft determine action
  Prepare`.** It is not automatic.
- **Generate handler skeletons with `Ctrl + 1`.** Hand-written `FOR ...` signatures are the
  number-one activation error.

---

[< Read-Only Report](07-ReadOnly-Fiori-Report-Walkthrough.md) | [Index](00-README.md) | [Next: Behavior Pool Classes >](09-Behavior-Pool-Classes.md)
