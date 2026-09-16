# Chapter 07 — Building a Read-Only Fiori Report, Step by Step

[< Service Binding](06-Service-Definition-and-Binding.md) | [Index](00-README.md) | [Next: Behavior Definition >](08-Behavior-Definition.md)

---

## 7.1 The point of this chapter

This is the **smallest useful RAP application**: a Fiori List Report with search, filters, sorting,
export to Excel, personalisation and an Object Page — with **no behavior definition, no behavior
pool, no ABAP class, no draft table**.

If your requirement is "the business wants to see this data in Fiori instead of SE16/ALV",
this chapter is the whole answer. Do not build a transactional app for it.

### What you build — 4 objects

```
1.  ZI_SalesOrderItem      Data Definition   (interface view)   <- optional but recommended
2.  ZC_SalesOrderItem      Data Definition   (projection view)
3.  ZC_SalesOrderItem      Metadata Extension
4.  ZSD_SALESORDER_RPT     Service Definition
5.  ZUI_SALESORDER_RPT_O4  Service Binding
```

(Five objects if you count the binding separately from the definition. No BDEF, no class.)

### What it costs

Roughly 45 minutes for the first one, 10 minutes for the tenth.

---

## 7.2 Scenario

Report on **sales order items**: order, item, material, customer, quantity, net value, delivery
status. Header fields come from `VBAK`, item fields from `VBAP`.

We will use the standard SAP CDS views where they exist and fall back to tables where they do not.
For an on-premise S/4HANA system, `I_SalesOrderItem` and `I_SalesOrder` are released and preferable
to reading `VBAK`/`VBAP` directly. The example below reads the tables so it works everywhere; swap
in the released views if they are available.

---

## 7.3 Step 1 — The interface view `ZI_SalesOrderItem`

```abap
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Sales Order Item - interface view'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType: { serviceQuality: #C, sizeCategory: #L, dataClass: #TRANSACTIONAL }
define view entity ZI_SalesOrderItem
  as select from vbap as Item
    inner join   vbak as Header on Header.vbeln = Item.vbeln

  association [0..1] to I_Customer  as _Customer on  $projection.SoldToParty = _Customer.Customer
  association [0..1] to I_Product   as _Product  on  $projection.Material    = _Product.Product
  association [0..1] to I_Currency  as _Currency on  $projection.Currency    = _Currency.Currency
  association [0..1] to I_SalesOrganization as _SalesOrg
                                              on  $projection.SalesOrganization = _SalesOrg.SalesOrganization
{
  key Item.vbeln            as SalesOrder,
  key Item.posnr            as SalesOrderItem,

      Header.auart          as SalesOrderType,
      Header.vkorg          as SalesOrganization,
      Header.vtweg          as DistributionChannel,
      Header.spart          as Division,
      Header.kunnr          as SoldToParty,
      Header.erdat          as CreationDate,
      Header.audat          as DocumentDate,

      Item.matnr            as Material,
      Item.arktx            as MaterialDescription,
      Item.werks            as Plant,

      @Semantics.quantity.unitOfMeasure: 'OrderQuantityUnit'
      Item.kwmeng           as OrderQuantity,
      Item.vrkme            as OrderQuantityUnit,

      @Semantics.amount.currencyCode: 'Currency'
      Item.netwr            as NetAmount,
      Header.waerk          as Currency,

      Item.abgru            as RejectionReason,

      // ---- calculated: overall item status, business semantics, lives here ----
      case when Item.abgru <> ''       then 'Rejected'
           when Item.kwmeng = 0        then 'Zero Qty'
           else 'Open'
      end                   as ItemStatus,

      case when Item.abgru <> ''       then 1   // red
           when Item.kwmeng = 0        then 2   // yellow
           else 3                              // green
      end                   as ItemStatusCriticality,

      /* Associations */
      _Customer,
      _Product,
      _Currency,
      _SalesOrg
}
```

### Why an interface view at all, for a report?

You could put everything in the projection. Keep the two layers anyway:

- The joins, the `case` expressions and the associations are **reusable**. The next report that
  needs "sales order items with status" reuses `ZI_SalesOrderItem`.
- The projection stays short and readable.
- If you later need the same data as an API and as a UI, you make two projections over one model.

For a genuinely throwaway one-off, a single projection over a table is acceptable. Be honest about
which one you are building.

### Notes on the code

| Line | Why |
|---|---|
| `inner join vbak as Header on Header.vbeln = Item.vbeln` | A **join** is correct here (not an association) because header fields are always needed — every row of the report shows them. Associations are for *optional* navigation. |
| `key Item.vbeln, key Item.posnr` | The compound key. A CDS view **must** have a key for OData to address rows. |
| `@Semantics.quantity.unitOfMeasure` | Mandatory on quantity fields. |
| `case ... end as ItemStatusCriticality` | Calculated in the interface view because it is business semantics. The MDE will only *point at* it. |
| `@ObjectModel.usageType.sizeCategory: #L` | Honest sizing. Signals to the runtime and to reviewers that this can return a lot of rows. |

