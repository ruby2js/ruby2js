export class NavComponent extends Phlex.HTML {
  render() {
    let _phlex_out = "";
    _phlex_out += "<nav class=\"site-nav\"><div class=\"nav-brand\"><a href=\"/\" onclick=\"return navigate(event, '/')\" class=\"brand-link\">Phlex Blog</a></div><div class=\"nav-links\"><a href=\"/posts\" onclick=\"return navigate(event, '/posts')\" class=\"nav-link\">Posts</a><a href=\"/posts/new\" onclick=\"return navigate(event, '/posts/new')\" class=\"nav-link\">New Post</a></div></nav>";
    return _phlex_out
  }
}
//# sourceMappingURL=nav_component.js.map
