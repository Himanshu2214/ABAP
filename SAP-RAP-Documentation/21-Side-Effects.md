# Chapter 21 — Side Effects

[< Troubleshooting & Cheat Sheet](20-Messages-Troubleshooting-and-Cheat-Sheet.md) | [Index](00-README.md) | [Next: Value Helps >](22-Value-Helps-and-Text-Associations.md)

---

## 21.1 What is it?

A **side effect** is a declaration in the behavior definition that tells the **consumer** (in
practice: Fiori Elements) *"when X changes, the data you are holding for Y is now stale — go and
read it again."*

It changes nothing on the server. It changes what the client asks for.

```abap
side effects
{
  field BookingFee affects field TotalPrice;
}
```

Read it as: *"after the user changes `BookingFee`, re-request `TotalPrice`."*

---

## 21.2 Why do we need it?

Because OData is stateless and the UI is not clairvoyant.

When the user types into `BookingFee`, Fiori Elements sends a `PATCH` containing **only that field**
and gets back a response containing — by default — only what it asked about. Meanwhile, on the
server, your determination recalculated `TotalPrice`. That new value sits in the transactional
buffer, correct and invisible.

```
  UI                                Server
  --                                ------
  PATCH { BookingFee: 30 }   ---->  buffer: BookingFee = 30
                                    determination calculateTotalPrice runs
                                    buffer: TotalPrice = 430
  <----  200 { BookingFee: 30 }
  screen: BookingFee 30
          TotalPrice  400   <-- STALE. The user sees the old number.
```

The determination is not broken. The UI simply never asked.

> **This is the single most common "my determination doesn't work" false alarm in RAP.**
> Before debugging a determination, check whether a side effect is declared. If you can see the
> correct value after pressing F5, the determination is fine and the side effect is missing.

---

## 21.3 Where is it used?

| Situation | Declare |
|---|---|
| A determination derives field B from field A | `field A affects field B;` |
| A determination derives a header total from item changes | `field Price affects entity _Travel;` (on the child) |
| An action changes fields on the instance | `action X affects field F;` — or give the action `result [1] $self` instead |
| An action creates or deletes child rows | `action X affects entity _Booking;` |
| An action produces messages the user must see | `action X affects messages;` |
| A field change enables or disables a button | `field Status affects permissions;` |
| Draft: `Prepare` produces validation messages | `determine action Prepare affects messages;` |

### Where to declare it — base BDEF or projection BDEF?

Both are legal. The useful split:

| Put it in the... | For |
|---|---|
| **Base BDEF** | Side effects that follow from the **business logic** and are true for every consumer — e.g. a total that always recalculates |
| **Projection BDEF** | Side effects that exist because of **this service's UI** — e.g. refreshing a field that only this app displays |

If in doubt, the base BDEF is the safer default: every projection inherits it.

---

## 21.4 Syntax

```abap
side effects
{
  // a field change invalidates another field
  field BookingFee                affects field TotalPrice;

  // one field invalidates several
  field CurrencyCode              affects field TotalPrice, BookingFee;

  // several fields invalidate one
  field BeginDate, EndDate        affects field TripDuration;

  // a field change invalidates a whole associated entity (the child table)
  field CurrencyCode              affects entity _Booking;

  // a field change invalidates the instance itself (everything)
  field OverallStatus             affects $self;

  // a field change requires re-evaluating enablement / feature control
  field OverallStatus             affects permissions;

  // an action invalidates fields, entities, messages, permissions
  action acceptTravel             affects field OverallStatus;
  action createBookingSet         affects entity _Booking;
  action validateDocument         affects messages;
  action acceptTravel             affects permissions;

  // draft: refresh the message list after Prepare
  determine action Prepare        affects messages;

  // a determination's effect (rarely needed - usually you name the field instead)
  determination calculateTotalPrice affects field TotalPrice;
}
```

### The right-hand side

