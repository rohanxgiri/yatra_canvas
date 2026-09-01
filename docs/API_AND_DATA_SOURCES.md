# APIs and data sources

Last reviewed: 2026-09-01

Last verified: 2026-09-01 for Geoapify autocomplete and OpenStreetMap/Overpass;
2026-08-31 for other provider rows

Provider behavior, pricing, quotas, schemas, and policies are volatile. The facts below were
checked against the linked official pages on the stated date; re-check them before launch or a
provider change. `[PLANNED]` entries are not configured or callable in this repository.

## Operational matrix

| Provider | Purpose | Current status | Runtime/batch | Owner | Key required | Classification |
| --- | --- | --- | --- | --- | --- | --- |
| PostgreSQL / Supabase | Canonical app data; target auth | `[IMPLEMENTED]` PostgreSQL connection; `[PLANNED]` Supabase Auth/client | Runtime | Backend/database | `DATABASE_URL`; no Supabase API key is used | PostgreSQL open source; hosted Supabase is freemium/paid |
| FSQ Open Source Places | Open POI candidate ingestion | `[IMPLEMENTED]` local CSV/JSONL importer | Operator export + batch import | Backend CLI | No importer key; current Places Portal access uses an operator token outside app config | Free/open dataset |
| Geoapify | Destination city and arrival/address/transport-location autocomplete | `[IMPLEMENTED]` | Runtime | Backend | `GEOAPIFY_API_KEY` | Freemium |
| OpenStreetMap / Overpass | Bounded POI discovery for recommendations | `[IMPLEMENTED]` with a public-instance availability caveat | Runtime cache refresh | Backend | No key for the configured public endpoint | Open data/public service; commercial/self-hosted options vary |
| Wikimedia / Wikipedia / Wikidata | Descriptions, notable context, licensed images | `[PLANNED]` | Batch enrichment | Backend ingestion | No key for intended public read API; identify the application | Open-access API; content license varies by item |
| openrouteservice | Target directions and route matrices | `[PLANNED]` | Runtime | Backend | Hosted API key; self-host configuration differs | Freemium hosted / open-source self-host option |
| Open-Meteo | Forecasts | `[PLANNED]` | Runtime via backend | Backend | Free non-commercial endpoint: no key; commercial customer endpoint: key | Freemium; commercial plan decision required |
| Frankfurter | Exchange rates | `[PLANNED]` | Runtime via backend | Backend | Public API: no key | Free/open-source public API |
| Google Places API (New) | Legacy city autocomplete/details and legacy POI discovery endpoint | `[DEPRECATED]` for normal flows; adapter retained | Runtime | Backend | `GOOGLE_PLACES_API_KEY` only for legacy endpoints | Commercial, billed/quota-controlled |
| Local coordinate estimator | Approximate route-order distance and time matrices | `[IMPLEMENTED]` for the normal optimizer | Runtime | Backend | None | Application-owned calculation |
| Google Routes API | Legacy route-matrix adapter | `[DEPRECATED]` for normal flows; adapter retained | Not used by the normal endpoint | Backend | `GOOGLE_ROUTES_API_KEY` only for legacy adapter use | Commercial, billed/quota-controlled |
| Google Maps SDK | Interactive map rendering | `[PLANNED]` decision; **not installed** | None | None | None in current repo | Not applicable currently |
| Proprietary Foursquare Places API | No approved responsibility | `[DEPRECATED]`/not integrated | None | None | None | Not applicable |

## Data, policy, and fallback matrix

