/**
 * ruby2js-astro
 *
 * Astro integration for Ruby2JS - transform .astro.rb files to .astro
 *
 * Usage:
 *   import { defineConfig } from 'astro/config';
 *   import ruby2js from 'ruby2js-astro';
 *
 *   export default defineConfig({
 *     integrations: [ruby2js()]
 *   });
 *
 * This enables writing Astro components in Ruby:
 *
 *   # src/pages/index.astro.rb
 *   @title = "Hello"
 *   @posts = await Astro.glob("./posts/*.md")
 *   __END__
 *   <Layout title={title}>
 *     {posts.map(post => <PostCard post={post} />)}
 *   </Layout>
 */

import { readdir, readFile, writeFile, stat } from 'fs/promises';
import { join, relative } from 'path';
import { fileURLToPath } from 'url';
import { AstroComponentTransformer } from 'ruby2js/astro';
import { ErbPnodeTransformer } from 'ruby2js/erb';
import { convert, initPrism } from 'ruby2js';

// Import filters for JSX transformation
import 'ruby2js/filters/react.js';
import 'ruby2js/filters/jsx.js';
import 'ruby2js/filters/functions.js';
import 'ruby2js/filters/esm.js';
import 'ruby2js/filters/camelCase.js';
import 'ruby2js/filters/return.js';

let prismReady = false;

async function ensurePrism() {
  if (!prismReady) {
    await initPrism();
    prismReady = true;
  }
}

/**
 * Transform a single .astro.rb file to .astro
 */
async function transformAstroFile(filePath, options = {}) {
  const source = await readFile(filePath, 'utf-8');
  const result = AstroComponentTransformer.transform(source, {
    eslevel: 2022,
    camelCase: true,
    autoImports: false,  // Disable auto-importing models - use explicit imports
    ...options
  });

  if (result.errors?.length > 0) {
    const errorMsg = result.errors
      .map(e => typeof e === 'string' ? e : JSON.stringify(e))
      .join(', ');
    throw new Error(`Transform errors in ${filePath}: ${errorMsg}`);
  }

  const outputPath = filePath.replace(/\.astro\.rb$/, '.astro');
  await writeFile(outputPath, result.component);
  return outputPath;
}

/**
 * Transform a single .jsx.rb file to .jsx
 * Uses React + JSX filters to output actual JSX syntax
 */
async function transformJsxFile(filePath, options = {}) {
  const source = await readFile(filePath, 'utf-8');
  const jsxFilters = ['React', 'JSX', 'Functions', 'ESM', 'CamelCase', 'Return'];

  // Use Preact mode by default for Astro islands (can be overridden via options)
  const result = convert(source, {
    filters: jsxFilters,
    eslevel: options.eslevel || 2022,
    react: options.react || 'Preact',
    file: filePath,
    ...options
  });

  const outputPath = filePath.replace(/\.jsx\.rb$/, '.jsx');
  await writeFile(outputPath, result.toString());
  return outputPath;
}

/**
 * Transform a single .erb.rb file to .jsx
 * Uses ErbPnodeTransformer for ERB-style templates
 */
async function transformErbFile(filePath, options = {}) {
  const source = await readFile(filePath, 'utf-8');
  const result = ErbPnodeTransformer.transform(source, {
    eslevel: options.eslevel || 2022,
    react: options.react || 'Preact',
    ...options
  });

  if (result.errors?.length > 0) {
    const errorMsg = result.errors
      .map(e => typeof e === 'string' ? e : (e.message || JSON.stringify(e)))
      .join(', ');
    throw new Error(`Transform errors in ${filePath}: ${errorMsg}`);
  }

  const outputPath = filePath.replace(/\.erb\.rb$/, '.jsx');
  await writeFile(outputPath, result.component);
  return outputPath;
}

// Backward compatibility alias
const transformFile = transformAstroFile;

/**
 * Recursively find all .astro.rb files in a directory
 */
