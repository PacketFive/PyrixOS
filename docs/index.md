---
title: Requests for Comments
description: >-
  PyrixOS is designed in the open through numbered RFCs. Each RFC is reviewed
  and accepted before the work it describes begins.
---

# Requests for Comments

<div class="pyrix-meta" markdown>
<span class="pyrix-flag">Design stage</span>
<span>Project <strong>PyrixOS</strong></span>
<span>Process <strong>RFC first</strong></span>
</div>

PyrixOS is designed before it is built. Every component, interface and file format is first proposed in a numbered RFC, discussed in public, and accepted or revised. Implementation of a component starts only once its RFC is accepted, and an accepted RFC is the reference against which that implementation is reviewed and tested.

| RFC | Title | Status | Covers |
| --- | --- | --- | --- |
| [0001](rfc/0001-pyrixos-architecture.md) | PyrixOS Architecture | Draft | PyBonsai language, derivations, build sandbox, immutable store, dependency database, garbage collector, profiles and stacks, binary caches, measurement |

[Read RFC 0001](rfc/0001-pyrixos-architecture.md){ .md-button .md-button--primary }
[Introduction to PyrixOS](introduction.md){ .md-button }

## Status values

| Status | Meaning |
| --- | --- |
| Draft | Open for comment. The design may still change in any part. |
| Accepted | The design is agreed. Implementation may begin, and later changes need a new RFC or an amendment. |
| Implemented | The accepted design has been built and its tests pass. |
| Superseded | Replaced by a later RFC, which is named in the RFC header. |

## Commenting

Comments on an RFC in Draft are made through [issues on the PyrixOS repository](https://github.com/PacketFive/PyrixOS/issues), with the RFC number and section in the title, for example `RFC 0001 §9.2 sandbox /proc mount`. Proposals for a new RFC follow the structure of RFC 0001: summary, motivation, goals and non-goals, specification, security considerations, alternatives and open questions.
