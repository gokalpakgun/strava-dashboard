const notice = document.querySelector('#demo-notice');
let noticeTimer;

function showNotice(message) {
  notice.textContent = message;
  notice.classList.add('visible');
  window.clearTimeout(noticeTimer);
  noticeTimer = window.setTimeout(() => notice.classList.remove('visible'), 4800);
}

function formatDuration(seconds) {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainder = Math.floor(seconds % 60);
  return hours ? `${hours}:${String(minutes).padStart(2, '0')}` : `${minutes}:${String(remainder).padStart(2, '0')}`;
}

function formatHours(seconds) {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return `${hours}:${String(minutes).padStart(2, '0')}`;
}

function formatPace(activity) {
  const km = activity.distance / 1000;
  if (!km || !activity.moving_time) return '—';
  const seconds = activity.type.toLowerCase().includes('run') ? activity.moving_time / km : 3600 / (activity.average_speed || 0);
  if (!Number.isFinite(seconds)) return '—';
  const value = `${Math.floor(seconds / 60)}:${String(Math.round(seconds % 60)).padStart(2, '0')}`;
  return activity.type.toLowerCase().includes('run') ? `${value} /km` : `${(activity.average_speed * 3.6).toFixed(1)} km/sa`;
}

function formatDate(value) {
  return new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'short' }).format(new Date(value));
}

function activityType(activity) {
  const type = activity.type || '';
  if (type.toLowerCase().includes('run')) return { label: 'Koşu', icon: '↗', className: 'run' };
  if (type.toLowerCase().includes('ride') || type.toLowerCase().includes('cycle')) return { label: 'Bisiklet', icon: '⌁', className: 'ride' };
  return { label: type || 'Aktivite', icon: '✳', className: 'run' };
}

function renderActivities(activities) {
  const table = document.querySelector('.activity-table');
  table.querySelectorAll('.activity-row').forEach((row) => row.remove());
  const head = table.querySelector('.table-head');
  const sorted = [...activities].sort((a, b) => new Date(b.start_date_local) - new Date(a.start_date_local));
  sorted.slice(0, 8).forEach((activity) => {
    const type = activityType(activity);
    const row = document.createElement('article');
    row.className = 'activity-row';
    const name = document.createElement('div');
    name.className = 'activity-name';
    const icon = document.createElement('span');
    icon.className = `activity-icon ${type.className}`;
    icon.textContent = type.icon;
    const details = document.createElement('div');
    const title = document.createElement('strong');
    title.textContent = activity.name || type.label;
    const subtitle = document.createElement('small');
    subtitle.textContent = type.label;
    details.append(title, subtitle);
    name.append(icon, details);
    const date = document.createElement('span');
    date.className = 'activity-date';
    date.textContent = formatDate(activity.start_date_local);
    const distance = document.createElement('b');
    distance.textContent = `${(activity.distance / 1000).toFixed(2)} km`;
    const duration = document.createElement('span');
    duration.textContent = formatDuration(activity.moving_time);
    const pace = document.createElement('span');
    pace.textContent = formatPace(activity);
    row.append(name, date, distance, duration, pace);
    table.insertBefore(row, head.nextSibling);
  });
  if (!sorted.length) {
    const empty = document.createElement('article');
    empty.className = 'activity-row empty-row';
    empty.textContent = 'Henüz görüntülenecek aktivite yok.';
    table.insertBefore(empty, head.nextSibling);
  }
}

function drawChart(activities, weekStart) {
  const totals = Array.from({ length: 7 }, () => 0);
  activities.forEach((activity) => {
    const date = new Date(activity.start_date_local);
    const day = Math.floor((new Date(date.getFullYear(), date.getMonth(), date.getDate()) - weekStart) / 86400000);
    if (day >= 0 && day < 7) totals[day] += activity.distance / 1000;
  });
  const scale = Math.max(4, Math.ceil(Math.max(...totals, 1) / 4) * 4);
  const coords = totals.map((value, index) => `${Math.round(index * 700 / 6)},${Math.round(170 - value / scale * 150)}`);
  const linePath = `M${coords.join(' L')}`;
  const line = document.querySelector('.chart .line');
  const area = document.querySelector('.chart .area');
  const marker = document.querySelector('.chart circle');
  line.setAttribute('d', linePath);
  area.setAttribute('d', `${linePath} L700 190 L0 190Z`);
  const last = coords.at(-1).split(',');
  marker.setAttribute('cx', last[0]);
  marker.setAttribute('cy', last[1]);
  document.querySelectorAll('.y-labels span').forEach((label, index) => {
    label.textContent = `${Math.round(scale * (3 - index) / 3)} km`;
  });
  document.querySelectorAll('.x-labels span').forEach((label, index) => {
    label.textContent = new Intl.DateTimeFormat('tr-TR', { weekday: 'short' }).format(new Date(weekStart.getTime() + index * 86400000));
  });
}

