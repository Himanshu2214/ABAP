# Chapter 14 — Feature Control and Authorization

[< Actions & Buttons](13-Actions-Functions-and-Buttons.md) | [Index](00-README.md) | [Next: Unmanaged Scenario >](15-Unmanaged-Scenario.md)

---

## 14.1 Four different mechanisms, often confused

| Mechanism | Question it answers | Where declared | Where implemented |
|---|---|---|---|
| **DCL / Access Control** | Which **rows** may this user *see*? | `@AccessControl.authorizationCheck: #CHECK` + a DCL role | DCL (declarative) |
| **Global authorization** | May this user perform this operation **at all**? | `authorization master ( global )` | `FOR GLOBAL AUTHORIZATION` |
| **Instance authorization** | May this user change **this specific** instance? | `authorization master ( instance )` | `FOR INSTANCE AUTHORIZATION` |
| **Feature control** | Is this field/button **available** right now (business state, not authorization)? | `field ( features : instance )` / `action ( features : instance )` | `FOR INSTANCE FEATURES` / `FOR GLOBAL FEATURES` |

The distinction that matters most:

- **Authorization** = "you are not allowed". Enforced. A rejection is a security failure.
- **Feature control** = "this does not apply right now". A UI affordance. An already-accepted travel
  cannot be accepted again — that is not about permissions.

> Never implement authorization as feature control. Feature control only greys out the button; the
> OData call still reaches the backend and will succeed. Feature control is **not** a security
> boundary.

---

## 14.2 Read authorization — DCL

```abap
@EndUserText.label: 'Access control for Travel'
@MappingRole: true
define role ZC_TRAVELTP {
  grant select on ZC_TravelTP
    where ( AgencyId ) = aspect pfcg_auth( ZTRAVEL_AUTH, AGENCY_ID, ACTVT = '03' );
}
```

| Clause | Meaning |
|---|---|
| `define role ZC_TRAVELTP` | The DCL object. Same name as the view is the convention |
| `@MappingRole: true` | Automatically applies to users holding the PFCG authorization |
| `grant select on ZC_TravelTP` | Read access to this entity |
| `where ( AgencyId ) = aspect pfcg_auth( ... )` | Restrict rows to the agencies the user is authorized for |
| `ZTRAVEL_AUTH` | The authorization object (SU21) |
| `AGENCY_ID` | The authorization field |
| `ACTVT = '03'` | Activity 03 = Display |

### Other DCL constructs

```abap
" unconditional grant
grant select on ZC_TravelTP where ( AgencyId ) = aspect pfcg_auth( ... )
                                or ( CreatedBy ) = aspect user;

" fixed value restriction
grant select on ZC_TravelTP where ( OverallStatus ) = 'A';

" inherit from another entity's DCL
grant select on ZC_BookingTP where inheriting conditions from entity ZC_TravelTP;
```

`inheriting conditions from entity` is the right pattern for child entities: a Booking is visible if
its Travel is visible. Write the rule once, on the root.

### Which layer to put the DCL on

There is no single correct layer. The rule belongs wherever the **authorization requirement**
belongs, and that follows from your reuse and security architecture.

| Option | `ZR_` interface | `ZC_` projection | Use when |
|---|---|---|---|
| **Projection-level** | `#NOT_REQUIRED` | `#CHECK` + DCL | Different services over the same BO need different row-level restrictions. The most common case for a single custom app family. |
| **Interface-level** | `#CHECK` + DCL | `#NOT_REQUIRED` (or `#CHECK` with no extra DCL) | The restriction is an invariant of the data model — no consumer, now or later, may read unrestricted. Typical for sensitive domains (HR, payroll, personal data) and for models you publish for reuse. |
| **Both layers** | `#CHECK` + baseline DCL | `#CHECK` + narrower DCL | A mandatory baseline plus a service-specific narrowing. Conditions from both layers apply, so the effective visibility is the **intersection**. |

Trade-offs to weigh:

| Consideration | Favours projection-level | Favours interface-level |
|---|---|---|
| Several services, different rules | yes | no |
| A rule that must never be bypassed | no | yes |
| The model is consumed directly by other developers' views | no | yes |
| Rule likely to change per app | yes | no |
| Fewer objects to maintain | no (one DCL per service) | yes (one DCL total) |
| Easy to reason about "who can see what" | no | yes |

