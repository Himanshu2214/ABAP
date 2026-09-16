# Chapter 03 — The Basic / Interface View, Line by Line

[< Data Model](02-Data-Model-and-Tables.md) | [Index](00-README.md) | [Next: Projection View >](04-Projection-View.md)

---

## 3.1 What this layer is and is not

The interface view (`ZR_TravelTP`) is **the business object's data model**. It is the one place that
defines:

- which database fields exist in the BO and what they are called
- the composition tree (what belongs to the BO)
- associations to other BOs / master data
- semantic annotations (amount, quantity, user, date-time)

It **must not** contain:

- `@UI.*` annotations (those go in the metadata extension, Chapter 05)
- `@Search.*` for a specific app
- anything service-specific

> If two different Fiori apps need the same business object, they share `ZR_TravelTP` and have their
> own `ZC_...` projections. That only works if `ZR_` stays neutral.

---

## 3.2 `DEFINE VIEW` vs `DEFINE VIEW ENTITY` vs `DEFINE ROOT VIEW ENTITY`

| Syntax | Generates a DDIC SQL view? | Use it? |
|---|---|---|
| `define view ZX as select from ...` | Yes (`@AbapCatalog.sqlViewName` required) | **Legacy.** Only for old releases or when you must expose an SQL view. |
| `define view entity ZX as select from ...` | No | **Yes** — the modern form. Faster activation, better syntax checks, no SQL view artifact. |
| `define root view entity ZX as select from ...` | No | **Yes** — for the *root* of a composition tree. |

Everything in this documentation uses **view entities**. If you see `@AbapCatalog.sqlViewName` in a
tutorial, that tutorial predates ABAP Platform 1909.

The word `root` does exactly one thing: it marks this entity as the **top of a composition tree**,
which is a precondition for attaching a behavior definition that has children.

---

## 3.3 The root interface view `ZR_TravelTP` — full source

```abap
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Travel - interface view (RAP root)'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType: { serviceQuality: #X, sizeCategory: #S, dataClass: #MIXED }
define root view entity ZR_TravelTP
  as select from ztravel as Travel

  composition [0..*] of ZR_BookingTP as _Booking

  association [0..1] to /DMO/I_Agency   as _Agency   on $projection.AgencyId   = _Agency.AgencyID
  association [0..1] to /DMO/I_Customer as _Customer on $projection.CustomerId = _Customer.CustomerID
  association [0..1] to I_Currency      as _Currency on $projection.CurrencyCode = _Currency.Currency
{
  key travel_uuid             as TravelUUID,

      travel_id               as TravelId,
      agency_id               as AgencyId,
      customer_id             as CustomerId,
      begin_date              as BeginDate,
      end_date                as EndDate,

      @Semantics.amount.currencyCode: 'CurrencyCode'
      booking_fee             as BookingFee,
      @Semantics.amount.currencyCode: 'CurrencyCode'
      total_price             as TotalPrice,
      currency_code           as CurrencyCode,

      description             as Description,
      overall_status          as OverallStatus,

      @Semantics.user.createdBy: true
      created_by              as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at              as CreatedAt,
      @Semantics.user.lastChangedBy: true
      last_changed_by         as LastChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at         as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at   as LocalLastChangedAt,

      /* Associations */
      _Booking,
      _Agency,
      _Customer,
      _Currency
}
```

---

## 3.4 Line by line

### The header annotations

```abap
@AccessControl.authorizationCheck: #NOT_REQUIRED
```
Declares whether a DCL (access control / CDS role) is expected for this view.

| Value | Meaning | When to use |
|---|---|---|
| `#CHECK` | A DCL exists and **is** applied. Activation warns if no DCL is found. | Production views where row-level authorization is needed. |
| `#NOT_REQUIRED` | No DCL. No warning. | Interface views where authorization is enforced *one layer up* (in the projection) or in the BDEF. |
| `#NOT_ALLOWED` | DCL must not exist. | Rare — technical/helper views. |
| `#PRIVILEGED_ONLY` | Only privileged callers. | Internal framework views. |

