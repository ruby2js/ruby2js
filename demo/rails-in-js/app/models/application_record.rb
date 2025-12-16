# Base class for all models
# Transpiled to JavaScript, runs on sql.js
class ApplicationRecord
  class << self
    attr_accessor :table_name, :columns

    def inherited(subclass)
      subclass.table_name = subclass.name.downcase + 's'
      subclass.columns = []
    end
  end

  attr_accessor :id, :attributes, :errors

  def initialize(attrs = {})
    @attributes = {}
    @errors = []
    @persisted = false

    attrs.each do |key, value|
      @attributes[key.to_s] = value
      @id = value if key.to_s == 'id'
    end

    @persisted = true if @id
  end

  # Class methods
  def self.all
    sql = "SELECT * FROM #{table_name}"
    results = DB.exec(sql)
    return [] unless results.length > 0
    result_to_models(results[0])
  end

  def self.find(id)
    stmt = DB.prepare("SELECT * FROM #{table_name} WHERE id = ?")
    stmt.bind([id])
    if stmt.step
      obj = stmt.getAsObject
      stmt.free
      new(obj)
    else
      stmt.free
      raise "#{name} not found with id=#{id}"
    end
  end

  def self.find_by(conditions)
    where_clause, values = build_where(conditions)
    stmt = DB.prepare("SELECT * FROM #{table_name} WHERE #{where_clause} LIMIT 1")
    stmt.bind(values)
    if stmt.step
      obj = stmt.getAsObject
      stmt.free
      new(obj)
    else
      stmt.free
      nil
    end
  end

  def self.where(conditions)
    where_clause, values = build_where(conditions)
    stmt = DB.prepare("SELECT * FROM #{table_name} WHERE #{where_clause}")
    stmt.bind(values)
    results = []
    while stmt.step
      results << new(stmt.getAsObject)
    end
    stmt.free
    results
  end

  def self.create(attrs)
    record = new(attrs)
    record.save
    record
  end

  def self.count
    result = DB.exec("SELECT COUNT(*) FROM #{table_name}")
    result[0].values[0][0]
  end

  def self.first
    result = DB.exec("SELECT * FROM #{table_name} ORDER BY id ASC LIMIT 1")
    return nil unless result.length > 0 && result[0].values.length > 0
    result_to_models(result[0])[0]
  end

  def self.last
    result = DB.exec("SELECT * FROM #{table_name} ORDER BY id DESC LIMIT 1")
    return nil unless result.length > 0 && result[0].values.length > 0
    result_to_models(result[0])[0]
  end

  # Instance methods
  def persisted?
    @persisted
  end

  def new_record?
    !@persisted
  end

  def save
    return false unless valid?

    if @persisted
      do_update
    else
      do_insert
    end
  end

  def update(attrs)
    attrs.each do |key, value|
      @attributes[key.to_s] = value
    end
    save
  end

  def destroy
    return false unless @persisted
    DB.run("DELETE FROM #{self.class.table_name} WHERE id = ?", [@id])
    @persisted = false
    true
  end

  def valid?
    @errors = []
    validate
    @errors.empty?
  end

  def validate
    # Override in subclasses
  end

  # Validation helpers
  def validates_presence_of(field)
    value = @attributes[field.to_s]
    if value.nil? || value.to_s.strip.empty?
      @errors << "#{field} can't be blank"
    end
  end

  def validates_length_of(field, options)
    value = @attributes[field.to_s].to_s
    if options[:minimum] && value.length < options[:minimum]
      @errors << "#{field} is too short (minimum is #{options[:minimum]} characters)"
    end
  end

  private

  def do_insert
    now = Time.now.to_s
    @attributes['created_at'] = now
    @attributes['updated_at'] = now

    cols = []
    placeholders = []
    values = []

    @attributes.each do |key, value|
      next if key == 'id'
      cols << key
      placeholders << '?'
      values << value
    end

    sql = "INSERT INTO #{self.class.table_name} (#{cols.join(', ')}) VALUES (#{placeholders.join(', ')})"
    DB.run(sql, values)

    id_result = DB.exec('SELECT last_insert_rowid()')
    @id = id_result[0].values[0][0]
    @attributes['id'] = @id
    @persisted = true
    true
  end

  def do_update
    @attributes['updated_at'] = Time.now.to_s

    sets = []
    values = []

    @attributes.each do |key, value|
      next if key == 'id'
      sets << "#{key} = ?"
      values << value
    end
    values << @id

    sql = "UPDATE #{self.class.table_name} SET #{sets.join(', ')} WHERE id = ?"
    DB.run(sql, values)
    true
  end

  def self.build_where(conditions)
    clauses = []
    values = []
    conditions.each do |key, value|
      clauses << "#{key} = ?"
      values << value
    end
    [clauses.join(' AND '), values]
  end

  def self.result_to_models(result)
    columns = result.columns
    result.values.map do |row|
      obj = {}
      columns.each_with_index do |col, i|
        obj[col] = row[i]
      end
      new(obj)
    end
  end
end
