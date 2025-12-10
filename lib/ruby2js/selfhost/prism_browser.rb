# Browser-compatible loader for @ruby/prism
# The official index.js uses Node.js WASI which isn't available in browsers.
# This provides a browser-compatible loadPrism() function.

import parsePrism, './node_modules/@ruby/prism/src/parsePrism.js'

export "*", from: './node_modules/@ruby/prism/src/visitor.js'
export "*", from: './node_modules/@ruby/prism/src/nodes.js'

# Load the prism wasm module for browsers and return a parse function.
# Uses fetch() instead of Node's fs, and browser WASI polyfill.
export async def loadPrism
  # Fetch the WASM file
  wasmUrl = URL.new('./node_modules/@ruby/prism/src/prism.wasm', import.meta.url)
  response = await fetch(wasmUrl)
  wasmBytes = await response.arrayBuffer()
  wasm = await WebAssembly.compile(wasmBytes)

  # Minimal WASI implementation for browser
  # Provides all WASI preview1 functions that Prism might need
  wasiImports = {
    wasi_snapshot_preview1: {
      # Process
      proc_exit: ->(code) { raise "exit(#{code})" },
      sched_yield: -> { 0 },

      # Arguments
      args_get: -> { 0 },
      args_sizes_get: ->(argc, argvBufSize) do
        view = DataView.new(instance.exports.memory.buffer)
        view.setUint32(argc, 0, true)
        view.setUint32(argvBufSize, 0, true)
        0
      end,

      # Environment
      environ_get: -> { 0 },
      environ_sizes_get: ->(environCount, environBufSize) do
        view = DataView.new(instance.exports.memory.buffer)
        view.setUint32(environCount, 0, true)
        view.setUint32(environBufSize, 0, true)
        0
      end,

      # Clock
      clock_res_get: -> { 0 },
      clock_time_get: ->(id, precision, time) do
        view = DataView.new(instance.exports.memory.buffer)
        now = BigInt(Date.now()) * BigInt(1000000)
        view.setBigUint64(time, now, true)
        0
      end,

      # File descriptors
      fd_advise: -> { 0 },
      fd_allocate: -> { 0 },
      fd_close: -> { 0 },
      fd_datasync: -> { 0 },
      fd_fdstat_get: -> { 0 },
      fd_fdstat_set_flags: -> { 0 },
      fd_fdstat_set_rights: -> { 0 },
      fd_filestat_get: -> { 0 },
      fd_filestat_set_size: -> { 0 },
      fd_filestat_set_times: -> { 0 },
      fd_pread: -> { 0 },
      fd_prestat_get: -> { 8 }, # EBADF - no preopened directories
      fd_prestat_dir_name: -> { 0 },
      fd_pwrite: -> { 0 },
      fd_read: -> { 0 },
      fd_readdir: -> { 0 },
      fd_renumber: -> { 0 },
      fd_seek: -> { 0 },
      fd_sync: -> { 0 },
      fd_tell: -> { 0 },
      fd_write: ->(fd, iovs, iovsLen, nwritten) { 0 },

      # Paths
      path_create_directory: -> { 0 },
      path_filestat_get: -> { 0 },
      path_filestat_set_times: -> { 0 },
      path_link: -> { 0 },
      path_open: -> { 0 },
      path_readlink: -> { 0 },
      path_remove_directory: -> { 0 },
      path_rename: -> { 0 },
      path_symlink: -> { 0 },
      path_unlink_file: -> { 0 },

      # Polling
      poll_oneoff: -> { 0 },

      # Random
      random_get: ->(buf, len) do
        view = Uint8Array.new(instance.exports.memory.buffer, buf, len)
        crypto.getRandomValues(view)
        0
      end,

      # Sockets (stub)
      sock_accept: -> { 0 },
      sock_recv: -> { 0 },
      sock_send: -> { 0 },
      sock_shutdown: -> { 0 }
    }
  }

  instance = await WebAssembly.instantiate(wasm, wasiImports)

  ->(source, options = {}) do
    parsePrism(instance.exports, source, options)
  end
end