**Where to put the DCL in RAP — a design decision, not a fixed rule.**

DCL can be applied at whichever CDS layer the authorization rule actually belongs to:

| Put the DCL on the... | When |
|---|---|
| **Projection** (`ZC_TravelTP`) | Different services over the same BO need **different** row-level restrictions — e.g. a manager app and a self-service app. The interface view then stays `#NOT_REQUIRED`. |
| **Interface view** (`ZR_TravelTP`) | The restriction is an **invariant of the data model itself** — every consumer, present and future, must be subject to it. Common for sensitive data (HR, payroll) where an unrestricted read must not be possible at any layer. |
| **Both** | An invariant baseline on the interface view, plus a narrower service-specific filter on the projection. DCL conditions at different layers are combined, so the effective result is the intersection. |

The example above uses `#NOT_REQUIRED` because this BO's restriction is service-specific. If your
security architecture says the rule belongs to the reusable model, put it on `ZR_` and set
`#CHECK` there instead — that is equally valid.

What drives the choice is **reuse and security architecture**: how many services will consume this
model, and whether an unfiltered read of the interface view is acceptable. Decide it deliberately
and write the decision down; it is hard to change once several services depend on the model.
See Chapter 14 for the implementation and for how DCL relates to BDEF authorization.

```abap
@EndUserText.label: 'Travel - interface view (RAP root)'
```
Description. Max 60 characters. Shown in ADT, in the where-used list, and — if you forget a label on
the projection — in the UI.

```abap
@Metadata.ignorePropagatedAnnotations: true
```
**Important and frequently misunderstood.**
By default, a CDS view *inherits* annotations from the entities it selects from. With `true`, that
inheritance is switched off: this view sees only the annotations written in this file.

Use `true` on interface views. Reason: you do not want a stray `@UI.lineItem` from a lower view
silently leaking into your BO and then into every service. It makes the view self-contained and
predictable. (`@Semantics` you write *here* still applies — you are only blocking *propagated* ones.)

```abap
@ObjectModel.usageType: { serviceQuality: #X, sizeCategory: #S, dataClass: #MIXED }
```
Classification metadata for the VDM. It has no runtime effect on RAP, but SAP's CDS checks (and ATC)
expect it on interface views.

| Sub-annotation | Values | Meaning |
|---|---|---|
| `serviceQuality` | `#A` (transactional/high) ... `#X` (extreme, no guarantee) | Expected response-time class. `#X` = "not classified". |
| `sizeCategory` | `#S`, `#M`, `#L`, `#XL`, `#XXL` | Expected result-set size. |
| `dataClass` | `#TRANSACTIONAL`, `#MASTER`, `#ORGANIZATIONAL`, `#CUSTOMIZING`, `#META`, `#MIXED` | What kind of data. |

For a transactional BO root, `{ serviceQuality: #D, sizeCategory: #S, dataClass: #TRANSACTIONAL }`
is also a common and more accurate choice.

---

### The entity declaration

```abap
define root view entity ZR_TravelTP
  as select from ztravel as Travel
```

| Token | Meaning |
|---|---|
| `define` | Start of a CDS entity definition. |
| `root` | This entity is the root of a composition tree. **Required** if the BDEF has child entities. Omitting it produces *"Entity must be a root entity"* when you activate the BDEF. |
| `view entity` | Modern CDS view — no generated DDIC SQL view. |
| `ZR_TravelTP` | The CDS entity name. Must match the file/object name in ADT. Case-insensitive at activation, but the spelling you use here is the one that appears in EML and the BDEF, so be consistent. |
| `as select from ztravel` | The data source. Can be a DDIC table, a CDS table entity, or another CDS view. |
| `as Travel` | Alias for the data source, used on the left side of field assignments and in join conditions. |

