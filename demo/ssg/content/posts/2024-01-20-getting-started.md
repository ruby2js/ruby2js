---
title: Getting Started with Ruby2JS
date: 2024-01-20
author: sam
draft: false
tags: [ruby, tutorial]
excerpt: Learn how to set up Ruby2JS for your static site.
---

Let's walk through setting up Ruby2JS for your static site generator.

## Installation

First, install the required packages:

```bash
npm install @ruby2js/content-adapter vite-plugin-ruby2js
```

## Configuration

Create your `eleventy.config.js`:

```javascript
export default function(eleventyConfig) {
  // Your config here
}
```

## Content Structure

Organize your content in directories:

```
content/
  posts/
    2024-01-15-welcome.md
  authors/
    sam.md
```

That's it! You're ready to start writing Ruby.
