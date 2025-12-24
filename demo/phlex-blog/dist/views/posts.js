import PostsIndexView from "../components/posts_index_view.js";
import PostsShowView from "../components/posts_show_view.js";
import PostsNewView from "../components/posts_new_view.js";
import PostsEditView from "../components/posts_edit_view.js";

export const PostViews = (() => {
  function index(props) {
    let view = new PostsIndexView({posts: props.posts});
    return view.view_template
  };

  function show(props) {
    let view = new PostsShowView({post: props.post});
    return view.view_template
  };

  function $new(props) {
    let view = new PostsNewView({post: props.post});
    return view.view_template
  };

  function edit(props) {
    let view = new PostsEditView({post: props.post});
    return view.view_template
  };

  return {index, show, $new, edit}
})()
//# sourceMappingURL=posts.js.map
