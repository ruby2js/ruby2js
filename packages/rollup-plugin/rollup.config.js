import { nodeResolve } from '@rollup/plugin-node-resolve';
import replace from '@rollup/plugin-replace';
import commonjs from '@rollup/plugin-commonjs';
import ruby2js from '@ruby2js/rollup-plugin';

const env = process.env.NODE_ENV || 'development';

export default {
  input: 'markdown.js.rb',

  output: {
    file: 'bundle.js',
    format: 'iife'
  },

  plugins: [
    nodeResolve(),

    commonjs(),

    replace({
      preventAssignment: true,
      values: {
        'process.env.NODE_ENV': JSON.stringify(env)
      }
    }),

    ruby2js({
      eslevel: 2021,
      filters: ['react', 'esm', 'functions']
    })
  ]
}
