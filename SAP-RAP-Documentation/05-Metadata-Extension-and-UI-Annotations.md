# Chapter 05 — Metadata Extension and UI Annotations

[< Projection View](04-Projection-View.md) | [Index](00-README.md) | [Next: Service Definition & Binding >](06-Service-Definition-and-Binding.md)

---

## 5.1 What a metadata extension is

A **Metadata Extension (MDE)** is a separate development object that adds annotations to a CDS view
without touching the view's source.

```
ZC_TravelTP  (Data Definition)         <- data: which fields exist
ZC_TravelTP  (Metadata Extension)      <- layout: where each field appears
```

Same name, different object type. ADT: *New → Other ABAP Repository Object → Metadata Extension*.

**Prerequisite:** the view must carry `@Metadata.allowExtensions: true`.

### Why bother — three concrete reasons

1. **Volume.** A real List Report + Object Page needs 150–400 lines of `@UI`. Mixed into the
   projection view, the data model becomes unreadable.
2. **Layering.** MDEs have a `@Metadata.layer` — you can ship a `#CORE` layer and let a customer
   override it with an `#INDUSTRY` or `#CUSTOMER` layer, without a modification.
3. **Separate transport.** Layout changes travel independently of model changes.

You *can* write `@UI` directly in the projection view. It works. For anything beyond a 5-field demo,
do not.

---

## 5.2 Anatomy of an MDE

```abap
@Metadata.layer: #CORE

@UI: {
  headerInfo: { typeName: 'Travel',
                typeNamePlural: 'Travels',
                title:       { type: #STANDARD, value: 'TravelId' },
                description: { type: #STANDARD, value: 'Description' } },
  presentationVariant: [ { sortOrder: [ { by: 'TravelId', direction: #DESC } ],
                           visualizations: [ { type: #AS_LINEITEM } ] } ]
}
annotate entity ZC_TravelTP with
{
  @UI.facet: [ ... ]

  @UI.lineItem:       [ { position: 10, importance: #HIGH } ]
  @UI.identification: [ { position: 10 } ]
  @UI.selectionField: [ { position: 10 } ]
  TravelId;

  ...
}
```

| Element | Meaning |
|---|---|
| `@Metadata.layer: #CORE` | The layer of this extension. Order of precedence: `#CORE` < `#LOCALIZATION` < `#INDUSTRY` < `#PARTNER` < `#CUSTOMER`. Higher layers win. Use `#CORE` for your own app. |
| Annotations **before** `annotate entity` | Entity-level annotations (`headerInfo`, `presentationVariant`, `selectionPresentationVariant`, `chart`). |
| `annotate entity ZC_TravelTP with { ... }` | Element-level annotations. Every element you annotate **must exist** in the view. |
| `TravelId;` | The element the preceding annotations apply to. Note the **semicolon**, not a comma. |

> **Syntax trap:** in an MDE, elements are terminated with `;`. In a CDS view, with `,`.
> Getting this wrong produces a confusing parser error.

You do **not** have to list every element. Unlisted elements are still in the OData service (they
are just not placed on any UI position) — they remain available for `$select`, filters via the
adapt-filters dialog, and personalisation.

---

## 5.3 The four annotation groups you cannot avoid

| Annotation | Controls | Appears in |
|---|---|---|
| `@UI.headerInfo` | App title, object title, object subtitle, icon | List Report header, Object Page header |
| `@UI.lineItem` | **Columns of the table** | List Report table, and tables inside Object Page sections |
| `@UI.selectionField` | **Fields in the filter bar** | List Report filter bar |
| `@UI.facet` | **Sections of the Object Page** | Object Page |
| `@UI.identification` | **Fields inside a facet** of type `#IDENTIFICATION_REFERENCE` | Object Page general-information section |
| `@UI.fieldGroup` | Fields grouped under a qualifier, placed by a facet | Object Page sub-sections |

Everything else is refinement.

---

## 5.4 `@UI.headerInfo`

```abap
@UI: {
  headerInfo: {
    typeName:       'Travel',
    typeNamePlural: 'Travels',
    title:          { type: #STANDARD, value: 'TravelId' },
    description:    { type: #STANDARD, value: 'Description' },
    imageUrl:       'ImageUrl',
    typeImageUrl:   'sap-icon://flight'
  }
}
```

