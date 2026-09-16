# Chapter 22 — Value Helps and Text Associations

[< Side Effects](21-Side-Effects.md) | [Index](00-README.md) | [Next: Testing & Debugging >](23-Testing-and-Debugging.md)

---

## 22.1 What is it?

Two related but distinct mechanisms:

| Mechanism | Answers | Annotation |
|---|---|---|
| **Value help** | "What may I type into this field?" | `@Consumption.valueHelpDefinition` |
| **Text association** | "What does this code mean?" | `@ObjectModel.text.element` + `@UI.textArrangement` |

A field usually needs **both**: a dropdown to pick `070001`, and a text so the user sees
*Aurora Travel* rather than a number.

---

## 22.2 Why do we need it?

- Users do not know code values. `AgencyId = 070001` is meaningless on screen.
- Free-text entry into a code field guarantees bad data. A value help turns a validation problem
  into an input constraint.
- A well-built value help can **fill several fields at once** (pick a flight → carrier, price and
  currency fill themselves), removing both typing and a determination.
- It is entirely declarative. A dependent, filtered, searchable value help with write-back is
  annotations only — no ABAP.

---

## 22.3 Where is it used?

| Layer | What goes there |
|---|---|
| Interface view `ZR_` / `ZI_` | The **association** to the master-data entity, and the text field if it is exposed via a path expression |
| Projection view `ZC_` | `@Consumption.valueHelpDefinition`, `@ObjectModel.text.element`, `@Consumption.filter` |
| Metadata extension | `@UI.textArrangement`, hiding the text element, `@UI.lineItem` on the code field |
| Service definition | **`expose`** of every value-help and text entity — the step people forget |

> **The single most common cause of an empty F4 in a custom app is a value-help entity that is not
> exposed in the service definition.** Check that before anything else.

---

## 22.4 Syntax

### Value help — the four forms

```abap
// 1. Simplest: one entity, one element
@Consumption.valueHelpDefinition: [{ entity: { name: '/DMO/I_Agency', element: 'AgencyID' } }]
AgencyId,

// 2. Several alternative value helps on one field (the UI offers a chooser)
@Consumption.valueHelpDefinition: [
  { entity: { name: 'ZI_ActiveCustomer',   element: 'CustomerId' }, label: 'Active customers' },
  { entity: { name: 'ZI_ProspectCustomer', element: 'CustomerId' }, label: 'Prospects' } ]
CustomerId,

// 3. Dependent / parameterised: the local value restricts the list,
//    and the chosen row writes back into several local fields
@Consumption.valueHelpDefinition: [{
  entity           : { name: '/DMO/I_Connection', element: 'ConnectionID' },
  additionalBinding: [
    { localElement: 'CarrierId',    element: 'AirlineID', usage: #FILTER_AND_RESULT },
    { localElement: 'FlightPrice',  element: 'Price',     usage: #RESULT },
    { localElement: 'CurrencyCode', element: 'Currency',  usage: #RESULT } ] }]
ConnectionId,

// 4. Value help on a CDS view with parameters
@Consumption.valueHelpDefinition: [{
  entity           : { name: 'ZI_PriceListVH', element: 'Material' },
  additionalBinding: [ { localElement: 'BeginDate', parameter: 'p_KeyDate' } ] }]
Material,
```

#### `additionalBinding.usage`

| Value | Effect |
|---|---|
| `#FILTER` | The local field's value **restricts** the value-help list |
| `#RESULT` | The selected row **writes back** into the local field |
| `#FILTER_AND_RESULT` | Both |

### Text association

```abap
// in the projection
@ObjectModel.text.element: ['AgencyName']
AgencyId,
_Agency.Name as AgencyName,
```

```abap
// in the metadata extension
@UI.textArrangement: #TEXT_FIRST
AgencyId;

@UI.hidden: true
AgencyName;
```

