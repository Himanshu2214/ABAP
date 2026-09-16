# Chapter 25 — Transport and Deployment (DEV → QA → PROD)

[< Performance & Production Readiness](24-Performance-and-Production-Readiness.md) | [Index](00-README.md) | [Next: Anti-Patterns >](26-Anti-Patterns.md)

---

## 25.1 What is it?

Everything between "it works in my ADT session" and "a business user opens the tile in production".

RAP adds several artifacts that classic ABAP developers have not transported before — behavior
definitions, service definitions, service bindings, metadata extensions — plus a set of
**non-transportable** steps that must be repeated per system.

---

## 25.2 Why do we need it?

Because a RAP app can transport cleanly and still not work. The usual reasons:

| Transported fine | Still broken because |
|---|---|
| All repository objects | The **service binding was never published** in the target system |
| All repository objects | The **ICF node / OData service** is not active (on-premise) |
| All repository objects | The **PFCG roles** were not transported or not assigned |
| All repository objects | The **Launchpad catalog / space / tile** does not exist |
| All repository objects | The **number range object** has no interval in the target client |
| All repository objects | **Customizing / master data** the app depends on is missing |

Transporting the code is maybe 60% of a RAP deployment.

---

## 25.3 Package design

Get this right on day one; it is painful to change later.

```
ZRAP_TRAVEL                      (main package, transport layer assigned)
 +-- ZRAP_TRAVEL_DB              tables, data elements, domains, lock objects
 +-- ZRAP_TRAVEL_MODEL           interface views (ZR_, ZI_), DCL for the model layer
 +-- ZRAP_TRAVEL_BEHAVIOR        BDEF, behavior pools, message class, exception classes
 +-- ZRAP_TRAVEL_UI              projection views, projection BDEF, MDEs, DCL for the service
 +-- ZRAP_TRAVEL_SRV             service definitions, service bindings
 +-- ZRAP_TRAVEL_TEST            test classes, test data helpers
```

| Decision | Guidance |
|---|---|
| Package type | **Development package**, not a structure package, for the leaves |
| Software component | `HOME` / `ZLOCAL` for custom development, unless your landscape says otherwise |
| Transport layer | Must be assigned, or objects land in `$TMP` and cannot be transported |
| Package interfaces | Worth defining if other teams will reuse `ZR_`/`ZI_` views |
| `$TMP` | **Never** for anything that must reach QA. Check before you start, not after |

> A very common first mistake: developing in `$TMP` "just to try it" and then discovering that
> reassigning a package changes the object's transport request handling. Create the package first.

---

## 25.4 What transports, and what does not

### Transportable repository objects

| Object | Notes |
|---|---|
| DDIC tables, data elements, domains, structures | Table changes may require conversion in the target |
| Lock objects | Needed for unmanaged locking |
| CDS views (interface, projection) | |
| Metadata extensions | Separate objects from the views |
| Access controls (DCL) | |
| Behavior definitions | |
| Behavior pool classes, exception classes, auxiliary classes | |
| Message class (SE91) | |
| Service definitions | |
| **Service bindings** | The object transports; **publication state may not** — see 25.6 |
| Number range **object** (SNRO) | The **intervals** do not — see below |
| Authorization object (SU21) | |
| PFCG roles | Transported via role transport, often a separate request |
| Fiori app (BSP) if you built a UI5 project | Deployed separately via `npm run deploy` or `/UI5/UI5_REPOSITORY_LOAD` |

### Not transported — repeat in every system

| Item | Where |
|---|---|
| **Number range intervals** | `SNRO` → *Number ranges* → maintain per client. Transporting the object does **not** carry the interval |
| **Service binding publication** | Publish in each system (see 25.6) |
| **ICF service activation** | `SICF` |
| **OData service registration** | `/IWFND/MAINT_SERVICE` (V2/on-premise scenarios) |
| **Launchpad content** (catalog, group, space, page, tile) | Maintained per system, or transported via its own mechanism |
| **Role assignment to users** | Per system, usually by the security team |
| **Customizing** | Its own customizing request |
| **Master data / test data** | Never transported |
| **Communication arrangements / scenarios** | Per system (cloud); RFC destinations per system (on-premise) |
| **Background job scheduling** | Per system |

---

## 25.5 Transport organisation and sequence

### One request or several?

For a new application: **one request with several tasks** is usually easiest, because RAP objects
are tightly coupled — a BDEF cannot activate without its CDS view.

Splitting becomes necessary when:

- DDIC changes must go ahead of the rest (a table extension released early),
- roles go on a separate request by policy,
- a hotfix must move independently.

**If you split, the import sequence matters.** The safe order is the same as the build order:

```
1. DDIC (tables, data elements, domains, lock objects)
2. Interface views (children before parents)
3. Behavior definitions + behavior pools + message class
4. Projection views + projection BDEF
5. Metadata extensions + DCL
6. Service definitions
7. Service bindings
8. Authorization objects and roles
```

