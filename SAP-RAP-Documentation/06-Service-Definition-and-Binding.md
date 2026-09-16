# Chapter 06 — Service Definition and Service Binding

[< Metadata Extension](05-Metadata-Extension-and-UI-Annotations.md) | [Index](00-README.md) | [Next: Read-Only Fiori Report >](07-ReadOnly-Fiori-Report-Walkthrough.md)

---

## 6.1 Two objects, two jobs

| Object | Answers the question | Transportable artifact |
|---|---|---|
| **Service Definition** (`ZSD_TRAVEL`) | *What* is exposed? Which entities, under which names? | Yes |
| **Service Binding** (`ZUI_TRAVEL_O4`) | *How* is it exposed? Which protocol, which version, is it published? | Yes |

One service definition can feed **several** bindings — e.g. one OData V2 binding for an older Fiori
app and one OData V4 binding for a new one, both serving exactly the same model.

```
ZC_TravelTP + ZC_BookingTP
        |
        v
   ZSD_TRAVEL            (Service Definition)
     |        |
     v        v
ZUI_TRAVEL_O4   ZAPI_TRAVEL_O4   (Service Bindings: UI vs Web API)
```

---

## 6.2 The Service Definition

ADT: *New → Other ABAP Repository Object → Business Services → Service Definition*.

```abap
@EndUserText.label: 'Service definition for Travel'
define service ZSD_TRAVEL {
  expose ZC_TravelTP    as Travel;
  expose ZC_BookingTP   as Booking;

  // master data / value help entities
  expose /DMO/I_Agency     as Agency;
  expose /DMO/I_Customer   as Customer;
  expose /DMO/I_Carrier    as Carrier;
  expose /DMO/I_Connection as Connection;
  expose I_Currency        as Currency;
}
```

### Line by line

| Line | Meaning |
|---|---|
| `define service ZSD_TRAVEL` | The service definition name. |
| `expose ZC_TravelTP as Travel;` | Publishes the CDS entity under the **OData entity set name** `Travel`. |
| `as Travel` | Optional alias. Without it the OData entity set is called `ZC_TravelTP`, which appears in every URL and in the UI's model. Always alias. |

### Which entities to expose

| Entity | Expose? | Why |
|---|---|---|
| Root projection | Yes | The main entity set |
| Child projections | **Yes** | Even though they are only reached via navigation, the OData metadata needs the entity type |
| Value-help entities | Yes, **unless released** | A `@Consumption.valueHelpDefinition` pointing at an entity that is neither exposed nor released produces an empty F4 |
| Text entities used by `@ObjectModel.text.element` | Yes | Same reason |
| Interface views `ZR_...` | **No** | Never expose the BO model layer. It bypasses the projection's field subset and DCL |

> **Rule:** if it appears in a `@Consumption.valueHelpDefinition`, a `redirected to`, or an
> `@ObjectModel.text.element`, it has to be exposed — or be a released C1 entity such as
> `I_Currency`.

### Exposing another service definition

```abap
define service ZSD_TRAVEL {
  expose ZC_TravelTP as Travel;
  expose ZSD_VALUEHELPS;          " include everything from another service definition
}
```
Useful to factor a shared set of value-help entities out of five services.

---

## 6.3 The Service Binding

ADT: *New → Other ABAP Repository Object → Business Services → Service Binding*.
You choose a **binding type** at creation and it cannot be changed afterwards.

### The binding types

| Binding type | Protocol | Use for |
|---|---|---|
| **OData V4 — UI** | OData V4 | New Fiori Elements apps. **The default choice.** |
| **OData V2 — UI** | OData V2 | Older Fiori Elements floorplans, SAPUI5 apps that require V2, Analytical List Page on older releases |
| **OData V4 — Web API** | OData V4 | Machine-to-machine integration. No UI annotations in the metadata |
| **OData V2 — Web API** | OData V2 | Legacy integration |
| **InA — UI** | InA | SAP Analytics Cloud / analytical consumption |
| **SQL** | SQL service | Direct SQL consumption from outside (e.g. SAC, Data Warehouse Cloud) |

