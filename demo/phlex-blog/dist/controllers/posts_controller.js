import { Post } from "../models/post.js";
import { PostViews } from "../views/posts.js";

export const PostsController = (() => {
  async function index() {
    let posts = await Post.all();
    return PostViews.index({posts})
  };

  async function show(id) {
    let post = await Post.find(id);
    return PostViews.show({post})
  };

  async function $new() {
    let post = new Post;
    return PostViews.$new({post})
  };

  async function create(params) {
    let post = new Post(params);
    return await post.save() ? {redirect: `/posts/${post.id}`} : {render: "new_article"}
  };

  async function edit(id) {
    let post = await Post.find(id);
    return PostViews.edit({post})
  };

  async function update(id, params) {
    let post = await Post.find(id);
    return await post.update(params) ? {redirect: `/posts/${post.id}`} : {render: "edit"}
  };

  async function destroy(id) {
    let post = await Post.find(id);
    await post.destroy();
    return {redirect: "/postss"}
  };

  return {index, show, $new, create, edit, update, destroy}
})()
//# sourceMappingURL=posts_controller.js.map
