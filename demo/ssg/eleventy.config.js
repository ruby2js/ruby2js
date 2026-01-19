/**
 * 11ty Configuration for Ruby2JS SSG Demo
 *
 * This demo shows Ruby authoring with:
 * - ActiveRecord-like queries over markdown content
 * - Liquid templates with Ruby expressions
 */

export default function(eleventyConfig) {
  // Copy static assets
  eleventyConfig.addPassthroughCopy("src/css");
  eleventyConfig.addPassthroughCopy("src/js");

  // Watch for changes in content
  eleventyConfig.addWatchTarget("content/");

  // Configure Liquid options
  eleventyConfig.setLiquidOptions({
    dynamicPartials: true,
    strictFilters: false
  });

  return {
    dir: {
      input: "src",
      output: "_site",
      includes: "_includes",
      data: "_data"
    },
    templateFormats: ["liquid", "md", "html"],
    htmlTemplateEngine: "liquid",
    markdownTemplateEngine: "liquid"
  };
}
