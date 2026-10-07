// Product layer disclosures. Hover previews a layer; click or tap keeps it open.
(function () {
  var root = document.getElementById('explorer');
  if (!root) return;

  var buttons = Array.prototype.slice.call(root.querySelectorAll('.board__call[aria-controls]'));
  var panels = Array.prototype.slice.call(root.querySelectorAll('.board__note'));
  var lines = Array.prototype.slice.call(root.querySelectorAll('.board__leaders line'));
  if (!buttons.length || !panels.length) return;

  var pinnedLayer = '';
  var hoveredLayer = '';
  var closeTimer;

  function cancelClose() {
    clearTimeout(closeTimer);
    closeTimer = null;
  }

  function render() {
    var layer = hoveredLayer || pinnedLayer;
    buttons.forEach(function (button) {
      button.setAttribute('aria-expanded', button.dataset.layer === layer ? 'true' : 'false');
    });
    panels.forEach(function (panel) {
      var on = panel.id === 'note-' + layer;
      panel.hidden = !on;
      panel.classList.toggle('is-active', on);
    });
    lines.forEach(function (line) {
      line.classList.toggle('is-on', line.getAttribute('data-for') === layer);
    });
    root.dataset.layer = layer;
  }

  function dismiss() {
    cancelClose();
    hoveredLayer = '';
    pinnedLayer = '';
    render();
  }

  function preview(layer, event) {
    if (event.pointerType === 'touch') return;
    cancelClose();
    hoveredLayer = layer;
    render();
  }

  function leave(layer, event) {
    if (event.pointerType === 'touch' || hoveredLayer !== layer) return;
    cancelClose();
    // Allow the pointer to cross the gap from its marker to the explanation.
    closeTimer = setTimeout(function () {
      hoveredLayer = '';
      render();
    }, 200);
  }

  buttons.forEach(function (button) {
    var layer = button.dataset.layer;
    button.tabIndex = 0;
    button.addEventListener('pointerenter', function (event) { preview(layer, event); });
    button.addEventListener('pointerleave', function (event) { leave(layer, event); });
    button.addEventListener('click', function () {
      cancelClose();
      pinnedLayer = pinnedLayer === layer ? '' : layer;
      // Clearing the hover also lets a second click close the note while the
      // pointer is still on its marker. Focus alone never reopens a note.
      hoveredLayer = '';
      render();
    });
  });

  panels.forEach(function (panel) {
    var button = buttons.filter(function (item) {
      return item.getAttribute('aria-controls') === panel.id;
    })[0];
    if (!button) return;
    panel.addEventListener('pointerenter', function (event) {
      if (!panel.hidden) preview(button.dataset.layer, event);
    });
    panel.addEventListener('pointerleave', function (event) { leave(button.dataset.layer, event); });
  });

  document.addEventListener('pointerdown', function (event) {
    var inside = buttons.concat(panels).some(function (element) {
      return element.contains(event.target);
    });
    if (!inside) dismiss();
  });

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && (pinnedLayer || hoveredLayer)) {
      event.preventDefault();
      dismiss();
    }
  });

  root.addEventListener('keydown', function (event) {
    var index = buttons.indexOf(document.activeElement);
    if (index < 0) return;
    var next = null;
    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') next = (index + 1) % buttons.length;
    else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') next = (index - 1 + buttons.length) % buttons.length;
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = buttons.length - 1;
    if (next === null) return;
    event.preventDefault();
    buttons[next].focus();
  });

  dismiss();
  root.classList.add('is-live');
})();
