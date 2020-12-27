import "@shoelace-style/shoelace/dist/shoelace/shoelace.css"
import {
  setAssetPath,
  SlIcon,
} from "@shoelace-style/shoelace"

setAssetPath(`${location.origin}/_bridgetown/static/icons`)
/* Define icons first: */
customElements.define("sl-icon", SlIcon)

console.info("imported!", SlIcon)

import "index.scss"

// Import all javascript files from src/_components
const componentsContext = require.context("bridgetownComponents", true, /.js$/)
componentsContext.keys().forEach(componentsContext)

import animateScrollTo from "animated-scroll-to"
import "bridgetown-quick-search"
