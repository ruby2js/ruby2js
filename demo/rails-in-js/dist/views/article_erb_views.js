// ERB-based article views - auto-generated from .html.erb templates
// Each exported function is a render function that takes { article } or { articles }

import { render as edit_render } from './erb/edit.js';
import { render as index_render } from './erb/index.js';
import { render as list_render } from './erb/list.js';
import { render as new_render } from './erb/new.js';
import { render as show_render } from './erb/show.js';

// Export with API matching ArticleViews
export const ArticleErbViews = {
  edit: edit_render,
  index: index_render,
  list: list_render,
  new: new_render,
  show: show_render,
  // Alias: new_article points to new (matches Ruby module API)
  new_article: new_render
};
