# Articles controller - SPA-friendly version
# Uses direct model/view calls instead of Rails conventions

import [Article], '../models/article.js'
import [ArticleViews], '../views/articles.js'

export module ArticlesController
  def self.list
    articles = Article.all
    ArticleViews.list({ articles: articles })
  end

  def self.show(id)
    article = Article.find(id)
    ArticleViews.show({ article: article })
  end

  def self.new_form
    article = { title: '', body: '', errors: [] }
    ArticleViews.new_article({ article: article })
  end

  def self.edit(id)
    article = Article.find(id)
    ArticleViews.edit({ article: article })
  end

  def self.create(title, body)
    article = Article.create({ title: title, body: body })
    if article.id
      { success: true, id: article.id }
    else
      { success: false, html: ArticleViews.new_article({ article: article }) }
    end
  end

  def self.update(id, title, body)
    article = Article.find(id)
    article.title = title
    article.body = body
    if article.save
      { success: true, id: article.id }
    else
      { success: false, html: ArticleViews.edit({ article: article }) }
    end
  end

  def self.destroy(id)
    article = Article.find(id)
    article.destroy
    { success: true }
  end
end
