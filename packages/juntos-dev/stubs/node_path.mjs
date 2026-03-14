// Stub for node:path — used by rails_server.js for Vite manifest reading
// Not needed in SharedWorker context (no filesystem access)
export function join(...args) { return args.join('/'); }
export function dirname(p) { return p.replace(/\/[^/]*$/, ''); }
export default { join, dirname };
