export function sortRows(rows, column, direction = 'asc') {
  const sign = direction === 'desc' ? -1 : 1;
  return [...rows].sort((a, b) => {
    const av = a[column];
    const bv = b[column];
    if (typeof av === 'number' && typeof bv === 'number') {
      return (av - bv) * sign;
    }
    return String(av).toLowerCase().localeCompare(String(bv).toLowerCase()) * sign;
  });
}

function esc(s) {
  return String(s)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

export function renderTable({ columns, rows, sortColumn, sortDir }) {
  const head = columns
    .map((col) => {
      const active = col.key === sortColumn;
      const dir = active ? sortDir : 'asc';
      const arrow = active ? (dir === 'asc' ? ' ↑' : ' ↓') : '';
      return `<th data-sort="${esc(col.key)}" data-type="${esc(col.type ?? 'string')}" aria-sort="${active ? (dir === 'asc' ? 'ascending' : 'descending') : 'none'}">${esc(col.label)}${arrow}</th>`;
    })
    .join('');
  const body = rows
    .map(
      (row) =>
        `<tr>${columns
          .map((col) =>
            typeof col.format === 'function'
              ? `<td>${col.format(row[col.key], row)}</td>`
              : `<td>${esc(row[col.key])}</td>`,
          )
          .join('')}</tr>`,
    )
    .join('');
  return `<table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
}