---

### The composition

```abap
composition [0..*] of ZR_BookingTP as _Booking
```

This single line is what makes `ZR_BookingTP` **part of this business object**.

| Part | Meaning |
|---|---|
| `composition` | A parent-owns-child relationship. Establishes the BO boundary. |
| `[0..*]` | Cardinality: a Travel has zero or more Bookings. |
| `of ZR_BookingTP` | The child entity. It **must** declare the matching `association to parent`. |
| `as _Booking` | The name you use in the BDEF (`_Booking`), in EML (`\_Booking`), and in UI facets. Convention: leading underscore. |

**There is no `on` condition.** That is not an omission — a composition derives its join condition
from the child's `association to parent` clause. The child owns the linking logic.

#### Composition vs association — the decision rule

| Ask | If yes → | If no → |
|---|---|---|
| Does the child have any meaning without the parent? | association | composition |
| Should deleting the parent delete it? | composition | association |
| Should it be locked together with the parent? | composition | association |
| Should it be saved in the same LUW as part of the same document? | composition | association |
| Is it master data (Customer, Agency, Currency, Plant)? | **association**, always | — |

Concretely: *Booking* is a composition (a booking outside a travel is meaningless).
*Customer* is an association (a customer exists independently and is owned by another BO).

#### Cardinalities

| Cardinality | Meaning |
|---|---|
| `[0..1]` | Optional single child |
| `[1..1]` | Mandatory single child |
| `[0..*]` | Zero or many — the normal case for item tables |
| `[1..*]` | At least one — the framework does **not** enforce this; you enforce it with a validation on save |

> `[1..*]` on a composition does not make RAP reject a Travel with no Bookings. Cardinality is
> metadata for the optimizer and the UI, not a constraint. Write a validation (Chapter 12).

---

### Associations

```abap
association [0..1] to /DMO/I_Agency as _Agency on $projection.AgencyId = _Agency.AgencyID
```

| Part | Meaning |
|---|---|
| `association [0..1] to /DMO/I_Agency` | A reference to another entity. Not part of this BO. |
| `as _Agency` | The alias. |
| `on $projection.AgencyId = _Agency.AgencyID` | The join condition. |

**`$projection` vs the source alias — this matters.**

| You write | It means |
|---|---|
| `$projection.AgencyId` | Use the field **as it appears in the SELECT list of this view** (i.e. after the `as AgencyId` rename). |
| `Travel.agency_id` | Use the field **from the data source**, with its DDIC name. |

Both work here. Prefer `$projection` because:

- it survives a change of data source,
- it works when the field is calculated (e.g. `cast(...)` or a `case`), which a direct source
  reference cannot do.

**When must you use the source alias instead?** When the field is *not* in the SELECT list. If you
want to join on `ztravel~agency_id` but you do not expose `AgencyId`, you must write
`Travel.agency_id`.

#### Associations are *not* joins

A CDS association is a **lazy** join. It is only resolved when the association is actually used
(a path expression, a `_Agency.Name` in a projection, an OData `$expand`, or a UI value help).
If nobody uses it, no join is executed. That is why exposing 10 associations costs nothing,
while 10 `LEFT OUTER JOIN`s cost a lot.

This is one of the strongest reasons to model with associations rather than joins in CDS.

#### Exposing an association's field directly

```abap
_Agency.Name as AgencyName,     " path expression - creates an implicit LEFT OUTER JOIN when used
```
Legal, and useful for a read-only report. Avoid it in a transactional interface view — it makes the
field non-updatable and drags the joined table into every read.

---

### The field list

```abap
key travel_uuid as TravelUUID,
```

| Part | Meaning |
|---|---|
| `key` | Marks this as a key element of the CDS entity. **This — not the DDIC key — is what RAP uses as the BO key.** |
| `travel_uuid` | Source field name. |
| `as TravelUUID` | The CDS element name. This is the name used in the BDEF, in EML, in the draft table, and in OData. |

