// Browser-compatible loader for @ruby/prism
// The official index.js uses Node.js WASI which isn't available in browsers.
// This provides a browser-compatible loadPrism() function.

import { parsePrism } from './node_modules/@ruby/prism/src/parsePrism.js';

// Re-export visitor and nodes
export * from './node_modules/@ruby/prism/src/visitor.js';
export * from './node_modules/@ruby/prism/src/nodes.js';

/**
 * Load the prism wasm module for browsers and return a parse function.
 * Uses fetch() instead of Node's fs, and browser WASI polyfill.
 */
export async function loadPrism() {
  // Fetch the WASM file
  const wasmUrl = new URL('./node_modules/@ruby/prism/src/prism.wasm', import.meta.url);
  const response = await fetch(wasmUrl);
  const wasmBytes = await response.arrayBuffer();
  const wasm = await WebAssembly.compile(wasmBytes);

  // Minimal WASI implementation for browser
  // Provides all WASI preview1 functions that Prism might need
  const wasiImports = {
    wasi_snapshot_preview1: {
      // Process
      proc_exit: (code) => { throw new Error(`exit(${code})`); },
      sched_yield: () => 0,

      // Arguments
      args_get: () => 0,
      args_sizes_get: (argc, argvBufSize) => {
        const view = new DataView(instance.exports.memory.buffer);
        view.setUint32(argc, 0, true);
        view.setUint32(argvBufSize, 0, true);
        return 0;
      },

      // Environment
      environ_get: () => 0,
      environ_sizes_get: (environCount, environBufSize) => {
        const view = new DataView(instance.exports.memory.buffer);
        view.setUint32(environCount, 0, true);
        view.setUint32(environBufSize, 0, true);
        return 0;
      },

      // Clock
      clock_res_get: () => 0,
      clock_time_get: (id, precision, time) => {
        const view = new DataView(instance.exports.memory.buffer);
        const now = BigInt(Date.now()) * BigInt(1000000);
        view.setBigUint64(time, now, true);
        return 0;
      },

      // File descriptors
      fd_advise: () => 0,
      fd_allocate: () => 0,
      fd_close: () => 0,
      fd_datasync: () => 0,
      fd_fdstat_get: () => 0,
      fd_fdstat_set_flags: () => 0,
      fd_fdstat_set_rights: () => 0,
      fd_filestat_get: () => 0,
      fd_filestat_set_size: () => 0,
      fd_filestat_set_times: () => 0,
      fd_pread: () => 0,
      fd_prestat_get: () => 8, // EBADF - no preopened directories
      fd_prestat_dir_name: () => 0,
      fd_pwrite: () => 0,
      fd_read: () => 0,
      fd_readdir: () => 0,
      fd_renumber: () => 0,
      fd_seek: () => 0,
      fd_sync: () => 0,
      fd_tell: () => 0,
      fd_write: (fd, iovs, iovsLen, nwritten) => {
        // Basic stdout/stderr support (optional, for debugging)
        return 0;
      },

      // Paths
      path_create_directory: () => 0,
      path_filestat_get: () => 0,
      path_filestat_set_times: () => 0,
      path_link: () => 0,
      path_open: () => 0,
      path_readlink: () => 0,
      path_remove_directory: () => 0,
      path_rename: () => 0,
      path_symlink: () => 0,
      path_unlink_file: () => 0,

      // Polling
      poll_oneoff: () => 0,

      // Random
      random_get: (buf, len) => {
        const view = new Uint8Array(instance.exports.memory.buffer, buf, len);
        crypto.getRandomValues(view);
        return 0;
      },

      // Sockets (stub)
      sock_accept: () => 0,
      sock_recv: () => 0,
      sock_send: () => 0,
      sock_shutdown: () => 0,
    }
  };

  let instance;
  instance = await WebAssembly.instantiate(wasm, wasiImports);

  return function (source, options = {}) {
    return parsePrism(instance.exports, source, options);
  };
}
