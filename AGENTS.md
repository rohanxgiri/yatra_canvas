# YatraCanvas agent instructions

Before editing, read [Project context](docs/PROJECT_CONTEXT.md),
[Architecture](docs/ARCHITECTURE.md), [APIs and data sources](docs/API_AND_DATA_SOURCES.md),
[Data model](docs/DATA_MODEL.md), [Environment variables](docs/ENVIRONMENT_VARIABLES.md),
[Roadmap](docs/ROADMAP.md), and [Decisions](docs/DECISIONS.md).

Use these labels for architectural claims: `[IMPLEMENTED]`, `[PARTIAL]`, `[PLANNED]`,
`[DEPRECATED]`, and `[UNKNOWN]`. Inspect the actual code, migrations, and tests first. Never
describe planned or partial work as production-ready, or invent provider capabilities,
fields, quotas, schemas, or environment variables. Verify changing provider facts against
official documentation and record the URL and verification date.

Keep secrets out of clients, logs, commits, examples, and documentation. New variables must
be added to `backend/.env.example` and `docs/ENVIRONMENT_VARIABLES.md`. Architecture,
provider, endpoint, database, migration, and deployment changes must update their source-of-
truth document in the same commit. Preserve legacy data with reviewed, reversible migrations;
do not apply migrations to production as part of repository work. Run relevant tests before
declaring completion.

## UI reference screenshots

Wanderlog screenshots in `design_reference/wanderlog/` are visual inspiration for spacing,
hierarchy, rounded cards, large headings, progress and selection controls, bottom CTAs,
navigation, maps, and itineraries. Inspect the relevant images before creating or
significantly redesigning a screen.

Maintain YatraCanvas's own identity. Do not copy Wanderlog branding, logo, exact colors,
marketing content, or screens pixel-for-pixel.
