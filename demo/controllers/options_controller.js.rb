# control all of the drop-downs and checkboxes: ESLevel, AST?, Filters,
# Options.

class OptionsController < DemoController
  def target
    @target ||= findController type: RubyController,
      element: document.querySelector(element.dataset.target)
  end

  def pair(target)
    target.options = options = parse_options()
    target.contents = options.ruby if options.ruby
  end

  def setup()
    # determine base URL and what filters and options are selected
    @filters = new Set()
    @options = {}
    window.location.search.scan(/(\w+)(=([^&]*))?/).each do |match|
      @options[match[0]] = match[2] && decodeURIComponent(match[2])
    end
    if @options.filter
      @options.filter.split(',').each {|option| @filters.add(option)}
    end

    optionDialog = document.getElementById('option')
    optionInput = optionDialog.querySelector('sl-input')
    optionClose = optionDialog.querySelector('sl-button[slot="footer"]')

    optionDialog.addEventListener 'sl-initial-focus' do
      event.preventDefault()
      optionInput.setFocus(preventScroll: true)
    end

    optionClose.addEventListener 'click' do
      @options[optionDialog.label] = optionInput.value
      optionDialog.hide()
    end

    ast = document.getElementById('ast')
    ast.addEventListener 'sl-change' do
      target.ast = ast.checked if target
    end

    document.querySelectorAll('sl-dropdown').each do |dropdown|
      menu = dropdown.querySelector('sl-menu')
      dropdown.addEventListener 'sl-show', -> {
        menu.style.display = 'block'
      }, once: true

      menu.addEventListener 'sl-select' do |event|
        item = event.detail.item

        if dropdown.id == 'options'
          item.checked = !item.checked
          name = item.textContent

          if @options.respond_to? name
            @options.delete(name)
          elsif item.dataset.args
            event.target.parentNode.hide()
            dialog = document.getElementById('option')
            dialog.label = name
            dialog.querySelector('sl-input').value = @options[name] || ''
            dialog.show()
          else
            @options[name] = undefined
          end

        elsif dropdown.id == 'filters'

          item.checked = !item.checked
          name = item.textContent
          @filters.add(name) unless @filters.delete!(name)

        elsif dropdown.id == 'eslevel'

          button = event.target.parentNode.querySelector('sl-button')
          value = item.textContent
          @options['es' + value] = undefined if value != "default"
          event.target.querySelectorAll('sl-menu-item').each do |option|
            option.checked = (option == item)
            next if option.value == 'default' || option.value == value
            @options.delete('es' + option.value)
          end
          button.textContent = value

        end

        updateLocation()
      end
    end

    # make inputs match query
    parse_options().each_pair do |name, value|
      case name
      when :filters
        nodes = document.getElementById(:filters).parentNode.querySelectorAll('sl-menu-item')
        nodes.forEach do |node|
          node.checked = true if value.include? node.textContent
        end
      when :eslevel
        eslevel = document.getElementById('eslevel')
        eslevel.querySelector('sl-button').textContent = value.to_s
        eslevel.querySelectorAll("sl-menu-item").each {|item| item.checked = false}
        eslevel.querySelector("sl-menu-item[value='#{value}']").checked = true
      when :comparison
        document.querySelector("sl-menu-item[name=identity]").checked = true if value == :identity
      when :nullish
        document.querySelector("sl-menu-item[name=or]").checked = true if value == :nullish
      else
        checkbox = document.querySelector("sl-menu-item[name=#{name}]")
        checkbox.checked = true if checkbox
      end
    end
  end

  def updateLocation()
    base = window.location.pathname
    location = URL.new(base, window.location)

    @options.filter = Array(@filters).join(',')
    @options.delete(:filter) if @filters.size == 0

    search = []
    @options.each_pair do |key, value|
      search << (value == undefined ? key : "#{key}=#{encodeURIComponent(value)}")
    end

    location.search = search.empty? ? "" : "#{search.join('&')}"
    return if window.location.to_s == location.to_s

    history.replaceState({}, null, location.to_s)

    return if document.getElementById('js').style.display == 'none'

    # update JavaScript
    target.options = parse_options() if target
  end

  # convert query into options
  def parse_options()
    options = {filters: []}
    search = document.location.search
    return options if search == ''

    search[1..-1].split('&').each do |parameter|
      name, value = parameter.split('=', 2)
      value = value ? decodeURIComponent(value.gsub('+', ' ')) : true

      if name == :filter
        name = :filters
        value = [] if value == true
      elsif name == :identity
        value = name
        name = :comparison
      elsif name == :nullish
        value = name
        name = :or
      elsif name =~ /^es\d+$/
        value = name[2..-1].to_i
        name = :eslevel
      end

      options[name] = value
    end

    return options
  end

end
