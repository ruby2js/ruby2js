import "@shoelace-style/shoelace/dist/shoelace/shoelace.css"
import {
  setAssetPath,
  SlButton,
  SlCheckbox,
  SlDialog,
  SlDropdown,
  SlIcon,
  SlInput,
  SlMenu,
  SlMenuItem,
  SlTab,
  SlTabGroup,
  SlTabPanel,
} from "@shoelace-style/shoelace"

setAssetPath(`${location.origin}/_bridgetown/static/icons`)

/* Define custom elements */
customElements.define("sl-button", SlButton)
customElements.define("sl-checkbox", SlCheckbox)
customElements.define("sl-dialog", SlDialog)
customElements.define("sl-dropdown", SlDropdown)
customElements.define("sl-icon", SlIcon)
customElements.define("sl-input", SlInput)
customElements.define("sl-menu", SlMenu)
customElements.define("sl-menu-item", SlMenuItem)
customElements.define("sl-tab", SlTab)
customElements.define("sl-tab-group", SlTabGroup)
customElements.define("sl-tab-panel", SlTabPanel)

import "index.scss"

// Import all javascript files from src/_components
const componentsContext = require.context("bridgetownComponents", true, /.js$/)
componentsContext.keys().forEach(componentsContext)

import animateScrollTo from "animated-scroll-to"
import "bridgetown-quick-search"
import { toggleMenuIcon, addHeadingAnchors } from "./lib/functions.js.rb"

document.addEventListener('turbo:load', () => {
  if (document.querySelector("#mobile-nav-activator")) {
    let navActivated = false
    document.querySelector("#mobile-nav-activator").addEventListener("click", event => {
      animateScrollTo(
        document.querySelector("layout-sidebar"),
        {
          maxDuration: 500
        }
      )
      if (!navActivated) {
        const button = event.currentTarget
        toggleMenuIcon(button)
        navActivated = true;
        setTimeout(() => { toggleMenuIcon(button); navActivated = false }, 6000)
      }
    })
  }

  addHeadingAnchors()
})
