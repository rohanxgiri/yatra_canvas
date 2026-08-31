# APIs and data sources

Last reviewed: 2026-08-31

Last verified: 2026-08-31 (all provider rows below)

Provider behavior, pricing, quotas, schemas, and policies are volatile. The facts below were
checked against the linked official pages on the stated date; re-check them before launch or a
provider change. `[PLANNED]` entries are not configured or callable in this repository.

## Operational matrix

| Provider | Purpose | Current status | Runtime/batch | Owner | Key required | Classification |
| --- | --- | --- | --- | --- | --- | --- |
| PostgreSQL / Supabase | Canonical app data; target auth | `[IMPLEMENTED]` PostgreSQL connection; `[PLANNED]` Supabase Auth/client | Runtime | Backend/database | `DATABASE_URL`; no Supabase API key is used | PostgreSQL open source; hosted Supabase is freemium/paid |
| FSQ Open Source Places | Open POI candidate ingestion | `[IMPLEMENTED]` local CSV/JSONL importer | Operator export + batch import | Backend CLI | No importer key; current Places Portal access uses an operator token outside app config | Free/open dataset |
| Geoapify | Arrival/address/transport-location autocomplete | `[IMPLEMENTED]` | Runtime | Backend | `GEOAPIFY_API_KEY` | Freemium |
| OpenStreetMap / Overpass | Supplemental open POI/geographic ingestion | `[PLANNED]` | Batch, not per-screen runtime | Backend ingestion | Public instances normally no key; chosen host is undecided | Open data/public service; commercial/self-hosted options vary |
| Wikimedia / Wikipedia / Wikidata | Descriptions, notable context, licensed images | `[PLANNED]` | Batch enrichment | Backend ingestion | No key for intended public read API; identify the application | Open-access API; content license varies by item |
| openrouteservice | Target directions and route matrices | `[PLANNED]` | Runtime | Backend | Hosted API key; self-host configuration differs | Freemium hosted / open-source self-host option |
| Open-Meteo | Forecasts | `[PLANNED]` | Runtime via backend | Backend | Free non-commercial endpoint: no key; commercial customer endpoint: key | Freemium; commercial plan decision required |
| Frankfurter | Exchange rates | `[PLANNED]` | Runtime via backend | Backend | Public API: no key | Free/open-source public API |
| Google Places API (New) | City autocomplete/details/resolve and nearby POI refresh | `[IMPLEMENTED]`, target `[DEPRECATED]` | Runtime | Backend | `GOOGLE_PLACES_API_KEY` | Commercial, billed/quota-controlled |
| Google Routes API | Current route matrices | `[IMPLEMENTED]`, target replacement planned | Runtime | Backend | `GOOGLE_ROUTES_API_KEY` | Commercial, billed/quota-controlled |
| Google Maps SDK | Interactive map rendering | `[PLANNED]` decision; **not installed** | None | None | None in current repo | Not applicable currently |
| Proprietary Foursquare Places API | No approved responsibility | `[DEPRECATED]`/not integrated | None | None | None | Not applicable |

## Data, policy, and fallback matrix

