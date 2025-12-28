// Phlex runtime for browser - provides base class for Phlex views
// This is used when Phlex views are transpiled to JavaScript

export const Phlex = {
  HTML: class {
    // call() is the standard Phlex interface - renders the view
    call() {
      return this.render();
    }
    
    // render() should be overridden by subclasses
    // The phlex filter generates this method from view_template
    render() {
      return "";
    }
  }
};

// Also export as default for flexible importing
export default Phlex;