The examples in this documentation use projection-level DCL because the running example is a
single-app scenario with service-specific filtering. That is a choice, not a rule — if your
architecture says the restriction belongs to the reusable model, put the DCL on `ZR_TravelTP`
and set `#CHECK` there.

> Whichever layer you choose, **write the decision down** in the package documentation. It is
> cheap now and expensive to reverse once several services depend on the model.

### The limit of DCL

**DCL controls `SELECT` only.** It does not stop an update, a delete, or an action. A user who can
see nothing can still, in principle, `PATCH` an instance whose key they guessed — unless the BDEF
authorization stops them. You need both.

---

## 14.3 Global authorization

"May this user create Travels at all?"

```abap
" BDEF
define behavior for ZR_TravelTP alias Travel
...
authorization master ( global )
{
  create ( authorization : global );
  update;
  delete;
}
```

```abap
METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
  IMPORTING REQUEST requested_authorizations FOR Travel RESULT result.
```

```abap
METHOD get_global_authorizations.

  " CREATE
  IF requested_authorizations-%create = if_abap_behv=>mk-on.
    AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH'
      ID 'AGENCY_ID' DUMMY
      ID 'ACTVT'     FIELD '01'.
    IF sy-subrc = 0.
      result-%create = if_abap_behv=>auth-allowed.
    ELSE.
      result-%create = if_abap_behv=>auth-unauthorized.
      APPEND VALUE #( %msg = new_message( id       = 'ZTRAVEL_MSG'
                                          number   = '050'
                                          severity = if_abap_behv_message=>severity-error ) )
             TO reported-%other.
    ENDIF.
  ENDIF.

  " UPDATE
  IF requested_authorizations-%update = if_abap_behv=>mk-on.
    AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH'
      ID 'AGENCY_ID' DUMMY
      ID 'ACTVT'     FIELD '02'.
    result-%update = COND #( WHEN sy-subrc = 0 THEN if_abap_behv=>auth-allowed
                                               ELSE if_abap_behv=>auth-unauthorized ).
  ENDIF.

  " DELETE
  IF requested_authorizations-%delete = if_abap_behv=>mk-on.
    AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH'
      ID 'AGENCY_ID' DUMMY
      ID 'ACTVT'     FIELD '06'.
    result-%delete = COND #( WHEN sy-subrc = 0 THEN if_abap_behv=>auth-allowed
                                               ELSE if_abap_behv=>auth-unauthorized ).
  ENDIF.

  " ACTIONS
  IF requested_authorizations-%action-acceptTravel = if_abap_behv=>mk-on.
    AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH'
      ID 'AGENCY_ID' DUMMY
      ID 'ACTVT'     FIELD '43'.        " 43 = Release / Approve
    result-%action-acceptTravel = COND #( WHEN sy-subrc = 0 THEN if_abap_behv=>auth-allowed
                                                            ELSE if_abap_behv=>auth-unauthorized ).
  ENDIF.

ENDMETHOD.
```

### Why the `IF requested_authorizations-%... = mk-on` guards

The framework asks about **only what it needs right now**. Evaluating everything on every call
costs `AUTHORITY-CHECK` round trips for no reason. Always guard.

### Values

| | |
|---|---|
| `if_abap_behv=>auth-allowed` | Permitted |
| `if_abap_behv=>auth-unauthorized` | Not permitted |

Standard ACTVT values: `01` create, `02` change, `03` display, `06` delete, `43` release/approve.

---

## 14.4 Instance authorization

"May this user change *this* Travel?"

```abap
" BDEF
authorization master ( instance )
```

```abap
METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
  IMPORTING keys REQUEST requested_authorizations FOR Travel RESULT result.
```

```abap
METHOD get_instance_authorizations.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( AgencyId CreatedBy )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels)
    FAILED DATA(read_failed).

  DATA(current_user) = cl_abap_context_info=>get_user_technical_name( ).

  LOOP AT travels INTO DATA(travel).

    " one AUTHORITY-CHECK per distinct agency would be better for mass cases;
    " shown per instance here for clarity
    AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH'
      ID 'AGENCY_ID' FIELD travel-AgencyId
      ID 'ACTVT'     FIELD '02'.
    DATA(agency_ok) = xsdbool( sy-subrc = 0 ).

    DATA(is_owner) = xsdbool( travel-CreatedBy = current_user ).

    DATA(may_change) = xsdbool( agency_ok = abap_true OR is_owner = abap_true ).

    APPEND VALUE #(
      %tky                       = travel-%tky
      %update                    = COND #( WHEN may_change = abap_true
                                           THEN if_abap_behv=>auth-allowed
                                           ELSE if_abap_behv=>auth-unauthorized )
      %delete                    = COND #( WHEN agency_ok = abap_true
                                           THEN if_abap_behv=>auth-allowed
                                           ELSE if_abap_behv=>auth-unauthorized )
      %action-acceptTravel       = COND #( WHEN agency_ok = abap_true
                                           THEN if_abap_behv=>auth-allowed
                                           ELSE if_abap_behv=>auth-unauthorized )
      %assoc-_Booking            = COND #( WHEN may_change = abap_true
                                           THEN if_abap_behv=>auth-allowed
                                           ELSE if_abap_behv=>auth-unauthorized )
    ) TO result.

  ENDLOOP.
ENDMETHOD.
```