Importing a request containing a projection view before the request containing its interface view
produces activation errors in the target system that look like code defects.

### Release checklist (DEV)

- [ ] Everything activates with **zero errors and zero warnings**.
- [ ] ATC run, findings triaged (HANA-readiness + security variants).
- [ ] ABAP Unit tests green.
- [ ] No object left in `$TMP` (`SE03` → *Search for Objects in Requests* / check the package).
- [ ] No `new_message_with_text` left in the code (not translatable).
- [ ] No temporary debug messages or hard-coded test values.
- [ ] Texts translated, or at least flagged for translation.
- [ ] The transport description says what the change does, not "RAP changes".

---

## 25.6 Service binding activation in the target system

**This is the step most often missed.**

The service binding object transports. Whether it arrives **published** depends on your release and
how the binding was created. Treat it as a post-import step:

1. Open the service binding in ADT, connected to the target system.
2. Check the status. If it is not **Published**, press **Publish**.
3. Confirm the Service URL is generated.

> In many landscapes, developers have no change authorization in QA/PROD. Then publication must be
> handled by whoever does — agree this **before** the first import, not on go-live day. It is a
> frequent cause of "the transport went in but the app is dead".

### On-premise: ICF and gateway

For a service to be reachable over HTTP on-premise:

| Step | Transaction | Notes |
|---|---|---|
| Activate the ICF node | `SICF` | Usually under `/sap/opu/odata4/...`; often already active for the whole branch |
| Register / activate the OData service | `/IWFND/MAINT_SERVICE` | Mainly relevant for V2 and for gateway-hub scenarios. A V4 service published locally may not need it |
| Check the gateway error log after first use | `/IWFND/ERROR_LOG` | First place to look if calls 500 |
| Clear the metadata cache | `/IWFND/CACHE_CLEANUP` | After changing annotations in a system where caching is aggressive |

The exact requirements vary by release and by whether you run an embedded or hub gateway. Confirm
with your Basis team once, and then write it into your own deployment runbook.

---

## 25.7 Authorizations

| Step | Where | Notes |
|---|---|---|
| Create the authorization object | `SU21` | Transportable |
| Add it to a PFCG role | `PFCG` | Maintain the field values (e.g. the agency ids) per system if they differ |
| Add the OData service authorization | `PFCG` → `S_SERVICE` (and the service in the role menu) | Needed for the user to call the service at all |
| Add the Launchpad catalog to the role | `PFCG` → role menu | Controls tile visibility |
| Assign the role to users | `SU01` / identity management | Per system |
| Test with a real role | — | Never validate authorization as a developer with wide authorizations |

> The DCL (`@MappingRole: true`) binds automatically to users who hold the PFCG authorization — but
> **only if the role exists and is assigned in that system**. A DCL that filters everything is the
> normal symptom of a missing role assignment in QA.

---

## 25.8 Launchpad

Development preview and a productive Launchpad tile are **not the same thing**:

| | ADT Preview | Fiori Launchpad |
|---|---|---|
| How it starts | Service binding → *Preview* | Tile in a catalog/space |
| Who can use it | Developers with ADT | End users |
| Needs a UI5 app / BSP | No | Usually yes |
| Needs catalog/group/space/page | No | Yes |
| Needs `S_SERVICE` and role menu entries | No (dev authorizations) | Yes |
| Theming, navigation, personalisation | Minimal | Full |
| Suitable for user acceptance testing | **No** | Yes |

**Do not sign off UAT on the ADT preview.** It bypasses Launchpad configuration, role checks and
navigation — exactly the areas that break in QA.

### Getting to a real tile

1. Generate a Fiori Elements app in SAP Business Application Studio (or VS Code) from the OData
   service — *List Report Object Page* template.
2. Deploy to ABAP (`npm run deploy`) → creates a BSP application, on a transport request.
3. Create/extend the **catalog** and **tile** (Launchpad App Manager app, or `/UI2/FLPD_CUST`).
4. Assign the catalog to a **space/page** (or group, on older launchpads).
5. Add the catalog to the **PFCG role**.
6. Transport the BSP and the Launchpad content.

---

## 25.9 APIs and integration

If the deliverable is a Web API binding rather than a UI:

| Step | On-premise | Cloud / ABAP Environment |
|---|---|---|
| Expose | Service binding, type *OData V4 - Web API* | Same |
| Reach it | ICF node + `S_SERVICE` authorization | **Communication scenario** (transportable) + **communication arrangement** (per system) |
| Credentials | Technical user, RFC destination | Communication user, communication system |
| Versioning | Service binding version (`0001`, `0002`) | Same |
| Contract | Publish `$metadata` to the consumer | Same |

For cloud: the **communication scenario** is a transportable development object; the
**communication arrangement** (which binds a scenario to a system and user) is configuration and is
maintained per system. Plan the arrangement with the integration team before the import.

For outbound integration (your RAP app calling somebody else), remember the phase rules from
Chapter 17: no synchronous RFC or HTTP in the late save phase. Enqueue and process asynchronously,
with retry and idempotency.

