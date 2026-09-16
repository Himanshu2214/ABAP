# Chapter 04 — The Projection (Consumption) View, Line by Line

[< Basic View](03-Basic-Interface-View.md) | [Index](00-README.md) | [Next: Metadata Extension >](05-Metadata-Extension-and-UI-Annotations.md)

---

## 4.1 Why a projection layer exists at all

A projection view is a **service-specific window onto the business object**.

The BO (`ZR_TravelTP`) has 40 fields, 6 actions, and 3 child levels. A given app might need 12
fields, 2 actions, and 1 child level. The projection is where you say so.

Three things the projection gives you that nothing else can:

1. **Field subsetting per service.** The manager app exposes `BookingFee`; the employee app does not.
2. **Independent lifecycle.** You can add a field to `ZR_` without changing any running service.
3. **UI attachment point.** Value helps, search, text arrangement and the metadata extension all hang
   off the projection, not the BO.

> **"Projection view" and "consumption view" mean the same thing in RAP.** SAP's terminology for
> the VDM calls the top layer "consumption"; RAP calls the `as projection on` construct a
> "projection view". Same object. This documentation uses **projection**.

---

## 4.2 `as projection on` vs `as select from`

This is the core syntactic difference from Chapter 03.

```abap
define view entity ZC_TravelTP as projection on ZR_TravelTP { ... }
```

| | `as select from` | `as projection on` |
|---|---|---|
| Can join, filter, aggregate | Yes | **No** (only `where`, and only in limited form) |
| Inherits the behavior of the source | No | **Yes** — this is how the BDEF projection attaches |
| Can rename fields | Yes | Yes |
| Can add calculated fields | Yes | Only via `virtual` elements or by exposing an existing one |
| Fields must exist in the source | — | Yes, all of them |
| Used for | Modelling | Service exposure |

`as projection on` is deliberately restrictive. It guarantees that the projection is a *true
subset* of the BO, which is what makes it safe for the behavior projection to reuse the BO's
behavior 1:1.

> If you find yourself needing a join in a projection, you need a new interface view, not a
> cleverer projection.

---

## 4.3 The root projection `ZC_TravelTP` — full source

```abap
@EndUserText.label: 'Travel - projection view for Fiori UI'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@Search.searchable: true
define root view entity ZC_TravelTP
  provider contract transactional_query
  as projection on ZR_TravelTP
{
  key TravelUUID,

      @Search.defaultSearchElement: true
      TravelId,

      @Consumption.valueHelpDefinition: [{ entity: { name: '/DMO/I_Agency', element: 'AgencyID' } }]
      @ObjectModel.text.element: ['AgencyName']
      AgencyId,
      _Agency.Name as AgencyName,

      @Consumption.valueHelpDefinition: [{ entity: { name: '/DMO/I_Customer', element: 'CustomerID' } }]
      @ObjectModel.text.element: ['CustomerName']
      CustomerId,
      _Customer.LastName as CustomerName,

      BeginDate,
      EndDate,

      @Semantics.amount.currencyCode: 'CurrencyCode'
      BookingFee,
      @Semantics.amount.currencyCode: 'CurrencyCode'
      TotalPrice,
      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_Currency', element: 'Currency' } }]
      CurrencyCode,

      @Search.defaultSearchElement: true
      Description,

      OverallStatus,
      OverallStatusCriticality,

      CreatedBy,
      CreatedAt,
      LastChangedBy,
      LastChangedAt,
      LocalLastChangedAt,

      /* Associations */
      _Booking : redirected to composition child ZC_BookingTP,
      _Agency,
      _Customer,
      _Currency
}
```

---

## 4.4 Line by line

### `@EndUserText.label`

```abap
@EndUserText.label: 'Travel - projection view for Fiori UI'
```
Appears in the OData `$metadata` as the entity set label and, if no `@UI.headerInfo` is defined,
in the app title.

### `@AccessControl.authorizationCheck: #CHECK`