---

## 7.4 Step 2 — The projection view `ZC_SalesOrderItem`

```abap
@EndUserText.label: 'Sales Order Item Report'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
@Search.searchable: true
@ObjectModel.semanticKey: ['SalesOrder', 'SalesOrderItem']
define root view entity ZC_SalesOrderItem
  as projection on ZI_SalesOrderItem
{
      @Search.defaultSearchElement: true
  key SalesOrder,
  key SalesOrderItem,

      @Consumption.filter: { selectionType: #SINGLE, multipleSelections: true }
      SalesOrderType,

      @Consumption.filter: { selectionType: #SINGLE, multipleSelections: true, mandatory: true }
      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_SalesOrganization',
                                                     element: 'SalesOrganization' } }]
      SalesOrganization,

      DistributionChannel,
      Division,

      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_Customer', element: 'Customer' } }]
      @ObjectModel.text.element: ['SoldToPartyName']
      SoldToParty,
      _Customer.CustomerName as SoldToPartyName,

      @Consumption.filter: { selectionType: #INTERVAL, mandatory: true }
      CreationDate,
      DocumentDate,

      @Search.defaultSearchElement: true
      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_Product', element: 'Product' } }]
      Material,

      @Search.defaultSearchElement: true
      @Search.fuzzinessThreshold: 0.8
      MaterialDescription,

      Plant,

      @Semantics.quantity.unitOfMeasure: 'OrderQuantityUnit'
      OrderQuantity,
      OrderQuantityUnit,

      @Semantics.amount.currencyCode: 'Currency'
      NetAmount,
      Currency,

      RejectionReason,
      ItemStatus,
      ItemStatusCriticality,

      /* Associations */
      _Customer,
      _Product,
      _Currency,
      _SalesOrg
}
```

### The three things that make or break a read-only report

1. **`root` but no `provider contract`.**
   ```abap
   define root view entity ZC_SalesOrderItem as projection on ZI_SalesOrderItem
   ```
   `root` is needed so it can be the main entity of the service.
   **`provider contract transactional_query` must NOT be there** — that would demand a behavior
   definition. Its absence is what makes this a read-only service. RAP generates a read-only
   OData service automatically: `GET` works, `POST`/`PATCH`/`DELETE` return HTTP 405.

2. **`mandatory: true` on a selective filter.**
   ```abap
   @Consumption.filter: { selectionType: #INTERVAL, mandatory: true }
   CreationDate,
   ```
   `VBAP` has tens of millions of rows. Without a mandatory filter the List Report issues an
   unrestricted `SELECT` on open. This one annotation is the difference between a 0.4-second report
   and a timeout. Make at least one high-selectivity field mandatory.

3. **`@ObjectModel.semanticKey`.**
   ```abap
   @ObjectModel.semanticKey: ['SalesOrder', 'SalesOrderItem']
   ```
   Tells Fiori which fields are the *business* key. Used for the Object Page title, for the
   "Sales Order 4711 / Item 10" breadcrumb, and for draft-conflict messages in transactional apps.
   Costs one line, improves every dialog in the app.

---

## 7.5 Step 3 — The metadata extension