| Target | Meaning |
|---|---|
| `field F1, F2` | Re-read exactly those fields |
| `entity _Assoc` | Re-read the associated entity (the whole child table) |
| `$self` | Re-read the entire instance |
| `messages` | Re-fetch the message list |
| `permissions` | Re-evaluate feature control and instance authorization |

### The left-hand side

| Trigger | Meaning |
|---|---|
| `field F` | The consumer changed F |
| `action A` | The consumer executed A |
| `determine action Prepare` | Prepare ran (draft) |
| `determination D` | Determination D ran |

---

## 21.5 Complete example

The full `side effects` block for the running Travel example, with a reason for every line:

```abap
define behavior for ZR_TravelTP alias Travel
...
{
  ...
  side effects
  {
    // --- price roll-up -------------------------------------------------
    // calculateTotalPrice recomputes TotalPrice whenever the fee or the
    // currency changes. Without these two lines the user sees a stale total.
    field BookingFee    affects field TotalPrice;
    field CurrencyCode  affects field TotalPrice;

    // A currency change also re-renders every child amount (decimal shift,
    // currency symbol), so the whole Bookings table must be re-read.
    field CurrencyCode  affects entity _Booking;

    // --- trip duration -------------------------------------------------
    field BeginDate, EndDate affects field TripDuration;

    // --- status actions ------------------------------------------------
    // acceptTravel / rejectTravel set OverallStatus and its criticality.
    // (These also return result [1] $self, which covers the instance itself;
    //  the 'permissions' line is the part $self does NOT cover.)
    action acceptTravel affects field OverallStatus, OverallStatusCriticality;
    action rejectTravel affects field OverallStatus, OverallStatusCriticality;

    // Once accepted, the Accept button must grey out and the date fields
    // must become read-only. That is feature control, not data.
    field  OverallStatus affects permissions;
    action acceptTravel  affects permissions;
    action rejectTravel  affects permissions;

    // --- an action that creates children --------------------------------
    action createStandardBookings affects entity _Booking;

    // --- draft ----------------------------------------------------------
    // Prepare runs the validations; their messages must reach the UI.
    determine action Prepare affects messages;
  }
}
```

And on the **child**, so that changing a booking price refreshes the parent's total:

```abap
define behavior for ZR_BookingTP alias Booking
...
{
  ...
  side effects
  {
    // FlightPrice feeds the parent's TotalPrice via the internal action
    // recalculatePrices. The parent's TotalPrice is what must be re-read.
    field FlightPrice   affects field _Travel.TotalPrice;
    field CurrencyCode  affects field _Travel.TotalPrice;
  }
}
```

> `field _Travel.TotalPrice` — a **path expression** on the right-hand side, following the
> `association to parent`. This is how a child declares an effect on its parent. Support for path
> expressions in side effects depends on your release; if it is rejected, fall back to
> `field FlightPrice affects entity _Travel;` (coarser, re-reads the whole parent).

---

## 21.6 Runtime behavior

What actually happens, step by step:

```
1. BDEF activated
     -> side effects are written into the OData $metadata as
        com.sap.vocabularies.Common.v1.SideEffects annotations

2. Fiori Elements loads $metadata and builds a map:
        "BookingFee changed"  ->  re-request TargetProperties [ TotalPrice ]

3. User edits BookingFee, field loses focus
     -> PATCH { BookingFee: 30 }

4. Server: determination runs, buffer updated

5. UI consults its map, issues a follow-up GET for TotalPrice
     -> GET .../Travel(...)?$select=TotalPrice

6. TotalPrice repaints
```

Consequences worth knowing:

| Behaviour | Implication |
|---|---|
| Side effects cost an **extra round trip** | Do not declare `affects $self` where `affects field X` will do |
| They are **client-side hints** | EML consumers ignore them entirely. A background job does not need and does not use them |
| They are **declarative only** | There is no handler method. Nothing to implement, nothing to debug in ABAP |
| They fire **after** the triggering request completes | The server has already run the determination by then |
| `affects permissions` triggers a `GET PERMISSIONS`-style request | More expensive than a field re-read; declare it only where enablement really changes |

### Side effect vs determination — they are not alternatives

