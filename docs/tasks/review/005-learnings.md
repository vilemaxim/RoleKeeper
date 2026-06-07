# 🧠 Task Learnings
**Task:** 005
**Role:** CODER

Two architectural pieces of friction surfaced during implementation:

1. CharactersScreen previously took zero constructor params and instantiated services via no-arg constructors at field-initializer time. Every dependency hop through to FirebaseAuth.instance / FirebaseFirestore.instance becomes a wall against widget tests. Splitting into a gated outer widget + injected inner body widget is the established pattern in this repo (see how LarpManagerIntegrationStatusService accepts injected deps). Recommend doing this on day one for any screen that touches LM data — it's much harder to retrofit later.

2. FirebaseAuth.instance was being read in build() to drive the 'Not signed in' empty state. That's a build-phase Firebase call, which throws hard in tests if Firebase isn't initialized. The cleanest mitigation was adding an optional `auth` constructor param that defaults to FirebaseAuth.instance. The streams (watchCharacters etc.) already gracefully return empty when signed out, so the build-phase check is mostly decorative — worth considering removing it entirely in a future cleanup.