| Field | Renders as |
|---|---|
| `typeName` | "Travel" — used in "Create Travel", "Delete Travel?" dialogs |
| `typeNamePlural` | "Travels" — the List Report page title |
| `title` | The big line on the Object Page header |
| `description` | The subtitle under it |
| `typeImageUrl` | An icon (any `sap-icon://` name) |
| `imageUrl` | An element containing a URL to a real image per instance |

`type` can be `#STANDARD` (a plain field) or `#AS_CONNECTED_FIELDS` / `#WITH_INTENT_BASED_NAVIGATION`.

---

## 5.5 `@UI.lineItem` — the table columns

```abap
@UI.lineItem: [ { position: 20, label: 'Travel Number', importance: #HIGH } ]
TravelId;
```

| Property | Meaning |
|---|---|
| `position` | Column order. Use gaps of 10 so you can insert later without renumbering. |
| `label` | Overrides the data element label for this column only. |
| `importance` | `#HIGH` / `#MEDIUM` / `#LOW`. Drives responsive hiding: on a phone only `#HIGH` columns survive. This is the one property people skip and then wonder why the phone layout is unusable. |
| `criticality` | Name of an element holding 0–3. Colours the cell. |
| `type` | `#STANDARD` (default), `#FOR_ACTION`, `#FOR_INTENT_BASED_NAVIGATION`, `#AS_CHART`, `#AS_DATAPOINT`, `#WITH_URL` |
| `hidden` | `true`, or the name of a boolean element for conditional hiding |
| `qualifier` | Lets you define **several different line-item sets** on the same entity (see 5.11) |

### Criticality

```abap
@UI.lineItem: [ { position: 90, criticality: 'OverallStatusCriticality',
                  criticalityRepresentation: #WITH_ICON } ]
OverallStatus;
```

| Value in the criticality element | Colour |
|---|---|
| `0` | Neutral (grey) |
| `1` | Negative (red) |
| `2` | Critical (yellow/orange) |
| `3` | Positive (green) |

`criticalityRepresentation`: `#WITH_ICON` (default) or `#WITHOUT_ICON` (colour only).

The criticality element is calculated in the **interface view** (Chapter 03, section 3.7) —
it is business semantics, not layout.

### Putting an action button in the table toolbar

```abap
@UI.lineItem: [ { position: 10, importance: #HIGH },
                { type: #FOR_ACTION, dataAction: 'acceptTravel', label: 'Accept Travel' } ]
TravelId;
```

The second array entry does not describe a column — it declares a **button**. It has to hang off
*some* element; by convention the first key-ish field. See Chapter 13 for the full action story.

---

## 5.6 `@UI.selectionField` — the filter bar

```abap
@UI.selectionField: [ { position: 10 } ]
TravelId;

@UI.selectionField: [ { position: 20 } ]
AgencyId;

@UI.selectionField: [ { position: 30 } ]
OverallStatus;
```

Only fields with `@UI.selectionField` appear in the filter bar by default. Every other field is
still filterable through *Adapt Filters*.

Combine with `@Consumption.filter` (in the projection view) to control mandatory / interval /
default value.

---

## 5.7 `@UI.facet` — the Object Page structure

This is the part that confuses people most, so here is the model:

```
Object Page
 +-- Header facets            (facet with purpose: #HEADER)
 +-- Section 1                (facet type #COLLECTION or #IDENTIFICATION_REFERENCE)
 |     +-- Subsection 1.1     (facet type #FIELDGROUP_REFERENCE)
 |     +-- Subsection 1.2
 +-- Section 2                (facet type #LINEITEM_REFERENCE -> a child table)
```

```abap
@UI.facet: [
  // ---------- Header ----------
  { id:            'TravelHeaderStatus',
    purpose:       #HEADER,
    type:          #DATAPOINT_REFERENCE,
    position:      10,
    targetQualifier: 'OverallStatusDP' },

  // ---------- Section: General Information ----------
  { id:       'TravelGeneral',
    purpose:  #STANDARD,
    type:     #COLLECTION,
    label:    'General Information',
    position: 10 },

  {   id:            'TravelData',
      parentId:      'TravelGeneral',
      purpose:       #STANDARD,
      type:          #IDENTIFICATION_REFERENCE,
      label:         'Travel Data',
      position:      10 },

  {   id:              'TravelPrices',
      parentId:        'TravelGeneral',
      purpose:         #STANDARD,
      type:            #FIELDGROUP_REFERENCE,
      label:           'Prices',
      position:        20,
      targetQualifier: 'PriceGroup' },

  // ---------- Section: Bookings (child table) ----------
  { id:           'BookingSection',
    purpose:      #STANDARD,
    type:         #LINEITEM_REFERENCE,
    label:        'Bookings',
    position:     20,
    targetElement: '_Booking' }
]
```