**Naming convention for elements:** `UpperCamelCase`, no underscores. `travel_uuid` → `TravelUUID`.
This is not cosmetic: OData property names come from here, and Fiori Elements conventions assume it.

> Do not expose the `client` field. CDS handles client dependency automatically. Exposing `mandt`
> breaks the OData model.

```abap
      travel_id   as TravelId,
      agency_id   as AgencyId,
```
Plain fields, renamed. No annotation needed.

---

### `@Semantics` annotations — what each one actually buys you

```abap
@Semantics.amount.currencyCode: 'CurrencyCode'
booking_fee as BookingFee,
```
Declares that `BookingFee` is an amount whose currency is in the element `CurrencyCode`
**of this same view** (note: element name, not `table.field` as in the DDIC table).

What it gives you:

- correct decimal-shift rendering in Fiori (JPY has 0 decimals, KWD has 3),
- the currency shown next to the number,
- aggregation/conversion support in analytical scenarios,
- a CDS activation **warning** if missing.

```abap
@Semantics.quantity.unitOfMeasure: 'UnitOfMeasure'
```
Same for quantities. Both annotations must point at an element that is actually in the SELECT list.

```abap
@Semantics.user.createdBy: true
created_by as CreatedBy,

@Semantics.systemDateTime.createdAt: true
created_at as CreatedAt,

@Semantics.user.lastChangedBy: true
last_changed_by as LastChangedBy,

@Semantics.systemDateTime.lastChangedAt: true
last_changed_at as LastChangedAt,

@Semantics.systemDateTime.localInstanceLastChangedAt: true
local_last_changed_at as LocalLastChangedAt,
```

These five are **functional, not documentation**. In a *managed* RAP BO they trigger automatic
behaviour:

| Annotation | Effect in managed RAP |
|---|---|
| `@Semantics.user.createdBy` | Framework fills the field with `sy-uname` on create. You do **not** write a determination. |
| `@Semantics.systemDateTime.createdAt` | Framework fills the timestamp on create. |
| `@Semantics.user.lastChangedBy` | Framework fills on every change. |
| `@Semantics.systemDateTime.lastChangedAt` | Framework fills on every change. Enables `total etag` support. |
| `@Semantics.systemDateTime.localInstanceLastChangedAt` | Framework fills on every local change. Enables `etag master` support. |

For the ETag annotations, the field type must be `utclong`, `timestamp` or `timestampl`
(`abp_locinst_lastchange_tstmpl` is `timestampl` — correct).

> Combined with the BDEF's `readonly` on these fields (Chapter 08), this is the complete admin-field
> solution. Zero lines of ABAP.

---

### Exposing associations at the end

```abap
      /* Associations */
      _Booking,
      _Agency,
      _Customer,
      _Currency
```

An association declared in the header is **not** available to consumers unless you also list it in
the SELECT list. Forgetting this is the classic cause of:

> *"_Booking is not a valid element of ZR_TravelTP"* when you write the BDEF or the projection.

Exposing `_Booking` (the composition) is **mandatory** — the BDEF needs it.

---

## 3.5 The child interface view `ZR_BookingTP`

```abap
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Booking - interface view'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZR_BookingTP
  as select from zbooking as Booking

  association to parent ZR_TravelTP as _Travel
    on $projection.TravelUUID = _Travel.TravelUUID

  association [0..1] to /DMO/I_Customer   as _Customer   on $projection.CustomerId   = _Customer.CustomerID
  association [0..1] to /DMO/I_Carrier    as _Carrier    on $projection.CarrierId    = _Carrier.AirlineID
  association [0..1] to /DMO/I_Connection as _Connection on  $projection.CarrierId    = _Connection.AirlineID
                                                         and $projection.ConnectionId = _Connection.ConnectionID
{
  key booking_uuid    as BookingUUID,
      travel_uuid     as TravelUUID,
      booking_id      as BookingId,
      booking_date    as BookingDate,
      customer_id     as CustomerId,
      carrier_id      as CarrierId,
      connection_id   as ConnectionId,
      flight_date     as FlightDate,
      @Semantics.amount.currencyCode: 'CurrencyCode'
      flight_price    as FlightPrice,
      currency_code   as CurrencyCode,
      booking_status  as BookingStatus,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      last_changed_at as LastChangedAt,

      /* Associations */
      _Travel,
      _Customer,
      _Carrier,
      _Connection
}
```