| Result component | Controls |
|---|---|
| `%update` | Updating the instance |
| `%delete` | Deleting it |
| `%action-<name>` | Executing that action on it |
| `%assoc-_Booking` | Create-by-association under it |

Note there is no `%create` in instance authorization — creating an instance that does not exist yet
cannot be instance-dependent. That is what global authorization is for.

### Performance

Instance authorization is called for **every instance the user touches**, including every row the
list report displays if the UI asks about permissions. For a mass scenario:

```abap
" collect distinct agencies, check once each, then map
DATA(agencies) = travels.
SORT agencies BY AgencyId.
DELETE ADJACENT DUPLICATES FROM agencies COMPARING AgencyId.

DATA authorized_agencies TYPE SORTED TABLE OF /dmo/agency_id WITH UNIQUE KEY table_line.
LOOP AT agencies INTO DATA(agency).
  AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH' ID 'AGENCY_ID' FIELD agency-AgencyId ID 'ACTVT' FIELD '02'.
  IF sy-subrc = 0.
    INSERT agency-AgencyId INTO TABLE authorized_agencies.
  ENDIF.
ENDLOOP.
" then use line_exists( authorized_agencies[ table_line = travel-AgencyId ] )
```

---

## 14.5 Feature control — static

Declared in the BDEF and never changes:

```abap
field ( readonly ) TotalPrice, OverallStatus, CreatedBy, CreatedAt;
field ( mandatory ) AgencyId, CustomerId, BeginDate, EndDate;
field ( readonly : update ) CurrencyCode;      " set on create, frozen afterwards
```

No code. The framework enforces it and the UI renders accordingly.

---

## 14.6 Feature control — dynamic (instance features)

"An accepted Travel cannot be accepted again, and its dates can no longer be changed."

```abap
" BDEF
define behavior for ZR_TravelTP alias Travel
...
{
  update;
  delete;

  field ( features : instance ) BeginDate, EndDate, BookingFee;

  action ( features : instance ) acceptTravel result [1] $self;
  action ( features : instance ) rejectTravel result [1] $self;

  association _Booking { create ( features : instance ); with draft; }
}
```

```abap
METHODS get_instance_features FOR INSTANCE FEATURES
  IMPORTING keys REQUEST requested_features FOR Travel RESULT result.
```

```abap
METHOD get_instance_features.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( OverallStatus BeginDate )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels)
    FAILED DATA(read_failed).

  result = VALUE #(
    FOR travel IN travels
    LET is_accepted = COND #( WHEN travel-OverallStatus = zbp_r_traveltp=>c_status-accepted
                              THEN if_abap_behv=>fc-o-disabled
                              ELSE if_abap_behv=>fc-o-enabled )
        is_rejected = COND #( WHEN travel-OverallStatus = zbp_r_traveltp=>c_status-rejected
                              THEN if_abap_behv=>fc-o-disabled
                              ELSE if_abap_behv=>fc-o-enabled )
        locked_flds = COND #( WHEN travel-OverallStatus <> zbp_r_traveltp=>c_status-open
                              THEN if_abap_behv=>fc-f-read_only
                              ELSE if_abap_behv=>fc-f-unrestricted )
    IN
    ( %tky                   = travel-%tky

      " operations
      %update                = COND #( WHEN travel-OverallStatus = zbp_r_traveltp=>c_status-rejected
                                       THEN if_abap_behv=>fc-o-disabled
                                       ELSE if_abap_behv=>fc-o-enabled )
      %delete                = COND #( WHEN travel-OverallStatus = zbp_r_traveltp=>c_status-open
                                       THEN if_abap_behv=>fc-o-enabled
                                       ELSE if_abap_behv=>fc-o-disabled )

      " actions
      %action-acceptTravel   = is_accepted
      %action-rejectTravel   = is_rejected

      " create-by-association
      %assoc-_Booking        = COND #( WHEN travel-OverallStatus = zbp_r_traveltp=>c_status-open
                                       THEN if_abap_behv=>fc-o-enabled
                                       ELSE if_abap_behv=>fc-o-disabled )

      " fields
      %field-BeginDate       = locked_flds
      %field-EndDate         = locked_flds
      %field-BookingFee      = locked_flds
    ) ).

ENDMETHOD.
```

