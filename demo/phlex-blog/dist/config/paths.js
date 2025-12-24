function extract_id(obj) {
  return obj && obj.id || obj
};

function root_path() {
  return "/"
};

function posts_path() {
  return "/posts"
};

function new_post_path() {
  return "/posts/new"
};

function post_path(post) {
  return `/posts/${extract_id(post)}`
};

function edit_post_path(post) {
  return `/posts/${extract_id(post)}/edit`
};

export { extract_id, root_path, posts_path, new_post_path, post_path, edit_post_path }
// Routes configuration - idiomatic Rails