| `@UI.textArrangement` | Renders |
|---|---|
| `#TEXT_FIRST` | `Aurora Travel (070001)` |
| `#TEXT_LAST` | `070001 (Aurora Travel)` |
| `#TEXT_ONLY` | `Aurora Travel` |
| `#TEXT_SEPARATE` | Two independent columns |

### Domain fixed values — the free option

If the field's data element has **domain fixed values**, Fiori renders a dropdown with the
translated texts and **no annotation is needed at all**. Reach for
`@Consumption.valueHelpDefinition` only when the values live in a table.

---

## 22.5 Complete example

A custom, searchable, filtered value help for **Agency**, built from scratch, with text, search and
a dependent second field.

### Step 1 — the value-help provider view

```abap
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Agency - value help'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType: { serviceQuality: #C, sizeCategory: #S, dataClass: #MASTER }

@Search.searchable: true                        // enables the search box in the F4 dialog
@ObjectModel.resultSet.sizeCategory: #XS        // hint: small result set

define view entity ZI_AgencyVH
  as select from /dmo/agency as Agency
{
      @Search.defaultSearchElement: true
      @Search.ranking: #HIGH
  key agency_id      as AgencyId,

      @Search.defaultSearchElement: true
      @Search.fuzzinessThreshold: 0.8
      name           as Name,

      @Search.defaultSearchElement: true
      city           as City,

      country_code   as CountryCode,
      postal_code    as PostalCode,
      phone_number   as PhoneNumber,
      email_address  as EmailAddress
}
```

Notes:

| Line | Why |
|---|---|
| `@Search.searchable: true` on the view | Turns on the free-text search field inside the F4 dialog |
| `@Search.defaultSearchElement: true` on several fields | The user can find an agency by id, name **or** city |
| `@Search.fuzzinessThreshold: 0.8` | HANA fuzzy search — finds *Barcelona* when the user types *Barcelna*. Below ~0.7 produces noise |
| `@Search.ranking: #HIGH` | An exact id match ranks above a name match |
| `@ObjectModel.resultSet.sizeCategory: #XS` | Tells the runtime this list is small, so it can be loaded eagerly |
| No `@UI` annotations | The F4 dialog builds its own columns; add `@UI.lineItem` only if you want to control which columns appear |

### Step 2 — the association in the interface view

```abap
define root view entity ZR_TravelTP
  as select from ztravel as Travel

  composition [0..*] of ZR_BookingTP as _Booking

  association [0..1] to ZI_AgencyVH as _Agency
    on $projection.AgencyId = _Agency.AgencyId
{
  key travel_uuid as TravelUUID,
      agency_id   as AgencyId,
      ...
      _Booking,
      _Agency                        // must be exposed
}
```

### Step 3 — the projection: value help + text + filter

```abap
define root view entity ZC_TravelTP
  provider contract transactional_query
  as projection on ZR_TravelTP
{
  key TravelUUID,

      // ---- value help ------------------------------------------------
      @Consumption.valueHelpDefinition: [{
        entity: { name: 'ZI_AgencyVH', element: 'AgencyId' } }]
      // ---- text association ------------------------------------------
      @ObjectModel.text.element: ['AgencyName']
      // ---- filter-bar behaviour ---------------------------------------
      @Consumption.filter: { selectionType: #SINGLE, multipleSelections: true }
      AgencyId,

      _Agency.Name as AgencyName,          // the text, read-only

      // ---- dependent value help: Connection depends on Carrier --------
      @Consumption.valueHelpDefinition: [{
        entity: { name: '/DMO/I_Carrier', element: 'AirlineID' } }]
      @ObjectModel.text.element: ['CarrierName']
      CarrierId,
      _Carrier.Name as CarrierName,

      @Consumption.valueHelpDefinition: [{
        entity           : { name: '/DMO/I_Connection', element: 'ConnectionID' },
        additionalBinding: [
          { localElement: 'CarrierId',    element: 'AirlineID',    usage: #FILTER_AND_RESULT },
          { localElement: 'FlightPrice',  element: 'Price',        usage: #RESULT },
          { localElement: 'CurrencyCode', element: 'Currency',     usage: #RESULT },
          { localElement: 'DepartureAirport', element: 'AirportFromID', usage: #RESULT } ] }]
      ConnectionId,

      FlightPrice,
      CurrencyCode,
      DepartureAirport,

      /* Associations */
      _Booking : redirected to composition child ZC_BookingTP,
      _Agency,
      _Carrier,
      _Connection
}
```