### The two constant families — do not mix them

| For **operations, actions, associations** (`%update`, `%delete`, `%action-X`, `%assoc-_A`) | |
|---|---|
| `if_abap_behv=>fc-o-enabled` | Available |
| `if_abap_behv=>fc-o-disabled` | Greyed out |

| For **fields** (`%field-X`) | |
|---|---|
| `if_abap_behv=>fc-f-unrestricted` | Editable |
| `if_abap_behv=>fc-f-read_only` | Display only |
| `if_abap_behv=>fc-f-mandatory` | Must be filled |

Using an `fc-o-` constant on a `%field-` (or vice versa) compiles and then behaves unpredictably.
`strict ( 2 )` catches most of these; it is still worth being careful.

### Global features

For operations that are disabled for everyone under some condition (a system-wide switch, a closed
period):

```abap
" BDEF
create ( features : global );
```

```abap
METHODS get_global_features FOR GLOBAL FEATURES
  IMPORTING REQUEST requested_features FOR Travel RESULT result.
```

```abap
METHOD get_global_features.
  result-%create = COND #( WHEN zcl_travel_config=>is_period_open( )
                           THEN if_abap_behv=>fc-o-enabled
                           ELSE if_abap_behv=>fc-o-disabled ).
ENDMETHOD.
```

### Refreshing feature control on screen

When a field change should re-evaluate button enablement, declare it:

```abap
side effects
{
  field OverallStatus affects permissions;
}
```

Without this, the user accepts a Travel and the *Accept* button stays enabled until they refresh.

---

## 14.7 Precheck

A `precheck` handler runs **before** the data enters the transactional buffer.

```abap
" BDEF
update ( precheck );
delete ( precheck );
association _Booking { create ( precheck ); with draft; }
```

```abap
METHODS precheck_update FOR PRECHECK IMPORTING entities FOR UPDATE Travel.
```

```abap
METHOD precheck_update.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel FIELDS ( OverallStatus ) WITH CORRESPONDING #( entities )
    RESULT DATA(travels).

  LOOP AT entities INTO DATA(entity).
    DATA(travel) = VALUE #( travels[ %tky = entity-%tky ] OPTIONAL ).

    IF travel-OverallStatus = zbp_r_traveltp=>c_status-rejected.
      APPEND VALUE #( %tky = entity-%tky ) TO failed-travel.
      APPEND VALUE #( %tky = entity-%tky
                      %msg = new_message( id = 'ZTRAVEL_MSG' number = '060'
                                          severity = if_abap_behv_message=>severity-error ) )
             TO reported-travel.
    ENDIF.
  ENDLOOP.
ENDMETHOD.
```

### Precheck vs validation

| | Precheck | Validation |
|---|---|---|
| Runs | Before the change enters the buffer | After (interaction) or at save |
| Sees | The **incoming request** (`entities`, with `%control`) | The **buffer state** (keys only; you read) |
| Prevents the change from happening | Yes | No — it rejects the *save* |
| Typical use | Reject a bad request early; check the *delta* being sent | Check the final document state |