### Facet properties

| Property | Meaning |
|---|---|
| `id` | Unique name. Needed so children can point at it with `parentId`. |
| `parentId` | Makes this facet a **subsection** of the named facet. |
| `purpose` | `#STANDARD` (a section) or `#HEADER` (in the page header) |
| `position` | Order |
| `label` | Section title |
| `type` | What the facet renders — see table below |
| `targetQualifier` | For `#FIELDGROUP_REFERENCE` / `#DATAPOINT_REFERENCE`: which qualifier to render |
| `targetElement` | For `#LINEITEM_REFERENCE`: which **association** to render as a table |

### Facet types

| `type` | Renders |
|---|---|
| `#IDENTIFICATION_REFERENCE` | All fields annotated with `@UI.identification` |
| `#FIELDGROUP_REFERENCE` | All fields annotated with `@UI.fieldGroup` carrying the matching `qualifier` |
| `#LINEITEM_REFERENCE` | A **table** of the associated entity (`targetElement: '_Booking'`), using that entity's own `@UI.lineItem` |
| `#COLLECTION` | A container that groups subsections. Has no content of its own. |
| `#DATAPOINT_REFERENCE` | A single KPI / status datapoint (usually in the header) |
| `#CHART_REFERENCE` | A chart defined with `@UI.chart` |
| `#CONTACT_REFERENCE` | A contact card from `@Communication.contact` |
| `#ADDRESS_REFERENCE` | An address block |

---

## 5.8 `@UI.identification` and `@UI.fieldGroup`

```abap
@UI.identification: [ { position: 10 } ]
TravelId;

@UI.identification: [ { position: 20 } ]
AgencyId;

@UI.fieldGroup: [ { qualifier: 'PriceGroup', position: 10 } ]
BookingFee;

@UI.fieldGroup: [ { qualifier: 'PriceGroup', position: 20 } ]
TotalPrice;

@UI.fieldGroup: [ { qualifier: 'PriceGroup', position: 30 } ]
CurrencyCode;
```

- `@UI.identification` → picked up by the facet of type `#IDENTIFICATION_REFERENCE`.
- `@UI.fieldGroup` with `qualifier: 'PriceGroup'` → picked up by the facet whose
  `targetQualifier` is `'PriceGroup'`.

The qualifier string is free text; it is just the link between the field and the facet. Getting a
letter wrong means the section renders empty — a very common and very silent failure.

---

## 5.9 `@UI.dataPoint` — KPIs and header status

```abap
@UI.dataPoint: { qualifier: 'OverallStatusDP',
                 title: 'Status',
                 criticality: 'OverallStatusCriticality' }
OverallStatus;

@UI.dataPoint: { qualifier: 'TotalPriceDP',
                 title: 'Total Price',
                 targetValue: 5000,
                 criticalityCalculation: {
                   improvementDirection: #MINIMIZE,
                   deviationRangeHighValue: 4000,
                   toleranceRangeHighValue: 3000 },
                 visualization: #PROGRESS }
TotalPrice;
```

| Property | Meaning |
|---|---|
| `qualifier` | Referenced from a `#DATAPOINT_REFERENCE` facet |
| `title` | Label |
| `criticality` | Element with 0–3 |
| `criticalityCalculation` | Let the UI derive criticality from thresholds instead |
| `improvementDirection` | `#MINIMIZE` / `#MAXIMIZE` / `#TARGET` |
| `visualization` | `#NUMBER`, `#PROGRESS`, `#RATING` |
| `targetValue` | For progress/rating |

---

## 5.10 The complete MDE for `ZC_TravelTP`