```abap
@Metadata.layer: #CORE

@UI: {
  headerInfo: { typeName: 'Sales Order Item',
                typeNamePlural: 'Sales Order Items',
                title:       { type: #STANDARD, value: 'SalesOrder' },
                description: { type: #STANDARD, value: 'MaterialDescription' },
                typeImageUrl: 'sap-icon://sales-order-item' },
  presentationVariant: [ { sortOrder: [ { by: 'SalesOrder',     direction: #DESC },
                                        { by: 'SalesOrderItem', direction: #ASC } ],
                           visualizations: [ { type: #AS_LINEITEM } ] } ]
}
annotate entity ZC_SalesOrderItem with
{
  @UI.facet: [
    { id: 'GeneralColl', purpose: #STANDARD, type: #COLLECTION,
      label: 'Item Details', position: 10 },
    { id: 'DocData',  parentId: 'GeneralColl', type: #IDENTIFICATION_REFERENCE,
      label: 'Document', position: 10 },
    { id: 'MatData',  parentId: 'GeneralColl', type: #FIELDGROUP_REFERENCE,
      label: 'Material & Quantity', position: 20, targetQualifier: 'MaterialGroup' },
    { id: 'AmtData',  parentId: 'GeneralColl', type: #FIELDGROUP_REFERENCE,
      label: 'Pricing', position: 30, targetQualifier: 'AmountGroup' }
  ]

  @UI.lineItem:       [ { position: 10, importance: #HIGH } ]
  @UI.identification: [ { position: 10 } ]
  @UI.selectionField: [ { position: 10 } ]
  SalesOrder;

  @UI.lineItem:       [ { position: 20, importance: #HIGH } ]
  @UI.identification: [ { position: 20 } ]
  SalesOrderItem;

  @UI.lineItem:       [ { position: 30, importance: #LOW } ]
  @UI.identification: [ { position: 30 } ]
  @UI.selectionField: [ { position: 20 } ]
  SalesOrderType;

  @UI.lineItem:       [ { position: 40, importance: #MEDIUM } ]
  @UI.identification: [ { position: 40 } ]
  @UI.selectionField: [ { position: 30 } ]
  SalesOrganization;

  @UI.lineItem:        [ { position: 50, importance: #HIGH } ]
  @UI.identification:  [ { position: 50 } ]
  @UI.selectionField:  [ { position: 40 } ]
  @UI.textArrangement: #TEXT_FIRST
  SoldToParty;

  @UI.hidden: true
  SoldToPartyName;

  @UI.lineItem:       [ { position: 60, importance: #MEDIUM } ]
  @UI.selectionField: [ { position: 50 } ]
  CreationDate;

  @UI.lineItem:   [ { position: 70, importance: #HIGH } ]
  @UI.fieldGroup: [ { qualifier: 'MaterialGroup', position: 10 } ]
  @UI.selectionField: [ { position: 60 } ]
  Material;

  @UI.lineItem:   [ { position: 80, importance: #HIGH } ]
  @UI.fieldGroup: [ { qualifier: 'MaterialGroup', position: 20 } ]
  MaterialDescription;

  @UI.fieldGroup: [ { qualifier: 'MaterialGroup', position: 30 } ]
  Plant;

  @UI.lineItem:   [ { position: 90, importance: #HIGH } ]
  @UI.fieldGroup: [ { qualifier: 'MaterialGroup', position: 40 } ]
  OrderQuantity;

  @UI.lineItem:   [ { position: 100, importance: #HIGH } ]
  @UI.fieldGroup: [ { qualifier: 'AmountGroup', position: 10 } ]
  NetAmount;

  @UI.fieldGroup: [ { qualifier: 'AmountGroup', position: 20 } ]
  Currency;

  @UI.lineItem:       [ { position: 110, importance: #HIGH,
                          criticality: 'ItemStatusCriticality' } ]
  @UI.identification: [ { position: 60, criticality: 'ItemStatusCriticality' } ]
  @UI.selectionField: [ { position: 70 } ]
  ItemStatus;

  @UI.hidden: true
  ItemStatusCriticality;
}
```

---

## 7.6 Step 4 — Service definition and binding

```abap
@EndUserText.label: 'Sales Order Item Report'
define service ZSD_SALESORDER_RPT {
  expose ZC_SalesOrderItem    as SalesOrderItem;
  expose I_Customer           as Customer;
  expose I_Product            as Product;
  expose I_SalesOrganization  as SalesOrganization;
  expose I_Currency           as Currency;
}
```

Then:

1. *New → Service Binding* → `ZUI_SALESORDER_RPT_O4`, type **OData V4 - UI**, definition `ZSD_SALESORDER_RPT`.
2. Activate.
3. **Publish**.
4. Select `SalesOrderItem` → **Preview**.

You now have a List Report with: free-text search, a filter bar, mandatory filters, sortable
columns, column personalisation, Export to Spreadsheet, variant management, and an Object Page —
none of which you wrote.

---

## 7.7 What you get for free (and what you do not)

### Free

| Feature | Comes from |
|---|---|
| Filter bar | `@UI.selectionField` |
| Free-text search | `@Search.searchable` + `@Search.defaultSearchElement` |
| Sort, group, column layout, personalisation | Fiori Elements standard |
| **Export to Spreadsheet** | Fiori Elements standard — no ALV needed |
| Saved variants / tiles | Fiori Elements standard |
| Object Page | `@UI.facet` + `@UI.identification` |
| Value helps | `@Consumption.valueHelpDefinition` |
| Paging (`$top`/`$skip`) | OData, automatic |
| Responsive / mobile layout | `importance` |

### Not free

| Feature | You need |
|---|---|
| Any edit capability | A BDEF — this is no longer a read-only report |
| A button that does something | An action → needs a BDEF (see 7.9) |
| Charts / KPI cards | `@UI.chart` + Analytical List Page, or an Overview Page |
| Cross-app navigation | `@Consumption.semanticObject` + Launchpad configuration |
| Aggregation with drill-down | An analytical CDS view (`@Analytics.query: true`) + InA/V4 analytics |
| A printed PDF form | Adobe Forms / a separate output solution |

---

## 7.8 Performance rules for read-only reports

