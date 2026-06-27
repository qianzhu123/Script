(function exposeRunSessionStore(root, factory) {
  const exported = factory();
  if (typeof module === 'object' && module.exports) module.exports = exported;
  if (root) root.RunSessionStore = exported.RunSessionStore;
}(typeof globalThis !== 'undefined' ? globalThis : this, function createModule() {
  class RunSessionStore {
    constructor() {
      this.items = new Map();
      this.selectedId = null;
      this.sequence = 0;
    }

    create({ scriptId, name, admin = false }) {
      const id = `run-${Date.now().toString(36)}-${(++this.sequence).toString(36)}`;
      const session = {
        id,
        scriptId,
        name,
        admin,
        output: '',
        status: 'running',
        socket: null,
        startedAt: new Date().toISOString()
      };
      this.items.set(id, session);
      this.selectedId = id;
      return session;
    }

    list() {
      return [...this.items.values()];
    }

    get(id) {
      return this.items.get(id) || null;
    }

    selected() {
      return this.get(this.selectedId);
    }

    select(id) {
      if (this.items.has(id)) this.selectedId = id;
      return this.selected();
    }

    append(id, text) {
      const session = this.get(id);
      if (session) session.output += String(text);
      return session;
    }

    setStatus(id, status) {
      const session = this.get(id);
      if (session) session.status = status;
      return session;
    }

    setSocket(id, socket) {
      const session = this.get(id);
      if (session) session.socket = socket;
      return session;
    }

    remove(id) {
      if (!this.items.delete(id)) return null;
      if (this.selectedId === id) {
        const remaining = this.list();
        this.selectedId = remaining.length ? remaining[remaining.length - 1].id : null;
      }
      return this.selected();
    }
  }

  return { RunSessionStore };
}));