```abap
@Metadata.layer: #CORE

@UI: {
  headerInfo: { typeName: 'Travel',
                typeNamePlural: 'Travels',
                title:       { type: #STANDARD, value: 'TravelId' },
                description: { type: #STANDARD, value: 'Description' },
                typeImageUrl: 'sap-icon://flight' },
  presentationVariant: [ { sortOrder: [ { by: 'TravelId', direction: #DESC } ],
                           visualizations: [ { type: #AS_LINEITEM } ] } ]
}
annotate entity ZC_TravelTP with
{
  @UI.facet: [
    { id: 'StatusHeader',  purpose: #HEADER, type: #DATAPOINT_REFERENCE,
      position: 10, targetQualifier: 'OverallStatusDP' },
    { id: 'PriceHeader',   purpose: #HEADER, type: #DATAPOINT_REFERENCE,
      position: 20, targetQualifier: 'TotalPriceDP' },

    { id: 'GeneralColl',  purpose: #STANDARD, type: #COLLECTION,
      label: 'General Information', position: 10 },
    { id: 'TravelData',   parentId: 'GeneralColl', type: #IDENTIFICATION_REFERENCE,
      label: 'Travel Data', position: 10 },
    { id: 'PriceData',    parentId: 'GeneralColl', type: #FIELDGROUP_REFERENCE,
      label: 'Prices', position: 20, targetQualifier: 'PriceGroup' },
    { id: 'AdminData',    parentId: 'GeneralColl', type: #FIELDGROUP_REFERENCE,
      label: 'Administrative Data', position: 30, targetQualifier: 'AdminGroup' },

    { id: 'BookingList',  purpose: #STANDARD, type: #LINEITEM_REFERENCE,
      label: 'Bookings', position: 20, targetElement: '_Booking' }
  ]

  @UI.hidden: true
  TravelUUID;

  @UI.lineItem:       [ { position: 10, importance: #HIGH },
                        { type: #FOR_ACTION, dataAction: 'acceptTravel',  label: 'Accept Travel' },
                        { type: #FOR_ACTION, dataAction: 'rejectTravel',  label: 'Reject Travel' } ]
  @UI.identification: [ { position: 10 },
                        { type: #FOR_ACTION, dataAction: 'acceptTravel',  label: 'Accept Travel' },
                        { type: #FOR_ACTION, dataAction: 'rejectTravel',  label: 'Reject Travel' } ]
  @UI.selectionField: [ { position: 10 } ]
  TravelId;

  @UI.lineItem:       [ { position: 20, importance: #HIGH } ]
  @UI.identification: [ { position: 20 } ]
  @UI.selectionField: [ { position: 20 } ]
  @UI.textArrangement: #TEXT_FIRST
  AgencyId;

  @UI.hidden: true
  AgencyName;

  @UI.lineItem:       [ { position: 30, importance: #MEDIUM } ]
  @UI.identification: [ { position: 30 } ]
  @UI.selectionField: [ { position: 30 } ]
  @UI.textArrangement: #TEXT_FIRST
  CustomerId;

  @UI.hidden: true
  CustomerName;

  @UI.lineItem:       [ { position: 40, importance: #MEDIUM } ]
  @UI.identification: [ { position: 40 } ]
  @UI.selectionField: [ { position: 40 } ]
  BeginDate;

  @UI.lineItem:       [ { position: 50, importance: #MEDIUM } ]
  @UI.identification: [ { position: 50 } ]
  EndDate;

  @UI.fieldGroup:     [ { qualifier: 'PriceGroup', position: 10 } ]
  BookingFee;

  @UI.lineItem:       [ { position: 60, importance: #HIGH } ]
  @UI.fieldGroup:     [ { qualifier: 'PriceGroup', position: 20 } ]
  @UI.dataPoint:      { qualifier: 'TotalPriceDP', title: 'Total Price' }
  TotalPrice;

  @UI.fieldGroup:     [ { qualifier: 'PriceGroup', position: 30 } ]
  CurrencyCode;

  @UI.lineItem:       [ { position: 70, importance: #LOW } ]
  @UI.identification: [ { position: 60 } ]
  @UI.multiLineText:  true
  Description;

  @UI.lineItem:       [ { position: 80, importance: #HIGH,
                          criticality: 'OverallStatusCriticality' } ]
  @UI.identification: [ { position: 70, criticality: 'OverallStatusCriticality' } ]
  @UI.selectionField: [ { position: 50 } ]
  @UI.dataPoint:      { qualifier: 'OverallStatusDP', title: 'Status',
                        criticality: 'OverallStatusCriticality' }
  @UI.textArrangement: #TEXT_ONLY
  OverallStatus;

  @UI.hidden: true
  OverallStatusCriticality;

  @UI.fieldGroup: [ { qualifier: 'AdminGroup', position: 10 } ]
  CreatedBy;
  @UI.fieldGroup: [ { qualifier: 'AdminGroup', position: 20 } ]
  CreatedAt;
  @UI.fieldGroup: [ { qualifier: 'AdminGroup', position: 30 } ]
  LastChangedBy;
  @UI.fieldGroup: [ { qualifier: 'AdminGroup', position: 40 } ]
  LastChangedAt;

  @UI.hidden: true
  LocalLastChangedAt;
}
```

