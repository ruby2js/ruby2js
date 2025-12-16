require 'minitest/autorun'
require 'ruby2js/inflector'

describe Ruby2JS::Inflector do
  describe 'singularize' do
    it "handles regular plurals" do
      _(Ruby2JS::Inflector.singularize('articles')).must_equal 'article'
      _(Ruby2JS::Inflector.singularize('comments')).must_equal 'comment'
      _(Ruby2JS::Inflector.singularize('users')).must_equal 'user'
      _(Ruby2JS::Inflector.singularize('posts')).must_equal 'post'
    end

    it "handles irregular plurals" do
      _(Ruby2JS::Inflector.singularize('people')).must_equal 'person'
      _(Ruby2JS::Inflector.singularize('men')).must_equal 'man'
      _(Ruby2JS::Inflector.singularize('women')).must_equal 'woman'
      _(Ruby2JS::Inflector.singularize('children')).must_equal 'child'
    end

    it "preserves capitalization for irregulars" do
      _(Ruby2JS::Inflector.singularize('People')).must_equal 'Person'
      _(Ruby2JS::Inflector.singularize('Children')).must_equal 'Child'
    end

    it "handles words ending in -ies" do
      _(Ruby2JS::Inflector.singularize('categories')).must_equal 'category'
      _(Ruby2JS::Inflector.singularize('queries')).must_equal 'query'
      _(Ruby2JS::Inflector.singularize('stories')).must_equal 'story'
    end

    it "handles words ending in -es" do
      _(Ruby2JS::Inflector.singularize('boxes')).must_equal 'box'
      _(Ruby2JS::Inflector.singularize('matches')).must_equal 'match'
      _(Ruby2JS::Inflector.singularize('wishes')).must_equal 'wish'
      _(Ruby2JS::Inflector.singularize('buses')).must_equal 'bus'
    end

    it "handles words ending in -ves" do
      _(Ruby2JS::Inflector.singularize('knives')).must_equal 'knife'
      _(Ruby2JS::Inflector.singularize('wives')).must_equal 'wife'
      _(Ruby2JS::Inflector.singularize('halves')).must_equal 'half'
      _(Ruby2JS::Inflector.singularize('wolves')).must_equal 'wolf'
    end

    it "handles special cases" do
      _(Ruby2JS::Inflector.singularize('databases')).must_equal 'database'
      _(Ruby2JS::Inflector.singularize('quizzes')).must_equal 'quiz'
      _(Ruby2JS::Inflector.singularize('matrices')).must_equal 'matrix'
      _(Ruby2JS::Inflector.singularize('indices')).must_equal 'index'
      _(Ruby2JS::Inflector.singularize('statuses')).must_equal 'status'
      _(Ruby2JS::Inflector.singularize('aliases')).must_equal 'alias'
    end

    it "handles uncountables" do
      _(Ruby2JS::Inflector.singularize('equipment')).must_equal 'equipment'
      _(Ruby2JS::Inflector.singularize('information')).must_equal 'information'
      _(Ruby2JS::Inflector.singularize('fish')).must_equal 'fish'
      _(Ruby2JS::Inflector.singularize('sheep')).must_equal 'sheep'
    end

    it "handles -ss words (doesn't strip s)" do
      _(Ruby2JS::Inflector.singularize('class')).must_equal 'class'
      _(Ruby2JS::Inflector.singularize('address')).must_equal 'address'
    end

    it "handles news" do
      _(Ruby2JS::Inflector.singularize('news')).must_equal 'news'
    end

    it "handles -ouse/-ice" do
      _(Ruby2JS::Inflector.singularize('mice')).must_equal 'mouse'
      _(Ruby2JS::Inflector.singularize('lice')).must_equal 'louse'
    end
  end
end
