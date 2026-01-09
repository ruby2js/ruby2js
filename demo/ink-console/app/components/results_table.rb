# Results table component for displaying query results
class ResultsTable < Ink::Component
  def view_template
    return Box { Text(dimColor: true) { "No results" } } if @data.nil? || @data.empty?

    Box(flexDirection: "column", marginTop: 1) do
      # Header row
      Box(borderStyle: "single", borderBottom: true) do
        columns.each do |col|
          Box(width: col[:width], paddingX: 1) do
            Text(bold: true) { col[:name] }
          end
        end
      end

      # Data rows
      @data.each_with_index do |row, idx|
        Box(key: idx.to_s) do
          columns.each do |col|
            Box(width: col[:width], paddingX: 1) do
              Text { format_value(row[col[:key]]) }
            end
          end
        end
      end

      # Count footer
      Box(marginTop: 1) do
        Text(dimColor: true) { "#{@data.length} record(s)" }
      end
    end
  end

  def columns
    return [] if @data.nil? || @data.empty?

    @data.first.keys.map do |key|
      { name: key.to_s, key: key, width: calculate_width(key) }
    end
  end

  def calculate_width(key)
    # Calculate column width based on header and data
    max_width = key.to_s.length

    @data.each do |row|
      val = format_value(row[key])
      max_width = val.length if val.length > max_width
    end

    [max_width + 2, 30].min  # Cap at 30 chars
  end

  def format_value(val)
    case val
    when nil
      "null"
    when true, false
      val.to_s
    else
      val.to_s[0, 28]  # Truncate long values
    end
  end
end
