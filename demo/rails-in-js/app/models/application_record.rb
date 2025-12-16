# Base class for all models
# Transpiled to JavaScript, runs on sql.js
export class ApplicationRecord
  # Use underscore-prefixed properties instead of private fields
  # so subclasses can access them (JS private fields don't inherit)
  def id
    @_id
  end

  def id=(value)
    @_id = value
  end

  # Expose internal properties for subclass access (JS private fields don't inherit)
  def _id
    @_id
  end

  def _attributes
    @_attributes
  end

  def attributes
    @_attributes
  end

  def errors
    @_errors
  end

  def initialize(attrs = {})
    @_attributes = {}
    @_errors = []
    @_persisted = false

    Object.keys(attrs).each do |key|
      value = attrs[key]
      @_attributes[key.to_s] = value
      # Also set as direct property for easy access (article.title instead of article._attributes['title'])
      self[key] = value
      @_id = value if key.to_s == 'id'
    end

    @_persisted = true if @_id
  end

  # Class methods
  def self.all
    sql = "SELECT * FROM #{self.table_name}"
    console.debug("  #{self.name} Load  #{sql}")
    results = DB.exec(sql)
    return [] unless results.length > 0
    self.result_to_models(results[0])
  end

  def self.find(id)
    sql = "SELECT * FROM #{self.table_name} WHERE id = ?"
    console.debug("  #{self.name} Load  #{sql}  [[\"id\", #{id}]]")
    stmt = DB.prepare(sql)
    stmt.bind([id])
    if stmt.step()
      obj = stmt.getAsObject()
      stmt.free()
      self.new(obj)
    else
      stmt.free()
      console.error("  #{self.name} not found with id=#{id}")
      raise "#{self.name} not found with id=#{id}"
    end
  end

  def self.find_by(conditions)
    where_clause, values = self.build_where(conditions)
    sql = "SELECT * FROM #{self.table_name} WHERE #{where_clause} LIMIT 1"
    console.debug("  #{self.name} Load  #{sql}  #{JSON.stringify(values)}")
    stmt = DB.prepare(sql)
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
    sql = "SELECT * FROM #{self.table_name} WHERE #{where_clause}"
    console.debug("  #{self.name} Load  #{sql}  #{JSON.stringify(values)}")
    stmt = DB.prepare(sql)
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
    @_persisted
  end

  def new_record?
    !@_persisted
  end

  def save
    return false unless is_valid

    if @_persisted
      do_update  # Access as getter
    else
      do_insert  # Access as getter
    end
  end

  def update(attrs)
    Object.keys(attrs).each do |key|
      @_attributes[key.to_s] = attrs[key]
    end
    save  # Access as getter
  end

  def destroy
    return false unless @_persisted
    sql = "DELETE FROM #{self.class.table_name} WHERE id = ?"
    console.debug("  #{self.class.name} Destroy  #{sql}  [[\"id\", #{@_id}]]")
    DB.run(sql, [@_id])
    @_persisted = false
    true
  end

  def is_valid
    @_errors = []
    validate()  # Call as method - subclasses define validate()
    if @_errors.length > 0
      console.warn("  Validation failed:", @_errors)
    end
    @_errors.length == 0
  end

  def validate
    # Override in subclasses
  end

  # Validation helpers
  def validates_presence_of(field)
    value = @_attributes[field.to_s]
    if value.nil? || value.to_s.strip.length == 0
      @_errors.push("#{field} can't be blank")
    end
  end

  def validates_length_of(field, options)
    value = @_attributes[field.to_s].to_s
    if options[:minimum] && value.length < options[:minimum]
      @_errors.push("#{field} is too short (minimum is #{options[:minimum]} characters)")
    end
  end

  private

  def do_insert
    now = Time.now().to_s
    @_attributes['created_at'] = now
    @_attributes['updated_at'] = now

    cols = []
    placeholders = []
    values = []

    Object.keys(@_attributes).each do |key|
      next if key == 'id'
      cols << key
      placeholders << '?'
      values << @_attributes[key]
    end

    sql = "INSERT INTO #{self.class.table_name} (#{cols.join(', ')}) VALUES (#{placeholders.join(', ')})"
    console.debug("  #{self.class.name} Create  #{sql}")
    DB.run(sql, values)

    id_result = DB.exec('SELECT last_insert_rowid()')
    @_id = id_result[0].values[0][0]
    @_attributes['id'] = @_id
    self['id'] = @_id  # Also set as direct property
    @_persisted = true
    console.log("  #{self.class.name} Create (id: #{@_id})")
    true
  end

  def do_update
    @_attributes['updated_at'] = Time.now().to_s

    sets = []
    values = []

    Object.keys(@_attributes).each do |key|
      next if key == 'id'
      sets << "#{key} = ?"
      values << @_attributes[key]
    end
    values << @_id

    sql = "UPDATE #{self.class.table_name} SET #{sets.join(', ')} WHERE id = ?"
    console.debug("  #{self.class.name} Update  #{sql}  [[\"id\", #{@_id}]]")
    DB.run(sql, values)
    console.log("  #{self.class.name} Update (id: #{@_id})")
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