async function findAstroRbFiles(dir) {
  const files = [];

  async function walk(currentDir) {
    let entries;
    try {
      entries = await readdir(currentDir, { withFileTypes: true });
    } catch {
      return; // Directory doesn't exist or not readable
    }

    for (const entry of entries) {
      const fullPath = join(currentDir, entry.name);
      if (entry.isDirectory()) {
        await walk(fullPath);
      } else if (entry.name.endsWith('.astro.rb')) {
        files.push(fullPath);
      }
    }
  }

  await walk(dir);
  return files;
}

/**
 * Recursively find all .jsx.rb files in a directory
 */
async function findJsxRbFiles(dir) {
  const files = [];

  async function walk(currentDir) {
    let entries;
    try {
      entries = await readdir(currentDir, { withFileTypes: true });
    } catch {
      return; // Directory doesn't exist or not readable
    }

    for (const entry of entries) {
      const fullPath = join(currentDir, entry.name);
      if (entry.isDirectory()) {
        await walk(fullPath);
      } else if (entry.name.endsWith('.jsx.rb')) {
        files.push(fullPath);
      }
    }
  }

  await walk(dir);
  return files;
}

/**
 * Recursively find all .erb.rb files in a directory
 */
async function findErbRbFiles(dir) {
  const files = [];

  async function walk(currentDir) {
    let entries;
    try {
      entries = await readdir(currentDir, { withFileTypes: true });
    } catch {
      return; // Directory doesn't exist or not readable
    }

    for (const entry of entries) {
      const fullPath = join(currentDir, entry.name);
      if (entry.isDirectory()) {
        await walk(fullPath);
      } else if (entry.name.endsWith('.erb.rb')) {
        files.push(fullPath);
      }
    }
  }

  await walk(dir);
  return files;
}

/**
 * Transform all .astro.rb, .jsx.rb, and .erb.rb files in the src directory
 */
async function transformAll(srcDir, options = {}, logger = console) {
  await ensurePrism();

  const astroFiles = await findAstroRbFiles(srcDir);
  const jsxFiles = await findJsxRbFiles(srcDir);
  const erbFiles = await findErbRbFiles(srcDir);

  if (astroFiles.length === 0 && jsxFiles.length === 0 && erbFiles.length === 0) {
    return [];
  }

  const transformed = [];

  // Transform .astro.rb files
  for (const file of astroFiles) {
    try {
      const outputPath = await transformAstroFile(file, options);
      transformed.push({ input: file, output: outputPath, type: 'astro' });
      logger.info?.(`  ${relative(srcDir, file)} → ${relative(srcDir, outputPath)}`);
    } catch (error) {
      logger.error?.(`  Error transforming ${file}: ${error.message}`);
      throw error;
    }
  }

  // Transform .jsx.rb files
  for (const file of jsxFiles) {
    try {
      const outputPath = await transformJsxFile(file, options);
      transformed.push({ input: file, output: outputPath, type: 'jsx' });
      logger.info?.(`  ${relative(srcDir, file)} → ${relative(srcDir, outputPath)}`);
    } catch (error) {
      logger.error?.(`  Error transforming ${file}: ${error.message}`);
      throw error;
    }
  }

  // Transform .erb.rb files (ERB-style templates)
  for (const file of erbFiles) {
    try {
      const outputPath = await transformErbFile(file, options);
      transformed.push({ input: file, output: outputPath, type: 'erb' });
      logger.info?.(`  ${relative(srcDir, file)} → ${relative(srcDir, outputPath)}`);
    } catch (error) {
      logger.error?.(`  Error transforming ${file}: ${error.message}`);
      throw error;
    }
  }

  return transformed;
}

/**
 * Create the Astro integration
 */
