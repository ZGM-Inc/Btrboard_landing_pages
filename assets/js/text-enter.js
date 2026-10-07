// Text enters on scroll: headings rise a line at a time, the label leads, the
// copy follows. Lines are measured after the webfont settles, and re-measured
// on resize, so a reflow never leaves a line stranded mid-animation.
(function () {
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)');
  if (reduce.matches || !('IntersectionObserver' in window)) return;

  var groups = Array.prototype.slice.call(document.querySelectorAll('[data-enter]'));
  if (!groups.length) return;

  document.documentElement.classList.add('js-enter');

  function splitLines(el) {
    if (!el.dataset.original) el.dataset.original = el.innerHTML;
    el.innerHTML = el.dataset.original;

    // <br> is a hard line break the author asked for — honour it.
    var chunks = el.innerHTML.split(/<br\s*\/?>/i);
    el.innerHTML = chunks
      .map(function (chunk) {
        return chunk
          .split(/\s+/)
          .filter(Boolean)
          .map(function (w) { return '<span class="w">' + w + '</span>'; })
          .join(' ');
      })
      .join('<br>');

    var words = Array.prototype.slice.call(el.querySelectorAll('.w'));
    if (!words.length) return;

    // Group words by vertical position — that is what a rendered line is.
    var lines = [];
    var current = null;
    var lastTop = null;
    words.forEach(function (w) {
      var top = Math.round(w.offsetTop);
      if (lastTop === null || Math.abs(top - lastTop) > 2) {
        current = [];
        lines.push(current);
        lastTop = top;
      }
      current.push(w.textContent);
    });

    el.innerHTML = lines
      .map(function (words, i) {
        return '<span class="ln" style="--i:' + i + '"><span class="ln__in">' +
               words.join(' ') + '</span></span>';
      })
      // Joined with a space, not nothing: .ln is display:block so it never
      // renders, but without it textContent runs the last word of one line
      // into the first of the next — breaking screen readers and copy-paste.
      .join(' ');
  }

  function prepare(group) {
    var heading = group.querySelector('.display, .heading, .lede, .head');
    if (heading) splitLines(heading);

    // Everything else in the group just steps in behind the heading.
    var rest = Array.prototype.slice.call(
      group.querySelectorAll(
        // Option A names the elements; Option B pre-marks them with .en.
        '.label, .body, .lead, .quiet, .spec, .witness, .hero__cta, .booking__cta, .proof__cta, .en'
      )
    );
    rest.forEach(function (el, i) { el.style.setProperty('--j', i); el.classList.add('en'); });
  }

  function run() { groups.forEach(prepare); }

  (document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve()).then(function () {
    run();

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('is-in'); io.unobserve(e.target); }
      });
    }, { rootMargin: '0px 0px -14% 0px', threshold: 0.1 });
    groups.forEach(function (g) { io.observe(g); });

    var t;
    window.addEventListener('resize', function () {
      clearTimeout(t);
      t = setTimeout(function () {
        groups.forEach(function (g) {
          var wasIn = g.classList.contains('is-in');
          prepare(g);
          if (wasIn) g.classList.add('is-in');
        });
      }, 180);
    });
  });
})();