### And the child MDE, `ZC_BookingTP`

```abap
@Metadata.layer: #CORE

@UI: { headerInfo: { typeName: 'Booking', typeNamePlural: 'Bookings',
                     title: { type: #STANDARD, value: 'BookingId' } } }
annotate entity ZC_BookingTP with
{
  @UI.facet: [ { id: 'BookingData', purpose: #STANDARD,
                 type: #IDENTIFICATION_REFERENCE, label: 'Booking', position: 10 } ]

  @UI.hidden: true
  BookingUUID;
  @UI.hidden: true
  TravelUUID;

  @UI.lineItem:       [ { position: 10, importance: #HIGH } ]
  @UI.identification: [ { position: 10 } ]
  BookingId;

  @UI.lineItem:       [ { position: 20, importance: #HIGH } ]
  @UI.identification: [ { position: 20 } ]
  BookingDate;

  @UI.lineItem:       [ { position: 30, importance: #HIGH } ]
  @UI.identification: [ { position: 30 } ]
  CustomerId;

  @UI.lineItem:       [ { position: 40, importance: #HIGH } ]
  @UI.identification: [ { position: 40 } ]
  CarrierId;

  @UI.lineItem:       [ { position: 50, importance: #HIGH } ]
  @UI.identification: [ { position: 50 } ]
  ConnectionId;

  @UI.lineItem:       [ { position: 60, importance: #MEDIUM } ]
  @UI.identification: [ { position: 60 } ]
  FlightDate;

  @UI.lineItem:       [ { position: 70, importance: #HIGH } ]
  @UI.identification: [ { position: 70 } ]
  FlightPrice;

  @UI.identification: [ { position: 80 } ]
  CurrencyCode;

  @UI.lineItem:       [ { position: 80, importance: #MEDIUM } ]
  @UI.identification: [ { position: 90 } ]
  BookingStatus;

  @UI.hidden: true
  LastChangedAt;
}
```

**Why the child needs its own `@UI.lineItem`:** the `#LINEITEM_REFERENCE` facet on the parent
renders the child table using the **child's** line items. If you forget them, the Bookings section
appears with no columns.

---

## 5.11 Qualifiers — several layouts on one entity

```abap
@UI.lineItem: [ { position: 10, importance: #HIGH },                        // default set
                { position: 10, qualifier: 'Compact', importance: #HIGH } ] // alternative set
TravelId;
```

Then reference the qualified set from a facet or a presentation variant:

```abap
{ id: 'CompactBookings', type: #LINEITEM_REFERENCE, targetElement: '_Booking',
  targetQualifier: 'Compact', label: 'Bookings (compact)', position: 30 }
```

Useful when the same child entity is rendered in two places with different columns.

---

## 5.12 Useful annotations that are easy to miss

| Annotation | Effect |
|---|---|
| `@UI.hidden: true` | Removes from the UI entirely. **Always hide UUID keys** — the user must never see them. |
| `@UI.hidden: 'HideFlagElement'` | Conditional hiding driven by a boolean element. |
| `@UI.multiLineText: true` | Renders a text area instead of a single-line input. |
| `@UI.textArrangement` | `#TEXT_FIRST` / `#TEXT_LAST` / `#TEXT_ONLY` / `#TEXT_SEPARATE` |
| `@UI.masked: true` | Renders as `****`. For sensitive fields. |
| `@UI.isImageURL: true` | Element contains a URL, rendered as an image. |
| `@Semantics.imageUrl: true` | Same intent, semantic layer. |
| `@UI.presentationVariant` | Default sort and grouping of the list |
| `@UI.selectionPresentationVariant` | A named combination of filter + presentation = a **saved view / tab** |
| `@Consumption.semanticObject: 'TravelObject'` | Enables intent-based navigation to other apps |
| `@UI.connectedFields` | Render several fields as one composed line |
| `@Communication.contact` | Renders a contact quick-view card |

### Multiple tabs (view switching) in a List Report