export default function ruby2jsIntegration(options = {}) {
  let srcDir;
  let logger;
  let transformedFiles = [];

  return {
    name: 'ruby2js-astro',

    hooks: {
      'astro:config:setup': async ({ config, command, updateConfig, addWatchFile, logger: astroLogger }) => {
        logger = astroLogger;
        srcDir = fileURLToPath(new URL('./src', config.root));

        logger.info('ruby2js: Transforming .astro.rb files...');

        try {
          transformedFiles = await transformAll(srcDir, options, logger);
          logger.info(`ruby2js: Transformed ${transformedFiles.length} file(s)`);
        } catch (error) {
          logger.error(`ruby2js: Transform failed: ${error.message}`);
          throw error;
        }

        // In dev mode, watch the .astro.rb files for changes
        if (command === 'dev') {
          for (const { input } of transformedFiles) {
            addWatchFile(input);
          }
        }

        // Add vite plugin for handling imports and HMR
        updateConfig({
          vite: {
            plugins: [{
              name: 'ruby2js-astro-watcher',
              async handleHotUpdate({ file, server }) {
                if (file.endsWith('.astro.rb')) {
                  logger.info(`ruby2js: Re-transforming ${relative(srcDir, file)}`);
                  try {
                    await ensurePrism();
                    await transformAstroFile(file, options);
                    // Trigger reload of the .astro file
                    const astroFile = file.replace(/\.astro\.rb$/, '.astro');
                    const mod = server.moduleGraph.getModuleById(astroFile);
                    if (mod) {
                      server.moduleGraph.invalidateModule(mod);
                      return [mod];
                    }
                  } catch (error) {
                    logger.error(`ruby2js: Transform error: ${error.message}`);
                  }
                } else if (file.endsWith('.jsx.rb')) {
                  logger.info(`ruby2js: Re-transforming ${relative(srcDir, file)}`);
                  try {
                    await ensurePrism();
                    await transformJsxFile(file, options);
                    // Trigger reload of the .jsx file
                    const jsxFile = file.replace(/\.jsx\.rb$/, '.jsx');
                    const mod = server.moduleGraph.getModuleById(jsxFile);
                    if (mod) {
                      server.moduleGraph.invalidateModule(mod);
                      return [mod];
                    }
                  } catch (error) {
                    logger.error(`ruby2js: Transform error: ${error.message}`);
                  }
                } else if (file.endsWith('.erb.rb')) {
                  logger.info(`ruby2js: Re-transforming ${relative(srcDir, file)}`);
                  try {
                    await ensurePrism();
                    await transformErbFile(file, options);
                    // Trigger reload of the .jsx file (erb.rb outputs .jsx)
                    const jsxFile = file.replace(/\.erb\.rb$/, '.jsx');
                    const mod = server.moduleGraph.getModuleById(jsxFile);
                    if (mod) {
                      server.moduleGraph.invalidateModule(mod);
                      return [mod];
                    }
                  } catch (error) {
                    logger.error(`ruby2js: Transform error: ${error.message}`);
                  }
                }
              },
              configureServer(server) {
                // Watch for new .astro.rb and .jsx.rb files
                server.watcher.on('add', async (file) => {
                  if (file.endsWith('.astro.rb')) {
                    logger.info(`ruby2js: New file ${relative(srcDir, file)}`);
                    try {
                      await ensurePrism();
                      await transformAstroFile(file, options);
                    } catch (error) {
                      logger.error(`ruby2js: Transform error: ${error.message}`);
                    }
                  } else if (file.endsWith('.jsx.rb')) {
                    logger.info(`ruby2js: New file ${relative(srcDir, file)}`);
                    try {
                      await ensurePrism();
                      await transformJsxFile(file, options);
                    } catch (error) {
                      logger.error(`ruby2js: Transform error: ${error.message}`);
                    }
                  } else if (file.endsWith('.erb.rb')) {
                    logger.info(`ruby2js: New file ${relative(srcDir, file)}`);
                    try {
                      await ensurePrism();
                      await transformErbFile(file, options);
                    } catch (error) {
                      logger.error(`ruby2js: Transform error: ${error.message}`);
                    }
                  }
                });
              }
            }]
          }
        });
      },

      'astro:build:start': async () => {
        // Re-transform before production build to ensure files are fresh
        logger.info('ruby2js: Preparing for build...');
        try {
          transformedFiles = await transformAll(srcDir, options, logger);
          logger.info(`ruby2js: Ready (${transformedFiles.length} file(s))`);
        } catch (error) {
          logger.error(`ruby2js: Build preparation failed: ${error.message}`);
          throw error;
        }
      }
    }
  };
}

// Named exports
export { ruby2jsIntegration as ruby2js };
export { transformFile, transformAstroFile, transformJsxFile, transformErbFile, findAstroRbFiles, findJsxRbFiles, findErbRbFiles, transformAll };
