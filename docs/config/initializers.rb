require "active_support/core_ext/object/blank"

Bridgetown.configure do |config|
  init :"bridgetown-seo-tag"
  init :"bridgetown-feed"
  init :"bridgetown-quick-search"
  init :"bridgetown-svg-inliner"
end