```abap
@AccessControl.authorizationCheck: #CHECK
```
This is the layer where DCL (CDS access control) belongs. `#CHECK` means: *a DCL role exists for
this entity and it will be applied to every read.*

The matching DCL object (`ZC_TravelTP` — same name, object type *Access Control*):

```abap
@EndUserText.label: 'Access control for Travel'
@MappingRole: true
define role ZC_TRAVELTP {
  grant select on ZC_TravelTP
    where ( AgencyId ) = aspect pfcg_auth( ZTRAVEL_AUTH, AGENCY_ID, ACTVT = '03' );
}
```

| Part | Meaning |
|---|---|
| `@MappingRole: true` | The role is automatically assigned to users who have the PFCG authorization. Without it the role has to be assigned explicitly. |
| `grant select on ZC_TravelTP` | Read access. DCL controls **read only** — write access is controlled by the BDEF's `authorization master`. |
| `aspect pfcg_auth( ... )` | Bind to a classic PFCG authorization object. The user's authorized `AGENCY_ID` values become a `WHERE` filter. |

> **Key point:** DCL filters *reads*. It does **not** stop an update. Modification authorization is
> the BDEF's job (`FOR GLOBAL AUTHORIZATION` / `FOR INSTANCE AUTHORIZATION`, Chapter 14).
> Many teams assume DCL covers everything. It does not.

### `@Metadata.allowExtensions: true`

```abap
@Metadata.allowExtensions: true
```
**Mandatory if you want a metadata extension.** It declares that this view may be annotated from a
separate Metadata Extension object.

If you forget it, activating the metadata extension fails with
*"Extension of view ZC_TravelTP is not allowed"*.

Note it is mutually exclusive with `@Metadata.ignorePropagatedAnnotations: true` in practice —
on a projection you want extensions, so use `allowExtensions`.

### `@Search.searchable: true`

```abap
@Search.searchable: true
```
Turns on the **free-text search box** in the Fiori List Report. Requires at least one element
annotated with `@Search.defaultSearchElement: true`.

```abap
@Search.defaultSearchElement: true
TravelId,
```
This field participates in free-text search. Optional refinements:
```abap
@Search.defaultSearchElement: true
@Search.fuzzinessThreshold: 0.8       " HANA fuzzy search, 0.0 - 1.0
@Search.ranking: #HIGH                " weight this field higher in the result ranking
Description,
```

`@Search.fuzzinessThreshold` is a real HANA feature: `0.8` finds "Barcelona" when the user types
"Barcelna". Values below ~0.7 produce noise.

---

### `provider contract transactional_query`

```abap
define root view entity ZC_TravelTP
  provider contract transactional_query
  as projection on ZR_TravelTP
```

This one clause decides what kind of service this projection is.

| Contract | Meaning | Needs a BDEF? |
|---|---|---|
| `transactional_query` | A transactional BO projection. Read **and** write. The behavior comes from the projection BDEF. | **Yes** |
| `transactional_interface` | Used on an interface-layer projection for reuse between services (an intermediate layer). | Yes |
| *(omitted)* | Plain read-only projection. No behavior at all. | **No** |
| `analytical_query` | An analytical query (`@Analytics.query: true` style). | No |

**For a read-only Fiori report (Chapter 07), omit `provider contract` entirely.** Adding
`transactional_query` without a BDEF causes activation error
*"No behavior definition found for ZC_TravelTP"*.

---

### `key TravelUUID,`

The key of the projection must be the key of the BO. You cannot re-key a projection.

---

### Field exposure and renaming

```abap
      TravelId,
      BookingFee,
```
Just list the element name. The name from `ZR_` carries through.

Renaming is allowed:
```abap
      TravelId as TravelNumber,
```
It changes the OData property name. Do it only when you must match an external contract — it breaks
the mental link between the layers, and the BDEF projection still refers to the **base** name.

**Fields you omit** simply do not exist in the service. They are not read, not sent, not writable.
This is a real performance lever on wide tables.