| Provider | Data stored or cached | Cache/expiry | License/attribution | Official documentation | Last verified | Fallback | Known limitations |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PostgreSQL / Supabase | Canonical entities and caches | Application-defined; no general retention job | Application data policy is `[UNKNOWN]`; RLS must be tracked before direct client access | [Supabase docs](https://supabase.com/docs), [database](https://supabase.com/docs/guides/database/overview), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) | 2026-08-31 | Backend cannot start without a valid PostgreSQL URL | Supabase Auth, SDK, migrations, RLS, and production topology are absent |
| FSQ OS Places | Selected fields in `PlaceSource`/`PlaceCategory`; ambiguity in `PlaceImportReview` | `date_refreshed` retained; no automated delta/deletion process | Dataset docs state Apache 2.0; preserve source/license metadata | [Access](https://docs.foursquare.com/data-products/docs/access-fsq-os-places), [schema](https://docs.foursquare.com/data-products/docs/places-os-data-schema) | 2026-08-31 | Skip import; existing canonical places remain | Portal now uses an Iceberg catalog/token; importer only reads operator-exported CSV/JSONL. Open schema does not list proprietary rating/popularity fields |
| Geoapify | Normalized suggestions in process memory; selected destination fields are persisted as a canonical city and selected trip start locations may be persisted | `GEOAPIFY_AUTOCOMPLETE_CACHE_TTL_SECONDS`; cleared on restart | OSM attribution always; Geoapify attribution required on free plan per official terms | [Autocomplete](https://apidocs.geoapify.com/docs/geocoding/address-autocomplete/), [terms](https://www.geoapify.com/terms-and-conditions/) | 2026-09-01 | Stored-city search remains available; device/custom arrival entry and unrelated stored data remain | Destination rows do not yet retain the Geoapify place ID; no persistent/shared autocomplete cache; pricing and quotas are volatile |
| OSM / Overpass | Canonical `Place` rows plus `PlaceSource` element ID/type, URL, and `ODbL-1.0` provenance | City/category TTL cache | OSM data is ODbL and requires attribution; the recommendation UI links the OSM copyright page | [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API), [OSM copyright](https://www.openstreetmap.org/copyright) | 2026-09-01 | Serve the last successfully persisted category data while cache is valid; return a retryable error when an uncached refresh fails | Public instances are best-effort and can be overloaded; production scale still needs reviewed regional extracts or self-hosting |
| Wikimedia | None | `[PLANNED]`; cache by revision/source timestamp | Preserve author, source URL, item license, attribution, and modifications; license varies by content | [Action API](https://www.mediawiki.org/wiki/API:Main_page), [API etiquette](https://www.mediawiki.org/wiki/API:Etiquette) | 2026-08-31 | Omit enrichment and keep canonical place | Meaningful User-Agent/contact and considerate serial/batched requests are required; image reuse cannot assume one universal license |
| openrouteservice | None currently; target route/matrix cache | `[PLANNED]`; define static versus volatile duration TTL before adapter | Routing is based on OSM; final hosted/self-hosted attribution and terms must be re-verified for selected deployment | [API docs](https://openrouteservice.org/dev/#/api-docs), [backend endpoint reference](https://giscience.github.io/openrouteservice/api-reference/endpoints/) | 2026-08-31 | Target: stale complete static cache, otherwise explicit failure | Hosted and self-hosted capabilities/limits differ; deployment model and commercial plan are unresolved |
| Open-Meteo | None | `[PLANNED]`; cache by coordinates, variables, and forecast issue/valid time | Weather data is CC BY 4.0 and requires attribution; free endpoint is non-commercial | [Forecast docs](https://open-meteo.com/en/docs), [pricing](https://open-meteo.com/en/pricing), [terms](https://open-meteo.com/en/terms) | 2026-08-31 | Hide weather or show explicitly stale cached forecast | Commercial YatraCanvas use needs a paid customer-endpoint decision/key or self-host evaluation; forecasts are not guarantees |
| Frankfurter | None | `[PLANNED]`; rates should be date/provider keyed with a daily refresh policy | Public API is open source; underlying provider terms still apply and provider attribution can be requested | [Frankfurter v2](https://frankfurter.dev/) | 2026-08-31 | Hide conversion or show last dated rate with timestamp | Daily reference rates are not payment/settlement quotes; v2 has no amount-conversion endpoint, so the app multiplies a fetched rate |
| Google Places API (New) | Legacy city IDs and legacy Google-sourced POIs/source IDs | Legacy city/category cache remains | Google Maps Platform terms/policies and required attribution apply to retained legacy data | [Overview](https://developers.google.com/maps/documentation/places/web-service/overview), [Autocomplete](https://developers.google.com/maps/documentation/places/web-service/place-autocomplete), [Nearby Search](https://developers.google.com/maps/documentation/places/web-service/nearby-search) | 2026-08-31 | Normal destination uses Geoapify; normal recommendations use OSM/Overpass | Retained legacy endpoints can still fail without a Google key; Flutter does not call them in the normal journey |
| Local coordinate estimator | `RouteMatrixCache` approximate distances/durations under travel mode `local_estimate` | Static complete cache can be reused | No external-provider terms; calculation is labelled approximate in the UI | Repository implementation and tests | 2026-09-01 | Recompute from stored coordinates | Straight-line distance with a road factor and average speed is not turn-by-turn routing or live traffic; optimizer currently emits day 1 only |
| Google Routes API | Legacy Google route-matrix cache rows, where present | Legacy traffic/static expiry behavior remains | Google Maps Platform terms/attribution apply to retained legacy data | [Compute Route Matrix](https://developers.google.com/maps/documentation/routes/compute_route_matrix) | 2026-08-31 | Normal optimizer uses local estimates | Adapter is retained but is not injected into the normal route-optimization endpoint |
| Google Maps SDK | Nothing | None | Would require separate Maps SDK terms, key restrictions, and attribution if adopted | [Google Maps Platform documentation](https://developers.google.com/maps/documentation) | 2026-08-31 | No current map exists | Places/Routes keys do not prove an SDK is configured; map renderer/tiles decision remains open |
| Proprietary Foursquare Places API | Nothing | None | Not assessed because it is not selected | [Foursquare developer docs](https://docs.foursquare.com/) | 2026-08-31 | Use reviewed open-dataset ingestion | Must not be introduced as a required runtime dependency without a new decision and documentation |

## Current Google dependency assessment

- **Places API (New): `[DEPRECATED]` for normal flows.** The backend retains legacy Autocomplete,
  Place Details, and discovery routes. Normal Flutter destinations use Geoapify and normal
  recommendations use OpenStreetMap/Overpass.
- **Routes API: `[DEPRECATED]` for normal flows.** Its adapter is retained, but the normal
  optimizer uses application-owned coordinate estimates and makes no Google request.
- **Places SDK, Maps SDK for Android/iOS/JavaScript, Geocoding API, Directions API, and legacy
  Distance Matrix API: not found.** They can remain disabled for this repository unless another
  deployment outside version control uses them; that external state is `[UNKNOWN]`.

Google Places and Routes keys may be left empty for the normal Flutter journey. Calling the
explicit legacy endpoints still requires their corresponding keys. Removing the retained adapters,
legacy data, or configuration is a separate reversible cleanup. A map SDK decision is independent.

## Introducing a provider

A provider is not adopted by adding a key. The same change must include an application-owned
adapter contract, tests, error/fallback behavior, data provenance, cache/expiry policy,
license/attribution treatment, environment documentation, and an architectural decision. If an
official fact cannot be verified, record `[UNKNOWN]` rather than copying an old example.