### The three differences from the root view

1. **No `root` keyword.** A child is not a root.

2. **`association to parent`** — this is a special association type, not a normal one:
   ```abap
   association to parent ZR_TravelTP as _Travel
     on $projection.TravelUUID = _Travel.TravelUUID
   ```
   | Rule | Detail |
   |---|---|
   | Exactly one per child entity | A child has exactly one parent. |
   | No cardinality allowed on the left | It is implicitly `[1..1]`. Writing `association [1..1] to parent` is a syntax error. |
   | Must be exposed in the SELECT list | Same rule as any association. |
   | Supplies the composition's join condition | This is why the parent's `composition` line has no `on`. |

3. **`TravelUUID` is exposed but is not a key.** It must be in the SELECT list so the
   `association to parent` can reference it via `$projection`.

---

## 3.6 Multi-level compositions

Compositions nest arbitrarily:

```
ZR_TravelTP  (root)
   +-- _Booking      ZR_BookingTP
          +-- _BookingSupplement   ZR_BookSupplTP
```

- `ZR_BookingTP` gets a `composition [0..*] of ZR_BookSupplTP as _BookingSupplement`.
- `ZR_BookSupplTP` gets `association to parent ZR_BookingTP as _Booking`.
- Only `ZR_TravelTP` is `root`. Intermediate nodes are plain `view entity`.
- **A grandchild may also declare an association back to the root** for convenience:
  ```abap
  association [1..1] to ZR_TravelTP as _Travel on $projection.TravelUUID = _Travel.TravelUUID
  ```
  This is normal and useful — you often need the root key in a child's validation.

Practical limit: SAP supports deep trees, but every level adds a lock scope, a draft table and a
handler class. Three levels is a lot. If you are at four, question the model.

---

## 3.7 Common building blocks in interface views

### `cast`

```abap
cast( overall_status as zde_overall_status preserving type ) as OverallStatus,
```
Retypes a field. `preserving type` keeps the underlying built-in type and only swaps the data
element — that is what you want when the source is a generic `char1` and you need your own
data element (with its fixed values) so the UI shows a dropdown.

### `case`

```abap
case overall_status
  when 'O' then 2      " yellow / critical
  when 'A' then 3      " green  / positive
  when 'X' then 1      " red    / negative
  else 0
end                                as OverallStatusCriticality,
```
Calculated criticality. Feeds `@UI.criticality` in the metadata extension (Chapter 05) to colour a
status column. Note it is calculated *here* in the interface view so that every consumer gets it —
this is business semantics, not layout.

### Arithmetic and `@EndUserText.label` on an element

```abap
@EndUserText.label: 'Trip duration (days)'
dats_days_between( begin_date, end_date ) as TripDuration,
```

### Currency and unit conversion

```abap
currency_conversion(
  amount               => total_price,
  source_currency      => currency_code,
  target_currency      => cast( 'EUR' as abap.cuky ),
  exchange_rate_date   => begin_date,
  error_handling       => #SET_TO_NULL )  as TotalPriceEUR,
```

### `@ObjectModel.text.element` — text for a code

```abap
@ObjectModel.text.element: ['OverallStatusText']
overall_status as OverallStatus,
_StatusText.Text as OverallStatusText,
```
Tells the UI: when displaying `OverallStatus`, show `OverallStatusText`. The rendering
(`#TEXT_ONLY`, `#TEXT_FIRST`, ...) is then controlled with `@UI.textArrangement` in the metadata
extension.

