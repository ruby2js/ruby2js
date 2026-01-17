require 'minitest/autorun'
require 'ruby2js/svelte_template_compiler'

describe Ruby2JS::SvelteTemplateCompiler do
  def compile(template, options = {})
    Ruby2JS::SvelteTemplateCompiler.compile(template, options)
  end

  describe "interpolations { }" do
    it "converts simple variable references" do
      result = compile('<h1>{title}</h1>')
      _(result.template).must_equal '<h1>{title}</h1>'
      _(result.errors).must_be_empty
    end

    it "converts property access" do
      result = compile('<span>{post.title}</span>')
      _(result.template).must_equal '<span>{post.title}</span>'
    end

    it "converts snake_case to camelCase" do
      result = compile('<span>{user_name}</span>')
      _(result.template).must_equal '<span>{userName}</span>'
    end

    it "converts method calls" do
      result = compile('<span>{items.length}</span>')
      _(result.template).must_equal '<span>{items.length}</span>'
    end

    it "handles multiple interpolations" do
      result = compile('<p>{first_name} {last_name}</p>')
      _(result.template).must_equal '<p>{firstName} {lastName}</p>'
    end

    it "handles interpolations with whitespace" do
      result = compile('<p>{  spaced_var  }</p>')
      _(result.template).must_equal '<p>{spacedVar}</p>'
    end

    it "handles ternary expressions" do
      result = compile('<span>{is_active ? "Yes" : "No"}</span>')
      _(result.template).must_equal '<span>{isActive ? "Yes" : "No"}</span>'
    end

    it "handles nested braces in strings" do
      result = compile('<span>{"hello {world}"}</span>')
      _(result.template).must_equal '<span>{"hello {world}"}</span>'
    end
  end

  describe "{#each} blocks" do
    it "converts simple each block" do
      result = compile('{#each items as item}{item}{/each}')
      _(result.template).must_equal '{#each items as item}{item}{/each}'
    end

    it "converts each with snake_case collection" do
      result = compile('{#each blog_posts as post}{post.title}{/each}')
      _(result.template).must_equal '{#each blogPosts as post}{post.title}{/each}'
    end

    it "converts each with index" do
      result = compile('{#each items as item, index}{index}: {item}{/each}')
      _(result.template).must_equal '{#each items as item, index}{index}: {item}{/each}'
    end

    it "converts each with key expression" do
      result = compile('{#each items as item (item.id)}{item.name}{/each}')
      _(result.template).must_equal '{#each items as item (item.id)}{item.name}{/each}'
    end

    it "converts each with index and key" do
      result = compile('{#each items as item, index (item.id)}{item}{/each}')
      _(result.template).must_equal '{#each items as item, index (item.id)}{item}{/each}'
    end

    it "converts each with property access collection" do
      result = compile('{#each user.items as item}{item}{/each}')
      _(result.template).must_equal '{#each user.items as item}{item}{/each}'
    end
  end

  describe "{#if} blocks" do
    it "converts simple if block" do
      result = compile('{#if show}Visible{/if}')
      _(result.template).must_equal '{#if show}Visible{/if}'
    end

    it "converts if with snake_case variable" do
      result = compile('{#if is_visible}Visible{/if}')
      _(result.template).must_equal '{#if isVisible}Visible{/if}'
    end

    it "converts if with comparison" do
      result = compile('{#if count > 0}Has items{/if}')
      _(result.template).must_equal '{#if count > 0}Has items{/if}'
    end

    it "converts if-else" do
      result = compile('{#if show}Yes{:else}No{/if}')
      _(result.template).must_equal '{#if show}Yes{:else}No{/if}'
    end

    it "converts else if" do
      result = compile('{#if a}A{:else if b}B{:else}C{/if}')
      _(result.template).must_equal '{#if a}A{:else if b}B{:else}C{/if}'
    end

    it "converts else if with snake_case" do
      result = compile('{#if first_option}A{:else if second_option}B{/if}')
      _(result.template).must_equal '{#if firstOption}A{:else if secondOption}B{/if}'
    end

    it "handles negation" do
      result = compile('{#if !is_loading}Loaded{/if}')
      _(result.template).must_equal '{#if !isLoading}Loaded{/if}'
    end
  end

  describe "{#await} blocks" do
    it "converts await block" do
      result = compile('{#await fetch_data}Loading...{:then data}{data}{:catch error}{error}{/await}')
      _(result.template).must_equal '{#await fetchData}Loading...{:then data}{data}{:catch error}{error}{/await}'
    end

    it "converts await with property access" do
      result = compile('{#await api.fetch_user}...{/await}')
      _(result.template).must_equal '{#await api.fetchUser}...{/await}'
    end
  end

  describe "{#key} blocks" do
    it "converts key block" do
      result = compile('{#key selected_item}<Component />{/key}')
      _(result.template).must_equal '{#key selectedItem}<Component />{/key}'
    end
  end

  describe "{@html} directive" do
    it "converts @html expression" do
      result = compile('{@html raw_content}')
      _(result.template).must_equal '{@html rawContent}'
    end
  end

  describe "{@debug} directive" do
    it "converts @debug expression" do
      result = compile('{@debug some_var}')
      _(result.template).must_equal '{@debug someVar}'
    end
  end

  describe "{@const} directive" do
    it "converts @const declaration" do
      result = compile('{@const total = item_count * price}')
      _(result.template).must_equal '{@const total = itemCount * price}'
    end
  end

  describe "event handlers on:event" do
    it "preserves on:click handlers" do
      result = compile('<button on:click={handle_click}>Click</button>')
      _(result.template).must_equal '<button on:click={handleClick}>Click</button>'
    end

    it "preserves on:submit handlers" do
      result = compile('<form on:submit={handle_submit}>...</form>')
      _(result.template).must_equal '<form on:submit={handleSubmit}>...</form>'
    end
  end

  describe "bind: directives" do
    it "converts bind:value" do
      result = compile('<input bind:value={user_input}>')
      _(result.template).must_equal '<input bind:value={userInput}>'
    end

    it "converts bind:checked" do
      result = compile('<input type="checkbox" bind:checked={is_selected}>')
      _(result.template).must_equal '<input type="checkbox" bind:checked={isSelected}>'
    end
  end

  describe "complex templates" do
    it "handles a full component template" do
      template = <<~SVELTE
        <div>
          <h1>{page_title}</h1>
          {#if items.length > 0}
            <ul>
              {#each filtered_items as item (item.id)}
                <li>{item.display_name}</li>
              {/each}
            </ul>
          {:else}
            <p>No items found</p>
          {/if}
          <button on:click={load_more} disabled={is_loading}>
            {is_loading ? "Loading..." : "Load More"}
          </button>
        </div>
      SVELTE

      result = compile(template)

      _(result.template).must_include '{pageTitle}'
      _(result.template).must_include '{#each filteredItems as item (item.id)}'
      _(result.template).must_include '{item.displayName}'
      _(result.template).must_include 'on:click={loadMore}'
      _(result.template).must_include 'disabled={isLoading}'
      _(result.template).must_include '{isLoading ? "Loading..." : "Load More"}'
      _(result.errors).must_be_empty
    end
  end

  describe "options" do
    it "respects camelCase: false option" do
      result = compile('<span>{user_name}</span>', camelCase: false)
      _(result.template).must_equal '<span>{user_name}</span>'
    end
  end

  describe "class method" do
    it "provides compile class method" do
      result = Ruby2JS::SvelteTemplateCompiler.compile('<p>{test_var}</p>')
      _(result.template).must_equal '<p>{testVar}</p>'
    end
  end

  describe "error handling" do
    it "handles unmatched braces gracefully" do
      result = compile('<p>{unclosed')
      _(result.errors).wont_be_empty
      _(result.errors.first[:type]).must_equal :unmatched_brace
    end
  end
end