---

### Path expressions for text fields

```abap
      _Agency.Name as AgencyName,
```
Legal in a projection — path expressions along an **exposed association** are one of the few
"calculated" things a projection may do.

Caveats:

- The resulting field is **read-only**. You cannot update `AgencyName`.
- It triggers a `LEFT OUTER JOIN` whenever read. Fine for a handful of fields.
- The association (`_Agency`) must also be exposed in the SELECT list.

---

### `@ObjectModel.text.element`

```abap
      @ObjectModel.text.element: ['AgencyName']
      AgencyId,
      _Agency.Name as AgencyName,
```
Declares that `AgencyName` is the descriptive text of `AgencyId`. The UI can then display
"Aurora Travel (070001)" instead of "070001". How it is arranged is decided in the metadata
extension:

```abap
@UI.textArrangement: #TEXT_FIRST       " Aurora Travel (070001)
@UI.textArrangement: #TEXT_LAST        " 070001 (Aurora Travel)
@UI.textArrangement: #TEXT_ONLY        " Aurora Travel
@UI.textArrangement: #TEXT_SEPARATE    " two separate columns
```

---

### `@Consumption.valueHelpDefinition` — the F4 help

```abap
      @Consumption.valueHelpDefinition: [{ entity: { name: '/DMO/I_Agency', element: 'AgencyID' } }]
      AgencyId,
```

| Part | Meaning |
|---|---|
| `[{ ... }]` | An **array** — a field can have several value helps (the UI shows a dropdown to pick which). |
| `entity.name` | The CDS entity providing the values. Must be exposed in the same service **or** be a released/searchable entity. |
| `entity.element` | Which element of that entity supplies the value for `AgencyId`. |

#### Value help with additional binding (multi-field / filtered)

For a dependent value help — e.g. Connection depends on Carrier:

```abap
      @Consumption.valueHelpDefinition: [{
        entity          : { name: '/DMO/I_Connection', element: 'ConnectionID' },
        additionalBinding: [
          { localElement: 'CarrierId', element: 'AirlineID', usage: #FILTER_AND_RESULT },
          { localElement: 'FlightPrice', element: 'Price',   usage: #RESULT }
        ]
      }]
      ConnectionId,
```

| `usage` | Meaning |
|---|---|
| `#FILTER` | The local value restricts the value-help list. |
| `#RESULT` | The selected row writes back into the local field. |
| `#FILTER_AND_RESULT` | Both. |

This is how you build "pick a flight and the price fills itself in" without a single line of ABAP.

#### Value help sourced from domain fixed values

If the underlying data element has domain fixed values, **you need no annotation at all** — the UI
renders a dropdown automatically. Only reach for `@Consumption.valueHelpDefinition` when the values
come from a table.

#### `@Consumption.filter`

```abap
      @Consumption.filter: { selectionType: #INTERVAL, multipleSelections: true, mandatory: false }
      BeginDate,
```
Controls how the field behaves in the filter bar.

| Sub-annotation | Values |
|---|---|
| `selectionType` | `#SINGLE`, `#INTERVAL`, `#RANGE`, `#HIERARCHY_NODE` |
| `multipleSelections` | `true` / `false` |
| `mandatory` | `true` forces the user to fill it before the list loads — useful on large tables |
| `defaultValue` / `defaultValueHigh` | Prefill |

`mandatory: true` on a selective field is the single most effective way to stop a List Report from
reading 10 million rows on open.

---

### `redirected to` — the most important line in the file

```abap
      _Booking : redirected to composition child ZC_BookingTP,
```

**What problem it solves:** `ZR_TravelTP._Booking` points at `ZR_BookingTP`. But the service
exposes `ZC_BookingTP`. Without redirection, navigating from the Travel to its Bookings in OData
would land on the *interface* entity, which is not part of the service. Activation fails with
*"_Booking must be redirected"*.

`redirected to` re-targets the association **inside this service**.

