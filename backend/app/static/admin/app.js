/**
 * YatraCanvas Admin Studio - Frontend Controller
 */

(() => {
  const API_BASE = window.location.origin;

  // Application State
  const state = {
    token: sessionStorage.getItem('yc_admin_token') || localStorage.getItem('yc_admin_token') || null,
    user: null,
    currentSection: 'overview',
    destinations: [],
    placesOffset: 0,
    placesLimit: 20,
    tripsOffset: 0,
    tripsLimit: 20,
  };

  // Toast notification helper
  function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    if (!container) return;
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    container.appendChild(toast);
    setTimeout(() => {
      toast.style.opacity = '0';
      setTimeout(() => toast.remove(), 250);
    }, 3500);
  }

  // Generic Authenticated Fetch
  async function apiFetch(endpoint, options = {}) {
    if (!state.token) {
      showLogin();
      throw new Error('Not authenticated');
    }

    const headers = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${state.token}`,
      ...(options.headers || {}),
    };

    try {
      const response = await fetch(`${API_BASE}${endpoint}`, {
        ...options,
        headers,
      });

      if (response.status === 401) {
        showToast('Session expired or unauthorized. Please sign in.', 'danger');
        logout();
        throw new Error('Unauthorized');
      }

      if (response.status === 403) {
        const err = await response.json().catch(() => ({ detail: 'Administrator access required.' }));
        showToast(`Access Denied: ${err.detail || 'Forbidden'}`, 'danger');
        throw new Error(err.detail || 'Forbidden');
      }

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({ detail: response.statusText }));
        throw new Error(errorData.detail || `Request failed with status ${response.status}`);
      }

      return await response.json();
    } catch (err) {
      if (err.message !== 'Unauthorized') {
        console.error(`API Error on ${endpoint}:`, err);
      }
      throw err;
    }
  }

  // View Switching
  function showLogin() {
    document.getElementById('login-view').style.display = 'flex';
    document.getElementById('app-view').style.display = 'none';
  }

  function showApp() {
    document.getElementById('login-view').style.display = 'none';
    document.getElementById('app-view').style.display = 'flex';
    if (state.user) {
      document.getElementById('admin-name').textContent = state.user.name || state.user.email;
      const initials = (state.user.name || state.user.email).substring(0, 2).toUpperCase();
      document.getElementById('admin-avatar').textContent = initials;
      document.getElementById('admin-role-badge').textContent = state.user.role;
    }
    navTo(state.currentSection || 'overview');
  }

  function logout() {
    state.token = null;
    state.user = null;
    sessionStorage.removeItem('yc_admin_token');
    localStorage.removeItem('yc_admin_token');
    showLogin();
  }

  // Navigation Controller
  function navTo(sectionName) {
    state.currentSection = sectionName;

    // Update navigation item active state
    document.querySelectorAll('.sidebar-nav .nav-item').forEach(item => {
      if (item.dataset.section === sectionName) {
        item.classList.add('active');
      } else {
        item.classList.remove('active');
      }
    });

    // Update sections visibility
    document.querySelectorAll('.admin-section').forEach(sec => {
      sec.classList.remove('active');
    });
    const activeSection = document.getElementById(`section-${sectionName}`);
    if (activeSection) {
      activeSection.classList.add('active');
    }

    // Update topbar title
    const titles = {
      overview: 'Dashboard Overview',
      destinations: 'Destination Management',
      places: 'Places & POI Moderation',
      trips: 'Trip Inspector',
      users: 'Travellers & Account Management',
      reports: 'Place Problem Reports',
      providers: 'External Providers & Health',
    };
    document.getElementById('section-title').textContent = titles[sectionName] || 'Admin Studio';

    // Close mobile drawer if open
    document.getElementById('sidebar').classList.remove('open');

    // Trigger section data load
    switch (sectionName) {
      case 'overview':
        loadOverview();
        break;
      case 'destinations':
        loadDestinations();
        break;
      case 'places':
        loadPlaces();
        break;
      case 'trips':
        loadTrips();
        break;
      case 'users':
        loadUsers();
        break;
      case 'reports':
        loadReports();
        break;
      case 'providers':
        loadProviders();
        break;
    }
  }

  window.navTo = navTo;

  // ---------------------------------------------------------------------------
  // 1. Overview Section
  // ---------------------------------------------------------------------------

  async function loadOverview() {
    try {
      const data = await apiFetch('/api/admin/dashboard');

      document.getElementById('metric-users').textContent = (data.total_users || 0).toLocaleString();
      document.getElementById('metric-trips').textContent = (data.total_trips || 0).toLocaleString();
      document.getElementById('metric-places').textContent = (data.total_places || 0).toLocaleString();
      document.getElementById('metric-destinations').textContent = `${data.active_destinations || 0} / ${data.total_destinations || 0}`;
      document.getElementById('metric-reports').textContent = (data.open_reports_count || 0).toLocaleString();

      // Badge on sidebar reports
      const rBadge = document.getElementById('reports-badge');
      if (data.open_reports_count > 0) {
        rBadge.textContent = data.open_reports_count;
        rBadge.style.display = 'inline-block';
      } else {
        rBadge.style.display = 'none';
      }

      // Moderation breakdown pills
      const pillContainer = document.getElementById('moderation-pills');
      pillContainer.innerHTML = '';
      const statuses = ['ACTIVE', 'HIDDEN', 'RESTRICTED', 'DUPLICATE', 'INVALID'];
      statuses.forEach(st => {
        const count = data.places_by_status[st] || 0;
        const div = document.createElement('div');
        div.className = 'moderation-stat-pill';
        div.innerHTML = `
          <div class="count status-text-${st.toLowerCase()}">${count.toLocaleString()}</div>
          <div class="label"><span class="status-pill ${st.toLowerCase()}">${st}</span></div>
        `;
        pillContainer.appendChild(div);
      });

      // Recent Trips
      const tripsBody = document.getElementById('overview-recent-trips');
      if (data.recent_trips && data.recent_trips.length > 0) {
        tripsBody.innerHTML = data.recent_trips.map(t => `
          <tr>
            <td><strong>${escapeHtml(t.trip_name)}</strong></td>
            <td>${escapeHtml(t.city_name)}</td>
            <td>${t.days} days</td>
            <td class="caption-muted">${formatDate(t.created_at)}</td>
          </tr>
        `).join('');
      } else {
        tripsBody.innerHTML = '<tr><td colspan="4" class="text-center caption-muted">No trips recorded yet.</td></tr>';
      }

      // Recent Reports
      const reportsBody = document.getElementById('overview-recent-reports');
      if (data.recent_reports && data.recent_reports.length > 0) {
        reportsBody.innerHTML = data.recent_reports.map(r => `
          <tr>
            <td><strong>${escapeHtml(r.place_name)}</strong><br><span class="caption-muted">${escapeHtml(r.city_name)}</span></td>
            <td>${escapeHtml(r.reason)}</td>
            <td><span class="status-pill ${r.status.toLowerCase()}">${r.status}</span></td>
            <td class="caption-muted">${formatDate(r.created_at)}</td>
          </tr>
        `).join('');
      } else {
        reportsBody.innerHTML = '<tr><td colspan="4" class="text-center caption-muted">No reports submitted.</td></tr>';
      }
    } catch (err) {
      console.error('Failed to load overview:', err);
    }
  }

  // ---------------------------------------------------------------------------
  // 2. Destinations Section
  // ---------------------------------------------------------------------------

  async function loadDestinations() {
    const tableBody = document.getElementById('destinations-table-body');
    tableBody.innerHTML = '<tr><td colspan="9" class="text-center">Loading destinations...</td></tr>';

    const q = document.getElementById('dest-search').value.trim();
    const isEnabled = document.getElementById('dest-filter-enabled').value;
    const isFeatured = document.getElementById('dest-filter-featured').value;
    const isPopular = document.getElementById('dest-filter-popular').value;

    const params = new URLSearchParams();
    if (q) params.set('q', q);
    if (isEnabled) params.set('is_enabled', isEnabled);
    if (isFeatured) params.set('is_featured', isFeatured);
    if (isPopular) params.set('is_popular', isPopular);

    try {
      const destinations = await apiFetch(`/api/admin/destinations?${params.toString()}`);
      state.destinations = destinations;
      populateCityDropdowns(destinations);

      if (!destinations || destinations.length === 0) {
        tableBody.innerHTML = '<tr><td colspan="9" class="text-center caption-muted">No destinations found.</td></tr>';
        return;
      }

      tableBody.innerHTML = destinations.map(d => `
        <tr>
          <td><strong>${escapeHtml(d.name)}</strong></td>
          <td>${escapeHtml(d.state || '')} ${escapeHtml(d.country)}</td>
          <td>${d.display_order}</td>
          <td>${d.places_count}</td>
          <td>${d.trips_count}</td>
          <td>
            <button class="btn btn-sm ${d.is_enabled ? 'btn-primary' : 'btn-outline'}"
                    onclick="window.toggleDestinationFlag('${d.id}', 'is_enabled', ${!d.is_enabled})">
              ${d.is_enabled ? 'Active' : 'Disabled'}
            </button>
          </td>
          <td>
            <button class="btn btn-sm ${d.is_featured ? 'btn-primary' : 'btn-outline'}"
                    onclick="window.toggleDestinationFlag('${d.id}', 'is_featured', ${!d.is_featured})">
              ${d.is_featured ? '★ Yes' : 'No'}
            </button>
          </td>
          <td>
            <button class="btn btn-sm ${d.is_popular ? 'btn-primary' : 'btn-outline'}"
                    onclick="window.toggleDestinationFlag('${d.id}', 'is_popular', ${!d.is_popular})">
              ${d.is_popular ? '🔥 Yes' : 'No'}
            </button>
          </td>
          <td>
            <button class="btn btn-outline btn-sm" onclick="window.editDestination('${d.id}')">Edit</button>
          </td>
        </tr>
      `).join('');
    } catch (err) {
      tableBody.innerHTML = `<tr><td colspan="9" class="text-center text-danger">Error: ${escapeHtml(err.message)}</td></tr>`;
    }
  }

  window.toggleDestinationFlag = async function(id, flag, value) {
    try {
      await apiFetch(`/api/admin/destinations/${id}`, {
        method: 'PATCH',
        body: JSON.stringify({ [flag]: value }),
      });
      showToast('Destination updated', 'success');
      loadDestinations();
    } catch (err) {
      showToast(`Update failed: ${err.message}`, 'danger');
    }
  };

  window.editDestination = function(id) {
    const dest = state.destinations.find(d => d.id === id);
    if (!dest) return;
    document.getElementById('modal-dest-title').textContent = 'Edit Destination';
    document.getElementById('dest-form-id').value = dest.id;
    document.getElementById('dest-form-name').value = dest.name;
    document.getElementById('dest-form-state').value = dest.state || '';
    document.getElementById('dest-form-country').value = dest.country || 'India';
    document.getElementById('dest-form-lat').value = dest.latitude;
    document.getElementById('dest-form-lng').value = dest.longitude;
    document.getElementById('dest-form-image').value = dest.image_url || '';
    document.getElementById('dest-form-desc').value = dest.description || '';
    document.getElementById('dest-form-order').value = dest.display_order || 0;
    document.getElementById('dest-form-enabled').checked = dest.is_enabled;
    document.getElementById('dest-form-featured').checked = dest.is_featured;
    document.getElementById('dest-form-popular').checked = dest.is_popular;
    openModal('dest-modal');
  };

  // ---------------------------------------------------------------------------
  // 3. Places & POI Moderation Section
  // ---------------------------------------------------------------------------

  async function loadPlaces() {
    const tableBody = document.getElementById('places-table-body');
    tableBody.innerHTML = '<tr><td colspan="8" class="text-center">Loading places...</td></tr>';

    const cityId = document.getElementById('places-city-select').value;
    const category = document.getElementById('places-category-select').value;
    const status = document.getElementById('places-status-select').value;
    const q = document.getElementById('places-search').value.trim();

    const params = new URLSearchParams({
      offset: state.placesOffset,
      limit: state.placesLimit,
    });
    if (cityId) params.set('city_id', cityId);
    if (category) params.set('category', category);
    if (status) params.set('moderation_status', status);
    if (q) params.set('q', q);

    try {
      const places = await apiFetch(`/api/admin/places?${params.toString()}`);

      document.getElementById('places-page-info').textContent =
        `Showing ${places.length} places (Offset ${state.placesOffset})`;
      document.getElementById('places-prev').disabled = state.placesOffset === 0;
      document.getElementById('places-next').disabled = places.length < state.placesLimit;

      if (!places || places.length === 0) {
        tableBody.innerHTML = '<tr><td colspan="8" class="text-center caption-muted">No places match the selected filters.</td></tr>';
        return;
      }

      tableBody.innerHTML = places.map(p => `
        <tr>
          <td><strong>${escapeHtml(p.name)}</strong></td>
          <td>${escapeHtml(p.city_name || '-')}</td>
          <td><span class="caption-muted">${escapeHtml(p.category)}</span></td>
          <td>${p.rating ? `★ ${p.rating.toFixed(1)} (${p.review_count})` : '-'}</td>
          <td>${p.importance_score != null ? p.importance_score.toFixed(2) : '-'}</td>
          <td><span class="status-pill ${p.moderation_status.toLowerCase()}">${p.moderation_status}</span></td>
          <td>${p.sources_count}</td>
          <td>
            <button class="btn btn-outline btn-sm" onclick="window.inspectPlace('${p.id}')">Moderate</button>
          </td>
        </tr>
      `).join('');
    } catch (err) {
      tableBody.innerHTML = `<tr><td colspan="8" class="text-center text-danger">Error: ${escapeHtml(err.message)}</td></tr>`;
    }
  }

  window.inspectPlace = async function(id) {
    try {
      const place = await apiFetch(`/api/admin/places/${id}`);
      document.getElementById('modal-place-name').textContent = place.name;
      document.getElementById('modal-place-city').textContent = place.city_name || '-';
      document.getElementById('modal-place-category').textContent = place.category;
      document.getElementById('modal-place-coords').textContent = `${place.latitude.toFixed(5)}, ${place.longitude.toFixed(5)}`;
      document.getElementById('modal-place-status-pill').innerHTML =
        `<span class="status-pill ${place.moderation_status.toLowerCase()}">${place.moderation_status}</span>`;

      document.getElementById('modal-place-status-select').value = place.moderation_status;
      document.getElementById('modal-place-popular').checked = place.is_popular;
      document.getElementById('modal-place-heritage').checked = place.is_heritage;
      document.getElementById('modal-place-local').checked = place.is_local_speciality;

      // Sources
      const sourcesDiv = document.getElementById('modal-place-sources');
      if (place.sources && place.sources.length > 0) {
        sourcesDiv.innerHTML = place.sources.map(s => `
          <div style="margin-bottom: 8px;">
            <strong>${escapeHtml(s.source)}</strong> (ID: <code>${escapeHtml(s.external_place_id)}</code>)
            ${s.wikidata_id ? ` · Wikidata: <code>${escapeHtml(s.wikidata_id)}</code>` : ''}
            ${s.address ? `<br>Address: ${escapeHtml(s.address)}` : ''}
          </div>
        `).join('');
      } else {
        sourcesDiv.textContent = 'No external provider records linked.';
      }

      // Opening hours
      const hoursDiv = document.getElementById('modal-place-hours');
      if (place.opening_hours && place.opening_hours.length > 0) {
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        hoursDiv.innerHTML = place.opening_hours.map(h => `
          <div><strong>${days[h.day_of_week]}:</strong> ${h.status} ${h.intervals && h.intervals.length > 0 ? JSON.stringify(h.intervals) : ''}</div>
        `).join('');
      } else {
        hoursDiv.textContent = place.raw_opening_hours ? `Raw: ${place.raw_opening_hours}` : 'Status: UNKNOWN';
      }

      document.getElementById('btn-save-place-moderation').onclick = async () => {
        const newStatus = document.getElementById('modal-place-status-select').value;
        const isPop = document.getElementById('modal-place-popular').checked;
        const isHer = document.getElementById('modal-place-heritage').checked;
        const isLoc = document.getElementById('modal-place-local').checked;

        try {
          await apiFetch(`/api/admin/places/${place.id}`, {
            method: 'PATCH',
            body: JSON.stringify({
              moderation_status: newStatus,
              is_popular: isPop,
              is_heritage: isHer,
              is_local_speciality: isLoc,
            }),
          });
          showToast(`Place updated to ${newStatus}`, 'success');
          closeModal('place-modal');
          loadPlaces();
        } catch (err) {
          showToast(`Moderation failed: ${err.message}`, 'danger');
        }
      };

      openModal('place-modal');
    } catch (err) {
      showToast(`Could not load place details: ${err.message}`, 'danger');
    }
  };

  // ---------------------------------------------------------------------------
  // 4. Trips Inspector Section
  // ---------------------------------------------------------------------------

  async function loadTrips() {
    const tableBody = document.getElementById('trips-table-body');
    tableBody.innerHTML = '<tr><td colspan="8" class="text-center">Loading trips...</td></tr>';

    const cityId = document.getElementById('trips-city-select').value;
    const q = document.getElementById('trips-search').value.trim();

    const params = new URLSearchParams({
      offset: state.tripsOffset,
      limit: state.tripsLimit,
    });
    if (cityId) params.set('city_id', cityId);
    if (q) params.set('q', q);

    try {
      const trips = await apiFetch(`/api/admin/trips?${params.toString()}`);

      document.getElementById('trips-page-info').textContent =
        `Showing ${trips.length} trips (Offset ${state.tripsOffset})`;
      document.getElementById('trips-prev').disabled = state.tripsOffset === 0;
      document.getElementById('trips-next').disabled = trips.length < state.tripsLimit;

      if (!trips || trips.length === 0) {
        tableBody.innerHTML = '<tr><td colspan="8" class="text-center caption-muted">No trips found.</td></tr>';
        return;
      }

      tableBody.innerHTML = trips.map(t => `
        <tr>
          <td><code>${t.id.substring(0, 8)}...</code></td>
          <td><strong>${escapeHtml(t.trip_name)}</strong></td>
          <td>${escapeHtml(t.city_name || '-')}</td>
          <td>${t.days}</td>
          <td>${t.start_date || '-'}</td>
          <td>${t.saved_places_count}</td>
          <td>${t.itinerary_stops_count}</td>
          <td>
            <button class="btn btn-outline btn-sm" onclick="window.inspectTrip('${t.id}')">Inspect</button>
          </td>
        </tr>
      `).join('');
    } catch (err) {
      tableBody.innerHTML = `<tr><td colspan="8" class="text-center text-danger">Error: ${escapeHtml(err.message)}</td></tr>`;
    }
  }

  window.inspectTrip = async function(id) {
    try {
      const trip = await apiFetch(`/api/admin/trips/${id}`);
      document.getElementById('modal-trip-title').textContent = `Inspect Trip: ${trip.trip_name}`;

      let html = `
        <div class="place-meta-grid mb-3">
          <div><strong>Destination:</strong> ${escapeHtml(trip.city_name || '-')}</div>
          <div><strong>Duration:</strong> ${trip.days} Days</div>
          <div><strong>Start Date:</strong> ${trip.start_date || 'Unspecified'}</div>
          <div><strong>Start Point:</strong> ${escapeHtml(trip.start_location_name || trip.arrival_place || 'Not specified')}</div>
        </div>

        <h4 class="mt-3">Trip Preferences</h4>
        <div class="caption-muted mb-3">
          ${trip.preferences && trip.preferences.length > 0
            ? trip.preferences.map(p => `<span class="status-pill active" style="margin-right: 4px;">${escapeHtml(p.preference)} (wt: ${p.weight})</span>`).join(' ')
            : 'No custom preferences.'}
        </div>

        <h4 class="mt-3">Selected Places (${trip.saved_places.length})</h4>
        <div class="table-responsive mb-3">
          <table class="table">
            <thead>
              <tr><th>Place</th><th>Category</th><th>Mode</th><th>Must Visit</th><th>Notes</th></tr>
            </thead>
            <tbody>
              ${trip.saved_places.map(sp => `
                <tr>
                  <td><strong>${escapeHtml(sp.place_name || '-')}</strong></td>
                  <td>${escapeHtml(sp.category || '-')}</td>
                  <td>${sp.assignment_mode}</td>
                  <td>${sp.must_visit ? 'Yes' : 'No'}</td>
                  <td class="caption-muted">${escapeHtml(sp.notes || '-')}</td>
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>

        <h4 class="mt-3">Itinerary Stops (${trip.itinerary.length})</h4>
        <div class="table-responsive">
          <table class="table">
            <thead>
              <tr><th>Day</th><th>Order</th><th>Place</th><th>Arrival</th><th>Departure</th><th>Status</th></tr>
            </thead>
            <tbody>
              ${trip.itinerary.length > 0
                ? trip.itinerary.map(it => `
                  <tr>
                    <td>Day ${it.day_number}</td>
                    <td>#${it.visit_order}</td>
                    <td><strong>${escapeHtml(it.place_name || '-')}</strong></td>
                    <td>${it.planned_arrival_time || '-'}</td>
                    <td>${it.planned_departure_time || '-'}</td>
                    <td><span class="status-pill ${it.status.toLowerCase()}">${it.status}</span></td>
                  </tr>
                `).join('')
                : '<tr><td colspan="6" class="text-center caption-muted">Itinerary not yet calculated or generated.</td></tr>'
              }
            </tbody>
          </table>
        </div>
      `;

      document.getElementById('modal-trip-body').innerHTML = html;
      openModal('trip-modal');
    } catch (err) {
      showToast(`Could not load trip details: ${err.message}`, 'danger');
    }
  };

  // ---------------------------------------------------------------------------
  // 5. Users Section
  // ---------------------------------------------------------------------------

  async function loadUsers() {
    const tableBody = document.getElementById('users-table-body');
    tableBody.innerHTML = '<tr><td colspan="8" class="text-center">Loading users...</td></tr>';

    const q = document.getElementById('users-search').value.trim();
    const role = document.getElementById('users-role-select').value;

    const params = new URLSearchParams();
    if (q) params.set('q', q);
    if (role) params.set('role', role);

    try {
      const users = await apiFetch(`/api/admin/users?${params.toString()}`);

      if (!users || users.length === 0) {
        tableBody.innerHTML = '<tr><td colspan="8" class="text-center caption-muted">No users found.</td></tr>';
        return;
      }

      tableBody.innerHTML = users.map(u => `
        <tr>
          <td><code>${u.id.substring(0, 8)}...</code></td>
          <td><strong>${escapeHtml(u.name)}</strong></td>
          <td>${escapeHtml(u.email)}</td>
          <td><span class="role-badge ${u.role.toLowerCase()}">${u.role}</span></td>
          <td><span class="status-pill ${u.is_active ? 'active' : 'hidden'}">${u.is_active ? 'Active' : 'Inactive'}</span></td>
          <td>${u.trip_count}</td>
          <td class="caption-muted">${formatDate(u.created_at)}</td>
          <td>
            <button class="btn btn-sm ${u.is_active ? 'btn-outline-danger' : 'btn-outline'}"
                    onclick="window.toggleUserActive('${u.id}', ${!u.is_active})">
              ${u.is_active ? 'Deactivate' : 'Activate'}
            </button>
          </td>
        </tr>
      `).join('');
    } catch (err) {
      tableBody.innerHTML = `<tr><td colspan="8" class="text-center text-danger">Error: ${escapeHtml(err.message)}</td></tr>`;
    }
  }

  window.toggleUserActive = async function(id, shouldBeActive) {
    if (state.user && state.user.id === id && !shouldBeActive) {
      alert('Security guard: You cannot deactivate your own administrative account.');
      return;
    }

    if (!confirm(`Are you sure you want to ${shouldBeActive ? 'activate' : 'deactivate'} this user account?`)) {
      return;
    }

    try {
      await apiFetch(`/api/admin/users/${id}`, {
        method: 'PATCH',
        body: JSON.stringify({ is_active: shouldBeActive }),
      });
      showToast('User account updated', 'success');
      loadUsers();
    } catch (err) {
      showToast(`Action failed: ${err.message}`, 'danger');
    }
  };

  // ---------------------------------------------------------------------------
  // 6. Reports Section
  // ---------------------------------------------------------------------------

  async function loadReports() {
    const tableBody = document.getElementById('reports-table-body');
    tableBody.innerHTML = '<tr><td colspan="8" class="text-center">Loading reports...</td></tr>';

    const status = document.getElementById('reports-status-select').value;
    const params = new URLSearchParams();
    if (status) params.set('status', status);

    try {
      const reports = await apiFetch(`/api/admin/reports?${params.toString()}`);

      if (!reports || reports.length === 0) {
        tableBody.innerHTML = '<tr><td colspan="8" class="text-center caption-muted">No problem reports found.</td></tr>';
        return;
      }

      tableBody.innerHTML = reports.map(r => `
        <tr>
          <td><code>${r.id.substring(0, 8)}...</code></td>
          <td><strong>${escapeHtml(r.place_name || '-')}</strong></td>
          <td>${escapeHtml(r.city_name || '-')}</td>
          <td>${escapeHtml(r.reason)}</td>
          <td class="caption-muted">${escapeHtml(r.details || '-')}</td>
          <td><span class="status-pill ${r.status.toLowerCase()}">${r.status}</span></td>
          <td class="caption-muted">${formatDate(r.created_at)}</td>
          <td>
            <button class="btn btn-outline btn-sm" onclick="window.triageReport('${r.id}')">Triage</button>
          </td>
        </tr>
      `).join('');
    } catch (err) {
      tableBody.innerHTML = `<tr><td colspan="8" class="text-center text-danger">Error: ${escapeHtml(err.message)}</td></tr>`;
    }
  }

  window.triageReport = async function(id) {
    try {
      const reports = await apiFetch('/api/admin/reports');
      const report = reports.find(r => r.id === id);
      if (!report) return;

      document.getElementById('report-form-id').value = report.id;
      document.getElementById('modal-report-place').textContent = report.place_name || '-';
      document.getElementById('modal-report-city').textContent = report.city_name || '-';
      document.getElementById('modal-report-reason').textContent = report.reason;
      document.getElementById('modal-report-details').textContent = report.details || 'No additional details provided.';
      document.getElementById('modal-report-status').value = report.status;
      document.getElementById('modal-report-notes').value = report.admin_notes || '';

      document.getElementById('btn-save-report').onclick = async () => {
        const newStatus = document.getElementById('modal-report-status').value;
        const notes = document.getElementById('modal-report-notes').value;

        try {
          await apiFetch(`/api/admin/reports/${report.id}`, {
            method: 'PATCH',
            body: JSON.stringify({
              status: newStatus,
              admin_notes: notes,
            }),
          });
          showToast('Report updated successfully', 'success');
          closeModal('report-modal');
          loadReports();
          loadOverview();
        } catch (err) {
          showToast(`Update failed: ${err.message}`, 'danger');
        }
      };

      openModal('report-modal');
    } catch (err) {
      showToast(`Could not load report: ${err.message}`, 'danger');
    }
  };

  // ---------------------------------------------------------------------------
  // 7. Providers & Health Section
  // ---------------------------------------------------------------------------

  async function loadProviders() {
    const container = document.getElementById('providers-container');
    container.innerHTML = '<div class="caption-muted">Loading provider diagnostics...</div>';

    try {
      const data = await apiFetch('/api/admin/provider-status');
      const prov = data.providers;

      container.innerHTML = `
        <div class="provider-card">
          <h4>${escapeHtml(prov.overpass.name)}</h4>
          <div><strong>Endpoint:</strong> <code>${escapeHtml(prov.overpass.endpoint)}</code></div>
          <div><strong>Status:</strong> <span class="status-pill active">${prov.overpass.status}</span></div>
          <div><strong>Timeout:</strong> ${prov.overpass.timeout_seconds}s</div>
          <div><strong>Circuit Breaker:</strong> Threshold: ${prov.overpass.circuit_breaker_threshold} errors, ${prov.overpass.circuit_breaker_cooldown_seconds}s cooldown</div>
        </div>

        <div class="provider-card">
          <h4>${escapeHtml(prov.geoapify.name)}</h4>
          <div><strong>Base URL:</strong> <code>${escapeHtml(prov.geoapify.endpoint)}</code></div>
          <div><strong>Configured Key:</strong> <span class="status-pill ${prov.geoapify.configured ? 'active' : 'hidden'}">${prov.geoapify.configured ? 'Configured' : 'Missing'}</span></div>
          <div><strong>Timeout:</strong> ${prov.geoapify.timeout_seconds}s</div>
          <div><strong>Cache TTL:</strong> ${prov.geoapify.cache_ttl_seconds}s</div>
        </div>

        <div class="provider-card">
          <h4>${escapeHtml(prov.audiala.name)}</h4>
          <div><strong>Dataset Path:</strong> <code>${escapeHtml(prov.audiala.path_configured || '-')}</code></div>
          <div><strong>File Exists:</strong> <span class="status-pill ${prov.audiala.file_exists ? 'active' : 'hidden'}">${prov.audiala.file_exists ? 'Ready' : 'Not Found'}</span></div>
        </div>

        <div class="provider-card">
          <h4>${escapeHtml(prov.routing.name)}</h4>
          <div><strong>Active Provider:</strong> <code>${escapeHtml(prov.routing.provider)}</code></div>
          <div><strong>OSRM Endpoint:</strong> <code>${escapeHtml(prov.routing.osrm_endpoint)}</code></div>
          <div><strong>OpenRouteService Key:</strong> <span class="status-pill ${prov.routing.ors_configured ? 'active' : 'invalid'}">${prov.routing.ors_configured ? 'Configured' : 'Optional / Disabled'}</span></div>
        </div>

        <div class="provider-card">
          <h4>${escapeHtml(prov.weather.name)}</h4>
          <div><strong>Provider:</strong> <code>${escapeHtml(prov.weather.provider)}</code></div>
          <div><strong>Endpoint:</strong> <code>${escapeHtml(prov.weather.endpoint)}</code></div>
          <div><strong>Cache TTL:</strong> ${prov.weather.cache_ttl_minutes} minutes</div>
        </div>
      `;
    } catch (err) {
      container.innerHTML = `<div class="text-danger">Failed to load provider diagnostics: ${escapeHtml(err.message)}</div>`;
    }
  }

  // Modal helpers
  function openModal(id) {
    const el = document.getElementById(id);
    if (el) el.style.display = 'flex';
  }

  function closeModal(id) {
    const el = document.getElementById(id);
    if (el) el.style.display = 'none';
  }

  window.closeModal = closeModal;

  function populateCityDropdowns(cities) {
    const placesCity = document.getElementById('places-city-select');
    const tripsCity = document.getElementById('trips-city-select');

    const options = ['<option value="">All Cities</option>'].concat(
      cities.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`)
    ).join('');

    if (placesCity && placesCity.children.length <= 1) placesCity.innerHTML = options;
    if (tripsCity && tripsCity.children.length <= 1) tripsCity.innerHTML = options;
  }

  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function formatDate(iso) {
    if (!iso) return '-';
    try {
      const d = new Date(iso);
      return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
    } catch {
      return iso;
    }
  }

  // Event Listeners Setup
  document.addEventListener('DOMContentLoaded', () => {
    // 1. Check existing token
    if (state.token) {
      apiFetch('/api/auth/me')
        .then(user => {
          if (user.role !== 'ADMIN') {
            logout();
            showToast('Access denied: You are not an administrator.', 'danger');
            return;
          }
          state.user = user;
          showApp();
        })
        .catch(() => logout());
    } else {
      showLogin();
    }

    // 2. Login Form
    const loginForm = document.getElementById('login-form');
    loginForm.addEventListener('submit', async e => {
      e.preventDefault();
      const email = document.getElementById('login-email').value.trim();
      const password = document.getElementById('login-password').value;
      const errorDiv = document.getElementById('login-error');
      const submitBtn = document.getElementById('btn-login');

      errorDiv.style.display = 'none';
      submitBtn.disabled = true;
      submitBtn.innerHTML = '<span>Verifying credentials...</span>';

      try {
        const resp = await fetch(`${API_BASE}/api/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, password }),
        });

        const data = await resp.json();
        if (!resp.ok) {
          throw new Error(data.detail || 'Authentication failed');
        }

        if (data.user.role !== 'ADMIN') {
          throw new Error('Access denied: Administrator privileges required.');
        }

        state.token = data.access_token;
        state.user = data.user;
        sessionStorage.setItem('yc_admin_token', data.access_token);
        localStorage.setItem('yc_admin_token', data.access_token);

        showApp();
        showToast(`Welcome back, ${data.user.name || data.user.email}!`, 'success');
      } catch (err) {
        errorDiv.textContent = err.message;
        errorDiv.style.display = 'block';
      } finally {
        submitBtn.disabled = false;
        submitBtn.innerHTML = '<span>Sign In to Studio</span>';
      }
    });

    // 3. Logout
    document.getElementById('btn-logout').addEventListener('click', () => {
      logout();
      showToast('Signed out successfully');
    });

    // 4. Sidebar Nav links
    document.querySelectorAll('.sidebar-nav .nav-item').forEach(item => {
      item.addEventListener('click', e => {
        e.preventDefault();
        navTo(item.dataset.section);
      });
    });

    // 5. Mobile Sidebar Toggles
    document.getElementById('sidebar-toggle').addEventListener('click', () => {
      document.getElementById('sidebar').classList.add('open');
    });
    document.getElementById('sidebar-close').addEventListener('click', () => {
      document.getElementById('sidebar').classList.remove('open');
    });

    // 6. Destination Filters & Add
    ['dest-search', 'dest-filter-enabled', 'dest-filter-featured', 'dest-filter-popular'].forEach(id => {
      document.getElementById(id).addEventListener('input', () => loadDestinations());
    });

    document.getElementById('btn-add-destination').addEventListener('click', () => {
      document.getElementById('modal-dest-title').textContent = 'Add Destination';
      document.getElementById('dest-form').reset();
      document.getElementById('dest-form-id').value = '';
      openModal('dest-modal');
    });

    document.getElementById('btn-save-destination').addEventListener('click', async () => {
      const id = document.getElementById('dest-form-id').value;
      const payload = {
        name: document.getElementById('dest-form-name').value.trim(),
        state: document.getElementById('dest-form-state').value.trim() || null,
        country: document.getElementById('dest-form-country').value.trim() || 'India',
        latitude: parseFloat(document.getElementById('dest-form-lat').value),
        longitude: parseFloat(document.getElementById('dest-form-lng').value),
        image_url: document.getElementById('dest-form-image').value.trim() || null,
        description: document.getElementById('dest-form-desc').value.trim() || null,
        display_order: parseInt(document.getElementById('dest-form-order').value, 10) || 0,
        is_enabled: document.getElementById('dest-form-enabled').checked,
        is_featured: document.getElementById('dest-form-featured').checked,
        is_popular: document.getElementById('dest-form-popular').checked,
      };

      if (!payload.name || isNaN(payload.latitude) || isNaN(payload.longitude)) {
        alert('Please fill out Name, Latitude, and Longitude.');
        return;
      }

      try {
        if (id) {
          await apiFetch(`/api/admin/destinations/${id}`, {
            method: 'PATCH',
            body: JSON.stringify(payload),
          });
          showToast('Destination updated', 'success');
        } else {
          await apiFetch('/api/admin/destinations', {
            method: 'POST',
            body: JSON.stringify(payload),
          });
          showToast('Destination created', 'success');
        }
        closeModal('dest-modal');
        loadDestinations();
      } catch (err) {
        showToast(`Save failed: ${err.message}`, 'danger');
      }
    });

    // 7. Place Filters & Pagination
    ['places-search', 'places-city-select', 'places-category-select', 'places-status-select'].forEach(id => {
      document.getElementById(id).addEventListener('change', () => {
        state.placesOffset = 0;
        loadPlaces();
      });
    });
    document.getElementById('places-search').addEventListener('input', () => {
      state.placesOffset = 0;
      loadPlaces();
    });

    document.getElementById('places-prev').addEventListener('click', () => {
      if (state.placesOffset >= state.placesLimit) {
        state.placesOffset -= state.placesLimit;
        loadPlaces();
      }
    });
    document.getElementById('places-next').addEventListener('click', () => {
      state.placesOffset += state.placesLimit;
      loadPlaces();
    });

    // 8. Trip Filters & Pagination
    ['trips-search', 'trips-city-select'].forEach(id => {
      document.getElementById(id).addEventListener('input', () => {
        state.tripsOffset = 0;
        loadTrips();
      });
    });
    document.getElementById('trips-prev').addEventListener('click', () => {
      if (state.tripsOffset >= state.tripsLimit) {
        state.tripsOffset -= state.tripsLimit;
        loadTrips();
      }
    });
    document.getElementById('trips-next').addEventListener('click', () => {
      state.tripsOffset += state.tripsLimit;
      loadTrips();
    });

    // 9. User Filters
    ['users-search', 'users-role-select'].forEach(id => {
      document.getElementById(id).addEventListener('input', () => loadUsers());
    });

    // 10. Report Filters
    document.getElementById('reports-status-select').addEventListener('change', () => loadReports());
  });
})();
