(function initTerminalCopy(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.TerminalCopy = api;
}(typeof window !== 'undefined' ? window : globalThis, () => {
  async function copyWithFallback(text, documentRef) {
    if (!documentRef?.body || typeof documentRef.execCommand !== 'function') {
      throw new Error('当前浏览器不支持复制');
    }

    const textarea = documentRef.createElement('textarea');
    textarea.value = text;
    textarea.setAttribute('readonly', '');
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    documentRef.body.appendChild(textarea);
    textarea.select();

    try {
      if (!documentRef.execCommand('copy')) throw new Error('复制命令执行失败');
    } finally {
      documentRef.body.removeChild(textarea);
    }
  }

  async function copyText(text, environment = globalThis) {
    const value = String(text || '');
    if (!value) throw new Error('没有可复制的运行结果');

    try {
      if (!environment.navigator?.clipboard?.writeText) throw new Error('Clipboard API unavailable');
      await environment.navigator.clipboard.writeText(value);
      return;
    } catch {
      await copyWithFallback(value, environment.document);
    }
  }

  function copyButtonPresentation(output, status = 'idle') {
    const hasOutput = Boolean(String(output || ''));
    const presentations = {
      success: { symbol: '✓', label: '运行结果已复制' },
      failure: { symbol: '!', label: '复制失败' },
      idle: { symbol: '⧉', label: '复制运行结果' }
    };
    const safeStatus = presentations[status] ? status : 'idle';

    return {
      ...presentations[safeStatus],
      disabled: !hasOutput,
      status: safeStatus
    };
  }

  return { copyButtonPresentation, copyText };
}));