function renderDashboard(activities) {
  const now = new Date();
  const weekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6);
  const thisWeek = activities.filter((activity) => new Date(activity.start_date_local) >= weekStart);
  const distance = thisWeek.reduce((sum, activity) => sum + activity.distance, 0) / 1000;
  const movingTime = thisWeek.reduce((sum, activity) => sum + activity.moving_time, 0);
  const elevation = thisWeek.reduce((sum, activity) => sum + (activity.total_elevation_gain || 0), 0);
  const runs = thisWeek.filter((activity) => (activity.type || '').toLowerCase().includes('run')).length;
  const values = document.querySelectorAll('.stat-value');
  values[0].textContent = `${distance.toFixed(1)} km`;
  values[1].textContent = `${formatHours(movingTime)} saat`;
  values[2].textContent = `${Math.round(elevation)} m`;
  values[3].textContent = `${thisWeek.length} antrenman`;
  document.querySelectorAll('.stat-note').forEach((note) => { note.textContent = 'Son 7 günde'; });
  const goals = document.querySelectorAll('.goal-row');
  const distancePercent = Math.min(100, Math.round(distance / 48 * 100));
  goals[0].querySelector('.goal-ring span').innerHTML = `${distancePercent}<small>%</small>`;
  goals[0].querySelector('.goal-info span').textContent = `${distance.toFixed(1)} / 48 km`;
  goals[0].querySelector('.goal-track i').style.width = `${distancePercent}%`;
  const runPercent = Math.min(100, Math.round(runs / 4 * 100));
  goals[1].querySelector('.goal-ring span').innerHTML = `${runPercent}<small>%</small>`;
  goals[1].querySelector('.goal-info span').textContent = `${runs} / 4 antrenman`;
  goals[1].querySelector('.goal-track i').style.width = `${runPercent}%`;
  document.querySelector('.goal-tip').innerHTML = `<span>✦</span> Haftalık hedefin için <b>${Math.max(0, 48 - distance).toFixed(1)} km</b> kaldı.`;
  drawChart(activities, weekStart);
  renderActivities(activities);
  document.querySelector('#connection-title').textContent = 'Strava bağlantısı aktif';
  document.querySelector('#connection-copy').textContent = 'Aktivitelerin canlı verilerle güncellendi.';
  document.querySelector('.profile strong').textContent = 'Strava hesabın';
  document.querySelector('.profile div:nth-child(2) span').textContent = 'Bağlantı kuruldu';
  document.querySelector('#connect-button').textContent = 'Strava bağlı ✓';
  document.querySelector('#connect-button').removeAttribute('href');
  document.querySelector('#connect-button').classList.add('connected');
  document.querySelector('#disconnect-link').hidden = false;
}

function renderAthlete(athlete) {
  const fullName = [athlete.firstname, athlete.lastname].filter(Boolean).join(' ') || 'Strava sporcusu';
  const location = [athlete.city, athlete.state, athlete.country].filter(Boolean).join(', ') || 'Konum paylaşılmamış';
  document.querySelector('#athlete-name').textContent = fullName;
  document.querySelector('#athlete-location').textContent = location;
  document.querySelector('#athlete-followers').textContent = athlete.follower_count ?? '—';
  document.querySelector('#athlete-following').textContent = athlete.friend_count ?? '—';
  document.querySelector('#athlete-weight').textContent = athlete.weight ? `${athlete.weight} kg` : '—';
  document.querySelector('#strava-profile-link').href = `https://www.strava.com/athletes/${encodeURIComponent(athlete.id)}`;
  const avatar = document.querySelector('#athlete-avatar');
  avatar.textContent = (athlete.firstname || 'S').slice(0, 1).toUpperCase();
  document.querySelector('.profile strong').textContent = fullName;
  document.querySelector('.profile div:nth-child(2) span').textContent = location;
  if (athlete.profile) {
    const image = document.createElement('img');
    image.src = athlete.profile;
    image.alt = '';
    image.referrerPolicy = 'no-referrer';
    image.addEventListener('load', () => { avatar.textContent = ''; avatar.append(image); });
  }
}