#### The three forms

| Form | Use for |
|---|---|
| `redirected to composition child ZC_BookingTP` | A **composition** to a child projection |
| `redirected to parent ZC_TravelTP` | The child's `association to parent` |
| `redirected to ZC_SomeOther` | A plain **association** to another projection in the same service |

```abap
" In ZC_TravelTP (parent):
_Booking : redirected to composition child ZC_BookingTP,

" In ZC_BookingTP (child):
_Travel  : redirected to parent ZC_TravelTP,
```

#### When do you *not* redirect?

Associations to entities that stay outside the service — `_Agency`, `_Customer`, `_Currency`.
They point at released interface views used only for value help and text. Leave them as-is.

Rule: **redirect everything inside your BO tree; leave everything outside alone.**

---

## 4.5 The child projection `ZC_BookingTP`

```abap
@EndUserText.label: 'Booking - projection view'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
define view entity ZC_BookingTP
  as projection on ZR_BookingTP
{
  key BookingUUID,
      TravelUUID,
      BookingId,
      BookingDate,

      @Consumption.valueHelpDefinition: [{ entity: { name: '/DMO/I_Customer', element: 'CustomerID' } }]
      CustomerId,

      @Consumption.valueHelpDefinition: [{ entity: { name: '/DMO/I_Carrier', element: 'AirlineID' } }]
      CarrierId,

      @Consumption.valueHelpDefinition: [{
        entity: { name: '/DMO/I_Connection', element: 'ConnectionID' },
        additionalBinding: [ { localElement: 'CarrierId', element: 'AirlineID', usage: #FILTER_AND_RESULT } ] }]
      ConnectionId,

      FlightDate,
      @Semantics.amount.currencyCode: 'CurrencyCode'
      FlightPrice,
      CurrencyCode,
      BookingStatus,
      LastChangedAt,

      /* Associations */
      _Travel : redirected to parent ZC_TravelTP,
      _Customer,
      _Carrier,
      _Connection
}
```

Note:

- **No `root`** and **no `provider contract`** on the child. The contract is declared once, on the root.
- `_Travel : redirected to parent ZC_TravelTP` — mandatory.

---

## 4.6 Virtual elements — calculated fields in the projection

When you need a field that cannot be derived in CDS (a call to a class, a conversion, a lookup that
SQL cannot express):

```abap
      @ObjectModel.virtualElement: true
      @ObjectModel.virtualElementCalculatedBy: 'ABAP:ZCL_TRAVEL_VE_CALC'
      @EndUserText.label: 'Days until departure'
      virtual DaysUntilDeparture : abap.int4,
```

The class implements `IF_SADL_EXIT_CALC_ELEMENT_READ`:

```abap
CLASS zcl_travel_ve_calc DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_sadl_exit_calc_element_read.
ENDCLASS.

CLASS zcl_travel_ve_calc IMPLEMENTATION.
  METHOD if_sadl_exit_calc_element_read~get_calculation_info.
    " tell the framework which real fields you need in order to calculate
    APPEND 'BEGINDATE' TO et_requested_orig_elements.
  ENDMETHOD.

  METHOD if_sadl_exit_calc_element_read~calculate.
    DATA lt_data TYPE STANDARD TABLE OF zc_traveltp.
    lt_data = CORRESPONDING #( it_original_data ).
    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<fs>).
      <fs>-DaysUntilDeparture = <fs>-BeginDate - cl_abap_context_info=>get_system_date( ).
    ENDLOOP.
    ct_calculated_data = CORRESPONDING #( lt_data ).
  ENDMETHOD.
ENDCLASS.
```

**Costs to know before you use one:**

- Virtual elements are **not filterable and not sortable** on the database. The framework reads
  the rows first, then calculates. Sorting/filtering on a virtual element pulls the full result set.
- They run **per page** of the result, so the class is called repeatedly.
- They are **read-only**.

