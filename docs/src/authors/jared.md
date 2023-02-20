---
layout: default
title: Jared White
paginate:
  collection: posts
---

{% rendercontent "shared/page_layout" %}
  <h1 class="mt-3 mb-10 title is-1 has-text-centered has-text-brown">{{ page.title }}</h1>

  <p class="content has-text-centered">Follow me on my <a href="https://jaredwhite.com">Website</a> / <a href="https://indieweb.social/@jaredwhite">Mastodon</a></p>

  {% for post in paginator.resources %}
    {% if post.data.author == "jared" %}
    {% render "content/news_item", post: post, authors: site.data.authors %}
    {% endif %}
  {% endfor %}

  {% render "shared/pagination", paginator: paginator %}
{% endrendercontent %}