These matter far more in a report than in a transactional app, because reports return many rows.

1. **Push the filter to the database.** Never read everything and filter in a virtual element.
2. **Make at least one selective field `mandatory: true`.**
3. **Avoid virtual elements on large result sets.** They are calculated per page in ABAP and cannot
   be filtered or sorted in HANA.
4. **Prefer associations to joins** for anything that is not always displayed.
5. **Do not expose fields you do not use.** The List Report issues `$select` based on visible
   columns, but `$expand` and Object Page reads pull everything.
6. **Avoid `LEFT OUTER JOIN` chains in the interface view.** Each one multiplies rows if the
   cardinality is wrong — and a wrong `[0..1]` on an association that is actually `[0..*]`
   silently produces duplicate rows.
7. **Check the generated SQL.** In ADT: run the CDS view with *Open with → Data Preview*, then use
   the SQL trace (`ST05`) or the *ABAP Profiler*. A report that does a full `VBAP` scan will show
   up immediately.
8. **`@ObjectModel.usageType.sizeCategory`** should be honest. It is metadata, not enforcement,
   but it documents intent for the next developer.

---

## 7.9 The moment a read-only report stops being read-only

The most common escalation: *"can we add a button that marks the item as reviewed?"*

That single button changes the architecture:

| Before | After |
|---|---|
| No BDEF | BDEF with `action` |
| No behavior pool | `ZBP_...` class with the action implementation |
| `ZC_` without `provider contract` | `ZC_` with `provider contract transactional_query` |
| Interface view can be a join over `VBAK`/`VBAP` | Root view must be a 1:1 projection of **one persistent table** if the action changes data on it |

Practically: if the button must write to a **Z status table**, model that Z table as the RAP root and
associate the sales-order data to it — do not try to make `VBAP` the RAP root.

```abap
define root view entity ZR_SoItemReviewTP as select from zso_item_review as Review
  association [0..1] to ZI_SalesOrderItem as _Item
    on  $projection.SalesOrder     = _Item.SalesOrder
    and $projection.SalesOrderItem = _Item.SalesOrderItem
{ ... }
```

That keeps the transactional root clean and 1:1 with its own table, which is what managed RAP requires.

---

## 7.10 Checklist

- [ ] Projection is `define root view entity ... as projection on ...` with **no** `provider contract`.
- [ ] `@Metadata.allowExtensions: true` on the projection.
- [ ] `@ObjectModel.semanticKey` set.
- [ ] At least one filter is `mandatory: true` on a high-volume source.
- [ ] Every value-help entity is exposed in the service definition.
- [ ] Every `@UI.lineItem` has an `importance`.
- [ ] Criticality is calculated in the interface view, not in the MDE.
- [ ] Binding is **Published**, and Preview shows data.

---

## 7.11 Interview answer

> **"How would you build a read-only Fiori report?"**
>
> With RAP, but without any behavior at all — four or five objects and no ABAP.
>
> An interface view for the data model with the joins, associations and any calculated status or
> criticality; a projection view over it; a metadata extension for the layout; and a service
> definition plus an OData V4 UI service binding.
>
> The key point is the projection: `define root view entity ... as projection on ...` with **no**
> `provider contract transactional_query`. `root` makes it the main entity of the service; the
> absence of the contract is what makes it read-only. RAP then generates a read-only OData service
> automatically — `GET` works, `POST`, `PATCH` and `DELETE` return HTTP 405. Adding the contract
> without a behavior definition is an activation error.
>
> From the annotations you get the filter bar, free-text search, sorting, column personalisation,
> variant management, export to spreadsheet and an Object Page — all standard Fiori Elements, none
> of it written by you.
>
> The one thing I always add is `@Consumption.filter: { ..., mandatory: true }` on a selective
> field. On a large table that single annotation is the difference between a sub-second report and
> a timeout.

## 7.12 Production considerations

- **A mandatory, selective filter is not optional** on any report over a large table.
- **`@ObjectModel.semanticKey`** improves every dialog, breadcrumb and message in the app for one
  line of effort.
- **Check the generated SQL with `ST05`** before release. A full table scan shows up immediately.
- **Keep virtual elements out of filterable and sortable columns** — they force the whole result set
  to be read.
- **Verify association cardinalities.** A `[0..1]` that is really `[0..*]` silently duplicates rows,
  and in a report nobody notices until the totals are wrong.
- **Plan for the "can we add a button?" request.** That converts the report into a transactional app
  (§7.9); model the status on your own Z table rather than trying to make a standard table the RAP
  root.
- **Read-only does not mean unsecured.** DCL still applies, and it still needs a role in every system.

---

[< Service Binding](06-Service-Definition-and-Binding.md) | [Index](00-README.md) | [Next: Behavior Definition >](08-Behavior-Definition.md)
