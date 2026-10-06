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

document.querySelector('#disconnect-link')?.addEventListener('click', async (event) => {
  event.preventDefault();
  await fetch('/auth/logout', { method: 'POST', credentials: 'same-origin' });
  window.location.reload();
});

document.querySelectorAll('.nav-item').forEach((link) => {
  link.addEventListener('click', () => {
    document.querySelector('.nav-item.active')?.classList.remove('active');
    link.classList.add('active');
  });
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
  })
  .catch((error) => {
    if (error.message !== 'not-connected') showNotice('Örnek veriler gösteriliyor. Canlı bağlantı için önce Strava’yı bağla.');
  });
