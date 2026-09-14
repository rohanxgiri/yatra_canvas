# Admin Architecture & Operation Guide

Last updated: 2026-09-14
Status: `[IMPLEMENTED]`

---

## 1. System Overview

YatraCanvas features a role-based administrative system comprising:
1. **Centralized Authentication & Role Authorization** in FastAPI with secure `bcrypt` password hashing and signed JWT bearer tokens.
2. **Role System**: Distinguishes between standard travelers (`USER`) and administrators (`ADMIN`).
3. **Admin API Suite** (`/api/admin/*`): Dedicated namespace guarded by the `require_admin` dependency.
4. **POI Moderation Subsystem**: Centralized moderation statuses (`ACTIVE`, `HIDDEN`, `RESTRICTED`, `DUPLICATE`, `INVALID`) that cleanly exclude restricted/low-quality places from discovery, recommendation scoring, and search without ad-hoc code filtering.
5. **Responsive Web Admin Dashboard**: Information-dense single page application served directly by FastAPI at `/admin` built with HTML5, Vanilla CSS, and reactive Vanilla JS.

```
                         YatraCanvas Backend
                            FastAPI
                               │
                  ┌────────────┴────────────┐
                  │                         │
             Traveler APIs              Admin APIs
             (/trips, /cities, etc.)    (/api/admin/*)
                  │                         │
           Flutter Mobile App         Admin Dashboard
           (Android / iOS / Web)      (FastAPI /admin Web App)
                  │                         │
              Travelers                   Admins
```

---

## 2. Authentication & Authorization Design

### 2.1 Token Flow
1. **Login** (`POST /api/auth/login`):
   - Accepts JSON `{"email": "...", "password": "..."}`.
   - Queries `User` by lowercase email.
   - Verifies hashed credentials using `bcrypt.checkpw()`.
   - Rejects inactive users with HTTP `403 Forbidden` (`User account is deactivated`).
   - Issues a signed JWT access token (`HS256`) carrying `sub` (user UUID), `email`, and `role`.
   - Returns `{ "access_token": "...", "token_type": "bearer", "user": { "id": "...", "name": "...", "email": "...", "role": "..." } }`.
2. **Current Identity** (`GET /api/auth/me`):
   - Reads `Authorization: Bearer <token>` header.
   - Decodes and validates JWT expiration and algorithm.
   - Loads the active user from the database.
3. **Admin Guard** (`require_admin` dependency):
   - Validates that `current_user.role == UserRole.ADMIN.value`.
   - Returns HTTP `401 Unauthorized` for missing/invalid tokens.
   - Returns HTTP `403 Forbidden` (`Administrator access required`) for non-admin accounts.

### 2.2 Security Principles
- **No hardcoded admin emails**: Role authorization inspects `current_user.role`, never matching against string literals like `admin@yatracanvas.com`.
- **Zero plain-text passwords**: Passwords hashed with salted bcrypt rounds.
- **Redaction & Masking**: Secrets, password hashes, and provider API keys are strictly excluded from API responses and settings representations.
- **Self-Deactivation Guard**: Admins cannot deactivate or demote their own active accounts.

---

## 3. Database Schema Changes

Tracked migration scripts:
- Forward: `backend/sql/add_admin_auth_and_moderation.sql`
- Rollback: `backend/sql/rollback_admin_auth_and_moderation.sql`

### 3.1 New Tables
- **`users` (`User`)**:
  - `id`: UUID (Primary Key)
  - `email`: String (Unique, Indexed, lowercase)
  - `name`: String
  - `password_hash`: String (bcrypt hash)
  - `role`: String (`USER` | `ADMIN`, check constraint `ck_users_role`)
  - `is_active`: Boolean (Default `true`)
  - `created_at`: Timestamp UTC
  - `updated_at`: Optional Timestamp UTC
- **`place_reports` (`PlaceReport`)**:
  - `id`: UUID (Primary Key)
  - `place_id`: UUID (Foreign key to `places.id`)
  - `user_id`: Optional UUID (Foreign key to `users.id`)
  - `reason`: String (e.g., `permanently_closed`, `restricted_facility`, `duplicate`, `wrong_category`, `other`)
  - `details`: Optional String
  - `status`: String (`OPEN`, `REVIEWING`, `RESOLVED`, `REJECTED`, check constraint `ck_place_reports_status`)
  - `admin_notes`: Optional String
  - `created_at`: Timestamp UTC
  - `updated_at`: Optional Timestamp UTC

### 3.2 Modified Tables
- **`cities` (`City`)**:
  - Added `is_enabled` (Boolean, default `true`, indexed)
  - Added `is_featured` (Boolean, default `false`, indexed)
  - Added `is_popular` (Boolean, default `false`, indexed)
  - Added `image_url` (Optional String)
  - Added `description` (Optional String)
  - Added `display_order` (Integer, default `0`, indexed)
