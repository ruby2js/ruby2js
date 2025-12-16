# Base class for all models
# Transpiled to JavaScript, runs on sql.js
export class ApplicationRecord
  attr_accessor :id, :attributes, :errors

  def initialize(attrs = {})
    @attributes = {}
    @errors = []
    @persisted = false

    Object.keys(attrs).each do |key|
      value = attrs[key]
      @attributes[key.to_s] = value
      @id = value if key.to_s == 'id'
    end

    @persisted = true if @id
  end

  # Class methods
  def self.all
    sql = "SELECT * FROM #{self.table_name}"
    results = DB.exec(sql)
    return [] unless results.length > 0
    self.result_to_models(results[0])
  end

  def self.find(id)
    stmt = DB.prepare("SELECT * FROM #{self.table_name} WHERE id = ?")
    stmt.bind([id])
    if stmt.step()
      obj = stmt.getAsObject()
      stmt.free()
      self.new(obj)
    else
      stmt.free()
      raise "#{self.name} not found with id=#{id}"
    end
  end

  def self.find_by(conditions)
    where_clause, values = self.build_where(conditions)
    stmt = DB.prepare("SELECT * FROM #{self.table_name} WHERE #{where_clause} LIMIT 1")
    stmt.bind(values)
    if stmt.step()
      obj = stmt.getAsObject()
      stmt.free()
      self.new(obj)
    else
      stmt.free()
      nil
    end
  end

  def self.where(conditions)
    where_clause, values = self.build_where(conditions)
    stmt = DB.prepare("SELECT * FROM #{self.table_name} WHERE #{where_clause}")
    stmt.bind(values)
    results = []
    while stmt.step()
      results << self.new(stmt.getAsObject())
    end
    stmt.free()
    results
  end

  def self.create(attrs)
    record = self.new(attrs)
    record.save  # Access as getter, not method call
    record
  end

  def self.count
    result = DB.exec("SELECT COUNT(*) FROM #{self.table_name}")
    result[0].values[0][0]
  end

  def self.first
    result = DB.exec("SELECT * FROM #{self.table_name} ORDER BY id ASC LIMIT 1")
    return nil unless result.length > 0 && result[0].values.length > 0
    self.result_to_models(result[0])[0]
  end

  def self.last
    result = DB.exec("SELECT * FROM #{self.table_name} ORDER BY id DESC LIMIT 1")
    return nil unless result.length > 0 && result[0].values.length > 0
    self.result_to_models(result[0])[0]
  end

  # Instance methods
  def persisted?
    @persisted
  end

  def new_record?
    !@persisted
  end

  def save
    return false unless is_valid

    if @persisted
      do_update  # Access as getter
    else
      do_insert  # Access as getter
    end
  end

  def update(attrs)
    Object.keys(attrs).each do |key|
      @attributes[key.to_s] = attrs[key]
    end
    save  # Access as getter
  end

  def destroy
    return false unless @persisted
    DB.run("DELETE FROM #{self.class.table_name} WHERE id = ?", [@id])
    @persisted = false
    true
  end

  def is_valid
    @errors = []
    validate  # Access as getter
    @errors.length == 0
  end

  def validate
    # Override in subclasses
  end

  # Validation helpers
  def validates_presence_of(field)
    value = @attributes[field.to_s]
    if value.nil? || value.to_s.strip.length == 0
      @errors.push("#{field} can't be blank")
    end
  end

  def validates_length_of(field, options)
    value = @attributes[field.to_s].to_s
    if options[:minimum] && value.length < options[:minimum]
      @errors.push("#{field} is too short (minimum is #{options[:minimum]} characters)")
    end
  end

  private

  def do_insert
    now = Time.now().to_s
    @attributes['created_at'] = now
    @attributes['updated_at'] = now

    cols = []
    placeholders = []
    values = []

    Object.keys(@attributes).each do |key|
      next if key == 'id'
      cols << key
      placeholders << '?'
      values << @attributes[key]
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
    @attributes['updated_at'] = Time.now().to_s

    sets = []
    values = []

    Object.keys(@attributes).each do |key|
      next if key == 'id'
      sets << "#{key} = ?"
      values << @attributes[key]
    end
    values << @id

    sql = "UPDATE #{self.class.table_name} SET #{sets.join(', ')} WHERE id = ?"
    DB.run(sql, values)
    true
  end

  def self.build_where(conditions)
    clauses = []
    values = []
    Object.keys(conditions).each do |key|
      clauses << "#{key} = ?"
      values << conditions[key]
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
      self.new(obj)
    end
  end
end
