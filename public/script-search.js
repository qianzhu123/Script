(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.ScriptSearch = api;
}(typeof window !== 'undefined' ? window : globalThis, function () {
  function normalizeSearchQuery(value) {
    return String(value || '').trim().toLocaleLowerCase();
  }

  function groupNameFor(groups, groupId) {
    return (groups || []).find((group) => group.id === groupId)?.name || '';
  }

  function findMatchingScripts(scripts, groups, query) {
    const normalized = normalizeSearchQuery(query);
    if (!normalized) return scripts;
    return (scripts || []).filter((script) => [
      script.name,
      script.description,
      script.path,
      groupNameFor(groups, script.groupId)
    ].some((value) => String(value || '').toLocaleLowerCase().includes(normalized)));
  }

  function escapeHtml(value) {
    return String(value || '').replace(/[&<>"']/g, (char) => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    }[char]));
  }

  function escapeRegExp(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  function highlightSearchText(value, query) {
    const text = String(value || '');
    const normalized = normalizeSearchQuery(query);
    if (!normalized) return escapeHtml(text);
    const matcher = new RegExp(escapeRegExp(String(query).trim()), 'gi');
    let cursor = 0;
    let output = '';
    for (const match of text.matchAll(matcher)) {
      output += escapeHtml(text.slice(cursor, match.index));
      output += `<mark>${escapeHtml(match[0])}</mark>`;
      cursor = match.index + match[0].length;
    }
    return output + escapeHtml(text.slice(cursor));
  }

  function nextSearchIndex(currentIndex, resultCount, direction) {
    if (resultCount <= 0) return -1;
    if (currentIndex < 0) return direction < 0 ? resultCount - 1 : 0;
    return (currentIndex + direction + resultCount) % resultCount;
  }

  return {
    normalizeSearchQuery,
    findMatchingScripts,
    highlightSearchText,
    nextSearchIndex,
    groupNameFor
  };
}));