function setEmptyList(container, message) {
  container.replaceChildren();
  const item = document.createElement('p');
  item.className = 'data-empty';
  item.textContent = message;
  container.append(item);
}

function renderGear(athlete) {
  const container = document.querySelector('#gear-list');
  const gear = [...(athlete.bikes || []), ...(athlete.shoes || [])];
  if (!gear.length) return setEmptyList(container, 'Strava profilinde kayıtlı ekipman bulunamadı.');
  container.replaceChildren();
  gear.forEach((item) => {
    const row = document.createElement('div');
    row.className = 'data-row';
    const name = document.createElement('strong');
    name.textContent = `${item.name || item.type}${item.primary ? ' · Varsayılan' : ''}`;
    const detail = document.createElement('span');
    detail.textContent = `${item.type} · ${(item.distance / 1000).toLocaleString('tr-TR', { maximumFractionDigits: 0 })} km`;
    row.append(name, detail);
    container.append(row);
  });
}

function renderSegments(segments) {
  const container = document.querySelector('#segments-list');
  if (!segments?.length) return setEmptyList(container, 'Strava’da favorilere eklenmiş segment bulunamadı.');
  container.replaceChildren();
  segments.forEach((segment) => {
    const row = document.createElement('div');
    row.className = 'data-row';
    const link = document.createElement('a');
    link.href = `https://www.strava.com/segments/${encodeURIComponent(segment.id)}`;
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    link.textContent = segment.name || 'İsimsiz segment';
    const detail = document.createElement('span');
    const climb = Number.isFinite(segment.average_grade) ? ` · %${segment.average_grade.toFixed(1)} eğim` : '';
    detail.textContent = `${(segment.distance / 1000).toFixed(2)} km${climb}`;
    row.append(link, detail);
    container.append(row);
  });
}

function renderMonthlyStats(activities) {
  const container = document.querySelector('#monthly-list');
  container.replaceChildren();
  const now = new Date();
  const months = [];
  for (let offset = 5; offset >= 0; offset -= 1) {
    const date = new Date(now.getFullYear(), now.getMonth() - offset, 1);
    months.push({ key: `${date.getFullYear()}-${date.getMonth()}`, date, distance: 0, count: 0, time: 0 });
  }
  const index = new Map(months.map((month) => [month.key, month]));
  activities.forEach((activity) => {
    const date = new Date(activity.start_date_local);
    const month = index.get(`${date.getFullYear()}-${date.getMonth()}`);
    if (!month) return;
    month.distance += activity.distance / 1000;
    month.count += 1;
    month.time += activity.moving_time;
  });
  const peak = Math.max(1, ...months.map((month) => month.distance));
  months.forEach((month) => {
    const card = document.createElement('div');
    card.className = 'month-card';
    const name = document.createElement('strong');
    name.textContent = new Intl.DateTimeFormat('tr-TR', { month: 'long' }).format(month.date);
    const metric = document.createElement('b');
    metric.textContent = `${month.distance.toFixed(1)} km`;
    const track = document.createElement('div');
    track.className = 'month-track';
    const fill = document.createElement('i');
    fill.style.width = `${Math.max(2, month.distance / peak * 100)}%`;
    track.append(fill);
    const note = document.createElement('span');
    note.textContent = `${month.count} aktivite · ${formatHours(month.time)} saat`;
    card.append(name, metric, track, note);
    container.append(card);
  });
}

