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
