Things left to be done:

 * Verify performance/scalability.  There potentially is a very good story
   here as snowpack transforms inputs concurrently/asynchronously enabling the
   Rack server to make use of multiple processes and therefore multiple
   cores.
 * Verify robustness.  This is both recovery from errors and usability
   of error messages.
 * Follow sourcemap support in snowpack and integrate with it.
   Example: https://github.com/snowpackjs/snowpack/discussions/1103
 * build an npm package for the plugin