| | Determination | Side effect |
|---|---|---|
| Where it runs | Server (behavior pool) | Client (Fiori Elements) |
| What it does | **Calculates** the new value | **Asks for** the new value |
| Implementation | ABAP method | One line of BDL |
| Without it | The value is wrong | The value is right but **displayed** wrong |

You almost always need **both**: the determination to compute, the side effect to display.

---

## 21.7 Common errors

| Symptom | Cause | Fix |
|---|---|---|
| Calculated field shows the old value until F5 | No side effect declared | `field A affects field B;` |
| Child table does not refresh after a header change | `affects entity _Booking` missing | Add it |
| Button stays enabled after the status changes | `affects permissions` missing | Add it |
| Validation messages do not appear after Prepare | `determine action Prepare affects messages;` missing | Add it |
| Action result is correct in the response but the screen is stale | Action has no `result [1] $self` **and** no side effect | Add `result [1] $self` (preferred) or a side effect |
| Every keystroke triggers several requests; the app feels slow | Over-declared side effects — `affects $self` or `affects entity` where a field would do | Narrow the targets |
| Side effect ignored in a test class | Correct — EML consumers do not use side effects | Assert on the buffer with `READ ENTITIES`, not on refresh behaviour |
| Change had no effect after adding the declaration | BDEF not re-activated, binding not re-published, or browser cache | Re-activate, re-publish, hard-reload |
| Activation error: unknown field on the right-hand side | The field is not exposed in the projection, or the path expression form is not supported on this release | Expose it, or use the coarser `affects entity` form |

### Diagnosing "is it the determination or the side effect?"

```
Change the field in the UI.  Is the displayed value wrong?
        |
        +-- Press F5.  Is it now right?
                |
                +-- YES -> the determination is fine. The SIDE EFFECT is missing.
                |
                +-- NO  -> the determination did not run, or ran wrongly.
                           Debug the determination (Chapter 12, §12.7).
```

This 10-second test saves hours. Run it before opening the debugger.

---

## 21.8 Interview answer

> **"What are side effects in RAP?"**
>
> A side effect is a declaration in the behavior definition that tells the consuming UI which data
> has become stale after a change, so that Fiori Elements knows to re-read it. For example, if a
> determination recalculates a total when the booking fee changes, the UI has no way of knowing
> that — it only sent the fee. Declaring `field BookingFee affects field TotalPrice;` makes the UI
> issue a follow-up read.
>
> It is purely declarative; there is no handler method. It is surfaced in the OData metadata as
> the standard `Common.SideEffects` annotation, so it only affects UI consumers — an EML caller
> ignores it.
>
> The practical point is that a side effect and a determination solve different halves of the same
> problem: the determination computes the value on the server, the side effect makes the client
> ask for it. If a calculated field looks stale but is correct after a refresh, the determination
> is working and the side effect is missing.

---

## 21.9 Production considerations

- **Declare the narrowest target that works.** `affects field TotalPrice` is one small `$select`;
  `affects $self` re-reads the whole instance; `affects entity _Booking` re-reads the child table.
  On an Object Page with 40 fields and 200 items, the difference is very visible.
- **`affects permissions` is the expensive one.** It triggers a permissions round trip. Declare it
  only where the enablement of a button or the read-only-ness of a field genuinely changes.
- **Audit the block when you add a determination.** Every new derived field needs a matching side
  effect, and this is routinely forgotten in change requests months after go-live.
- **Do not chain them into a storm.** `A affects B`, `B affects C`, `C affects entity _X` means one
  keystroke produces three follow-up requests. Collapse them where you can.
- **They are not a substitute for `result [1] $self` on actions.** Returning the instance from the
  action is one round trip; a side effect is two.
- **Review them on mobile.** Extra round trips that are invisible on a LAN are noticeable on a
  phone over mobile data.

---

[< Troubleshooting & Cheat Sheet](20-Messages-Troubleshooting-and-Cheat-Sheet.md) | [Index](00-README.md) | [Next: Value Helps >](22-Value-Helps-and-Text-Associations.md)
