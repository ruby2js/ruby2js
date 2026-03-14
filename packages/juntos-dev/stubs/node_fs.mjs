// Stub for node:fs — used by rails_server.js for Vite manifest reading
// Not needed in SharedWorker context (no filesystem access)
export function existsSync() { return false; }
export function readFileSync() { return ''; }
export default { existsSync, readFileSync };