### Step 4 — the metadata extension

```abap
@Metadata.layer: #CORE
annotate entity ZC_TravelTP with
{
  @UI.lineItem:        [ { position: 20, importance: #HIGH } ]
  @UI.identification:  [ { position: 20 } ]
  @UI.selectionField:  [ { position: 20 } ]
  @UI.textArrangement: #TEXT_FIRST          // "Aurora Travel (070001)"
  AgencyId;

  @UI.hidden: true                          // the text is shown *through* AgencyId
  AgencyName;

  @UI.lineItem:        [ { position: 30, importance: #HIGH } ]
  @UI.identification:  [ { position: 30 } ]
  @UI.textArrangement: #TEXT_FIRST
  CarrierId;

  @UI.hidden: true
  CarrierName;

  @UI.lineItem:       [ { position: 40, importance: #HIGH } ]
  @UI.identification: [ { position: 40 } ]
  ConnectionId;
}
```

### Step 5 — expose everything in the service definition

```abap
@EndUserText.label: 'Service definition for Travel'
define service ZSD_TRAVEL {
  expose ZC_TravelTP       as Travel;
  expose ZC_BookingTP      as Booking;

  // value-help and text providers - REQUIRED, or the F4 is empty
  expose ZI_AgencyVH       as Agency;
  expose /DMO/I_Carrier    as Carrier;
  expose /DMO/I_Connection as Connection;
  expose I_Currency        as Currency;
}
```

### What the user gets

1. Clicking the Agency field opens a dialog with a search box; typing *barcelna* still finds
   *Barcelona* (fuzzy search).
2. The Agency column shows **Aurora Travel (070001)**.
3. Selecting a Carrier restricts the Connection value help to that carrier's flights.
4. Selecting a Connection fills `FlightPrice`, `CurrencyCode` and `DepartureAirport` automatically —
   no determination, no ABAP.
5. Agency appears in the filter bar with multi-select.

---

## 22.6 Runtime behavior

```
1. User opens the value help on ConnectionId
2. Fiori reads the ValueList annotation from $metadata:
     CollectionPath = "Connection"
     Parameters     = [ In(CarrierId -> AirlineID),
                        Out(Price -> FlightPrice),
                        Out(Currency -> CurrencyCode),
                        InOut(ConnectionId -> ConnectionID) ]
3. It issues: GET /Connection?$filter=AirlineID eq 'LH'&$top=100
4. The user types in the search box:
     GET /Connection?$search=barcel&$filter=AirlineID eq 'LH'
5. The user picks a row; Fiori writes the Out parameters into the local model
6. A PATCH sends the changed fields to the server
```

Points that follow from this:

| Behaviour | Implication |
|---|---|
| The value help is a **normal OData read** of the exposed entity | It obeys that entity's DCL. A user sees only agencies they are authorized to read |
| It is **paged** | A value help over a million rows is fine, provided the entity is indexed and searchable |
| `#FILTER` bindings become `$filter` | The dependent list is filtered **on the database**, not in the browser |
| `#RESULT` bindings write into the **client model** | The server sees them in the subsequent `PATCH`, as if the user had typed them |
| `$search` requires `@Search.searchable` | Without it the dialog has no search box |
| A value help does **not** validate | A user can still `PATCH` an invalid code via the API. You still need a validation (Chapter 12) |

> **A value help is an input aid, not a constraint.** It improves data quality for UI users and does
> nothing for API consumers. Referential integrity still belongs in a validation.

---

## 22.7 Common errors