- **`places` (`Place`)**:
  - Added `moderation_status` (String, default `'ACTIVE'`, indexed, check constraint `ck_places_moderation_status` in `('ACTIVE', 'HIDDEN', 'RESTRICTED', 'DUPLICATE', 'INVALID')`)

---

## 4. Admin API Reference

All routes are prefixed with `/api/admin` and require an `ADMIN` bearer token:

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/admin/dashboard` | Aggregated system metrics: total users, trips, places by moderation status, active destinations, open reports, recent activity logs. |
| `GET` | `/api/admin/users` | Paginated user directory with trip counts, filterable by role and active status. |
| `GET` | `/api/admin/users/{user_id}` | Detailed user profile. |
| `PATCH` | `/api/admin/users/{user_id}` | Update user role or active status (self-deactivation/demotion prevented). |
| `GET` | `/api/admin/destinations` | Destination catalog with operational controls (`is_enabled`, `is_featured`, `is_popular`, `display_order`). |
| `POST` | `/api/admin/destinations` | Create a new destination city. |
| `PATCH` | `/api/admin/destinations/{city_id}` | Update destination metadata and flags. |
| `GET` | `/api/admin/places` | Curated POI directory filterable by city, category, and moderation status (`ACTIVE`, `HIDDEN`, `RESTRICTED`, `DUPLICATE`, `INVALID`). |
| `GET` | `/api/admin/places/{place_id}` | Detailed POI inspection with source provenance and coordinates. |
| `PATCH` | `/api/admin/places/{place_id}` | Moderate POI status and quality attributes. |
| `GET` | `/api/admin/trips` | Read-only itinerary inspector filterable by city and planning status. |
| `GET` | `/api/admin/trips/{trip_id}` | Detailed inspection of trip days, preferences, and stop schedules. |
| `GET` | `/api/admin/reports` | Traveler place reports queue filterable by status (`OPEN`, `REVIEWING`, `RESOLVED`, `REJECTED`). |
| `PATCH` | `/api/admin/reports/{report_id}` | Triage reports and append administrative review notes. |
| `GET` | `/api/admin/provider-status` | Safe diagnostic status of external providers (Overpass, Geoapify, Nominatim, OpenRouteService) with redacted credentials. |

---

## 5. Centralized POI Moderation

To eliminate fragile ad-hoc place filtering, POI moderation is enforced uniformly across the backend:
1. **Candidate Discovery** (`OpenStreetMapDiscoveryService`):
   - Internal queries `_stored_places` and `_stored_places_many` strictly append `where(Place.moderation_status == "ACTIVE")`.
   - Hidden or restricted locations are never pulled as candidate stops.
2. **Recommendation Scoring** (`RecommendationService`):
   - Non-active places are excluded during candidate scoring.
3. **Manual Search** (`GET /cities/{city_id}/places/search`):
   - Only returns places with `moderation_status == 'ACTIVE'`.

---

## 6. Admin Web Dashboard

The web dashboard is located in `backend/app/static/admin/` and served at `/admin`.
- **Information Density**: Clean data tables, tabular pagination, search filters, and status badges.
- **Design Alignment**: Built with YatraCanvas brand colors (Deep Navy/Teal `#0A303A`, Marigold `#E5A93C`, Slate borders `#E2E8F0`).
- **Responsive Layout**: Desktop sidebar navigation collapsing gracefully to compact mobile headers.
- **Security & Session Lifecycle**:
  - Secure token storage in `sessionStorage` (cleared on tab close or manual logout).
  - Interceptors redirect to the login overlay on `401 Unauthorized` or `403 Forbidden`.
  - Browser back-button navigation is blocked from accessing protected cached state.

---

## 7. Operational Instructions

### 7.1 Creating the Initial Admin Account
Run the idempotent CLI creation script:
```bash
cd backend
.venv\Scripts\python -m app.scripts.create_admin --email admin@yatracanvas.com --password "YourStrongPassword123!" --name "YatraCanvas Admin"
```
Or use environment variables:
```bash
set ADMIN_EMAIL=admin@yatracanvas.com
set ADMIN_PASSWORD=YourStrongPassword123!
.venv\Scripts\python -m app.scripts.create_admin
```

### 7.2 Running the Backend Server
```bash
cd backend
.venv\Scripts\python -m uvicorn app.main:app --reload --port 8000
```
Open your browser to:
- Admin Dashboard: `http://localhost:8000/admin`
- Interactive OpenAPI Docs: `http://localhost:8000/docs`

### 7.3 Running Tests
```bash
# Backend unit and integration tests (including admin API suite)
cd backend
.venv\Scripts\python -m pytest

# Flutter client tests
cd ..
flutter test
```