```abap
@UI: { selectionPresentationVariant: [
  { qualifier: 'AllTravels',      text: 'All',
    selectionVariant:    { parameters: [] },
    presentationVariant: { visualizations: [ { type: #AS_LINEITEM } ] } },
  { qualifier: 'OpenTravels',     text: 'Open',
    selectionVariant:    { parameters: [ { name: 'OverallStatus', value: 'O' } ] },
    presentationVariant: { visualizations: [ { type: #AS_LINEITEM } ] } },
  { qualifier: 'AcceptedTravels', text: 'Accepted',
    selectionVariant:    { parameters: [ { name: 'OverallStatus', value: 'A' } ] },
    presentationVariant: { visualizations: [ { type: #AS_LINEITEM } ] } }
] }
```

Gives the user "All | Open | Accepted" tabs above the table, with counts, for free.

---

## 5.13 Why the UI does not reflect your annotation change

In order of likelihood:

1. **Browser cache.** The Fiori preview aggressively caches `$metadata`. Press `F12` →
   right-click reload → *Empty cache and hard reload*, or use the preview's own
   *clear cache and refresh*. **This is the cause more than half the time.**
2. **The MDE is not activated** — activating the view does not activate the extension.
3. **`@Metadata.allowExtensions: true` missing** on the projection view.
4. **The service binding needs to be re-published/re-activated** after a metadata change (V2 more
   often than V4).
5. **Qualifier typo** — `'PriceGroup'` vs `'Pricegroup'`. Silent; the section just renders empty.
6. **You annotated the interface view instead of the projection.** The service exposes the
   projection; `@Metadata.ignorePropagatedAnnotations: true` on `ZR_` deliberately blocks the leak.
7. **The element is not exposed in the projection.** An MDE can only annotate what the view has.

---

## 5.14 Checklist

- [ ] `@Metadata.layer: #CORE` at the top.
- [ ] Elements terminated with `;`.
- [ ] Every UUID key is `@UI.hidden: true`.
- [ ] Every `@UI.lineItem` has an `importance`.
- [ ] Every `targetQualifier` in a facet has a matching `qualifier` on a field.
- [ ] The child entity has its own `@UI.lineItem` set.
- [ ] `positions` use gaps of 10.

---

## 5.15 Interview answer

> **"How does the Fiori Elements layout get generated?"**
>
> Entirely from CDS annotations, normally in a separate **metadata extension** object rather than in
> the view itself. Four groups carry most of the work: `@UI.headerInfo` for the titles,
> `@UI.lineItem` for the table columns, `@UI.selectionField` for the filter bar, and `@UI.facet`
> for the structure of the Object Page — where a facet of type `#IDENTIFICATION_REFERENCE` renders
> the `@UI.identification` fields, `#FIELDGROUP_REFERENCE` renders a `@UI.fieldGroup` matched by
> qualifier, and `#LINEITEM_REFERENCE` renders an associated entity as a table using **that
> entity's own** line items.
>
> I keep them in a metadata extension for three reasons: volume — a real app is 150 to 400 lines of
> `@UI`; layering — the extension has a `@Metadata.layer` so a higher layer can override without a
> modification; and separate transport of layout from model.
>
> The prerequisite is `@Metadata.allowExtensions: true` on the projection view.
>
> The practical gotcha: when an annotation change appears to have no effect, it is usually the
> browser cache, an unactivated extension, or a qualifier typo — a mismatched `targetQualifier`
> renders an empty section silently.

## 5.16 Production considerations

- **Always set `importance`** on line items. Without it the phone layout is unusable — only `#HIGH`
  columns survive at narrow widths.
- **Hide UUID keys** with `@UI.hidden: true`. Users must never see them.
- **Use position gaps of 10** so later insertions do not require renumbering everything.
- **Layout is a transportable object of its own.** Activating the view does not activate the
  extension; both must be in the transport.
- **Qualifier typos fail silently.** Add "every section renders content" to the post-import test
  list (Chapter 25).
- **Clear the browser cache before concluding anything** about an annotation change, and tell
  testers to do the same — otherwise you will chase phantom defects.
- **Translate labels.** A `label:` hard-coded in the MDE overrides the data element text and is a
  common source of untranslated UI.

---

[< Projection View](04-Projection-View.md) | [Index](00-README.md) | [Next: Service Definition & Binding >](06-Service-Definition-and-Binding.md)