---

## 3.8 What *not* to do in the interface view

| Anti-pattern | Why it hurts | Do instead |
|---|---|---|
| `@UI.lineItem` etc. | Every service inherits your layout | Metadata extension on `ZC_` |
| `LEFT OUTER JOIN` to master data | Always executed, even when unused | `association` |
| `WHERE` clause filtering business data (`where deleted = ''`) | Hidden filter surprises every consumer; also breaks managed CRUD (you can create a row the view then hides) | Filter in the projection, or model a proper status |
| Client field in the SELECT list | Breaks OData | Omit it |
| `union` / `union all` | A BO root with a union cannot be managed (no single persistent table) | One view per source, or an unmanaged BO |
| Aggregation (`sum(...)`, `group by`) | Not updatable, cannot be a transactional root | Separate analytical view |
| Field names with underscores | Non-standard OData properties; draft table naming becomes ambiguous | `UpperCamelCase` |

> **The hard rule for managed RAP:** the root interface view must be a **1:1 projection of one
> persistent table** — no joins that multiply rows, no aggregation, no union. The managed runtime
> maps `INSERT`/`UPDATE`/`DELETE` straight onto `persistent table`. Anything that breaks the 1:1
> mapping breaks the managed save.

---

## 3.9 Checklist

- [ ] Root view is `define root view entity`.
- [ ] Composition declared on the parent, `association to parent` on the child.
- [ ] Every association **and** the composition appear in the SELECT list.
- [ ] Element names are `UpperCamelCase`, no client field.
- [ ] All five admin fields carry their `@Semantics` annotations.
- [ ] Every amount has `@Semantics.amount.currencyCode`.
- [ ] No `@UI` annotations anywhere.
- [ ] Activates with zero warnings.

---

## 3.10 Interview answer

> **"What is the difference between a composition and an association?"**
>
> A composition defines the **boundary of the business object**: the child is owned by the parent,
> cannot exist without it, is locked with it, saved in the same LUW, and deleted when the parent is
> deleted. An association is just a reference to something outside the BO — master data, or another
> business object — and is completely independent.
>
> The composition is declared on the parent with `composition [0..*] of ZR_BookingTP as _Booking`,
> and the child declares the matching `association to parent`. There is no `on` condition on the
> composition, because the join condition comes from the child's parent association.
>
> The practical test: would deleting the parent delete it, and should it be locked with the parent?
> A booking inside a travel, yes — composition. A customer, no — association, always.
>
> One thing worth adding: a CDS association is **lazy**. It is only resolved when something actually
> uses it, so exposing ten associations costs nothing, whereas ten `LEFT OUTER JOIN`s cost every
> read. That is the main reason to model with associations rather than joins.

## 3.11 Production considerations

- **Keep `ZR_` free of `@UI` annotations.** Every future service inherits whatever you put there.
  Use `@Metadata.ignorePropagatedAnnotations: true` so nothing leaks up from below either.
- **Verify association cardinalities against real data.** CDS does not enforce `[0..1]`; a wrong
  cardinality silently multiplies rows when the association is used in a path expression.
- **For managed RAP the root must be a 1:1 projection of one persistent table.** No joins that
  multiply rows, no aggregation, no union — the managed save maps directly onto `persistent table`.
- **Avoid a `where` clause on the interface view.** A hidden filter surprises every consumer and can
  make a created instance invisible.
- **Calculate criticality and other business-semantic derivations here**, not in the metadata
  extension, so every consumer gets them consistently.
- **Element names are the OData property names.** Renaming one later is a breaking change for any
  external consumer.

---

[< Data Model](02-Data-Model-and-Tables.md) | [Index](00-README.md) | [Next: Projection View >](04-Projection-View.md)
