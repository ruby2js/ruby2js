# Database seeds - idiomatic Rails
# Seeds the database with sample data for development

module Seeds
  def self.run
    # Only seed if no articles exist
    return if Article.all.length > 0

    article1 = Article.create({
      title: 'Hello Rails',
      body: 'I am on Rails! This is my first blog post using the Ruby2JS-on-Rails demo. It demonstrates that you can write Ruby code that transpiles to JavaScript and runs entirely in the browser.'
    })

    article2 = Article.create({
      title: 'Getting Started with Ruby2JS',
      body: 'Ruby2JS is a Ruby to JavaScript transpiler. It parses Ruby source code and generates equivalent JavaScript. This demo shows how you can build a full Rails-like application that runs in JavaScript.'
    })

    Comment.create({
      article_id: article1.id,
      commenter: 'Alice',
      body: 'Great post! Welcome to the world of Ruby2JS-on-Rails.',
      status: 'approved'
    })

    Comment.create({
      article_id: article1.id,
      commenter: 'Bob',
      body: 'This is really cool. Looking forward to more posts!',
      status: 'approved'
    })
  end
end