| Provider | Data stored or cached | Cache/expiry | License/attribution | Official documentation | Last verified | Fallback | Known limitations |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PostgreSQL / Supabase | Canonical entities and caches | Application-defined; no general retention job | Application data policy is `[UNKNOWN]`; RLS must be tracked before direct client access | [Supabase docs](https://supabase.com/docs), [database](https://supabase.com/docs/guides/database/overview), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) | 2026-08-31 | Backend cannot start without a valid PostgreSQL URL | Supabase Auth, SDK, migrations, RLS, and production topology are absent |
| FSQ OS Places | Selected fields in `PlaceSource`/`PlaceCategory`; ambiguity in `PlaceImportReview` | `date_refreshed` retained; no automated delta/deletion process | Dataset docs state Apache 2.0; preserve source/license metadata | [Access](https://docs.foursquare.com/data-products/docs/access-fsq-os-places), [schema](https://docs.foursquare.com/data-products/docs/places-os-data-schema) | 2026-08-31 | Skip import; existing canonical places remain | Portal now uses an Iceberg catalog/token; importer only reads operator-exported CSV/JSONL. Open schema does not list proprietary rating/popularity fields |
| Geoapify | Normalized suggestions only in process memory; selected trip start location may be persisted | `GEOAPIFY_AUTOCOMPLETE_CACHE_TTL_SECONDS`; cleared on restart | OSM attribution always; Geoapify attribution required on free plan per official terms | [Autocomplete](https://apidocs.geoapify.com/docs/geocoding/address-autocomplete/), [terms](https://www.geoapify.com/terms-and-conditions/) | 2026-08-31 | Endpoint returns a safe failure; device/custom entry and unrelated stored data remain | One concrete provider-neutral interface exists, but no persistent/shared cache; pricing and quotas are volatile |
| OSM / Overpass | None | `[PLANNED]`; bounded extracts/cache required | OSM data is ODbL and requires attribution; preserve source and update behavior | [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API), [OSM copyright](https://www.openstreetmap.org/copyright) | 2026-08-31 | FSQ/canonical data; never silently switch at request time | Public instances are best-effort and may be overloaded; host, usage policy, and extract strategy are undecided |
| Wikimedia | None | `[PLANNED]`; cache by revision/source timestamp | Preserve author, source URL, item license, attribution, and modifications; license varies by content | [Action API](https://www.mediawiki.org/wiki/API:Main_page), [API etiquette](https://www.mediawiki.org/wiki/API:Etiquette) | 2026-08-31 | Omit enrichment and keep canonical place | Meaningful User-Agent/contact and considerate serial/batched requests are required; image reuse cannot assume one universal license |
| openrouteservice | None currently; target route/matrix cache | `[PLANNED]`; define static versus volatile duration TTL before adapter | Routing is based on OSM; final hosted/self-hosted attribution and terms must be re-verified for selected deployment | [API docs](https://openrouteservice.org/dev/#/api-docs), [backend endpoint reference](https://giscience.github.io/openrouteservice/api-reference/endpoints/) | 2026-08-31 | Target: stale complete static cache, otherwise explicit failure | Hosted and self-hosted capabilities/limits differ; deployment model and commercial plan are unresolved |
| Open-Meteo | None | `[PLANNED]`; cache by coordinates, variables, and forecast issue/valid time | Weather data is CC BY 4.0 and requires attribution; free endpoint is non-commercial | [Forecast docs](https://open-meteo.com/en/docs), [pricing](https://open-meteo.com/en/pricing), [terms](https://open-meteo.com/en/terms) | 2026-08-31 | Hide weather or show explicitly stale cached forecast | Commercial YatraCanvas use needs a paid customer-endpoint decision/key or self-host evaluation; forecasts are not guarantees |
| Frankfurter | None | `[PLANNED]`; rates should be date/provider keyed with a daily refresh policy | Public API is open source; underlying provider terms still apply and provider attribution can be requested | [Frankfurter v2](https://frankfurter.dev/) | 2026-08-31 | Hide conversion or show last dated rate with timestamp | Daily reference rates are not payment/settlement quotes; v2 has no amount-conversion endpoint, so the app multiplies a fetched rate |
| Google Places API (New) | Cities, Google ID, normalized POIs/source IDs, discovery freshness | City/category TTL; canonical/source records persist | Google Maps Platform terms/policies and required attribution apply; retention/backfill policy needs legal review | [Overview](https://developers.google.com/maps/documentation/places/web-service/overview), [Autocomplete](https://developers.google.com/maps/documentation/places/web-service/place-autocomplete), [Nearby Search](https://developers.google.com/maps/documentation/places/web-service/nearby-search) | 2026-08-31 | Stored data where permitted; provider-backed city/refresh operations fail safely | Still required by current city resolution and POI refresh. Do not disable until replacements and compliant backfill are verified |
| Google Routes API | `RouteMatrixCache` distances and durations | Traffic uses `expires_at`; static complete cache can survive provider outage | Google Maps Platform terms/attribution apply; re-check storage rules before production | [Compute Route Matrix](https://developers.google.com/maps/documentation/routes/compute_route_matrix) | 2026-08-31 | Use complete stored static legs; fail if any required pair is missing | Current optimizer emits day 1 only; matrix traffic and billing/element limits are provider-dependent and volatile |
| Google Maps SDK | Nothing | None | Would require separate Maps SDK terms, key restrictions, and attribution if adopted | [Google Maps Platform documentation](https://developers.google.com/maps/documentation) | 2026-08-31 | No current map exists | Places/Routes keys do not prove an SDK is configured; map renderer/tiles decision remains open |
| Proprietary Foursquare Places API | Nothing | None | Not assessed because it is not selected | [Foursquare developer docs](https://docs.foursquare.com/) | 2026-08-31 | Use reviewed open-dataset ingestion | Must not be introduced as a required runtime dependency without a new decision and documentation |

## Current Google dependency assessment

- **Places API (New): `[IMPLEMENTED]`.** The backend calls Autocomplete, Place Details, and
  Nearby Search. It supports city selection/normalization and cache refresh for place discovery.
- **Routes API: `[IMPLEMENTED]`.** The backend calls `computeRouteMatrix` for distance and
  duration legs used by the optimizer.
- **Places SDK, Maps SDK for Android/iOS/JavaScript, Geocoding API, Directions API, and legacy
  Distance Matrix API: not found.** They can remain disabled for this repository unless another
  deployment outside version control uses them; that external state is `[UNKNOWN]`.

Google Places and Routes cannot be disabled yet without breaking their implemented paths. After
Geoapify fully replaces city resolution, open POI ingestion covers discovery, openrouteservice
passes routing parity, and existing data is safely backfilled, the corresponding key can be
removed in a reversible release. A map SDK decision is independent.

## Introducing a provider

A provider is not adopted by adding a key. The same change must include an application-owned
adapter contract, tests, error/fallback behavior, data provenance, cache/expiry policy,
license/attribution treatment, environment documentation, and an architectural decision. If an
official fact cannot be verified, record `[UNKNOWN]` rather than copying an old example.
