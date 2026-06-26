(function () {
  'use strict';

  const table = document.querySelector('.files table');
  if (!table) return; // file pages have no .files table

  const ths = Array.from(table.querySelectorAll('thead th'));
  const tbody = table.querySelector('tbody');
  let currentCol = 0;   // default: File column, ascending
  let currentAsc = true;
  const collapsedGroups = new Set();

  // Reflect the Dart-side default sort (file name ascending).
  ths[0].querySelector('.sort-icon').textContent = ' ▲';
  ths[0].setAttribute('data-sort', 'asc');

  // ---- collapse / expand -------------------------------------------------

  function applyCollapsedState() {
    tbody.querySelectorAll('tr.pkg-header').forEach(headerRow => {
      const g = headerRow.dataset.group;
      const collapsed = collapsedGroups.has(g);
      headerRow.classList.toggle('collapsed', collapsed);
      tbody.querySelectorAll(`tr[data-group="${g}"]:not(.pkg-header)`)
          .forEach(row => { row.style.display = collapsed ? 'none' : ''; });
    });
  }

  tbody.querySelectorAll('tr.pkg-header').forEach(headerRow => {
    headerRow.addEventListener('click', () => {
      const g = headerRow.dataset.group;
      if (collapsedGroups.has(g)) collapsedGroups.delete(g);
      else collapsedGroups.add(g);
      applyCollapsedState();
    });
  });

  // ---- sort --------------------------------------------------------------

  function makeSortFn(colIdx, asc) {
    return (rowA, rowB) => {
      const cellA = rowA.cells[colIdx];
      const cellB = rowB.cells[colIdx];
      const a = cellA.dataset.value !== undefined
          ? cellA.dataset.value : cellA.textContent.trim();
      const b = cellB.dataset.value !== undefined
          ? cellB.dataset.value : cellB.textContent.trim();
      const numA = parseFloat(a);
      const numB = parseFloat(b);
      const cmp = !isNaN(numA) && !isNaN(numB) ? numA - numB : a.localeCompare(b);
      return asc ? cmp : -cmp;
    };
  }

  ths.forEach((th, colIdx) => {
    th.addEventListener('click', () => {
      currentAsc = (currentCol === colIdx) ? !currentAsc : true;
      currentCol = colIdx;

      ths.forEach(h => {
        h.querySelector('.sort-icon').textContent = '';
        h.removeAttribute('data-sort');
      });
      th.querySelector('.sort-icon').textContent = currentAsc ? ' ▲' : ' ▼';
      th.setAttribute('data-sort', currentAsc ? 'asc' : 'desc');

      const sortFn = makeSortFn(colIdx, currentAsc);
      const rows = Array.from(tbody.querySelectorAll('tr'));
      const hasTree = rows.some(r => r.classList.contains('pkg-header'));

      if (!hasTree) {
        rows.sort(sortFn);
        rows.forEach(row => tbody.appendChild(row));
      } else {
        const pkgHeaders = rows.filter(r => r.classList.contains('pkg-header'));
        // Non-pkg-header rows (files + folder links) are sorted together within each group.
        const contentRows = rows.filter(r => !r.classList.contains('pkg-header'));

        const groups = {};
        contentRows.forEach(row => {
          const g = row.dataset.group || '';
          if (!groups[g]) groups[g] = [];
          groups[g].push(row);
        });
        // Sort all content rows (files and folder links) together by the clicked column.
        Object.keys(groups).forEach(g => {
          groups[g].sort(sortFn);
        });

        pkgHeaders.sort(makeSortFn(0, true)).forEach(ph => {
          tbody.appendChild(ph);
          (groups[ph.dataset.group] || []).forEach(r => tbody.appendChild(r));
        });

        // Re-apply collapsed state after DOM rearrangement.
        applyCollapsedState();
      }
    });
  });
})();