### UI vs Web API — the real difference

| | UI binding | Web API binding |
|---|---|---|
| `@UI.*` annotations in `$metadata` | Yes | **No** (stripped) |
| Draft actions exposed | Yes | Yes |
| Intended consumer | Fiori Elements / UI5 | Another system, iFlow, external partner |
| `$metadata` size | Large | Small |
| Preview button in ADT | Yes | No |

Creating both from one service definition is normal and costs nothing.

### V2 vs V4 — how to choose

| Choose OData **V4** when | Choose OData **V2** when |
|---|---|
| New development (default) | You must support an existing V2-only UI5 app |
| You want `strict ( 2 )`, deep create, better `$batch` | You need the Analytical List Page on an older stack |
| You want draft with the modern UI | An external consumer only speaks V2 |

**V4 restriction to know:** in OData V4 UI bindings, **the entity set names are taken from the
`expose ... as` alias**, and navigation properties come from the association names. V2 is more
forgiving about naming but less capable.

---

## 6.4 Creating and activating the binding

1. *New → Service Binding*, name `ZUI_TRAVEL_O4`, binding type *OData V4 - UI*, service definition
   `ZSD_TRAVEL`.
2. Activate the binding object.
3. Press **Publish** (the button in the binding editor, left of the service-URL box).
   - Publishing generates the runtime service artifacts and the local service URL.
   - The status must go to **Published (Local)**.
4. The **Service URL** appears, e.g.
   `/sap/opu/odata4/sap/zui_travel_o4/srvd/sap/zsd_travel/0001/`
5. Select an entity set on the right and press **Preview** → the Fiori Elements preview opens in a
   browser.

> On S/4HANA on-premise the binding must additionally be exposed through the ICF and, for a real
> Launchpad tile, through `/IWFND/MAINT_SERVICE` or the SAP Gateway "Activate and Maintain Services"
> app. For **development preview**, Publish + Preview is enough.

### Service versions

The `0001` in the URL is the **service version**. Adding a new version lets you change the model
incompatibly while old consumers keep using `0001`.

- In the binding editor: *Add Version*.
- Each version points at its own service definition.
- Only relevant for Web API bindings consumed by systems you do not control. For an internal UI,
  stay at `0001`.

---

## 6.5 Testing the service without a UI

### From the browser

| URL suffix | Returns |
|---|---|
| `.../0001/$metadata` | The full EDM model — the single most useful debugging artifact |
| `.../0001/Travel` | All travels (JSON) |
| `.../0001/Travel?$top=5` | First 5 |
| `.../0001/Travel?$filter=OverallStatus eq 'O'` | Filtered |
| `.../0001/Travel?$expand=_Booking` | With children |
| `.../0001/Travel(TravelUUID=guid'...',IsActiveEntity=true)` | One instance (note the draft key part!) |
| `.../0001/Travel?$select=TravelId,TotalPrice&$orderby=TotalPrice desc` | Projection + sort |
| `.../0001/Travel/$count` | Row count |

**`$metadata` is your friend.** If a field, an action or a value help does not behave, look at
`$metadata` first. If it is not there, the problem is in CDS/BDEF, not in the UI.

### From ADT

Right-click the service binding → *Open with → Service Consumption* / use the **Preview**.
There is also the **OData V4 test tool** at
`/sap/bc/adt/businessservices/odatav4/feap` in some releases.

### From ABAP

Do **not** call your own service over HTTP from ABAP. Use EML (Chapter 18) — same BO, no network,
no serialization, full transactional integration.

---

## 6.6 Making it a real Fiori Launchpad app (on-premise)

The Preview button is a development tool. For end users you need one of:

**Option A — Fiori Elements app in BAS / VS Code (recommended)**