Use them for display-only derivations on small result sets. For anything filterable, calculate in
the interface view instead.

---

## 4.7 Adding a `where` clause

A projection may carry a `where`:

```abap
define view entity ZC_TravelActiveTP
  provider contract transactional_query
  as projection on ZR_TravelTP
{
  ...
}
where OverallStatus <> 'X'
```

This creates a **service-specific filter** — e.g. an app that only shows non-cancelled travels.

Be careful: in a transactional projection, a `where` clause means a user can create an instance
that then disappears from the list (because it does not match the filter). RAP does not warn you.
If you filter, make sure the filtered attribute is read-only or defaulted so this cannot happen.

---

## 4.8 Common activation errors in this layer and their real cause

| Error | Real cause |
|---|---|
| *"Association _Booking must be redirected"* | Missing `redirected to composition child` |
| *"No behavior definition found for ZC_TravelTP"* | `provider contract transactional_query` present but no projection BDEF created |
| *"Extension of view ... is not allowed"* | Missing `@Metadata.allowExtensions: true` |
| *"Element ... does not exist in ZR_TravelTP"* | Field not exposed in the interface view, or a typo in the CamelCase spelling |
| *"Use of ... not permitted in a projection view"* | You wrote a join / aggregation; move it to an interface view |
| *"The provider contract of the root ... differs"* | `provider contract` accidentally repeated on the child |
| Value help does not appear in the app | The value-help entity is not exposed in the service **and** is not a released entity; or `@Metadata.allowExtensions` blocked propagation |

---

## 4.9 Checklist

- [ ] `as projection on`, not `as select from`.
- [ ] `provider contract transactional_query` **only** on the root, **only** if a BDEF exists.
- [ ] `@Metadata.allowExtensions: true` on every projection you will annotate.
- [ ] `@AccessControl.authorizationCheck: #CHECK` plus a DCL, or a conscious decision not to.
- [ ] Every composition redirected with `composition child`; every parent association with `parent`.
- [ ] Value helps on all code fields that are not domain fixed values.
- [ ] Key field of the projection = key field of the BO.

---

## 4.10 Interview answer

> **"Why do we need a projection view?"**
>
> Because the business object model and the service are different concerns. The interface view is
> the canonical model — all fields, the composition tree, semantics. The projection is a
> **service-specific window** onto it: the subset of fields this app needs, the value helps, the
> DCL, and the attachment point for the metadata extension.
>
> That gives three things. One business object can serve several services with different fields and
> different enabled operations. You can extend the model without touching a running service. And
> business semantics stay separate from presentation.
>
> It is written with `as projection on`, which is deliberately restrictive — no joins, no
> aggregation — so the projection is guaranteed to be a true subset, which is what makes the
> projection behavior definition safe.
>
> Two details interviewers probe: `provider contract transactional_query` is what makes it a
> transactional service and requires a projection BDEF — leave it off and you get a read-only
> service, which is exactly right for a report. And every composition must be `redirected to
> composition child`, every parent association `redirected to parent`, otherwise navigation would
> land on the interface entity, which is not part of the service.

## 4.11 Production considerations

- **Expose only the fields the service uses.** Every extra field is read on every Object Page load
  and every `$expand`.
- **Decide the DCL layer deliberately** (§4.4) and write the decision down — it is hard to change
  once several services depend on the model.
- **Value-help entities must also be exposed in the service definition**, or the F4 is empty in the
  target system. This is a classic QA-only failure.
- **Renaming a projection field is a breaking change** for any external consumer of the Web API.
  Version the service binding rather than rename.
- **Virtual elements are display-only.** They are computed in ABAP per page and cannot be filtered
  or sorted on the database.
- **A `where` clause on a transactional projection can hide instances the user just created.**
  If you filter, make the filtered field read-only or defaulted.

---

[< Basic View](03-Basic-Interface-View.md) | [Index](00-README.md) | [Next: Metadata Extension >](05-Metadata-Extension-and-UI-Annotations.md)
