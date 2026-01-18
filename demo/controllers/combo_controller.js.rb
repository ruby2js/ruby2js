class ComboController < DemoController
  def setup()
    tab_group = document.createElement('sl-tab-group')
    tab_group.setAttribute 'placement', 'bottom'

    # ruby tab
    tab = document.createElement('sl-tab')
    tab.setAttribute 'slot', 'nav'
    tab.setAttribute 'panel', 'ruby'
    tab.textContent = element.dataset.erb == 'true' ? 'ERB' : 'Ruby'
    tab_group.appendChild(tab)

    # js tab
    tab = document.createElement('sl-tab')
    tab.setAttribute 'slot', 'nav'
    tab.setAttribute 'panel', 'js'
    # Check template option and filters to determine appropriate tab label
    options = JSON.parse(element.dataset.options || '{}')
    filters = options.filters || []
    # Determine tab label based on template type or filters
    js_label = filters.include?('jsx') ? 'JSX' : 'JavaScript'
    tab.textContent = case options.template
    when 'vue'
      'Vue SFC'
    when 'svelte'
      'Svelte'
    when 'astro'
      'Astro'
    else
      js_label
    end
    tab_group.appendChild(tab)

    # result tab (if there are children present)
    if element.children.length > 0
      tab = document.createElement('sl-tab')
      tab.setAttribute 'slot', 'nav'
      tab.setAttribute 'panel', 'result'
      tab.textContent = 'Result'
      tab_group.appendChild(tab)
    end

    # ruby panel
    ruby_panel = document.createElement('sl-tab-panel')
    ruby_panel.setAttribute 'name', 'ruby'
    div = document.createElement('div')
    # Use selfhost controller if data-selfhost="true" is set
    controller_name = element.dataset.selfhost == 'true' ? 'selfhost-ruby' : 'ruby'
    div.setAttribute 'data-controller', controller_name
    div.setAttribute 'data-options', element.dataset.options
    # Pass ERB mode flag if set
    div.setAttribute 'data-erb', 'true' if element.dataset.erb == 'true'
    ruby_panel.appendChild(div)
    tab_group.appendChild(ruby_panel)

    # js panel
    js_panel = document.createElement('sl-tab-panel')
    js_panel.setAttribute 'name', 'js'
    div = document.createElement('div')
    div.setAttribute 'data-controller', 'js'
    js_panel.appendChild(div)
    tab_group.appendChild(js_panel)

    # result panel (if there are children present)
    if element.children.length > 0
      result_panel = document.createElement('sl-tab-panel')
      result_panel.setAttribute 'name', 'result'
      while element.childNodes.length > 0
        result_panel.append_child element.firstChild
      end
      tab_group.appendChild(result_panel)
    end

    # clone adjacent ruby markdown code into ruby panel
    nextSibling = element.nextElementSibling
    if nextSibling.classList.contains('language-ruby')
      ruby_panel.appendChild(nextSibling.cloneNode(true))
      nextSibling.style.display = 'none'
    end

    # add tab group to document
    element.appendChild(tab_group)
  end

  def teardown()
    tab_group = element.querySelector('sl-tab-group')
    result_panel = element.querySelector('sl-tab-panel[data-controller=result]')

    while result_panel and result_panel.childNodes.length > 0
      element.append_child result_panel.firstChild
    end

    # make adjacent ruby markdown code visible again
    nextSibling = element.nextElementSibling
    if nextSibling.classList.contains('language-ruby')
      nextSibling.style.display = 'block'
    end

    # remove tab group from document
    tab_group.remove()
  end
end