1. SAP Business Application Studio → *Create Project from Template* → *SAP Fiori application*.
2. Data source: *Connect to a System* → your S/4 system → select the OData service.
3. Floorplan: *List Report Object Page*.
4. Main entity: `Travel`, navigation: `_Booking`.
5. Deploy to ABAP (`npm run deploy`) → creates a BSP application.
6. Create the Launchpad tile in the *Launchpad App Manager* app or via `/UI2/FLPD_CUST`.

**Option B — no UI5 project at all**
Use the *Manage Launchpad Spaces / Pages* apps with the **"SAP Fiori elements v4 app descriptor"**
route where supported — the service binding alone is sufficient, and the app is generated at
runtime. Availability depends on release.

**Option C — Custom UI5 app**
Full freedom, full cost. Only when Fiori Elements genuinely cannot do it.

---

## 6.7 Common problems

| Symptom | Cause |
|---|---|
| *"Service is not published"* | Press **Publish** in the binding editor |
| Preview opens with an empty table and no error | No data in the table, **or** DCL filtering everything out, **or** a mandatory filter is unfilled |
| Preview shows "No matching entity type found" | Entity exposed in the service definition but the binding was not re-published after the change |
| Value help is empty | The value-help entity is not exposed in the service definition |
| Action button missing | Not `use action` in the projection BDEF, or not annotated with `type: #FOR_ACTION`, or browser cache |
| `$metadata` HTTP 500 | Usually an inconsistent CDS/BDEF pair; activate BDEF, projection BDEF, views and binding in that order |
| Changes to the MDE do not show | Re-publish the binding and clear the browser cache |
| *"Entity ... does not have a behavior definition"* | `provider contract transactional_query` on a projection with no projection BDEF |

### The activation order that avoids 90% of these

```
1. DDIC tables
2. Interface views (child first, then root)
3. Behavior definition (base)
4. Behavior pool class
5. Projection views (child first, then root)
6. Projection behavior definition
7. Metadata extensions
8. Service definition
9. Service binding  -> then Publish
```

When something is inconsistent, re-activating in this order usually fixes it without any code change.

---

## 6.8 Interview answer

> **"How do you expose a RAP business object as an OData V4 service?"**
>
> Two objects. The **service definition** says *what* is exposed — `expose ZC_TravelTP as Travel;` —
> and must include the child entities plus every value-help and text entity, or the F4 comes back
> empty. The **service binding** says *how*: protocol and version, OData V4 UI for a Fiori app or
> V4 Web API for machine-to-machine, where the UI annotations are stripped out. You activate the
> binding and then **Publish** it, which generates the runtime artifacts and the service URL.
>
> One service definition can feed several bindings, so the same model can serve a Fiori app and an
> API without duplication.
>
> The prerequisite on the CDS side is `provider contract transactional_query` on the root projection
> plus a projection behavior definition. Omit the contract and you get a read-only service — which
> is what you want for a report.
>
> For diagnosis, `$metadata` is the source of truth: if an entity, an action or an annotation is not
> there, the problem is in CDS or the BDEF and there is no point looking at the UI.

## 6.9 Production considerations

- **Publishing is a per-system step.** The binding object transports; treat publication in QA and
  PROD as an explicit post-import task and agree who has the authorization to do it (Chapter 25).
- **On-premise you also need the ICF node active** and, in hub or V2 scenarios, the service
  registered in the gateway.
- **Version Web API bindings** consumed by external systems. Changing `$metadata` without a new
  version breaks the consumer.
- **Do not expose `ZR_` interface views.** That bypasses the projection's field subset and its DCL.
- **A UI binding's `$metadata` is large.** For integration consumers always use a Web API binding.
- **Re-publish after metadata changes** and clear the OData metadata cache, or annotation changes
  will not be visible.
- **Never call your own service over HTTP from ABAP.** Use EML — same BO, no network, full
  transactional integration.

---

[< Metadata Extension](05-Metadata-Extension-and-UI-Annotations.md) | [Index](00-README.md) | [Next: Read-Only Fiori Report >](07-ReadOnly-Fiori-Report-Walkthrough.md)