Use precheck when the incoming values themselves are the problem (e.g. "you may not change
`CurrencyCode` on a posted document"). Use validation for document-level consistency.

---

## 14.8 The complete authorization picture for our example

| Concern | Mechanism | Object |
|---|---|---|
| Which travels can a user see in the list? | DCL | `ZC_TRAVELTP` role, `pfcg_auth( ZTRAVEL_AUTH, AGENCY_ID, ACTVT='03' )` |
| May the user create any travel? | Global authorization | `get_global_authorizations`, ACTVT `01` |
| May the user change *this* travel? | Instance authorization | `get_instance_authorizations`, ACTVT `02` on the row's `AgencyId` |
| May the user accept *this* travel? | Instance authorization | `%action-acceptTravel`, ACTVT `43` |
| Can an accepted travel be accepted again? | Feature control | `%action-acceptTravel = fc-o-disabled` |
| Are the dates editable after acceptance? | Feature control | `%field-BeginDate = fc-f-read_only` |
| Can `TotalPrice` ever be typed by a user? | Static field control | `field ( readonly ) TotalPrice;` |

### The authorization object (SU21)

```
Object      : ZTRAVEL_AUTH
Class       : Z_CUSTOM
Fields      : AGENCY_ID  (referencing data element /DMO/AGENCY_ID)
              ACTVT      (ACTVT, allowed values 01, 02, 03, 06, 43)
```

Then a PFCG role with `ZTRAVEL_AUTH` and the relevant agency values, assigned to the user.

---

## 14.9 End-to-end worked scenario

One requirement, implemented across all four mechanisms, so the division of labour is concrete.

### The requirement

> A travel agent may only work with travels of the agencies they are assigned to.
> Within those agencies: a **clerk** may create and change travels but not delete or accept them;
> a **supervisor** may do everything. Nobody may change a travel that has been rejected.
> A user with no assignment sees nothing at all.

### The authorization object (SU21)

```
Object : ZTRAVEL_AUTH
Fields : AGENCY_ID   (data element /DMO/AGENCY_ID)
         ACTVT       (values 01 create, 02 change, 03 display, 06 delete, 43 release)
```

Two PFCG roles:

| Role | `AGENCY_ID` | `ACTVT` |
|---|---|---|
| `Z_TRAVEL_CLERK` | assigned agencies | `01`, `02`, `03` |
| `Z_TRAVEL_SUPERVISOR` | assigned agencies | `01`, `02`, `03`, `06`, `43` |

### Step 1 — DCL: which rows are visible

```abap
@EndUserText.label: 'Access control for Travel'
@MappingRole: true
define role ZC_TRAVELTP {
  grant select on ZC_TravelTP
    where ( AgencyId ) = aspect pfcg_auth( ZTRAVEL_AUTH, AGENCY_ID, ACTVT = '03' );
}
```

```abap
@EndUserText.label: 'Access control for Booking'
@MappingRole: true
define role ZC_BOOKINGTP {
  grant select on ZC_BookingTP
    where inheriting conditions from entity ZC_TravelTP;
}
```

A user with no `ZTRAVEL_AUTH` values gets an empty list — correctly, and without any ABAP running.

### Step 2 — BDEF declarations

```abap
define behavior for ZR_TravelTP alias Travel
persistent table ztravel
draft table ztravel_d
lock master
total etag LastChangedAt
authorization master ( global, instance )
etag master LocalLastChangedAt
{
  create ( authorization : global );
  update ( authorization : instance, features : instance );
  delete ( authorization : instance, features : instance );

  association _Booking { create ( authorization : instance ); with draft; }

  action ( authorization : instance, features : instance ) acceptTravel result [1] $self;
  action ( authorization : instance, features : instance ) rejectTravel result [1] $self;

  field ( features : instance ) BeginDate, EndDate, BookingFee;
  ...
}

define behavior for ZR_BookingTP alias Booking
...
authorization dependent by _Travel
{ ... }
```

Note `create ( authorization : global )` — creating an instance that does not exist yet cannot be
instance-dependent.

### Step 3 — global authorization: may this user create at all?

```abap
METHOD get_global_authorizations.

  IF requested_authorizations-%create = if_abap_behv=>mk-on.
    AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH'
      ID 'AGENCY_ID' DUMMY
      ID 'ACTVT'     FIELD '01'.
    IF sy-subrc = 0.
      result-%create = if_abap_behv=>auth-allowed.
    ELSE.
      result-%create = if_abap_behv=>auth-unauthorized.
      APPEND VALUE #( %msg = new_message( id       = 'ZTRAVEL_MSG'
                                          number   = '050'   " 'Not authorized to create travels'
                                          severity = if_abap_behv_message=>severity-error ) )
             TO reported-%other.
    ENDIF.
  ENDIF.

ENDMETHOD.
```

`DUMMY` on `AGENCY_ID` means "any value" — at create time no agency is known yet, so the check is
"may this user create for *some* agency". The agency-specific check happens on the subsequent update.

> The `IF requested_authorizations-%... = mk-on` guard matters: the framework asks about only what
> it needs, and evaluating everything on every call wastes `AUTHORITY-CHECK` round trips.

### Step 4 — instance authorization: may this user touch *this* travel?

```abap
METHOD get_instance_authorizations.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( AgencyId OverallStatus )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels)
    FAILED DATA(read_failed).

  " --- one AUTHORITY-CHECK per DISTINCT agency, not per row ---------------
  DATA(agencies) = travels.
  SORT agencies BY AgencyId.
  DELETE ADJACENT DUPLICATES FROM agencies COMPARING AgencyId.

  DATA: may_change TYPE HASHED TABLE OF /dmo/agency_id WITH UNIQUE KEY table_line,
        may_delete TYPE HASHED TABLE OF /dmo/agency_id WITH UNIQUE KEY table_line,
        may_accept TYPE HASHED TABLE OF /dmo/agency_id WITH UNIQUE KEY table_line.

  LOOP AT agencies INTO DATA(agency).

    IF requested_authorizations-%update              = if_abap_behv=>mk-on
    OR requested_authorizations-%assoc-_Booking      = if_abap_behv=>mk-on.
      AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH'
        ID 'AGENCY_ID' FIELD agency-AgencyId
        ID 'ACTVT'     FIELD '02'.
      IF sy-subrc = 0. INSERT agency-AgencyId INTO TABLE may_change. ENDIF.
    ENDIF.

    IF requested_authorizations-%delete = if_abap_behv=>mk-on.
      AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH'
        ID 'AGENCY_ID' FIELD agency-AgencyId
        ID 'ACTVT'     FIELD '06'.
      IF sy-subrc = 0. INSERT agency-AgencyId INTO TABLE may_delete. ENDIF.
    ENDIF.

    IF requested_authorizations-%action-acceptTravel = if_abap_behv=>mk-on
    OR requested_authorizations-%action-rejectTravel = if_abap_behv=>mk-on.
      AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH'
        ID 'AGENCY_ID' FIELD agency-AgencyId
        ID 'ACTVT'     FIELD '43'.
      IF sy-subrc = 0. INSERT agency-AgencyId INTO TABLE may_accept. ENDIF.
    ENDIF.

  ENDLOOP.

  " --- map the results onto the instances ---------------------------------
  LOOP AT travels INTO DATA(travel).

    DATA(chg) = COND #( WHEN line_exists( may_change[ table_line = travel-AgencyId ] )
                        THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(del) = COND #( WHEN line_exists( may_delete[ table_line = travel-AgencyId ] )
                        THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(acc) = COND #( WHEN line_exists( may_accept[ table_line = travel-AgencyId ] )
                        THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).

    APPEND VALUE #( %tky                 = travel-%tky
                    %update              = chg
                    %delete              = del
                    %assoc-_Booking      = chg
                    %action-acceptTravel = acc
                    %action-rejectTravel = acc ) TO result.

    " optional: explain the refusal, so the user is not left guessing
    IF chg = if_abap_behv=>auth-unauthorized.
      APPEND VALUE #( %tky = travel-%tky
                      %msg = new_message( id       = 'ZTRAVEL_MSG'
                                          number   = '051'  " 'Not authorized for agency &1'
                                          severity = if_abap_behv_message=>severity-error
                                          v1       = travel-AgencyId ) ) TO reported-travel.
    ENDIF.

  ENDLOOP.

ENDMETHOD.
```

### Step 5 — feature control: business state, not permission

```abap
METHOD get_instance_features.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( OverallStatus )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  result = VALUE #(
    FOR travel IN travels
    LET is_rejected = xsdbool( travel-OverallStatus = zbp_r_traveltp=>c_status-rejected )
        is_open     = xsdbool( travel-OverallStatus = zbp_r_traveltp=>c_status-open )
    IN
    ( %tky = travel-%tky

      " a rejected travel is frozen - nothing to do with permissions
      %update              = COND #( WHEN is_rejected = abap_true
                                     THEN if_abap_behv=>fc-o-disabled
                                     ELSE if_abap_behv=>fc-o-enabled )
      %delete              = COND #( WHEN is_open = abap_true
                                     THEN if_abap_behv=>fc-o-enabled
                                     ELSE if_abap_behv=>fc-o-disabled )

      " an accepted travel cannot be accepted again
      %action-acceptTravel = COND #( WHEN travel-OverallStatus = zbp_r_traveltp=>c_status-accepted
                                     THEN if_abap_behv=>fc-o-disabled
                                     ELSE if_abap_behv=>fc-o-enabled )
      %action-rejectTravel = COND #( WHEN is_rejected = abap_true
                                     THEN if_abap_behv=>fc-o-disabled
                                     ELSE if_abap_behv=>fc-o-enabled )

      " dates freeze once the travel leaves 'open'
      %field-BeginDate     = COND #( WHEN is_open = abap_true
                                     THEN if_abap_behv=>fc-f-unrestricted
                                     ELSE if_abap_behv=>fc-f-read_only )
      %field-EndDate       = COND #( WHEN is_open = abap_true
                                     THEN if_abap_behv=>fc-f-unrestricted
                                     ELSE if_abap_behv=>fc-f-read_only )
    ) ).

ENDMETHOD.
```

Note that "nobody may change a **rejected** travel" is implemented **here**, not in authorization —
it is a state rule that applies to everyone, including supervisors. Authorization answers *"may
you?"*; feature control answers *"does it apply right now?"*.

### Step 6 — rejecting with `failed` and `reported`

The authorization and feature handlers return a `result`; the framework turns an
`auth-unauthorized` into a rejection for you. Where **you** must reject explicitly — in an action,
a precheck or a validation — fill both response parameters and set a cause:

```abap
METHOD acceptTravel.

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel
      FIELDS ( AgencyId OverallStatus )
      WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

  DATA update_lines TYPE TABLE FOR UPDATE zr_traveltp.

  LOOP AT travels INTO DATA(travel).

    " defence in depth: feature control is a UI hint, an API caller can still get here
    IF travel-OverallStatus = zbp_r_traveltp=>c_status-rejected.
      APPEND VALUE #( %tky        = travel-%tky
                      %fail-cause = if_abap_behv=>cause-disabled ) TO failed-travel.
      APPEND VALUE #( %tky = travel-%tky
                      %msg = new_message( id       = 'ZTRAVEL_MSG'
                                          number   = '052'   " 'Rejected travel cannot be accepted'
                                          severity = if_abap_behv_message=>severity-error ) )
             TO reported-travel.
      CONTINUE.
    ENDIF.

    AUTHORITY-CHECK OBJECT 'ZTRAVEL_AUTH'
      ID 'AGENCY_ID' FIELD travel-AgencyId
      ID 'ACTVT'     FIELD '43'.
    IF sy-subrc <> 0.
      APPEND VALUE #( %tky        = travel-%tky
                      %fail-cause = if_abap_behv=>cause-unauthorized ) TO failed-travel.
      APPEND VALUE #( %tky = travel-%tky
                      %msg = new_message( id       = 'ZTRAVEL_MSG'
                                          number   = '053'
                                          severity = if_abap_behv_message=>severity-error
                                          v1       = travel-AgencyId ) ) TO reported-travel.
      CONTINUE.
    ENDIF.

    APPEND VALUE #( %tky          = travel-%tky
                    OverallStatus = zbp_r_traveltp=>c_status-accepted ) TO update_lines.
  ENDLOOP.

  CHECK update_lines IS NOT INITIAL.

  MODIFY ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel UPDATE FIELDS ( OverallStatus ) WITH update_lines
    REPORTED DATA(mod_reported).
  reported = CORRESPONDING #( DEEP mod_reported ).

  READ ENTITIES OF zr_traveltp IN LOCAL MODE
    ENTITY Travel ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travels_after).
  result = VALUE #( FOR t IN travels_after ( %tky = t-%tky %param = t ) ).

ENDMETHOD.
```

Re-checking the authorization inside the action is **defence in depth**. `( authorization : instance )`
in the BDEF already makes the framework call `get_instance_authorizations`, so in normal operation
this branch never fires — but it costs little and it documents the rule at the point of use.

### What each user actually experiences

| User | List | Create | Change own agency | Delete | Accept | Change a rejected travel |
|---|---|---|---|---|---|---|
| No `ZTRAVEL_AUTH` | **empty** (DCL) | refused (global auth) | — | — | — | — |
| Clerk, agency 070001 | only 070001 rows (DCL) | allowed | allowed (instance auth) | button disabled (instance auth) | button disabled (instance auth) | disabled (feature control) |
| Clerk, viewing 070002 | not visible (DCL) | — | — | — | — | — |
| Supervisor, agency 070001 | only 070001 rows (DCL) | allowed | allowed | allowed | allowed | **disabled** (feature control applies to everyone) |

### DCL versus behavior authorization, in one sentence each

- **DCL** decided that the clerk's list contains only agency 070001 — a `WHERE` clause on every read.
- **Behavior authorization** decided that the clerk may change but not delete those rows — checked
  when a modification is attempted, whatever the client.
- **Feature control** decided that nobody edits a rejected travel — a state rule, and only a UI hint.

A user who can see nothing through DCL could still, in principle, `PATCH` an instance whose key they
guessed. Only the behavior authorization stops them. That is why you need both.

---

## 14.10 Troubleshooting

| Symptom | Cause |
|---|---|
| User sees no data at all | DCL filters everything; check the PFCG values and `@MappingRole: true` |
| User sees data but cannot edit anything | Global or instance authorization returns `unauthorized`; or feature control marks everything read-only |
| Button greyed out for everyone | `get_instance_features` does not set `%action-X`, so it defaults to disabled |
| Button enabled for everyone despite the status | `( features : instance )` missing in the BDEF |
| Button enablement does not refresh after a change | `field X affects permissions;` missing in `side effects` |
| Feature control works in the UI but EML bypasses it | Correct — `IN LOCAL MODE` deliberately skips feature control and authorization |
| Authorization check runs far too often | Not guarding with `IF requested_authorizations-%... = mk-on` |
| DCL has no effect | `@AccessControl.authorizationCheck` is `#NOT_REQUIRED` on the projection |
| Child rows visible although the parent is not | Child DCL missing; use `inheriting conditions from entity` |

---

## 14.11 Checklist

- [ ] DCL exists on the **projection** with `#CHECK`; child inherits with `inheriting conditions from entity`.
- [ ] `authorization master ( global, instance )` on the root; `dependent by` on children.
- [ ] `get_global_authorizations` and `get_instance_authorizations` guard on `requested_authorizations`.
- [ ] Authorization returns `auth-allowed` / `auth-unauthorized`, never the `fc-` constants.
- [ ] Feature control uses `fc-o-` for operations and `fc-f-` for fields.
- [ ] `side effects ... affects permissions` declared where state drives enablement.
- [ ] No security rule is implemented **only** as feature control.
- [ ] `AUTHORITY-CHECK` is not called once per row in mass scenarios.

---

## 14.12 Interview answer

> **"How do you handle authorization in RAP?"**
>
> Four mechanisms, and the point is that they are not interchangeable.
>
> **DCL** — CDS access control — filters **reads**. A role with `aspect pfcg_auth(...)` becomes a
> `WHERE` clause on every select. It does not stop an update or a delete.
>
> **Global authorization**, `FOR GLOBAL AUTHORIZATION`, answers "may this user create at all" —
> instance-independent.
>
> **Instance authorization**, `FOR INSTANCE AUTHORIZATION`, answers "may this user change *this*
> instance" — typically an `AUTHORITY-CHECK` on a field of the row, returning `auth-allowed` or
> `auth-unauthorized` per operation, action and association.
>
> **Feature control** is different in kind: it answers "does this apply right now" — an accepted
> document cannot be accepted again. It uses the `fc-o-` and `fc-f-` constants and it is a **UI hint
> only**. The OData call still reaches the backend and still succeeds, so a security rule must never
> be implemented as feature control.
>
> The combination matters: a user who can see nothing through DCL could still `PATCH` an instance
> whose key they guessed, unless behavior authorization stops them. You need both.
>
> On performance — instance authorization runs for every row the list displays, so I do one
> `AUTHORITY-CHECK` per distinct authorization value and then a hashed lookup, and guard on
> `requested_authorizations` so only what the framework asked about is evaluated.

## 14.13 Production considerations

- **Test with real PFCG roles, never as a developer.** Authorization defects are the single most
  common "it worked in DEV" failure, and a developer with wide authorizations will never see them.
- **One test user per role in QA**, with a documented expected-result matrix (§14.9).
- **DCL depends on the role existing and being assigned in that system.** A DCL that filters
  everything in QA is almost always a missing role assignment, not a code defect.
- **Roles are usually a separate transport** and often a separate team. Plan the hand-off.
- **Do not use `PRIVILEGED` casually.** Where a job needs it, document why, and prefer
  `GET PERMISSIONS` to filter what the job may touch.
- **Authorization is a hot path.** Set-based `AUTHORITY-CHECK` and `requested_...` guards are
  performance requirements, not style.
- **Write down the DCL layer decision** (§14.2) — it is hard to reverse once several services depend
  on the model.

---

[< Actions & Buttons](13-Actions-Functions-and-Buttons.md) | [Index](00-README.md) | [Next: Unmanaged Scenario >](15-Unmanaged-Scenario.md)