---

## 25.10 Post-import checklist (run in every target system)

**Technical**

- [ ] Import log shows return code 0 or 4 (investigate any 4; never accept 8).
- [ ] All objects active — `SE03` → *Check Objects* / activate inactive objects.
- [ ] Table conversions completed (`SE14` if a table changed).
- [ ] Service binding is **Published**; Service URL present.
- [ ] `$metadata` returns 200 and contains the expected entities, actions and annotations.
- [ ] ICF node active (on-premise).
- [ ] Metadata/OData caches cleared.
- [ ] Number range intervals maintained in the target **client**.
- [ ] Draft clean-up job scheduled.
- [ ] Any application jobs scheduled.

**Functional**

- [ ] Log on as a **business test user**, not as a developer.
- [ ] Tile visible in the Launchpad.
- [ ] List Report opens; mandatory filters behave.
- [ ] **Value helps return data** (the classic QA-only failure — a missing `expose`, or DCL).
- [ ] Create → save works; number range assigns a document number.
- [ ] Validations fire with the right messages.
- [ ] Determinations produce the right calculated values, and the UI refreshes (side effects).
- [ ] Action buttons appear, are enabled/disabled correctly, and work.
- [ ] Draft: cancel, resume, and a two-session lock conflict.
- [ ] Delete cascades to children.
- [ ] Texts appear in the target language.

**Authorization**

- [ ] A user **with** the role sees the expected rows.
- [ ] A user **without** it sees nothing / is refused.
- [ ] Instance-level restriction works (a user restricted to one agency cannot change another's).
- [ ] Buttons requiring a specific activity are hidden/disabled for users without it.

---

## 25.11 Common errors

| Symptom in QA/PROD | Cause |
|---|---|
| Tile missing | Catalog not in the PFCG role, or Launchpad content not transported |
| Tile present, app does not start | Service binding not published; ICF node inactive |
| App starts, no data | DCL + missing role assignment; or no data in that client |
| Value helps empty | Value-help entity not exposed, or DCL on it |
| Document number not assigned | Number range interval not maintained in the target client |
| Action button missing | Metadata cache; or the projection BDEF request was not part of the import |
| Activation errors after import | Requests imported in the wrong order |
| Works for the developer, not for users | Developer has wide authorizations; role incomplete |
| Texts in English only | Translation not transported |
| App worked, broke after the next import | A partially imported change set — check that all related requests moved together |
| Background job never runs | Not scheduled in the target system |

---

## 25.12 Interview answer

> **"How did you transport and activate the service in QA and production?"**
>
> The repository objects — tables, CDS views, DCL, behavior definitions and pools, metadata
> extensions, service definition and service binding — all go on transport requests from a proper
> development package, never `$TMP`. If the change set is split across requests, the import order
> has to follow the build order: DDIC, then interface views, then behavior, then projections, then
> metadata extensions, then the service objects — otherwise you get activation errors in the target
> that look like code defects.
>
> The part people underestimate is what does **not** transport. The service binding object moves,
> but I treat **publishing it in the target system** as an explicit post-import step, and I agree up
> front who does it, because developers usually have no change authorization in QA and PROD.
> Number range **intervals** are not transported either — the SNRO object is, the interval is not —
> so a missing document number in QA is almost always that. Launchpad catalogs and tiles, role
> assignments, ICF activation, communication arrangements and job scheduling are all per-system too.
>
> Then I run a post-import checklist as a **business test user**, not as a developer: tile visible,
> `$metadata` correct, value helps returning data, create and save producing a document number,
> validations firing, action buttons enabled correctly, and the authorization cases — a user with
> the role and a user without it. Testing authorization as a developer with wide authorizations
> proves nothing.
>
> And UAT is signed off on the real Launchpad app, never on the ADT service-binding preview, because
> the preview bypasses exactly the Launchpad and role configuration that tends to break.

---

## 25.13 Production considerations

- **Write a deployment runbook** for the application, listing every non-transportable step. Do it
  after the first QA import, while the pain is fresh.
- **Automate what you can.** The post-import checks that can be scripted (service reachable,
  `$metadata` contains expected actions, number range interval exists) are worth a small ABAP report.
- **Keep DEV, QA and PROD on the same release.** RAP syntax availability differs between releases;
  code that activates in DEV on a newer stack will not activate in an older PROD.
- **Plan a rollback.** For a RAP app the realistic rollback is a corrective transport, not an
  un-import — design changes so that the previous version still runs if the new one is disabled.
- **Version Web API bindings** if external systems consume them. Breaking a published `$metadata`
  contract without a new version breaks the consumer.
- **Record who publishes bindings and who assigns roles.** These two hand-offs cause more go-live
  delays than any code problem.

---

[< Performance & Production Readiness](24-Performance-and-Production-Readiness.md) | [Index](00-README.md) | [Next: Anti-Patterns >](26-Anti-Patterns.md)
