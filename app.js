const periodButton = document.querySelector('#period-button');
const notice = document.querySelector('#demo-notice');
let noticeTimer;

periodButton?.addEventListener('click', () => {
  notice.textContent = 'Örnek veriler gösteriliyor. Canlı bağlantı adımları için Proje bilgisi’ni açın.';
  notice.classList.add('visible');
  window.clearTimeout(noticeTimer);
  noticeTimer = window.setTimeout(() => notice.classList.remove('visible'), 3600);
});
