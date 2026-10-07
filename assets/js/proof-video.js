// Handles the contained testimonial player and the alternate full-width proof.
// A source is attached only on play; an empty source keeps the coming-soon state.
(function () {
  var section = document.querySelector('[data-testimonial-player], .proof');
  if (!section) return;

  var video = section.querySelector('.proof__video');
  var button = section.querySelector('.proof__play');
  var text = section.querySelector('.proof__play-text');
  var overlay = section.querySelector('[data-testimonial-overlay]');
  var close = section.querySelector('[data-testimonial-close]');
  if (!video || !button) return;
  if (close) close.hidden = true;

  var source = (video.getAttribute('data-src') || '').trim();
  if (!source) {
    button.disabled = true;
    if (text) text.textContent = 'Video coming soon';
    return;
  }
  button.disabled = false;
  if (text) text.textContent = 'Watch the film';
  button.setAttribute('aria-label', 'Play the testimonial film');

  var started = false;
  var playAttempt = 0;
  var failed = false;
  var initialTabindex = video.getAttribute('tabindex');

  function showOverlay() {
    section.classList.remove('is-playing');
    video.removeAttribute('controls');
    if (initialTabindex === null) video.removeAttribute('tabindex');
    else video.setAttribute('tabindex', initialTabindex);
    if (overlay) {
      overlay.removeAttribute('aria-hidden');
      overlay.removeAttribute('inert');
    }
    if (close) close.hidden = true;
  }

  function focusPlayButton() {
    button.focus({ preventScroll: true });
  }

  // A rejected play() is usually transient — a missing user gesture, an
  // interrupted load, a policy block. Step back out of the playing state but
  // leave the control usable, because trying again normally works.
  function softFail() {
    var returnFocus = section.contains(document.activeElement);
    video.pause();
    showOverlay();
    if (text) text.textContent = 'Try playing the film again';
    button.setAttribute('aria-label', 'Try playing the testimonial film again');
    if (returnFocus) focusPlayButton();
  }

  // The media itself is unavailable. Nothing to retry, so say so and stop.
  function hardFail(message) {
    failed = true;
    playAttempt += 1;
    var returnFocus = section.contains(document.activeElement);
    video.pause();
    showOverlay();
    button.disabled = true;
    if (text) text.textContent = message;
    button.setAttribute('aria-label', message);
    // The disabled play control cannot take focus. Keep keyboard users in the
    // visible error state rather than on a control that has just disappeared.
    if (returnFocus) {
      var notice = overlay || section;
      notice.setAttribute('tabindex', '-1');
      notice.focus({ preventScroll: true });
    }
  }

  function reset(forceFocus) {
    var returnFocus = forceFocus || section.contains(document.activeElement);
    playAttempt += 1;
    // Pause before rewinding. Seeking an un-paused element after 'ended' makes
    // it resume, which re-fires 'playing' and hides the copy again.
    video.pause();
    showOverlay();
    try { video.currentTime = 0; } catch (e) { /* not seekable yet */ }
    if (text) text.textContent = 'Watch the film';
    button.setAttribute('aria-label', 'Play the testimonial film');
    if (returnFocus) focusPlayButton();
  }

  button.addEventListener('click', function () {
    if (failed) return;
    if (!started) {
      video.src = source;
      started = true;
    }
    var thisAttempt = ++playAttempt;
    function rejected() {
      if (!failed && thisAttempt === playAttempt) softFail();
    }
    try {
      var attempt = video.play();
      if (attempt && typeof attempt.catch === 'function') attempt.catch(rejected);
    } catch (e) { rejected(); }
  });

  video.addEventListener('playing', function () {
    if (failed) return;
    var transferFocus = document.activeElement === button ||
      (overlay && overlay.contains(document.activeElement));
    // Hand over to native controls once it is running — that is where people
    // already know to find pause, scrub and volume.
    video.setAttribute('controls', '');
    video.setAttribute('tabindex', '0');
    // Move focus before making the overlay inert so it never remains inside
    // content that is hidden from keyboard and assistive-technology users.
    if (transferFocus) video.focus({ preventScroll: true });
    if (overlay) {
      overlay.setAttribute('aria-hidden', 'true');
      overlay.setAttribute('inert', '');
    }
    section.classList.add('is-playing');
    if (close) close.hidden = false;
  });

  video.addEventListener('ended', function () { reset(false); });
  video.addEventListener('error', function () { hardFail('Film could not be loaded'); });
  if (close) close.addEventListener('click', function () { reset(true); });

  // Leaving the section should not leave audio playing behind you.
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting && !video.paused) video.pause();
      });
    }, { threshold: 0.15 }).observe(section);
  }

  // Escape backs out of the film.
  section.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && section.classList.contains('is-playing')) {
      reset(true);
    }
  });
})();