| Symptom | Cause | Fix |
|---|---|---|
| F4 dialog is empty | Value-help entity not exposed in the service definition | `expose ZI_AgencyVH as Agency;` |
| F4 dialog does not open at all | Annotation on the interface view instead of the projection, or the field is `readonly` | Move the annotation; check field control |
| No search box in the F4 dialog | `@Search.searchable: true` missing on the value-help view | Add it, plus at least one `@Search.defaultSearchElement` |
| Text does not appear next to the code | `@ObjectModel.text.element` missing, or the text element is not exposed, or `@UI.textArrangement` missing | All three are needed |
| Text column appears twice | The text element is not `@UI.hidden: true` | Hide it |
| Dependent value help shows everything | `usage: #FILTER` missing, or `localElement` spelling is wrong | Check both names against the projection |
| Write-back fields stay empty | `usage: #RESULT` missing, or the target field is `readonly` in the BDEF | A `#RESULT` target must be writable |
| Value help works in the List Report filter bar but not on the Object Page | The field is read-only in edit mode via feature control | Check `get_instance_features` |
| Fuzzy search returns nonsense | `fuzzinessThreshold` too low | Raise it to 0.8 or above |
| Value help slow to open | The provider view joins large tables, or has no `sizeCategory` hint | Simplify the view; add `@ObjectModel.resultSet.sizeCategory` |
| Works in DEV, empty in QA | The value-help entity's DCL filters everything for that user | Check the PFCG role in the target system |
| Activation error: element not found | `element:` refers to the value-help entity's element name, not the local one — the two are easy to swap | `entity.element` = remote, `localElement` = local |

---

## 22.8 Interview answer

> **"How do you implement a value help in RAP?"**
>
> With the `@Consumption.valueHelpDefinition` annotation on the field in the **projection view**,
> pointing at a CDS entity that supplies the values. The entity must also be exposed in the service
> definition, otherwise the F4 comes back empty — that is the usual cause of a value help that
> silently does nothing.
>
> For a dependent value help you add `additionalBinding` entries. `usage: #FILTER` means a local
> field restricts the list; `usage: #RESULT` means the selected row writes back into a local field.
> So selecting a flight connection can automatically fill the price and currency without any ABAP.
>
> Separately from the value help, you show the description with `@ObjectModel.text.element`
> pointing at a text field — usually exposed through an association — and control how it renders
> with `@UI.textArrangement`, for example `#TEXT_FIRST`.
>
> If the field's domain has fixed values you need no annotation at all: Fiori renders a dropdown
> automatically.
>
> One thing worth saying: a value help is an input aid, not a constraint. It does not stop an API
> consumer sending an invalid code, so referential integrity still belongs in a validation in the
> behavior pool.

---

## 22.9 Production considerations

- **Build a dedicated `ZI_..._VH` view** rather than pointing the value help at a big transactional
  view. It keeps the F4 fast and lets you filter out obsolete or blocked master data
  (`where DeletionFlag = ''`).
- **Filter out inactive records in the value-help view**, not in the UI. Users should not be offered
  a blocked customer at all.
- **Check the DCL on the value-help entity.** It is a normal read, so it is filtered per user. A
  value help that is full in DEV and empty in PROD is nearly always this.
- **Expose value-help entities in every service that uses them.** Easy to miss when you add a
  second service over the same projection.
- **Use `@ObjectModel.resultSet.sizeCategory`** honestly — it drives whether the UI loads the list
  eagerly or lazily.
- **Fuzzy search costs CPU.** Enable it on the one or two fields where it helps, not on everything.
- **Translate the texts.** A text association pointing at a non-translated field looks fine in
  English and wrong everywhere else.
- **Value helps are part of the transport.** A missing `expose` line is a classic QA-only defect;
  include an F4 check in the post-import test list (Chapter 25).
- **Think about volume.** A value help over a table with millions of rows needs a searchable,
  indexed provider view and should never be marked `#XS`.

---

[< Side Effects](21-Side-Effects.md) | [Index](00-README.md) | [Next: Testing & Debugging >](23-Testing-and-Debugging.md)
