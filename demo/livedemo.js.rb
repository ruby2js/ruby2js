async {
  # determine base URL and what filters and options are selected
  base = window.location.pathname
  filters = new Set()
  options = {}
  window.location.search.scan(/(\w+)(=([^&]*))?/).each do |match|
    options[match[0]] = match[2] && decodeURIComponent(match[2])
  end
  if options.filter
    options.filter.split(',').each {|option| filters.add(option)}
  end

  updateLocation = -> (force = false) do
    location = URL.new(base, window.location)

    options.filter = Array(filters).join(',')
    options.delete(:filter) if filters.empty?

    search = []
    options.each_pair do |key, value|
      search << (value == undefined ? key : "#{key}=#{encodeURIComponent(value)}")
    end

    location.search = search.empty? ? "" : "#{search.join('&')}"
    return if !force && window.location.to_s == location.to_s

    history.replaceState({}, null, location.to_s)

    return if document.getElementById('js').style.display == 'none'

    # update JavaScript
    event = MouseEvent.new('click',
      bubbles: true, cancelable: true, view: window)
    document.querySelector('input[type=submit]').dispatchEvent(event)
  end

  optionDialog = document.getElementById('option')
  optionInput = optionDialog.querySelector('sl-input')
  optionClose = optionDialog.querySelector('sl-button[slot="footer"]')

  optionDialog.addEventListener 'sl-initial-focus' do
    event.preventDefault()
    optionInput.setFocus(preventScroll: true)
  end

  optionClose.addEventListener 'click' do
    options[optionDialog.label] = optionInput.value
    optionDialog.hide()
  end

  document.getElementById('ast').addEventListener 'sl-change' do
    updateLocation(true)
  end

  document.querySelectorAll('sl-dropdown').each do |dropdown|
    menu = dropdown.querySelector('sl-menu')
    dropdown.addEventListener 'sl-show', -> () {
      menu.style.display = 'block'
    }, once: true

    menu.addEventListener 'sl-select' do |event|
      item = event.detail.item

      if dropdown.id == 'options'
	item.checked = !item.checked
	name = item.textContent

	if options.include? name
	  options.delete(name)
	elsif item.dataset.args
	  event.target.parentNode.hide()
	  dialog = document.getElementById('option')
	  dialog.label = name
	  dialog.querySelector('sl-input').value = options[name] || ''
	  dialog.show()
	else
	  options[name] = undefined
	end

      elsif dropdown.id == 'filters'

	item.checked = !item.checked
	name = item.textContent
        filters.add(name) unless filters.delete!(name)

      elsif dropdown.id == 'eslevel'

	button = event.target.parentNode.querySelector('sl-button')
	value = item.textContent
        options['es' + value] = undefined if value != "default"
	event.target.querySelectorAll('sl-menu-item').each do |option|
	  option.checked = (option == item)
	  next if option.value == 'default' || option.value == value
	  options.delete('es' + option.value)
	end
	button.textContent = value

      end

      updateLocation()
    end
  end
}[]
