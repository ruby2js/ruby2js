# Articles controller using ERB-transpiled views
# Identical to articles_controller.rb but uses ArticleErbViews

import [Article], '../models/article.js'
import [ArticleErbViews], '../views/article_erb_views.js'

export module ArticlesErbController
  def self.list
    articles = Article.all
    ArticleErbViews.list({ articles: articles })
  end

  def self.show(id)
    article = Article.find(id)
    ArticleErbViews.show({ article: article })
  end

  def self.new_form
    article = { title: '', body: '', errors: [] }
    ArticleErbViews.new_article({ article: article })
  end

  def self.edit(id)
    article = Article.find(id)
    ArticleErbViews.edit({ article: article })
  end

  def self.create(title, body)
    article = Article.create({ title: title, body: body })
    if article.id
      { success: true, id: article.id }
    else
      { success: false, html: ArticleErbViews.new_article({ article: article }) }
    end
  end

  def self.update(id, title, body)
    article = Article.find(id)
    article.title = title
    article.body = body
    if article.save
      { success: true, id: article.id }
    else
      { success: false, html: ArticleErbViews.edit({ article: article }) }
    end
  end

  def self.destroy(id)
    article = Article.find(id)
    article.destroy
    { success: true }
  end
end
