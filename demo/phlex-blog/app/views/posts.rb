# Posts views - wraps Phlex components for controller compatibility
# Each method instantiates and renders a Phlex view component

import PostsIndexView, "../components/posts_index_view.js"
import PostsShowView, "../components/posts_show_view.js"
import PostsNewView, "../components/posts_new_view.js"
import PostsEditView, "../components/posts_edit_view.js"

export module PostViews
  def self.index(props)
    view = PostsIndexView.new(posts: props[:posts])
    return view.view_template
  end

  def self.show(props)
    view = PostsShowView.new(post: props[:post])
    return view.view_template
  end

  def self.new(props)
    view = PostsNewView.new(post: props[:post])
    return view.view_template
  end

  def self.edit(props)
    view = PostsEditView.new(post: props[:post])
    return view.view_template
  end
end
