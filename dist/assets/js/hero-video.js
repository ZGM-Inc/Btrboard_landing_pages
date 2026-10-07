// Keep the responsive still visible until playback actually starts.
(function () {
  var video = document.querySelector('.hero__video');
  var button = document.querySelector('.hero__motion');
  if (!video || !button) return;

  var label = button.querySelector('.hero__motion-label');
  var reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  var connection = navigator.connection;
  var userPaused = false;
  var inView = true;
  var failed = false;

  function allowed() {
    var constrained = connection && (connection.saveData || /^(slow-)?2g$/.test(connection.effectiveType || ''));
    return !reducedMotion.matches && !constrained;
  }

  function updateButton() {
    var paused = video.paused;
    button.classList.toggle('is-paused', paused);
    button.setAttribute('aria-label', paused ? 'Play background video' : 'Pause background video');
    label.textContent = paused ? 'Play motion' : 'Pause motion';
  }

  function syncPlayback() {
    if (!allowed()) {
      video.pause();
      video.classList.remove('is-ready');
      button.hidden = true;
      if (video.hasAttribute('src')) {
        video.removeAttribute('src');
        video.load();
      }
      return;
    }
    if (!failed && userPaused) {
      // Restore the manual play option when motion/data preferences change back.
      button.hidden = false;
      video.pause();
      updateButton();
      return;
    }
    if (failed || document.hidden || !inView) {
      video.pause();
      return;
    }
    if (!video.hasAttribute('src')) video.src = video.dataset.src;
    video.muted = true;
    var play = video.play();
    if (play && typeof play.catch === 'function') {
      play.catch(function (error) {
        // Pausing during loading is expected on scroll, visibility or preference changes.
        if (error.name === 'AbortError') return;
        if (!allowed() || failed || document.hidden || !inView) return;
        userPaused = true;
        button.hidden = false;
        updateButton();
      });
    }
  }

  video.addEventListener('playing', function () {
    if (!allowed()) { syncPlayback(); return; }
    video.classList.add('is-ready');
    button.hidden = false;
    updateButton();
  });
  video.addEventListener('pause', updateButton);
  video.addEventListener('error', function () {
    failed = true;
    video.classList.remove('is-ready');
    button.hidden = true;
  });

  button.addEventListener('click', function () {
    userPaused = !video.paused;
    syncPlayback();
    updateButton();
  });
  document.addEventListener('visibilitychange', syncPlayback);
  if (reducedMotion.addEventListener) reducedMotion.addEventListener('change', syncPlayback);
  else if (reducedMotion.addListener) reducedMotion.addListener(syncPlayback);
  if (connection && connection.addEventListener) connection.addEventListener('change', syncPlayback);

  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (entries) {
      inView = entries[0].isIntersecting;
      syncPlayback();
    }).observe(video.closest('.hero'));
  }
  syncPlayback();
})();
