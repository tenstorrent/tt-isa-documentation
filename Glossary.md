# Glossary of Behavioral and Pseudocode Terminology

This glossary defines normative behavioral terms used throughout this specification. Each term
defines a specific class of hardware behavior and may appear in English text (e.g. "results in
UndefinedBehavior") or in pseudocode form.

## NonContractualBehavior

Behavior that functions on current hardware but is **not part of the architectural contract**.
Hardware **must validate** its implementation against this specification, yet may alter it in a
future revision or tape-out with *no predefined architectural mechanism* for software to detect
such a change. Software must not rely on such behavior for correctness or compatibility.

Example:
```c
if (register offset is invalid) {
    NonContractualBehavior {
        return 0xFFFFFFFF; // value or behavior could change in future silicon
    }
}
```

**Architectural note:** NonContractualBehavior provides a contained and verifiable response to
otherwise invalid inputs and is the preferred mechanism for replacing UndefinedBehavior and
UnpredictableValue cases in future revisions.

## UndefinedBehavior

Behavior for which the specification provides no guarantees of any kind. Once triggered, the
system may produce arbitrary results, including incorrect operation, nonlocal data corruption,
loss of forward progress, indefinite hangs, or even physical damage to the device or surrounding
system. Implementations should attempt to prevent physical damage and minimize nonlocal effects,
but software must assume no protection or containment.

Example:
```c
if (voltage > MAX_VOLTAGE) {
    UndefinedBehavior(); // up to and including possible physical damage
}
```

**Architectural note:** Occurrences of UndefinedBehavior indicate a failure of architectural
definition or verification and should be eliminated or narrowed in future revisions wherever
possible.

**Note on redefinition:** Redefining a case from UndefinedBehavior to defined behavior — whether
to UnpredictableValue, NonContractualBehavior, or a fully defined value — is a one-way,
contract-binding change. It requires positive evidence: characterization of the input space,
an architectural rationale for the proposed new contract, and an explicit verification commitment.
The absence of observed failures in specific test workloads (e.g., "works on silicon under
the cases we have run") is not equivalent to defined behavior. Silicon executes some behavior
on every input, including UB inputs; that behavior may vary across format combinations, silicon
revisions, surrounding instruction sequences, customer workloads, and test environments not
covered by existing tests. Programs that exercise UB inputs are nonconforming with respect to
this specification, and the specification's silence on those inputs is intentional rather than
an oversight to be corrected.

## UnpredictableValue

A value whose bit pattern is architecturally unpredictable and may vary arbitrarily, including
randomly, between executions, cores, or revisions. Software must treat it as unconstrained data and
contain its effects to prevent propagation into architecturally visible state. This term concerns
value nondeterminism only and excludes hangs or physical damage.

Example:
```c
if (unsupported mode of operation) {
    return UnpredictableValue(); // software must never depend on the value returned
}
```

**Architectural note:** UnpredictableValue represents residual architectural uncertainty and
should be minimized in future revisions by converting such cases into defined, verifiable behavior.

## UnsupportedFunctionality

A feature, mode, or behavior that the architecture describes for completeness but does **not**
commit to supporting. Software should not rely on the documented behavior of an
`UnsupportedFunctionality` feature for correctness, performance, or compatibility: future silicon
revisions may change, remove, or invalidate it without notice; validation against current silicon
may be limited or absent; and the documented description itself may be incomplete, imprecise, or
missing entirely.

`UnsupportedFunctionality` differs from `UndefinedBehavior`, `NonContractualBehavior`, and
`UnpredictableValue` in being explicitly fuzzy and probabilistic. Those terms are sharp categorical
claims about behavior; this one captures the architecture's lack of confidence or commitment in
something which may appear to empirically work on silicon.

Example:
```c
if (feature that is incompletely validated) {
    UnsupportedFunctionality();
    // best known model/description of the feature may optionally follow
}
```

**Architectural note:** UnsupportedFunctionality captures a forward-looking architectural stance,
not a claim about present-state correctness. The category is probabilistic at its core: for
features unexercised by real workloads, the Bayesian estimate that further investigation would
uncover incorrect behavior, undefined cases, or non-contractual divergence is high, and the
architecture does not commit to defining those cases retroactively merely because the feature has
not yet been observed to fail. Promotion of a feature from UnsupportedFunctionality to a
supported status is a one-way, contract-binding change subject to the same evidence requirements
articulated for UndefinedBehavior above.
