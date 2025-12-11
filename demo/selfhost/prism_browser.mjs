import { parsePrism } from "./node_modules/@ruby/prism/src/parsePrism.js";
export * from "./node_modules/@ruby/prism/src/visitor.js";
export * from "./node_modules/@ruby/prism/src/nodes.js";

export async function loadPrism() {
  let wasmUrl = new URL("./node_modules/@ruby/prism/src/prism.wasm", import.meta.url);
  let response = await fetch(wasmUrl);
  let wasmBytes = await response.arrayBuffer();
  let wasm = await WebAssembly.compile(wasmBytes);

  let wasiImports = {wasi_snapshot_preview1: {
    proc_exit(code) {
      return (() => { throw `exit(${code})` })()
    },

    sched_yield() {
      return 0
    },

    args_get() {
      return 0
    },

    args_sizes_get(argc, argvBufSize) {
      let view = new DataView(instance.exports.memory.buffer);
      view.setUint32(argc, 0, true);
      view.setUint32(argvBufSize, 0, true);
      return 0
    },

    environ_get() {
      return 0
    },

    environ_sizes_get(environCount, environBufSize) {
      let view = new DataView(instance.exports.memory.buffer);
      view.setUint32(environCount, 0, true);
      view.setUint32(environBufSize, 0, true);
      return 0
    },

    clock_res_get() {
      return 0
    },

    clock_time_get(id, precision, time) {
      let view = new DataView(instance.exports.memory.buffer);
      let now = BigInt(Date.now()) * BigInt(1_000_000);
      view.setBigUint64(time, now, true);
      return 0
    },

    fd_advise() {
      return 0
    },

    fd_allocate() {
      return 0
    },

    fd_close() {
      return 0
    },

    fd_datasync() {
      return 0
    },

    fd_fdstat_get() {
      return 0
    },

    fd_fdstat_set_flags() {
      return 0
    },

    fd_fdstat_set_rights() {
      return 0
    },

    fd_filestat_get() {
      return 0
    },

    fd_filestat_set_size() {
      return 0
    },

    fd_filestat_set_times() {
      return 0
    },

    fd_pread() {
      return 0
    },

    fd_prestat_get() {
      return 8
    },

    fd_prestat_dir_name() {
      return 0
    },

    fd_pwrite() {
      return 0
    },

    fd_read() {
      return 0
    },

    fd_readdir() {
      return 0
    },

    fd_renumber() {
      return 0
    },

    fd_seek() {
      return 0
    },

    fd_sync() {
      return 0
    },

    fd_tell() {
      return 0
    },

    fd_write(fd, iovs, iovsLen, nwritten) {
      return 0
    },

    path_create_directory() {
      return 0
    },

    path_filestat_get() {
      return 0
    },

    path_filestat_set_times() {
      return 0
    },

    path_link() {
      return 0
    },

    path_open() {
      return 0
    },

    path_readlink() {
      return 0
    },

    path_remove_directory() {
      return 0
    },

    path_rename() {
      return 0
    },

    path_symlink() {
      return 0
    },

    path_unlink_file() {
      return 0
    },

    poll_oneoff() {
      return 0
    },

    random_get(buf, len) {
      let view = new Uint8Array(instance.exports.memory.buffer, buf, len);
      crypto.getRandomValues(view);
      return 0
    },

    sock_accept() {
      return 0
    },

    sock_recv() {
      return 0
    },

    sock_send() {
      return 0
    },

    sock_shutdown() {
      return 0
    }
  }};

  let instance = await WebAssembly.instantiate(wasm, wasiImports);
  return (source, options={}) => parsePrism(instance.exports, source, options)
};

// Browser-compatible loader for @ruby/prism
// The official index.js uses Node.js WASI which isn't available in browsers.
// This provides a browser-compatible loadPrism() function.
// Load the prism wasm module for browsers and return a parse function.
// Uses fetch() instead of Node's fs, and browser WASI polyfill.
// Fetch the WASM file
// Minimal WASI implementation for browser
// Provides all WASI preview1 functions that Prism might need
// Process
// Arguments
// Environment
// Clock
// File descriptors
// EBADF - no preopened directories
// Paths
// Polling
// Random
// Sockets (stub)
// Export Prism namespace object with loadPrism method
// This allows runtime.mjs to use `await Prism.loadPrism()` in browser
const Prism = {loadPrism};
export { Prism }
