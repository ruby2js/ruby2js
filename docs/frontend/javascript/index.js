// Example Shoelace components. Mix 'n' match however you like!
import "@shoelace-style/shoelace/dist/components/button/button.js"
import "@shoelace-style/shoelace/dist/components/checkbox/checkbox.js"
import "@shoelace-style/shoelace/dist/components/dialog/dialog.js"
import "@shoelace-style/shoelace/dist/components/dropdown/dropdown.js"
import "@shoelace-style/shoelace/dist/components/icon/icon.js"
import "@shoelace-style/shoelace/dist/components/input/input.js"
import "@shoelace-style/shoelace/dist/components/menu/menu.js"
import "@shoelace-style/shoelace/dist/components/menu-item/menu-item.js"
import "@shoelace-style/shoelace/dist/components/tab/tab.js"
import "@shoelace-style/shoelace/dist/components/tab-group/tab-group.js"
import "@shoelace-style/shoelace/dist/components/tab-panel/tab-panel.js"

// Use the public icons folder:
import { setBasePath } from "@shoelace-style/shoelace/dist/utilities/base-path.js"
setBasePath("/shoelace-assets")

import "index.scss"

import components from "bridgetownComponents/**/*.{js,jsx,js.rb,css}"

import animateScrollTo from "animated-scroll-to"
import "bridgetown-quick-search/dist"
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
