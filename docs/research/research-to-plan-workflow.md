# Research → plan → approval → implementation

## Operational rule

Before planning or making substantive documentation changes that depend on external facts, use Perplexity research when available. Prefer official sources. Record sources and distinguish verified facts from assumptions. Do not modify implementation code until the plan has been reviewed and explicitly approved.

## Research provider order

1. Prefer the Perplexity MCP server when available to the coding agent (`perplexity_research` / related tools).
2. If MCP is unavailable but the `pplx` CLI is installed and authenticated, use it.
3. Otherwise use the project's documented fallback research process and label the output:

`Research provider: Perplexity unavailable — fallback process used.`

## Plan location

Store plans in the repository's established location. If there is no convention, use:

`docs/plans/YYYY-MM-DD-<short-name>.md`

## Required plan sections (non-trivial work)

1. Goal and non-goals
2. Repository findings (exact file paths and relevant symbols)
3. External research findings with source URLs
4. Proposed design and alternatives considered
5. Ordered implementation steps with affected files
6. API / schema / configuration implications
7. Test strategy and acceptance criteria
8. Security, privacy, operational, rollout, and rollback considerations
9. Assumptions, risks, and open questions
10. Explicit approval gate before code changes

## Output hygiene

Distinguish in the plan:

- verified facts
- repository-specific observations
- assumptions
- recommendations
- unresolved questions

Minimize what is sent to external research: ask the needed question; do not transmit secrets, `.env` content, private configuration, customer data, credentials, internal-only URLs, or unnecessary proprietary source.
