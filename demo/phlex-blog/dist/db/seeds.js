import { Post } from "../models/index.js";

export const Seeds = (() => {
  async function run() {
    // Only seed if no posts exist
    if ((await Post.all()).length > 0) return;

    await Post.create({
      title: "Welcome to Phlex Blog",
      body: "This is a demo blog built with Ruby2JS and Phlex. It demonstrates how to build complete applications that run entirely in the browser using familiar Rails patterns.",
      author: "Admin"
    });

    await Post.create({
      title: "Getting Started with Phlex",
      body: "Phlex is a Ruby gem for building fast, reusable view components. When combined with Ruby2JS, you can write your views in Ruby and run them in the browser with the same component patterns you know and love.",
      author: "Developer"
    });

    await Post.create({
      title: "Component-Based Architecture",
      body: "Building applications with components makes code more maintainable and reusable. This blog uses a component architecture inspired by Rails patterns, demonstrating how Phlex views work seamlessly with Ruby2JS transpilation.",
      author: "Architect"
    })
  };

  return {run}
})()
//# sourceMappingURL=seeds.js.map
