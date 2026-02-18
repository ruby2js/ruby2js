export class ApplicationController extends ActionController.Base {
};

// Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
ApplicationController.allow_browser({versions: "modern"});

// Changes to the importmap will invalidate the etag for HTML responses
ApplicationController.stale_when_importmap_changes