function renderEddington(activities, historyLimited) {
  const days = new Map();
  activities.filter((activity) => (activity.type || '').toLowerCase().includes('run')).forEach((activity) => {
    const date = activity.start_date_local.slice(0, 10);
    days.set(date, (days.get(date) || 0) + activity.distance / 1000);
  });
  const distances = [...days.values()].sort((a, b) => b - a);
  let number = 0;
  distances.forEach((distance, index) => { if (distance >= index + 1) number = index + 1; });
  document.querySelector('#eddington-number').textContent = number;
  document.querySelector('#eddington-copy').textContent = `${number} farklı günde en az ${number} km koştun.${historyLimited ? ' Hesaplama son 1.000 aktiviteyle sınırlı.' : ''}`;
}

function decodePolyline(encoded) {
  const points = [];
  let index = 0;
  let lat = 0;
  let lng = 0;
  while (index < encoded.length) {
    let result = 0;
    let shift = 0;
    let byte;
    do { byte = encoded.charCodeAt(index++) - 63; result |= (byte & 0x1f) << shift; shift += 5; } while (byte >= 0x20 && index < encoded.length);
    lat += result & 1 ? ~(result >> 1) : result >> 1;
    result = 0;
    shift = 0;
    do { byte = encoded.charCodeAt(index++) - 63; result |= (byte & 0x1f) << shift; shift += 5; } while (byte >= 0x20 && index < encoded.length);
    lng += result & 1 ? ~(result >> 1) : result >> 1;
    points.push([lat / 1e5, lng / 1e5]);
  }
  return points;
}

function renderHeatmap(activities) {
  const group = document.querySelector('#heatmap-routes');
  const tracks = activities.slice(0, 300).map((activity) => decodePolyline(activity.polyline || '')).filter((points) => points.length > 1);
  const allPoints = tracks.flat();
  const caption = document.querySelector('#heatmap-copy');
  group.replaceChildren();
  if (!allPoints.length) {
    caption.textContent = 'Aktivitelerde GPS rotası bulunamadı. Strava’da aktivite haritası görünüyorsa hesabı yeniden bağla.';
    return;
  }
  const meanLat = allPoints.reduce((sum, [lat]) => sum + lat, 0) / allPoints.length;
  const longitudeScale = Math.max(0.01, Math.cos(meanLat * Math.PI / 180));
  const projectedTracks = tracks.map((track) => track.map(([lat, lng]) => [lat, lng * longitudeScale]));
  const points = projectedTracks.flat();
  const bounds = points.reduce((value, [lat, lng]) => ({
    minLat: Math.min(value.minLat, lat), maxLat: Math.max(value.maxLat, lat),
    minLng: Math.min(value.minLng, lng), maxLng: Math.max(value.maxLng, lng),
  }), { minLat: Infinity, maxLat: -Infinity, minLng: Infinity, maxLng: -Infinity });
  const { minLat, maxLat, minLng, maxLng } = bounds;
  const latSpan = maxLat - minLat || 0.001;
  const lngSpan = maxLng - minLng || 0.001;
  const scale = Math.min(920 / lngSpan, 380 / latSpan);
  const width = lngSpan * scale;
  const height = latSpan * scale;
  const xOffset = (1000 - width) / 2;
  const yOffset = (440 - height) / 2;
  const ns = 'http://www.w3.org/2000/svg';
  projectedTracks.forEach((track) => {
    const path = document.createElementNS(ns, 'polyline');
    path.setAttribute('points', track.map(([lat, lng]) => `${(lng - minLng) * scale + xOffset},${(maxLat - lat) * scale + yOffset}`).join(' '));
    path.setAttribute('class', 'heatmap-route');
    group.append(path);
  });
  caption.textContent = `${tracks.length} GPS rotası · son ${activities.length} aktiviteden`;
}

