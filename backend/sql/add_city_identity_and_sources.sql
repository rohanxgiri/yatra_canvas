-- Migration: enforce canonical city identity and preserve provider provenance.
-- Duplicate city rows are consolidated by normalized name, state, and country.
-- All known foreign keys are reassigned before duplicate rows are removed.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

CREATE TABLE IF NOT EXISTS public.city_sources (
    id UUID PRIMARY KEY,
    city_id UUID NOT NULL REFERENCES public.cities(id) ON DELETE CASCADE,
    source VARCHAR(50) NOT NULL,
    external_city_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_city_sources_source_external_city
        UNIQUE (source, external_city_id)
);

CREATE INDEX IF NOT EXISTS ix_city_sources_city_id
    ON public.city_sources (city_id);
CREATE INDEX IF NOT EXISTS ix_city_sources_source
    ON public.city_sources (source);
CREATE INDEX IF NOT EXISTS ix_city_sources_external_city_id
    ON public.city_sources (external_city_id);

-- The historical column has held more than one provider namespace. Preserve
-- every value under an explicit legacy namespace instead of guessing its
-- original provider.
INSERT INTO public.city_sources (
    id,
    city_id,
    source,
    external_city_id,
    created_at,
    last_seen_at
)
SELECT
    gen_random_uuid(),
    c.id,
    'legacy_city_id',
    c.google_place_id,
    COALESCE(c.created_at, NOW()),
    NOW()
FROM public.cities AS c
WHERE c.google_place_id IS NOT NULL
ON CONFLICT (source, external_city_id) DO NOTHING;

CREATE TEMP TABLE city_identity_map ON COMMIT DROP AS
SELECT
    id AS city_id,
    FIRST_VALUE(id) OVER (
        PARTITION BY
            lower(trim(name)),
            lower(COALESCE(trim(state), '')),
            lower(trim(country))
        ORDER BY created_at NULLS LAST, id
    ) AS canonical_city_id
FROM public.cities;

UPDATE public.places AS row
SET city_id = mapping.canonical_city_id
FROM city_identity_map AS mapping
WHERE row.city_id = mapping.city_id
  AND mapping.city_id <> mapping.canonical_city_id;

UPDATE public.trips AS row
SET city_id = mapping.canonical_city_id
FROM city_identity_map AS mapping
WHERE row.city_id = mapping.city_id
  AND mapping.city_id <> mapping.canonical_city_id;

UPDATE public.place_import_reviews AS row
SET city_id = mapping.canonical_city_id
FROM city_identity_map AS mapping
WHERE row.city_id = mapping.city_id
  AND mapping.city_id <> mapping.canonical_city_id;

UPDATE public.city_sources AS row
SET city_id = mapping.canonical_city_id,
    last_seen_at = NOW()
FROM city_identity_map AS mapping
WHERE row.city_id = mapping.city_id
  AND mapping.city_id <> mapping.canonical_city_id;

-- Keep the newest successful cache record for each merged identity/category.
CREATE TEMP TABLE city_cache_winners ON COMMIT DROP AS
SELECT DISTINCT ON (mapping.canonical_city_id, cache.category)
    cache.id,
    mapping.canonical_city_id
FROM public.city_category_cache AS cache
JOIN city_identity_map AS mapping ON mapping.city_id = cache.city_id
ORDER BY
    mapping.canonical_city_id,
    cache.category,
    cache.last_fetched_at DESC,
    cache.id;

DELETE FROM public.city_category_cache AS cache
USING city_identity_map AS mapping
WHERE cache.city_id = mapping.city_id
  AND NOT EXISTS (
      SELECT 1 FROM city_cache_winners AS winner WHERE winner.id = cache.id
  );

UPDATE public.city_category_cache AS cache
SET city_id = winner.canonical_city_id
FROM city_cache_winners AS winner
WHERE cache.id = winner.id
  AND cache.city_id <> winner.canonical_city_id;

-- Preserve one durable refresh lease/outcome per merged identity/category.
CREATE TEMP TABLE city_job_winners ON COMMIT DROP AS
SELECT DISTINCT ON (mapping.canonical_city_id, job.versioned_category)
    job.id,
    mapping.canonical_city_id
FROM public.place_refresh_jobs AS job
JOIN city_identity_map AS mapping ON mapping.city_id = job.city_id
ORDER BY
    mapping.canonical_city_id,
    job.versioned_category,
    CASE job.state
        WHEN 'running' THEN 0
        WHEN 'queued' THEN 1
        WHEN 'completed' THEN 2
        ELSE 3
    END,
    job.updated_at DESC,
    job.id;

DELETE FROM public.place_refresh_jobs AS job
USING city_identity_map AS mapping
WHERE job.city_id = mapping.city_id
  AND NOT EXISTS (
      SELECT 1 FROM city_job_winners AS winner WHERE winner.id = job.id
  );

UPDATE public.place_refresh_jobs AS job
SET city_id = winner.canonical_city_id
FROM city_job_winners AS winner
WHERE job.id = winner.id
  AND job.city_id <> winner.canonical_city_id;

DELETE FROM public.cities AS city
USING city_identity_map AS mapping
WHERE city.id = mapping.city_id
  AND mapping.city_id <> mapping.canonical_city_id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_cities_normalized_identity
    ON public.cities (
        lower(trim(name)),
        lower(COALESCE(trim(state), '')),
        lower(trim(country))
    );

COMMIT;