function renderRewind(activities, historyLimited) {
  const year = new Date().getFullYear();
  const yearActivities = activities.filter((activity) => new Date(activity.start_date_local).getFullYear() === year);
  const totalKm = yearActivities.reduce((sum, activity) => sum + activity.distance, 0) / 1000;
  const totalHours = yearActivities.reduce((sum, activity) => sum + activity.moving_time, 0);
  const elevation = yearActivities.reduce((sum, activity) => sum + (activity.total_elevation_gain || 0), 0);
  const longest = Math.max(0, ...yearActivities.map((activity) => activity.distance / 1000));
  document.querySelector('#rewind-title').textContent = `${year} özeti`;
  const container = document.querySelector('#rewind-list');
  container.replaceChildren();
  [[`${totalKm.toFixed(1)} km`, 'Toplam mesafe'], [yearActivities.length, 'Aktivite'], [`${formatHours(totalHours)} sa`, 'Hareket süresi'], [`${Math.round(elevation).toLocaleString('tr-TR')} m`, 'Yükseklik'], [`${longest.toFixed(1)} km`, 'En uzun aktivite']].forEach(([value, label]) => {
    const item = document.createElement('div');
    item.className = 'rewind-item';
    const metric = document.createElement('strong');
    metric.textContent = value;
    const caption = document.createElement('span');
    caption.textContent = label;
    item.append(metric, caption);
    container.append(item);
  });
  if (historyLimited) {
    const note = document.createElement('p');
    note.className = 'data-empty full-row';
    note.textContent = 'Strava API sayfa sınırı nedeniyle son 1.000 aktivite kullanıldı.';
    container.append(note);
  }
}

function renderPhotos(photos) {
  const container = document.querySelector('#photos-grid');
  container.replaceChildren();
  if (!photos?.length) return setEmptyList(container, 'Son aktivitelerinde gösterilecek fotoğraf bulunamadı.');
  photos.forEach((photo) => {
    const link = document.createElement('a');
    link.className = 'photo-card';
    link.href = `https://www.strava.com/activities/${encodeURIComponent(photo.activity_id)}`;
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    const image = document.createElement('img');
    image.src = photo.image;
    image.alt = photo.activity_name || 'Strava aktivite fotoğrafı';
    image.loading = 'lazy';
    const title = document.createElement('span');
    title.textContent = photo.activity_name || 'Aktiviteyi görüntüle';
    link.append(image, title);
    container.append(link);
  });
}

function renderStravaSections(data) {
  renderGear(data.athlete);
  renderSegments(data.segments);
  renderMonthlyStats(data.activities);
  renderEddington(data.activities, data.historyLimited);
  renderHeatmap(data.activities);
  renderRewind(data.activities, data.historyLimited);
  renderPhotos(data.photos);
}

document.querySelector('#disconnect-link')?.addEventListener('click', async (event) => {
  event.preventDefault();
  await fetch('/auth/logout', { method: 'POST', credentials: 'same-origin' });
  window.location.reload();
});

document.querySelectorAll('.nav-item').forEach((link) => {
  link.addEventListener('click', () => {
    document.querySelector('.nav-item.active')?.classList.remove('active');
    link.classList.add('active');
    document.body.classList.remove('mobile-nav-open');
    document.querySelector('.menu-toggle')?.setAttribute('aria-expanded', 'false');
  });
});

const menuToggle = document.querySelector('.menu-toggle');
const closeMobileMenu = () => {
  document.body.classList.remove('mobile-nav-open');
  menuToggle?.setAttribute('aria-expanded', 'false');
};
menuToggle?.addEventListener('click', () => {
  const isOpen = document.body.classList.toggle('mobile-nav-open');
  menuToggle.setAttribute('aria-expanded', String(isOpen));
});
document.querySelectorAll('.sidebar-close, .sidebar-backdrop').forEach((button) => {
  button.addEventListener('click', closeMobileMenu);
});
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') closeMobileMenu();
});

const params = new URLSearchParams(window.location.search);
if (params.get('connected') === '1') {
  showNotice('Strava bağlandı. Güncel aktivitelerin yükleniyor.');
  window.history.replaceState({}, '', window.location.pathname);
}

fetch('/api/dashboard', { credentials: 'same-origin' })
  .then(async (response) => {
    if (!response.ok) throw new Error(response.status === 401 ? 'not-connected' : 'load-failed');
    return response.json();
  })
  .then((data) => {
    renderDashboard(data.activities);
    renderAthlete(data.athlete);
    renderStravaSections(data);
  })
  .catch((error) => {
    if (error.message !== 'not-connected') showNotice('Örnek veriler gösteriliyor. Canlı bağlantı için önce Strava’yı bağla.');
  });
